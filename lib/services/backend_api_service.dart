import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:flutter/services.dart';
import 'package:flutter_timezone/flutter_timezone.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../config/backend_config.dart';
import '../constants/powerup_copy.dart';
import '../models/balance_config.dart';
import '../models/powerup_shop_admin_item.dart';
import '../models/race_discovery_summary.dart';
import '../models/race_resolution_status.dart';
import '../models/step_data.dart';
import '../models/step_sample_data.dart';
import '../models/step_sync_v2_result.dart';

/// Session-scoped support state for an additive endpoint. Only a definite `404`
/// downgrades an endpoint to [unsupported] (spec §9.1 / D6); a timeout or `5xx`
/// never does. Reset on sign-out, authenticated-user change, or backend base URL
/// change — but NOT on ordinary session-token rotation.
enum EndpointSupport { unknown, supported, unsupported }

/// An API error with a user-friendly message.
class ApiException implements Exception {
  final String message;
  final int? statusCode;

  /// Machine-readable backend error code when the response includes one
  /// (e.g. TEAM_FULL, TEAMS_UNEVEN, UPDATE_REQUIRED). Null on older backends
  /// or plain-message errors — callers must treat it as optional.
  final String? code;
  const ApiException(this.message, {this.statusCode, this.code});

  @override
  String toString() => message;
}

String describeBackendConnectionError(Object error, {required Uri uri}) {
  if (error is TimeoutException) {
    return 'Connection timed out. Check your internet connection and try again.';
  }

  if (error is SocketException) {
    return "Can't connect right now. Check your internet connection and try again.";
  }

  if (error is HandshakeException) {
    return 'Secure connection failed. Please try again later.';
  }

  if (error is HttpException) {
    if (error.message.contains('App Transport Security')) {
      return 'Secure connection failed. Please try again later.';
    }

    return 'Request failed. Please try again.';
  }

  return 'Could not connect. Please try again.';
}

class BackendApiService {
  BackendApiService({HttpClient? httpClient})
    : _httpClient = httpClient ?? HttpClient() {
    _httpClient.connectionTimeout = _requestTimeout;
  }

  static const Duration _requestTimeout = Duration(seconds: 15);
  static const MethodChannel _appInfoChannel = MethodChannel(
    'com.steptracker/app_info',
  );

  // The `ads` capability is advertised ONLY when this build can actually
  // complete a rewarded-ad flow: a build that baked in a real rewarded ad unit
  // for THIS platform (iOS: ADMOB_EXTRA_SPIN_AD_UNIT_ID; Android:
  // ADMOB_EXTRA_SPIN_AD_UNIT_ID_ANDROID). This keeps the extra-spin offer off
  // any build where the platform's dart-define was forgotten — otherwise users
  // would see an offer whose reward can never verify.
  static const String _adUnitIdIos = String.fromEnvironment(
    'ADMOB_EXTRA_SPIN_AD_UNIT_ID',
  );
  static const String _adUnitIdAndroid = String.fromEnvironment(
    'ADMOB_EXTRA_SPIN_AD_UNIT_ID_ANDROID',
  );
  static bool get _adsSupported {
    if (kIsWeb) return false;
    if (Platform.isIOS) return _adUnitIdIos.isNotEmpty;
    if (Platform.isAndroid) return _adUnitIdAndroid.isNotEmpty;
    return false;
  }

  // `spinpowerups` tells the backend this build can render a shop-powerup prize
  // won from the daily-reward box (reel tile + reveal). Old binaries omit it and
  // never get offered a powerup — they'd mis-render it as "+0 coins".
  // `team_races` tells the backend this build can render team races (H2H banner,
  // team-grouped planks, team-aware join). Old binaries omit it, so the backend
  // filters team races out of their lists and rejects their team joins (TR-701).
  // `tournaments` tells the backend this build can render bracket tournaments
  // (lobby/bracket/champion screens, matchup races). Old binaries omit it, so
  // the backend keeps `/races` byte-identical for them, hides matchup races from
  // every listing, and rejects their tournament create/join (spec §4).
  // `powerups2` tells the backend this build can render the second-wave shop
  // powerups (Leech, X-Ray/DEFENSE_SCAN): their icons, the Leech victim badge,
  // and the X-Ray recon sheet. Old binaries omit it, so the gated catalog never
  // offers them and the app can't crash on the unknown enum values.
  // `powerups3` tells the backend this build can render the THIRD-wave shop
  // powerups (Hitchhike, Quick Rinse) and the backend-served copy catalog. It
  // also selects the 60-minute Leech window: a request without this token keeps
  // the legacy 30-minute behavior, so a frozen old binary still creates exactly
  // the effect its bundled copy describes (§7.5).
  //
  // NOTE: the token must appear in BOTH branches of the ternary. Editing only
  // the ads branch silently disables the whole feature on ad-less builds.
  static final String clientFeaturesHeader = _adsSupported
      ? 'characters,ads,jammer,spinpowerups,team_races,tournaments,powerups2,powerups3'
      : 'characters,jammer,spinpowerups,team_races,tournaments,powerups2,powerups3';
  final HttpClient _httpClient;
  String? _cachedTimeZone;
  String? _cachedReleaseChannel;
  String? _cachedAppVersion;

  // Session-scoped capability caches for the additive endpoints (spec §9.1).
  // Only a 404 flips one to `unsupported`; timeouts/5xx leave it untouched so a
  // transient blip never permanently strands the app on the legacy path.
  EndpointSupport _syncV2Support = EndpointSupport.unknown;
  EndpointSupport _discoverySummarySupport = EndpointSupport.unknown;
  EndpointSupport _raceResolutionStatusSupport = EndpointSupport.unknown;
  // Identity guards: capability caches are keyed to (user, base URL). A plain
  // token refresh for the SAME user must not clear them.
  String? _sessionUserId;
  String? _sessionBaseUrl;

  static final Random _uuidRandom = Random.secure();

  @visibleForTesting
  EndpointSupport get syncV2Support => _syncV2Support;
  @visibleForTesting
  EndpointSupport get discoverySummarySupport => _discoverySummarySupport;
  @visibleForTesting
  EndpointSupport get raceResolutionStatusSupport =>
      _raceResolutionStatusSupport;

  /// Clears every session-scoped capability cache. Call on sign-out.
  void resetSessionCapabilities() {
    _syncV2Support = EndpointSupport.unknown;
    _discoverySummarySupport = EndpointSupport.unknown;
    _raceResolutionStatusSupport = EndpointSupport.unknown;
    _sessionUserId = null;
  }

  /// Records the authenticated user for this session. Clears capability caches
  /// only when the user or backend base URL actually changed — an ordinary
  /// session-token rotation for the same user is a no-op.
  void onAuthenticatedUser(String userId) {
    final baseUrl = BackendConfig.baseUrl;
    if (_sessionUserId != userId || _sessionBaseUrl != baseUrl) {
      _syncV2Support = EndpointSupport.unknown;
      _discoverySummarySupport = EndpointSupport.unknown;
      _raceResolutionStatusSupport = EndpointSupport.unknown;
      _sessionUserId = userId;
      _sessionBaseUrl = baseUrl;
    }
  }

  /// A canonical v4 UUID string (36 chars) for the sync-v2 `Idempotency-Key`.
  /// The same key is reused for the single permitted retry.
  static String generateIdempotencyKey() {
    final bytes = List<int>.generate(16, (_) => _uuidRandom.nextInt(256));
    bytes[6] = (bytes[6] & 0x0f) | 0x40; // version 4
    bytes[8] = (bytes[8] & 0x3f) | 0x80; // RFC 4122 variant
    String hex(int b) => b.toRadixString(16).padLeft(2, '0');
    final s = bytes.map(hex).join();
    return '${s.substring(0, 8)}-${s.substring(8, 12)}-${s.substring(12, 16)}'
        '-${s.substring(16, 20)}-${s.substring(20)}';
  }

  /// Builds the ONE immutable, normalized sync-v2 body for a sync attempt group:
  /// samples pre-sorted chronologically (periodStart, then periodEnd) in UTC ISO
  /// with integer step values. The same object is reused for the retry so the
  /// server's canonical hash matches and the idempotency key never conflicts.
  static Map<String, dynamic> buildStepSyncV2Payload({
    required StepData stepData,
    required List<StepSampleData> samples,
  }) {
    final sorted = [...samples]
      ..sort((a, b) {
        final byStart = a.periodStart.toUtc().compareTo(b.periodStart.toUtc());
        if (byStart != 0) return byStart;
        return a.periodEnd.toUtc().compareTo(b.periodEnd.toUtc());
      });
    final month = stepData.date.month.toString().padLeft(2, '0');
    final day = stepData.date.day.toString().padLeft(2, '0');
    return <String, dynamic>{
      'date': '${stepData.date.year}-$month-$day',
      'steps': stepData.steps,
      'samples': sorted.map((s) => s.toJson()).toList(growable: false),
    };
  }

  // The running build's version (e.g. "1.3.0"), sent on every request so the
  // backend can gate responses by client capability instead of guessing.
  // Resolved once; falls back to "unknown" rather than ever failing a request.
  Future<String> _getAppVersion() async {
    if (_cachedAppVersion != null) return _cachedAppVersion!;
    try {
      final info = await PackageInfo.fromPlatform();
      _cachedAppVersion = info.version.isEmpty ? 'unknown' : info.version;
    } catch (_) {
      _cachedAppVersion = 'unknown';
    }
    return _cachedAppVersion!;
  }

  Future<String> _getTimeZone() async {
    _cachedTimeZone ??= await FlutterTimezone.getLocalTimezone();
    return _cachedTimeZone!;
  }

  // The build's release channel, sent to the backend so it knows whether to
  // reveal test-only catalog items. TestFlight (and dev) builds report
  // 'testflight'; App Store builds — and any platform where detection fails or
  // isn't implemented — report 'prod', the safe default. Resolved once, then
  // cached for the life of the service.
  Future<String> _getReleaseChannel() async {
    if (_cachedReleaseChannel != null) return _cachedReleaseChannel!;
    try {
      final isTestFlight =
          await _appInfoChannel.invokeMethod<bool>('isTestFlight') ?? false;
      _cachedReleaseChannel = isTestFlight ? 'testflight' : 'prod';
    } catch (_) {
      _cachedReleaseChannel = 'prod';
    }
    return _cachedReleaseChannel!;
  }

  Future<Map<String, dynamic>> provisionAppleUser({
    required String identityToken,
    required String userIdentifier,
    String? email,
    String? referralCode,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/auth/apple',
      body: {
        'identityToken': identityToken,
        'userIdentifier': userIdentifier,
        'email': email,
        // No 'name': the Apple real name is never requested nor sent; the
        // backend generates the display name (see ensureAppleUser.js).
        // Additive/optional — included only when a referral code was captured,
        // so older backends (which ignore it) and this build both stay happy.
        if (referralCode != null && referralCode.isNotEmpty)
          'referralCode': referralCode,
      },
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return payload;
  }

  /// Provisions/looks up a user from a Google ID token (Android). The backend
  /// verifies the token and derives the stable Google `sub` itself — there is no
  /// `userIdentifier` field (unlike Apple). Returns the same
  /// `{user, sessionToken}` envelope as [provisionAppleUser].
  Future<Map<String, dynamic>> provisionGoogleUser({
    required String idToken,
    String? email,
    String? name,
    String? referralCode,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/auth/google',
      body: {
        'idToken': idToken,
        'email': email,
        'name': name,
        if (referralCode != null && referralCode.isNotEmpty)
          'referralCode': referralCode,
      },
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return payload;
  }

  Future<Map<String, dynamic>> signInAsReviewer({
    required String email,
    required String password,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/auth/review',
      body: {'email': email, 'password': password},
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return payload;
  }

  Future<Map<String, dynamic>> refreshSessionToken({
    required String authToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/auth/session',
      identityToken: authToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Fetches the client version policy behind the force-update gate. Public —
  /// no auth, so it answers before a session exists. The running build's version
  /// rides the standard X-App-Version header, but the caller re-derives the gate
  /// from minSupportedVersion/latestVersion rather than trusting the server's
  /// convenience flags. Throws [ApiException] on any failure (incl. a 404 from
  /// an older backend that predates this endpoint); callers fail open.
  Future<Map<String, dynamic>> fetchVersionPolicy() async {
    final response = await _sendGetRequest(path: '/app-version/policy');
    return _decodeJsonResponse(response);
  }

  /// §9.5.3 — the backend-served powerup copy catalog.
  ///
  /// Unauthenticated and client-feature-independent: copy is not a capability,
  /// so this returns every user-renderable type regardless of what this build
  /// can actually acquire.
  ///
  /// Throws [PowerupCopyUnavailable] for a 404 (older backend) or a 5xx so the
  /// caller can treat it as TRANSIENT. This endpoint deliberately does NOT get
  /// an [EndpointSupport] cache: the backend deploys independently of an
  /// installed app, so marking it unsupported for the session would strand the
  /// client on stale copy until the next cold start for no reason.
  Future<Map<String, dynamic>> fetchPowerupCatalog() async {
    final response = await _sendGetRequest(path: '/powerups/catalog');
    if (response.statusCode == 404 || response.statusCode >= 500) {
      throw PowerupCopyUnavailable(response.statusCode);
    }
    return _decodeJsonResponse(response);
  }

  Future<void> recordSteps({
    required String identityToken,
    required StepData stepData,
    bool skipRaceResolution = false,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/steps',
      body: {
        'steps': stepData.steps,
        'date': _formatDate(stepData.date),
        if (skipRaceResolution) 'skipRaceResolution': true,
      },
      identityToken: identityToken,
    );

    await _decodeJsonResponse(response);
  }

  Future<void> recordStepSamples({
    required String identityToken,
    required List<StepSampleData> samples,
  }) async {
    if (samples.isEmpty) return;

    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/steps/samples',
      body: {'samples': samples.map((s) => s.toJson()).toList()},
      identityToken: identityToken,
    );

    await _decodeJsonResponse(response);
  }

  /// `POST /steps/sync-v2` (spec §6.4): persists the daily total + optional
  /// hourly samples and returns the uploader-current reconciliation state plus a
  /// durable job handle. [payload] must be the immutable normalized body from
  /// [buildStepSyncV2Payload]; [idempotencyKey] must be reused verbatim across
  /// this call's single internal retry. All non-2xx/ambiguous cases are mapped
  /// to a [StepSyncV2Result] the orchestration layer can act on defensively —
  /// only a definite 404 or pre-persistence `ASYNC_DISABLED` permits a legacy
  /// write.
  Future<StepSyncV2Result> recordStepSyncV2({
    required String identityToken,
    required String idempotencyKey,
    required Map<String, dynamic> payload,
  }) async {
    if (_syncV2Support == EndpointSupport.unsupported) {
      return const StepSyncV2Result(kind: StepSyncV2Kind.unsupported);
    }

    var result = await _attemptStepSyncV2(
      identityToken,
      idempotencyKey,
      payload,
    );
    if (result.kind == StepSyncV2Kind.ambiguousFailure) {
      // The single permitted retry — SAME key, SAME immutable payload. The
      // server may have committed the first attempt, so we never fall back to a
      // legacy write from here.
      result = await _attemptStepSyncV2(identityToken, idempotencyKey, payload);
    }
    return result;
  }

  Future<StepSyncV2Result> _attemptStepSyncV2(
    String identityToken,
    String idempotencyKey,
    Map<String, dynamic> payload,
  ) async {
    HttpClientResponse response;
    try {
      response = await _sendJsonRequest(
        method: 'POST',
        path: '/steps/sync-v2',
        body: payload,
        identityToken: identityToken,
        headers: {'Idempotency-Key': idempotencyKey},
      );
    } on ApiException {
      // Connection loss / timeout / handshake — ambiguous and retryable.
      return const StepSyncV2Result(kind: StepSyncV2Kind.ambiguousFailure);
    }

    final raw = await _readRawResponse(response);
    final status = raw.statusCode;

    if (status == 404) {
      _syncV2Support = EndpointSupport.unsupported;
      return const StepSyncV2Result(kind: StepSyncV2Kind.unsupported);
    }

    // A definite HTTP reply from the route proves it exists this session.
    _syncV2Support = EndpointSupport.supported;

    if (status >= 200 && status < 300) {
      if (raw.decodeFailed || raw.json == null) {
        // Persisted-but-status-unknown: never legacy-write, use live Home.
        return const StepSyncV2Result(
          kind: StepSyncV2Kind.persistedStatusUnknown,
          diagnostic: 'sync-v2 success body was not a JSON object',
        );
      }
      return _parseStepSyncV2Success(raw.json!);
    }

    if (status == 503 && raw.code == 'ASYNC_DISABLED') {
      // Guaranteed pre-persistence — safe to run the legacy flow.
      return const StepSyncV2Result(kind: StepSyncV2Kind.asyncDisabled);
    }

    if (status >= 500) {
      return const StepSyncV2Result(kind: StepSyncV2Kind.ambiguousFailure);
    }

    if (status == 409) {
      // Idempotency conflict: the server may already hold the first input.
      return const StepSyncV2Result(
        kind: StepSyncV2Kind.persistedStatusUnknown,
        diagnostic: 'sync-v2 idempotency conflict (409)',
      );
    }

    // 400 / 401 / 413 and any other definite rejection: no legacy write.
    return const StepSyncV2Result(kind: StepSyncV2Kind.failed);
  }

  StepSyncV2Result _parseStepSyncV2Success(Map<String, dynamic> json) {
    final recon = json['uploaderReconciliation'];
    final reconMap = recon is Map<String, dynamic>
        ? recon
        : const <String, dynamic>{};
    // Absent/unknown state degrades to DEFERRED so a stale own card can never
    // replace good UI.
    final isCurrent = reconMap['state'] == 'CURRENT';
    final rawResolved = reconMap['resolvedRaceCount'];
    final boxCurrent = reconMap['boxStateCurrent'];

    final job = json['raceResolution'];
    final jobMap = job is Map<String, dynamic>
        ? job
        : const <String, dynamic>{};
    final rawJobId = jobMap['jobId'];
    final rawGeneration = jobMap['generation'];

    return StepSyncV2Result(
      kind: isCurrent ? StepSyncV2Kind.current : StepSyncV2Kind.deferred,
      jobId: rawJobId is String && rawJobId.isNotEmpty ? rawJobId : null,
      generation: rawGeneration is int ? rawGeneration : null,
      resolvedRaceCount: rawResolved is int && rawResolved >= 0
          ? rawResolved
          : 0,
      boxStateCurrent: isCurrent && boxCurrent == true,
    );
  }

  /// `GET /steps/race-resolution/:jobId?generation=` (spec §6.5). Optional,
  /// never blocks any indicator. A 404 (job unknown/not-owned) stops the poll
  /// loop; malformed/transient reads return [RaceResolutionState.unknown] so the
  /// loop may retry on its fixed schedule.
  Future<RaceResolutionStatus> fetchRaceResolutionStatus({
    required String identityToken,
    required String jobId,
    required int generation,
  }) async {
    HttpClientResponse response;
    try {
      response = await _sendGetRequest(
        path: '/steps/race-resolution/$jobId?generation=$generation',
        identityToken: identityToken,
      );
    } on ApiException {
      return const RaceResolutionStatus(RaceResolutionState.unknown);
    }

    final raw = await _readRawResponse(response);
    final status = raw.statusCode;

    // 404 here means the specific job is unknown/not-owned (or the endpoint is
    // absent). Either way the poll must stop — but we do NOT permanently cache
    // "unsupported", because a job-not-found on one poll must not disable status
    // reads for later jobs.
    if (status == 404) {
      return const RaceResolutionStatus(RaceResolutionState.notFound);
    }
    // 400 = invalid generation: nothing to poll.
    if (status == 400) {
      return const RaceResolutionStatus(RaceResolutionState.notFound);
    }

    _raceResolutionStatusSupport = EndpointSupport.supported;

    if (status >= 200 &&
        status < 300 &&
        raw.json != null &&
        !raw.decodeFailed) {
      final rr = raw.json!['raceResolution'];
      final state = rr is Map<String, dynamic>
          ? RaceResolutionStatus.parseState(rr['state'])
          : RaceResolutionState.unknown;
      return RaceResolutionStatus(state);
    }

    return const RaceResolutionStatus(RaceResolutionState.unknown);
  }

  /// `GET /races/discovery-summary` (spec §6.2): one compact request replacing
  /// the featured/public/tournament background calls. A 404 marks the endpoint
  /// unsupported for the session and signals the caller to run the legacy
  /// discovery calls in parallel; malformed/transient failures retain the last
  /// known values (no legacy fallback, no data erasure).
  Future<RaceDiscoverySummary> fetchRaceDiscoverySummary({
    required String identityToken,
  }) async {
    if (_discoverySummarySupport == EndpointSupport.unsupported) {
      return RaceDiscoverySummary.unsupportedResult;
    }

    HttpClientResponse response;
    try {
      response = await _sendGetRequest(
        path: '/races/discovery-summary',
        identityToken: identityToken,
      );
    } on ApiException {
      return RaceDiscoverySummary.empty;
    }

    final raw = await _readRawResponse(response);
    final status = raw.statusCode;

    if (status == 404) {
      _discoverySummarySupport = EndpointSupport.unsupported;
      return RaceDiscoverySummary.unsupportedResult;
    }

    _discoverySummarySupport = EndpointSupport.supported;

    if (status >= 200 &&
        status < 300 &&
        raw.json != null &&
        !raw.decodeFailed) {
      return RaceDiscoverySummary.fromJson(raw.json!);
    }

    // 401 / 5xx / malformed: retain last known values.
    return RaceDiscoverySummary.empty;
  }

  Future<Map<String, dynamic>> fetchMe({required String identityToken}) async {
    final response = await _sendGetRequest(
      path: '/auth/me',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return user;
  }

  Future<Map<String, dynamic>> fetchStepMilestonesToday({
    required String identityToken,
    required String localDate,
  }) async {
    final response = await _sendGetRequest(
      path: '/users/me/step-milestones/today?localDate=$localDate',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> claimStepMilestone({
    required String identityToken,
    required String localDate,
    required int threshold,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/users/me/step-milestones/$threshold/claim',
      body: {'localDate': localDate},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> setDisplayName({
    required String identityToken,
    required String? displayName,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/auth/me/display-name',
      body: {'displayName': displayName},
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return user;
  }

  /// Toggles whether the signed-in user is hidden from the global leaderboard.
  /// Additive endpoint (backend >= June 2026); older backends 404 here, so
  /// callers degrade gracefully. Returns the updated `user` map.
  Future<Map<String, dynamic>> updateLeaderboardVisibility({
    required String identityToken,
    required bool hidden,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/auth/me/leaderboard-visibility',
      body: {'hidden': hidden},
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return user;
  }

  /// Toggles auto-joining the daily/weekly featured challenges. Additive
  /// endpoint (backend >= July 2026); older backends 404 here, so callers
  /// degrade gracefully. Enabling also opts the user into the already-pending
  /// next race server-side. Returns the updated `user` map.
  Future<Map<String, dynamic>> updateFeaturedAutoJoin({
    required String identityToken,
    required bool enabled,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/auth/me/featured-auto-join',
      body: {'enabled': enabled},
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];

    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return user;
  }

  /// GET /notifications/preferences (spec §9.1). Reads the daily-reward
  /// reminder opt-in. Additive endpoint — older backends 404 and the caller
  /// defaults to enabled; an absent/non-boolean field also reads as `true`
  /// (the documented default). Throws [ApiException] on non-2xx so callers can
  /// distinguish an unreachable/unversioned backend and degrade to the default.
  Future<bool> fetchDailyRewardRemindersEnabled({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/notifications/preferences',
      identityToken: identityToken,
    );
    final payload = await _decodeJsonResponse(response);
    final value = payload['dailyRewardRemindersEnabled'];
    return value is bool ? value : true;
  }

  /// PATCH /notifications/preferences (spec §9.1). Persists the daily-reward
  /// reminder opt-in and returns the stored value. Additive endpoint; unknown
  /// fields are ignored server-side. Falls back to the requested value if the
  /// response omits the field.
  Future<bool> updateDailyRewardRemindersEnabled({
    required String identityToken,
    required bool enabled,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PATCH',
      path: '/notifications/preferences',
      body: {'dailyRewardRemindersEnabled': enabled},
      identityToken: identityToken,
    );
    final payload = await _decodeJsonResponse(response);
    final value = payload['dailyRewardRemindersEnabled'];
    return value is bool ? value : enabled;
  }

  Future<Map<String, dynamic>> checkDisplayName({
    required String identityToken,
    required String name,
  }) async {
    final response = await _sendGetRequest(
      path: '/auth/check-display-name?name=${Uri.encodeComponent(name)}',
      identityToken: identityToken,
    );

    return await _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> requestProfilePhotoUpload({
    required String identityToken,
    required String contentType,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/auth/me/profile-photo/upload-url',
      body: {'contentType': contentType},
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final upload = payload['upload'];
    if (upload is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return upload;
  }

  Future<Map<String, dynamic>> saveProfilePhoto({
    required String identityToken,
    required String key,
    required String url,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/auth/me/profile-photo',
      body: {'key': key, 'url': url},
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];
    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return user;
  }

  Future<Map<String, dynamic>> removeProfilePhoto({
    required String identityToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'DELETE',
      path: '/auth/me/profile-photo',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];
    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return user;
  }

  Future<void> deleteAccount({required String identityToken}) async {
    await _sendJsonRequest(
      method: 'DELETE',
      path: '/auth/account',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
  }

  Future<Map<String, dynamic>> dismissProfilePhotoPrompt({
    required String identityToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/auth/me/profile-photo/prompt-dismiss',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final user = payload['user'];
    if (user is! Map<String, dynamic>) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return user;
  }

  Future<void> uploadProfilePhotoBytes({
    required String uploadUrl,
    required Uint8List bytes,
    required String contentType,
  }) async {
    final uri = Uri.parse(uploadUrl);

    try {
      final request = await _httpClient.putUrl(uri);
      request.headers.set(HttpHeaders.contentTypeHeader, contentType);
      request.contentLength = bytes.length;
      request.add(bytes);
      final response = await request.close().timeout(_requestTimeout);
      await response.drain<void>();

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw const ApiException(
          'Couldn’t upload your photo. Please try again.',
        );
      }
    } on TimeoutException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on SocketException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on HandshakeException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on HttpException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    }
  }

  Future<List<Map<String, dynamic>>> searchUsers({
    required String identityToken,
    required String query,
  }) async {
    final response = await _sendGetRequest(
      path: '/friends/search?q=${Uri.encodeComponent(query)}',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final users = payload['users'];

    if (users is! List) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return users.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchFriends({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/friends',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> sendFriendRequest({
    required String identityToken,
    required String addresseeId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/friends/request',
      body: {'addresseeId': addresseeId},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> respondToFriendRequest({
    required String identityToken,
    required String friendshipId,
    required bool accept,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/friends/request/$friendshipId',
      body: {'accept': accept},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<void> removeFriend({
    required String identityToken,
    required String friendshipId,
  }) async {
    await _sendJsonRequest(
      method: 'DELETE',
      path: '/friends/$friendshipId',
      body: {},
      identityToken: identityToken,
    );
  }

  Future<List<Map<String, dynamic>>> fetchFriendsSteps({
    required String identityToken,
    required String date,
  }) async {
    final response = await _sendGetRequest(
      path: '/friends/steps?date=${Uri.encodeComponent(date)}',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final friends = payload['friends'];

    if (friends is! List) {
      throw const ApiException('Something went wrong. Please try again.');
    }

    return friends.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchLeaderboard({
    required String identityToken,
    String type = 'steps',
    String period = 'today',
    String scope = 'global',
  }) async {
    final uri = Uri(
      path: '/leaderboard',
      queryParameters: {'type': type, 'period': period, 'scope': scope},
    );

    final response = await _sendGetRequest(
      path: uri.toString(),
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRanked({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/ranked',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Weekly-cohort ranked ladder (backend >= June 2026). 404 means the backend
  /// predates v2 — callers fall back to [fetchRanked] and the legacy UI.
  Future<Map<String, dynamic>> fetchRankedV2({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/ranked/v2',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchHomeRaceCard({
    required String identityToken,
    bool usePersistedTotals = false,
  }) async {
    // Opt-in flag: tells the backend this build understands the new
    // ACTIVE_RACES list state (horizontal row of active-race cards). Older app
    // builds never send it and keep receiving the legacy single-state response.
    //
    // localDate: asks the backend to embed `stepMilestones` (same shape as
    // /users/me/step-milestones/today) so the claim-rewards card loads with
    // the rest of the home page instead of racing its own request. Old
    // backends ignore the param; the field is then absent and the milestones
    // widget falls back to its standalone fetch.
    //
    // homePersistedTotals=1 (spec §6.3): opt-in, sent ONLY after a sync-v2 whose
    // uploaderReconciliation was CURRENT. It tells the backend to build active
    // race entries from persisted RaceParticipant.totalSteps instead of
    // recomputing live windows for every participant. An old backend ignores it
    // and keeps live computation, so it is always safe.
    final now = DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    final localDate = '${now.year}-${two(now.month)}-${two(now.day)}';
    final persistedParam = usePersistedTotals ? '&homePersistedTotals=1' : '';
    final response = await _sendGetRequest(
      path:
          '/home/race-card?homeActiveRaces=1&localDate=$localDate'
          '$persistedParam',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchStats({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/steps/stats',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchStepCalendar({
    required String identityToken,
    required String month,
  }) async {
    final response = await _sendGetRequest(
      path: '/steps/calendar?month=$month',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<List<Map<String, dynamic>>> fetchStepsHistory({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/steps',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    final records = payload['records'];
    if (records is! List) return [];
    return records.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> fetchAdminShopItems({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/admin/shop/items',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// GET /admin/settings -> `{settings: {bannerAdsEnabled, ...}}`.
  Future<Map<String, dynamic>> fetchAdminSettings({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/admin/settings',
      identityToken: identityToken,
    );
    final body = await _decodeJsonResponse(response);
    final settings = body['settings'];
    return settings is Map<String, dynamic> ? settings : <String, dynamic>{};
  }

  /// PATCH /admin/settings with a subset of boolean flags; echoes the full
  /// updated settings map.
  Future<Map<String, dynamic>> updateAdminSettings({
    required String identityToken,
    required Map<String, bool> settings,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PATCH',
      path: '/admin/settings',
      body: settings,
      identityToken: identityToken,
    );
    final body = await _decodeJsonResponse(response);
    final updated = body['settings'];
    return updated is Map<String, dynamic> ? updated : <String, dynamic>{};
  }

  /// GET /admin/stats -> `{stats: {...}}` product-health snapshot.
  Future<Map<String, dynamic>> fetchAdminStats({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/admin/stats',
      identityToken: identityToken,
    );
    final body = await _decodeJsonResponse(response);
    final stats = body['stats'];
    return stats is Map<String, dynamic> ? stats : <String, dynamic>{};
  }

  Future<Map<String, dynamic>> updateAdminShopItem({
    required String identityToken,
    required String itemId,
    // Not Map<String, double>: carries non-numeric keys too (renderLayer,
    // animationFrames). The backend sanitizes per-key.
    Map<String, dynamic>? renderMetadata,
    bool? active,
    int? priceCoins,
    bool? testOnly,
    bool? bobble,
  }) async {
    final body = <String, dynamic>{};
    if (renderMetadata != null) body['renderMetadata'] = renderMetadata;
    if (active != null) body['active'] = active;
    if (priceCoins != null) body['priceCoins'] = priceCoins;
    if (testOnly != null) body['testOnly'] = testOnly;
    if (bobble != null) body['bobble'] = bobble;
    final response = await _sendJsonRequest(
      method: 'PATCH',
      path: '/admin/shop/items/$itemId',
      body: body,
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  // -- Admin: powerup shop catalog (spec §5.1) --

  /// `GET /admin/powerup-shop/items`. Null when the backend does not implement
  /// the endpoint (404), which the editor shows as unsupported rather than as
  /// an empty catalog an admin might try to save into.
  Future<List<PowerupShopAdminItem>?> fetchAdminPowerupShopItems({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/admin/powerup-shop/items',
      identityToken: identityToken,
    );
    final raw = await _readRawResponse(response);
    if (raw.statusCode == 404) return null;
    if (raw.statusCode < 200 || raw.statusCode >= 300) {
      throw ApiException(
        _errorMessage(raw) ?? 'Failed to load powerup shop items.',
        statusCode: raw.statusCode,
        code: raw.code,
      );
    }
    final items = raw.json?['items'];
    if (items is! List) return const [];
    return items
        .map(PowerupShopAdminItem.tryParse)
        .whereType<PowerupShopAdminItem>()
        .toList();
  }

  /// `PATCH /admin/powerup-shop/items/:itemId`. Every field is optional but the
  /// contract requires at least one, so an all-null call is refused here rather
  /// than sent for the backend to reject with a 400.
  ///
  /// `name`/`description` are absent by design — `PowerupCopy` owns copy.
  Future<PowerupShopAdminItem?> updateAdminPowerupShopItem({
    required String identityToken,
    required String itemId,
    int? priceCoins,
    bool? active,
    bool? testOnly,
    int? sortOrder,
  }) async {
    final body = <String, dynamic>{
      'priceCoins': ?priceCoins,
      'active': ?active,
      'testOnly': ?testOnly,
      'sortOrder': ?sortOrder,
    };
    if (body.isEmpty) {
      throw const ApiException('Nothing to update.', statusCode: 400);
    }
    final response = await _sendJsonRequest(
      method: 'PATCH',
      path: '/admin/powerup-shop/items/$itemId',
      body: body,
      identityToken: identityToken,
    );
    final payload = await _decodeJsonResponse(response);
    return PowerupShopAdminItem.tryParse(payload['item']);
  }

  // -- Admin: balance config (spec §5.2) --
  //
  // These four endpoints are ADDITIVE and may not exist on the backend serving
  // this build. A definite 404 means "old backend": the editor shows an
  // unsupported notice rather than an empty form that would PUT garbage.

  /// `GET /admin/balance-config`. Returns null when the backend does not
  /// implement the endpoint (404) or sends a body this build can't read.
  Future<AdminBalanceConfig?> fetchAdminBalanceConfig({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/admin/balance-config',
      identityToken: identityToken,
    );
    final raw = await _readRawResponse(response);
    if (raw.statusCode == 404) return null;
    if (raw.statusCode < 200 || raw.statusCode >= 300) {
      throw ApiException(
        _errorMessage(raw) ?? 'Failed to load balance config.',
        statusCode: raw.statusCode,
        code: raw.code,
      );
    }
    return AdminBalanceConfig.tryParse(raw.json);
  }

  /// `GET /admin/balance-config/versions`. An unreadable or absent list is an
  /// empty history, never a crash — history is informational.
  Future<List<BalanceConfigVersion>> fetchAdminBalanceConfigVersions({
    required String identityToken,
    int limit = 50,
  }) async {
    final response = await _sendGetRequest(
      path: '/admin/balance-config/versions?limit=$limit',
      identityToken: identityToken,
    );
    final raw = await _readRawResponse(response);
    if (raw.statusCode < 200 || raw.statusCode >= 300) return const [];
    final versions = raw.json?['versions'];
    if (versions is! List) return const [];
    return versions
        .map(BalanceConfigVersion.tryParse)
        .whereType<BalanceConfigVersion>()
        .toList();
  }

  /// `PUT /admin/balance-config`. 409 and 422 are returned as data (not thrown)
  /// so the editor can re-diff / acknowledge without string-matching an error.
  Future<BalanceConfigSaveResult> saveAdminBalanceConfig({
    required String identityToken,
    required int expectedVersion,
    required Map<String, dynamic> config,
    String? note,
    bool acknowledgeBoundWarnings = false,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/admin/balance-config',
      body: {
        'expectedVersion': expectedVersion,
        'config': config,
        if (note != null && note.isNotEmpty) 'note': note,
        'acknowledgeBoundWarnings': acknowledgeBoundWarnings,
      },
      identityToken: identityToken,
    );
    return _readBalanceSaveResult(await _readRawResponse(response));
  }

  /// `POST /admin/balance-config/rollback`. Same 409 semantics as the PUT.
  Future<BalanceConfigSaveResult> rollbackAdminBalanceConfig({
    required String identityToken,
    required int version,
    required int expectedVersion,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/admin/balance-config/rollback',
      body: {'version': version, 'expectedVersion': expectedVersion},
      identityToken: identityToken,
    );
    return _readBalanceSaveResult(await _readRawResponse(response));
  }

  BalanceConfigSaveResult _readBalanceSaveResult(_RawResponse raw) {
    final body = raw.json;

    if (raw.statusCode == 409) {
      final current = body?['currentVersion'];
      final config = body?['config'];
      return BalanceConfigSaveResult.conflict(
        currentVersion: current is num ? current.toInt() : -1,
        config: config is Map ? Map<String, dynamic>.from(config) : null,
      );
    }

    if (raw.statusCode == 422) {
      final rawWarnings = body?['warnings'];
      final warnings = rawWarnings is List
          ? rawWarnings
                .map(BalanceBoundWarning.tryParse)
                .whereType<BalanceBoundWarning>()
                .toList()
          : <BalanceBoundWarning>[];
      // A 422 with no readable warning list would otherwise present an
      // acknowledge-toggle with nothing to acknowledge.
      if (warnings.isEmpty) {
        return BalanceConfigSaveResult.failed(
          _errorMessage(raw) ?? 'The backend rejected these values.',
        );
      }
      return BalanceConfigSaveResult.boundWarnings(warnings);
    }

    if (raw.statusCode >= 200 && raw.statusCode < 300) {
      final version = body?['version'];
      return BalanceConfigSaveResult.saved(
        version: version is num ? version.toInt() : -1,
      );
    }

    return BalanceConfigSaveResult.failed(
      _errorMessage(raw) ?? 'Save failed (${raw.statusCode}).',
    );
  }

  String? _errorMessage(_RawResponse raw) {
    final error = raw.json?['error'];
    return error is String && error.isNotEmpty ? error : null;
  }

  Future<void> registerDeviceToken({
    required String identityToken,
    required String deviceToken,
    required String platform,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/notifications/device-token',
      body: {'deviceToken': deviceToken, 'platform': platform},
      identityToken: identityToken,
    );

    await _decodeJsonResponse(response);
  }

  // -- Races --

  Future<Map<String, dynamic>> createRace({
    required String identityToken,
    required String name,
    int maxDurationDays = 7,
    bool powerupsEnabled = false,
    int? powerupStepInterval,
    int buyInAmount = 0,
    String payoutPreset = 'WINNER_TAKES_ALL',
    bool isPublic = false,
    // null => no participant limit (unlimited). Sent explicitly as JSON null so
    // the backend can distinguish "unlimited" from an omitted field (which it
    // still defaults to 10 for older clients).
    int? maxParticipants = 10,
    // 1.1.7: optional future auto-start time. Omitted from the body when null so
    // the backend treats it as an instant/manual race (unchanged behavior).
    DateTime? scheduledStartAt,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'maxDurationDays': maxDurationDays,
      'buyInAmount': buyInAmount,
      'payoutPreset': payoutPreset,
      'isPublic': isPublic,
      'maxParticipants': maxParticipants,
    };
    if (powerupsEnabled) {
      body['powerupsEnabled'] = true;
      body['powerupStepInterval'] = powerupStepInterval;
    }
    if (scheduledStartAt != null) {
      body['scheduledStartAt'] = scheduledStartAt.toUtc().toIso8601String();
    }

    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races',
      body: body,
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Creates a TEAM race (TR-101/103/104, contract §3). Separate from
  /// [createRace] so the individual-race wire shape (and every existing
  /// override in tests) stays byte-identical.
  Future<Map<String, dynamic>> createTeamRace({
    required String identityToken,
    required String name,
    required int teamSize,
    int maxDurationDays = 7,
    bool powerupsEnabled = false,
    int? powerupStepInterval,
    int buyInAmount = 0,
    bool isPublic = false,
    DateTime? scheduledStartAt,
    String? teamAName,
    String? teamBName,
    // The creator's chosen side (TR-104); server defaults TEAM_A when omitted.
    String? creatorTeam,
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'maxDurationDays': maxDurationDays,
      'buyInAmount': buyInAmount,
      // TR-102: ignored for team races server-side; stored for display compat.
      'payoutPreset': 'WINNER_TAKES_ALL',
      'isPublic': isPublic,
      // TR-101: the field cap is always 2 x teamSize (server derives it too).
      'maxParticipants': teamSize * 2,
      'isTeamRace': true,
      'teamSize': teamSize,
      'teamAName': ?teamAName,
      'teamBName': ?teamBName,
      // Contract §3: the creator's side rides the `team` key.
      'team': ?creatorTeam,
    };
    if (powerupsEnabled) {
      body['powerupsEnabled'] = true;
      body['powerupStepInterval'] = powerupStepInterval;
    }
    if (scheduledStartAt != null) {
      body['scheduledStartAt'] = scheduledStartAt.toUtc().toIso8601String();
    }

    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races',
      body: body,
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaces({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/races',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaceDetails({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendGetRequest(
      path: '/races/$raceId',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> inviteToRace({
    required String identityToken,
    required String raceId,
    required List<String> inviteeIds,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/invite',
      body: {'inviteeIds': inviteeIds},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> respondToRaceInvite({
    required String identityToken,
    required String raceId,
    required bool accept,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/races/$raceId/respond',
      body: {'accept': accept},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// TR-201: accepts a TEAM-race invite, picking a side. Separate from
  /// [respondToRaceInvite] so existing overrides/signatures stay untouched.
  /// Declines don't need a side — use [respondToRaceInvite] for those.
  Future<Map<String, dynamic>> acceptTeamRaceInvite({
    required String identityToken,
    required String raceId,
    required String team,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/races/$raceId/respond',
      body: {'accept': true, 'team': team},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<List<Map<String, dynamic>>> fetchPublicRaces({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/races/public',
      identityToken: identityToken,
    );
    final decoded = await _decodeJsonResponse(response);
    final races = decoded['races'] as List? ?? [];
    return races.cast<Map<String, dynamic>>();
  }

  /// The live seeded daily/weekly races for the Featured section. Each entry
  /// includes `myStatus` (null when not joined) and `finishReward`. Returns an
  /// empty list on older backends that don't expose the endpoint.
  Future<List<Map<String, dynamic>>> fetchFeaturedRaces({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/races/featured',
      identityToken: identityToken,
    );
    final decoded = await _decodeJsonResponse(response);
    final races = decoded['races'] as List? ?? [];
    return races.cast<Map<String, dynamic>>();
  }

  Future<Map<String, dynamic>> joinPublicRace({
    required String identityToken,
    required String raceId,
    bool onboarding = false,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/join',
      // Only send the onboarding flag when set so older backends that ignore
      // the body keep working; when true the backend grants mystery boxes if
      // eligible (server-enforced).
      body: onboarding ? const {'onboarding': true} : const {},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// TR-201: joins a public TEAM race on a chosen side. Separate from
  /// [joinPublicRace] so existing overrides/signatures stay untouched.
  Future<Map<String, dynamic>> joinPublicRaceOnTeam({
    required String identityToken,
    required String raceId,
    required String team,
    bool onboarding = false,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/join',
      body: {if (onboarding) 'onboarding': true, 'team': team},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// TR-103/TR-801 (contract §3b): a fresh pair of DISTINCT team names from
  /// the real backend pool, for the create screen's plaques + dice-reroll
  /// before the race exists. Read-only and side-effect free — safe to call on
  /// every dice tap.
  ///
  /// Returns null on ANY failure (older backend without the route, offline,
  /// malformed/blank payload) so the caller can fall back to the local preview
  /// pool. Suggestions are cosmetic: they must never block race creation.
  Future<(String, String)?> fetchTeamNameSuggestion({
    required String identityToken,
  }) async {
    try {
      final response = await _sendGetRequest(
        path: '/races/team-names/suggest',
        identityToken: identityToken,
      );
      final payload = await _decodeJsonResponse(response);
      final a = payload['teamAName'];
      final b = payload['teamBName'];
      if (a is String &&
          b is String &&
          a.trim().isNotEmpty &&
          b.trim().isNotEmpty) {
        return (a.trim(), b.trim());
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// TR-205: leaves a PENDING team-race lobby (buy-in hold released;
  /// re-joining later is a fresh join on either side). Team races only —
  /// the backend 400s for individual races and the creator (TR-208).
  Future<Map<String, dynamic>> leaveRace({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/leave',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// TR-601: forfeits an ACTIVE team race. Permanent — steps freeze as-is and
  /// stay in the team total; no refund; no rejoin. A team collapse settles the
  /// race instantly (TR-603), reflected in the returned race state.
  Future<Map<String, dynamic>> forfeitRace({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/forfeit',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// TR-203: switches the caller's side in a PENDING team race. Locked once
  /// ACTIVE (server-enforced); a full destination side answers 409 TEAM_FULL.
  Future<Map<String, dynamic>> setRaceTeam({
    required String identityToken,
    required String raceId,
    required String team,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/races/$raceId/team',
      body: {'team': team},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Mints (or returns the existing) shareable link for [raceId]. The caller
  /// must be an ACCEPTED participant (server-enforced). Returns the backend
  /// payload `{shareToken, url}`; share the `url`.
  Future<Map<String, dynamic>> createRaceShareLink({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/share-link',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  // ---- Tournaments (spec §6) ----------------------------------------------
  // Single-elimination bracket layer over the existing race engine. All new
  // endpoints; the `tournaments` X-Client-Features token gates them. Each method
  // is a small sibling of the race methods above — existing race methods stay
  // byte-identical (the createTeamRace precedent). Callers read every response
  // field defensively via lib/utils/tournament.dart (#1 rule: backend may be a
  // different version than this build).

  /// Creates a tournament (§6.1). `buyInAmount` 0 (free) or 10..max per the D4
  /// ladder; the caller validates against [kTournamentBuyInMax] first. Returns
  /// `{tournament: {...}}`.
  Future<Map<String, dynamic>> createTournament({
    required String identityToken,
    required String name,
    required int bracketSize,
    required int matchupDurationDays,
    int buyInAmount = 0,
    bool powerupsEnabled = false,
    int? powerupStepInterval,
    bool isPublic = false,
    List<String> inviteeIds = const [],
  }) async {
    final body = <String, dynamic>{
      'name': name,
      'bracketSize': bracketSize,
      'matchupDurationDays': matchupDurationDays,
      'buyInAmount': buyInAmount,
      'isPublic': isPublic,
    };
    if (powerupsEnabled) {
      body['powerupsEnabled'] = true;
      body['powerupStepInterval'] = powerupStepInterval;
    }
    if (inviteeIds.isNotEmpty) {
      body['inviteeIds'] = inviteeIds;
    }

    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tournaments',
      body: body,
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Full bracket payload for one tournament (§6.4). Returns `{tournament: {...}}`.
  Future<Map<String, dynamic>> fetchTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    final response = await _sendGetRequest(
      path: '/tournaments/$tournamentId',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Browsable public + featured tournaments (§6.3/§6.10). Returns
  /// `{featured: [...], tournaments: [...]}`; both keys default to `[]` on an
  /// older backend so the public screen simply shows no tournament section.
  Future<Map<String, dynamic>> fetchPublicTournaments({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/tournaments/public',
      identityToken: identityToken,
    );
    final decoded = await _decodeJsonResponse(response);
    return {
      'featured': (decoded['featured'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false),
      'tournaments': (decoded['tournaments'] as List? ?? const [])
          .whereType<Map>()
          .map((e) => e.cast<String, dynamic>())
          .toList(growable: false),
    };
  }

  /// Public join of an open bracket (§6.2). Returns the full tournament payload.
  Future<Map<String, dynamic>> joinTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tournaments/$tournamentId/join',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Share-link join (§6.2) — possession of the token IS the invite (bypasses
  /// `isPublic`). Returns the full tournament payload.
  Future<Map<String, dynamic>> joinTournamentByShareToken({
    required String identityToken,
    required String token,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tournaments/share/$token/join',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Unauthed preview of a shared tournament (§6.2), for the pre-join screen.
  /// Returns the `tournament` preview map (name/bracketSize/filled/buyIn), or an
  /// empty map on 404 / older backend so callers default safely.
  Future<Map<String, dynamic>> fetchSharedTournament({
    required String token,
    String? identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/tournaments/share/$token',
      identityToken: identityToken,
    );
    final body = await _decodeJsonResponse(response);
    final tournament = body['tournament'];
    return tournament is Map<String, dynamic>
        ? tournament
        : <String, dynamic>{};
  }

  /// Accept/decline a tournament invite (§6.2). Accept holds the buy-in.
  Future<Map<String, dynamic>> respondToTournamentInvite({
    required String identityToken,
    required String tournamentId,
    required bool accept,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/tournaments/$tournamentId/respond',
      body: {'accept': accept},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Creator-only post-create invites (§6.2). Returns
  /// `{invited: [...], needsUpdate: [...]}` (plus the tournament payload) so the
  /// lobby can explain skipped old-client friends.
  Future<Map<String, dynamic>> inviteToTournament({
    required String identityToken,
    required String tournamentId,
    required List<String> userIds,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tournaments/$tournamentId/invite',
      body: {'userIds': userIds},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Leave a PENDING lobby (§6.2) — refunds the held buy-in; creator must
  /// cancel instead.
  Future<Map<String, dynamic>> leaveTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tournaments/$tournamentId/leave',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Creator-only kick from a PENDING lobby (§6.2) — soft-removes + refunds.
  Future<Map<String, dynamic>> kickTournamentParticipant({
    required String identityToken,
    required String tournamentId,
    required String userId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tournaments/$tournamentId/kick',
      body: {'userId': userId},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Creator-only manual start (§6.5) — allowed only when the bracket is full.
  Future<Map<String, dynamic>> startTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tournaments/$tournamentId/start',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Forfeit my live matchup (§6.7) — opponent advances, no refund. Returns the
  /// updated tournament payload.
  Future<Map<String, dynamic>> forfeitTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tournaments/$tournamentId/forfeit',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Creator-only cancel of a PENDING bracket (§6.8) — refunds every held
  /// buy-in.
  Future<void> cancelTournament({
    required String identityToken,
    required String tournamentId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'DELETE',
      path: '/tournaments/$tournamentId',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    await _decodeJsonResponse(response);
  }

  /// Mints (or returns) the shareable link for a tournament. Returns the backend
  /// payload `{shareToken, url}`; share the `url`. Mirrors [createRaceShareLink].
  Future<Map<String, dynamic>> createTournamentShareLink({
    required String identityToken,
    required String tournamentId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tournaments/$tournamentId/share-link',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  // ---- Referrals ----------------------------------------------------------
  // All additive: older backends 404 these and callers degrade gracefully (like
  // fetchFeaturedRaces / markRaceResultsSeen). See REFERRAL_FEATURE_RESEARCH.md.

  /// Lazily mints (or returns) the signed-in user's stable referral code and the
  /// canonical share URL. POST /referrals/link -> `{code, url}`.
  Future<Map<String, dynamic>> createReferralLink({
    required String identityToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/referrals/link',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// The signed-in user's referral dashboard. GET /referrals/me ->
  /// `{code, url, referredCount, completedCount, coinsEarned, friends:[...]}`.
  /// Callers read defensively — fields may be absent on an older backend.
  Future<Map<String, dynamic>> fetchReferralStatus({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/referrals/me',
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Attaches a referrer AFTER sign-in (the manual-entry / iOS-paste path, where
  /// the code wasn't in the provision body). POST /referrals/redeem ->
  /// `{attributed: bool, reason?: String}`.
  Future<Map<String, dynamic>> redeemReferralCode({
    required String identityToken,
    required String code,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/referrals/redeem',
      body: {'referralCode': code},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Public, unauthenticated preview of an invite code for the tailored welcome.
  /// GET /referrals/:code -> `{referral: {inviterName, inviterAvatar, rewardCoins}}`.
  /// Returns an empty map for an unknown/invalid code or an older backend, so
  /// callers can default safely.
  Future<Map<String, dynamic>> fetchReferralPreview({
    required String code,
  }) async {
    try {
      final response = await _sendGetRequest(
        path: '/referrals/${Uri.encodeComponent(code)}',
      );
      final body = await _decodeJsonResponse(response);
      final referral = body['referral'];
      return referral is Map<String, dynamic> ? referral : <String, dynamic>{};
    } on ApiException {
      return <String, dynamic>{};
    }
  }

  /// Fetches the public preview of a shared race by its share [token]. Used by
  /// the pre-join screen. No auth required, but we forward the token when
  /// signed in (harmless, and lets the backend personalize later). Returns the
  /// `race` preview map, or throws [ApiException] (404 for an unknown/revoked
  /// link).
  Future<Map<String, dynamic>> fetchSharedRace({
    required String token,
    String? identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/races/share/$token',
      identityToken: identityToken,
    );
    final body = await _decodeJsonResponse(response);
    final race = body['race'];
    return race is Map<String, dynamic> ? race : <String, dynamic>{};
  }

  /// Joins the race behind a shared [token]. Works for private races too
  /// (possession of the token IS the invite). Mirrors [joinPublicRace]'s
  /// onboarding flag. Returns the backend payload, which includes `raceId`.
  Future<Map<String, dynamic>> joinRaceByShareToken({
    required String identityToken,
    required String token,
    bool onboarding = false,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/share/$token/join',
      body: onboarding ? const {'onboarding': true} : const {},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// TR-201: joins a TEAM race behind a share [token], picking a side.
  /// Separate from [joinRaceByShareToken] so existing overrides stay valid.
  Future<Map<String, dynamic>> joinRaceByShareTokenOnTeam({
    required String identityToken,
    required String token,
    required String team,
    bool onboarding = false,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/share/$token/join',
      body: {if (onboarding) 'onboarding': true, 'team': team},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Additive v2 activation contract. Callers must treat a 404 as an older
  /// backend and hide the reward surface without blocking the race.
  Future<Map<String, dynamic>> fetchStarterReward({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/onboarding/starter-reward',
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Claims the shared tutorial_complete ledger grant. The backend is the
  /// authority for eligibility, membership and deduplication.
  Future<Map<String, dynamic>> claimStarterReward({
    required String identityToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/onboarding/starter-reward/claim',
      body: const {},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Best-effort activation telemetry. The queueing service allowlists all
  /// names/context before this reaches the wire; navigation never awaits it.
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async {
    if (events.isEmpty) return;
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/analytics/activation-events',
      body: {'events': events},
      identityToken: identityToken,
    );
    await _decodeJsonResponse(response);
  }

  /// Marks the first-race onboarding step as seen for the current user.
  /// Idempotent; used by the skip path. No request body.
  Future<void> markFirstRaceOnboardingSeen({
    required String identityToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/onboarding/first-race-seen',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    _decodeJsonResponse(response);
  }

  /// Grants the one-time 100-coin tutorial-completion reward and marks the
  /// tutorial onboarding step seen. Idempotent server-side (the backend dedups
  /// on the coin ledger), so replays / reinstalls never re-grant. Returns
  /// `{granted: bool, coins: int}` where `coins` is the resulting balance.
  Future<Map<String, dynamic>> claimTutorialReward({
    required String identityToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tutorial/complete-reward',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Marks the tutorial onboarding step seen without granting (the skip path).
  /// Idempotent; no request body. Mirrors [markFirstRaceOnboardingSeen].
  Future<void> markTutorialOnboardingSeen({
    required String identityToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/tutorial/onboarding-seen',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    _decodeJsonResponse(response);
  }

  /// Acknowledges that the user has seen the results popup for the given
  /// finished races. Additive endpoint: older backends 404 here and the popup
  /// simply re-shows next session, so tolerate any non-2xx (or network error)
  /// silently rather than surfacing it to the user.
  Future<void> markRaceResultsSeen({
    required String identityToken,
    required List<String> raceIds,
  }) async {
    if (raceIds.isEmpty) return;
    try {
      final response = await _sendJsonRequest(
        method: 'POST',
        path: '/races/results/seen',
        body: {'raceIds': raceIds},
        identityToken: identityToken,
      );
      await _decodeJsonResponse(response);
    } catch (_) {
      // Best-effort ack; never disrupt the UI if it fails.
    }
  }

  /// Acks the post-settlement ranked-week summary popup for one settled week.
  /// Best-effort, display-only (sibling of [markRaceResultsSeen]). A backend
  /// that predates the endpoint (or the weekIndex no longer existing) is a
  /// harmless no-op — the local seen flag still suppresses re-show this session.
  Future<void> markRankedResultsSeen({
    required String identityToken,
    required int weekIndex,
  }) async {
    try {
      final response = await _sendJsonRequest(
        method: 'POST',
        path: '/ranked/results/seen',
        body: {'weekIndex': weekIndex},
        identityToken: identityToken,
      );
      await _decodeJsonResponse(response);
    } catch (_) {
      // Best-effort ack; never disrupt the UI if it fails.
    }
  }

  Future<void> kickRaceParticipant({
    required String identityToken,
    required String raceId,
    required String userId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'DELETE',
      path: '/races/$raceId/participants/$userId',
      body: const {},
      identityToken: identityToken,
    );
    _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> startRace({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/start',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaceProgress({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendGetRequest(
      path: '/races/$raceId/progress',
      identityToken: identityToken,
    );

    final payload = await _decodeJsonResponse(response);
    return payload['progress'] as Map<String, dynamic>;
  }

  Future<void> cancelRace({
    required String identityToken,
    required String raceId,
  }) async {
    await _sendJsonRequest(
      method: 'DELETE',
      path: '/races/$raceId',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
  }

  Future<Map<String, dynamic>> updateRace({
    required String identityToken,
    required String raceId,
    String? name,
    int? maxDurationDays,
    bool? isPublic,
    bool? powerupsEnabled,
    int? powerupStepInterval,
    int? buyInAmount,
    String? payoutPreset,
    int? maxParticipants,
    // When true, send maxParticipants: null explicitly to set the race to
    // "no limit" (unlimited). Needed because a null value can't otherwise be
    // distinguished from "unchanged" in this sparse PATCH body.
    bool setMaxParticipantsUnlimited = false,
    // TR-105: team names and size are editable while PENDING. isTeamRace
    // itself is immutable and intentionally has no parameter here.
    String? teamAName,
    String? teamBName,
    int? teamSize,
  }) async {
    final body = <String, dynamic>{};
    if (name != null) body['name'] = name;
    if (teamAName != null) body['teamAName'] = teamAName;
    if (teamBName != null) body['teamBName'] = teamBName;
    if (teamSize != null) body['teamSize'] = teamSize;
    if (maxDurationDays != null) body['maxDurationDays'] = maxDurationDays;
    if (isPublic != null) body['isPublic'] = isPublic;
    if (powerupsEnabled != null) body['powerupsEnabled'] = powerupsEnabled;
    if (powerupStepInterval != null) {
      body['powerupStepInterval'] = powerupStepInterval;
    }
    if (buyInAmount != null) body['buyInAmount'] = buyInAmount;
    if (payoutPreset != null) body['payoutPreset'] = payoutPreset;
    if (setMaxParticipantsUnlimited) {
      body['maxParticipants'] = null;
    } else if (maxParticipants != null) {
      body['maxParticipants'] = maxParticipants;
    }

    final response = await _sendJsonRequest(
      method: 'PATCH',
      path: '/races/$raceId',
      body: body,
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> usePowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
    String? targetUserId,
    String? targetDirection,
    String? targetEffectId,
    int upgradeLevel = 0,
  }) async {
    // Sneaky Swap's retired swapOfferedPowerupId/swapRequestedPowerupId are
    // gone: the steal redesign is target-only, and the server ignores the
    // legacy ids anyway.
    final body = <String, dynamic>{};
    if (targetUserId != null) body['targetUserId'] = targetUserId;
    if (targetDirection != null) body['targetDirection'] = targetDirection;
    // §6.3: OMITTED entirely for the legacy self-buff path, so a request from
    // this build is byte-identical to an older binary's unless the user
    // explicitly picked a rival debuff to extend.
    if (targetEffectId != null) body['targetEffectId'] = targetEffectId;
    if (upgradeLevel > 0) body['upgradeLevel'] = upgradeLevel;

    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/powerups/$powerupId/use',
      body: body,
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Returns the participants the user could Sneaky Swap with right now — only
  /// those holding >=1 stealable powerup (not self, stealthed, or finished).
  /// Additive endpoint; older backends 404 here, so callers should fall back to
  /// the existing eligible-racer behavior on failure.
  Future<Map<String, dynamic>> fetchSneakySwapTargets({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendGetRequest(
      path: '/races/$raceId/powerups/sneaky-swap-targets',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> openMysteryBox({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/powerups/$powerupId/open',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Opens several mystery boxes in one call (item #1 "Open All"): the given
  /// slot [powerupIds] plus, when [includeQueued] is true, up to [maxCount]
  /// server-materialized queued/overflow boxes. Mirrors the single-open result
  /// shape per box so the reveal reuses existing code. Additive endpoint —
  /// older backends 404 here, so callers MUST feature-detect and fall back to N
  /// single `/open` calls (and omit queued, which have no client-side ids).
  Future<Map<String, dynamic>> openMysteryBoxBatch({
    required String identityToken,
    required String raceId,
    required List<String> powerupIds,
    bool includeQueued = true,
    int maxCount = 20,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/powerups/open-batch',
      body: <String, dynamic>{
        'powerupIds': powerupIds,
        'includeQueued': includeQueued,
        'maxCount': maxCount,
      },
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> discardPowerup({
    required String identityToken,
    required String raceId,
    required String powerupId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/powerups/$powerupId/discard',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaceInventory({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendGetRequest(
      path: '/races/$raceId/inventory',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaceFeed({
    required String identityToken,
    required String raceId,
    String? cursor,
  }) async {
    final query = cursor != null
        ? '?cursor=${Uri.encodeComponent(cursor)}'
        : '';
    final response = await _sendGetRequest(
      path: '/races/$raceId/feed$query',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchRaceMessages({
    required String identityToken,
    required String raceId,
    String? cursor,
    int? limit,
    String? kind, // 'USER' | 'SYSTEM'; omitted => merged feed (legacy).
  }) async {
    final params = <String, String>{};
    if (cursor != null) params['cursor'] = cursor;
    if (limit != null) params['limit'] = '$limit';
    if (kind != null) params['kind'] = kind;
    final query = params.isEmpty
        ? ''
        : '?${params.entries.map((e) => '${e.key}=${Uri.encodeComponent(e.value)}').join('&')}';
    final response = await _sendGetRequest(
      path: '/races/$raceId/messages$query',
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> sendRaceMessage({
    required String identityToken,
    required String raceId,
    required String body,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/messages',
      body: {'body': body},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> deleteRaceMessage({
    required String identityToken,
    required String raceId,
    required String messageId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'DELETE',
      path: '/races/$raceId/messages/$messageId',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> setRaceChatMute({
    required String identityToken,
    required String raceId,
    required bool muted,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/races/$raceId/chat/mute',
      body: {'muted': muted},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  /// Per-race opt-out for live placement-change pushes. Additive endpoint
  /// (backend default false); only newer builds call it.
  Future<Map<String, dynamic>> setRacePlacementMute({
    required String identityToken,
    required String raceId,
    required bool muted,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/races/$raceId/placement/mute',
      body: {'muted': muted},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> markRaceChatRead({
    required String identityToken,
    required String raceId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/chat/read',
      body: const <String, dynamic>{},
      identityToken: identityToken,
    );
    return _decodeJsonResponse(response);
  }

  // -- Shop --

  Future<Map<String, dynamic>> fetchDailyRewardStatus({
    required String identityToken,
    required String localDate,
  }) async {
    final response = await _sendGetRequest(
      path: '/daily-reward/status?localDate=$localDate',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> claimDailyReward({
    required String identityToken,
    required String localDate,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/daily-reward/claim',
      body: {'localDate': localDate},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Daily reward v2: rolls a mystery box whose odds scale with the login
  /// streak. Only call when the status response includes the `box` field —
  /// older backends don't have this endpoint.
  Future<Map<String, dynamic>> claimDailyRewardBox({
    required String identityToken,
    required String localDate,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/daily-reward/claim-box',
      body: {'localDate': localDate},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Extra daily box spin, unlocked by a verified rewarded-ad watch. Only call
  /// when the status response carries `adExtraSpin` — older backends 404 this.
  /// A 409 shortly after the ad means the server-side verification hasn't
  /// landed yet; callers retry briefly.
  Future<Map<String, dynamic>> claimExtraDailyRewardBox({
    required String identityToken,
    required String localDate,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/daily-reward/claim-extra-box',
      body: {'localDate': localDate},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Watch-ad-for-coins (Get Coins hub), paid by a verified rewarded-ad
  /// watch. Only call when the status response carries `adCoinReward` — older
  /// backends 404 this. A 409 shortly after the ad means the server-side
  /// verification hasn't landed yet; callers retry briefly.
  Future<Map<String, dynamic>> claimAdCoinReward({
    required String identityToken,
    required String localDate,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/coins/claim-ad-reward',
      body: {'localDate': localDate},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/shop/catalog',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> purchaseShopItem({
    required String identityToken,
    required String itemId,
    required String idempotencyKey,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/shop/items/$itemId/purchase',
      body: const <String, dynamic>{},
      identityToken: identityToken,
      headers: {'Idempotency-Key': idempotencyKey},
    );

    return _decodeJsonResponse(response);
  }

  /// Active coin-purchasable powerups + coin balance + per-type owned quantity.
  /// Additive endpoint; older backends 404 here, so callers must degrade
  /// gracefully (hide the powerup store section, no crash).
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/shop/powerups',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Buys a (re-buyable) powerup from the coin store. Idempotent via the
  /// Idempotency-Key header. Returns the updated balance + inventory.
  Future<Map<String, dynamic>> purchasePowerupItem({
    required String identityToken,
    String? sku,
    String? powerupType,
    required String idempotencyKey,
  }) async {
    final body = <String, dynamic>{};
    if (sku != null) body['sku'] = sku;
    if (powerupType != null) body['powerupType'] = powerupType;

    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/shop/powerups/purchase',
      body: body,
      identityToken: identityToken,
      headers: {'Idempotency-Key': idempotencyKey},
    );

    return _decodeJsonResponse(response);
  }

  /// The user's GLOBAL powerup inventory (powerupType + quantity). Additive
  /// endpoint; older backends 404 here, so callers must degrade gracefully.
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async {
    final response = await _sendGetRequest(
      path: '/powerups/inventory',
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  /// Spends ONE global-inventory powerup into an active race, creating a HELD
  /// in-race powerup that the normal use flow then applies. Additive endpoint.
  Future<Map<String, dynamic>> redeemPowerupToRace({
    required String identityToken,
    required String raceId,
    required String powerupType,
  }) async {
    final response = await _sendJsonRequest(
      method: 'POST',
      path: '/races/$raceId/powerups/redeem',
      body: {'powerupType': powerupType},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<Map<String, dynamic>> equipAccessory({
    required String identityToken,
    required String slot,
    required String? itemId,
  }) async {
    final response = await _sendJsonRequest(
      method: 'PUT',
      path: '/shop/equipment/$slot',
      body: {'itemId': itemId},
      identityToken: identityToken,
    );

    return _decodeJsonResponse(response);
  }

  Future<void> unregisterDeviceToken({
    required String identityToken,
    required String deviceToken,
  }) async {
    final response = await _sendJsonRequest(
      method: 'DELETE',
      path: '/notifications/device-token',
      body: {'deviceToken': deviceToken},
      identityToken: identityToken,
    );

    await _decodeJsonResponse(response);
  }

  Future<HttpClientResponse> _sendGetRequest({
    required String path,
    String? identityToken,
  }) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}$path');

    try {
      final request = await _httpClient.openUrl('GET', uri);
      if (identityToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $identityToken',
        );
      }
      request.headers.set('X-Timezone', await _getTimeZone());
      request.headers.set('X-Release-Channel', await _getReleaseChannel());
      request.headers.set('X-App-Version', await _getAppVersion());
      // Declares renderable feature set; the backend hides CHARACTER-slot shop
      // items (base animals) and the rewarded-ad extra-spin offer from clients
      // that don't send the matching capability.
      request.headers.set('X-Client-Features', clientFeaturesHeader);
      return await request.close().timeout(_requestTimeout);
    } on SocketException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on TimeoutException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on HandshakeException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on HttpException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    }
  }

  Future<HttpClientResponse> _sendJsonRequest({
    required String method,
    required String path,
    required Map<String, dynamic> body,
    String? identityToken,
    Map<String, String>? headers,
  }) async {
    final uri = Uri.parse('${BackendConfig.baseUrl}$path');

    try {
      final request = await _httpClient.openUrl(method, uri);

      request.headers.contentType = ContentType.json;

      if (identityToken != null) {
        request.headers.set(
          HttpHeaders.authorizationHeader,
          'Bearer $identityToken',
        );
      }
      request.headers.set('X-Timezone', await _getTimeZone());
      request.headers.set('X-Release-Channel', await _getReleaseChannel());
      request.headers.set('X-App-Version', await _getAppVersion());
      // Declares renderable feature set; the backend hides CHARACTER-slot shop
      // items (base animals) and the rewarded-ad extra-spin offer from clients
      // that don't send the matching capability.
      request.headers.set('X-Client-Features', clientFeaturesHeader);
      headers?.forEach(request.headers.set);

      request.write(jsonEncode(body));

      return await request.close().timeout(_requestTimeout);
    } on SocketException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on TimeoutException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on HandshakeException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    } on HttpException catch (error) {
      throw ApiException(describeBackendConnectionError(error, uri: uri));
    }
  }

  Future<Map<String, dynamic>> _decodeJsonResponse(
    HttpClientResponse response,
  ) async {
    final rawBody = await response.transform(utf8.decoder).join();
    final parsedBody = rawBody.isEmpty
        ? <String, dynamic>{}
        : jsonDecode(rawBody) as Map<String, dynamic>;

    if (response.statusCode >= 200 && response.statusCode < 300) {
      return parsedBody;
    }

    final message = parsedBody['error'];
    // Optional machine-readable code (team-race errors and future features).
    // Read defensively: absent on older backends.
    final rawCode = parsedBody['code'];
    final code = rawCode is String && rawCode.isNotEmpty ? rawCode : null;

    if (message is String && message.isNotEmpty) {
      throw ApiException(message, statusCode: response.statusCode, code: code);
    }

    throw ApiException(
      'Something went wrong. Please try again.',
      statusCode: response.statusCode,
      code: code,
    );
  }

  /// Reads a response body WITHOUT throwing on a non-2xx status or malformed
  /// body — the additive endpoints need to branch on the raw status/code and
  /// treat an unparseable success as a distinct outcome. `decodeFailed` is true
  /// when a non-empty body was not a JSON object.
  Future<_RawResponse> _readRawResponse(HttpClientResponse response) async {
    final rawBody = await response.transform(utf8.decoder).join();
    Map<String, dynamic>? json;
    var decodeFailed = false;
    if (rawBody.isNotEmpty) {
      try {
        final decoded = jsonDecode(rawBody);
        if (decoded is Map<String, dynamic>) {
          json = decoded;
        } else {
          decodeFailed = true;
        }
      } catch (_) {
        decodeFailed = true;
      }
    }
    final rawCode = json?['code'];
    final code = rawCode is String && rawCode.isNotEmpty ? rawCode : null;
    return _RawResponse(response.statusCode, json, code, decodeFailed);
  }

  String _formatDate(DateTime date) {
    final month = date.month.toString().padLeft(2, '0');
    final day = date.day.toString().padLeft(2, '0');

    return '${date.year}-$month-$day';
  }
}

/// A read HTTP response that does not throw on non-2xx/malformed bodies, so the
/// additive endpoints can branch on status/code defensively.
class _RawResponse {
  const _RawResponse(this.statusCode, this.json, this.code, this.decodeFailed);
  final int statusCode;
  final Map<String, dynamic>? json;
  final String? code;
  final bool decodeFailed;
}
