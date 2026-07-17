import 'dart:async';

import 'package:app_links/app_links.dart';
import 'package:flutter/foundation.dart';

import 'auth_service.dart';

/// The app's custom URL scheme, registered in Info.plist (iOS) and
/// AndroidManifest (Android). Used by the landing page's "Open in app" button
/// (`bara://join/<token>`) as the reliable re-tap after install.
const String kAppUrlScheme = 'bara';

/// Reserved prefix marking a referral code (vs a race share token). Both ride
/// the same `/r/<...>` path; this prefix is the disambiguator. Race share tokens
/// are hyphen-free, so they never collide with it. Mirrors the backend
/// `REFERRAL_CODE_PREFIX` in src/lib/referralCode.js.
const String kReferralCodePrefix = 'BARA-';

/// Captures race share links — both Universal/App Links
/// (`https://<host>/r/<token>`) and the custom-scheme deep link
/// (`bara://join/<token>`) — and turns them into a pending share token.
///
/// The token is persisted to [AuthService] immediately (so it survives a fresh
/// install's sign-in/onboarding gap) and surfaced via [pendingToken] so a live,
/// already-running app can react at once. The actual join happens at a single
/// drain point (MainShell), regardless of which path captured the token.
class DeepLinkService {
  DeepLinkService({required AuthService authService, AppLinks? appLinks})
    : _authService = authService,
      _appLinks = appLinks ?? AppLinks();

  final AuthService _authService;
  final AppLinks _appLinks;
  StreamSubscription<Uri>? _subscription;

  /// The most recently captured-but-undrained token. MainShell listens to this
  /// to join immediately when a link is tapped while the app is already open.
  final ValueNotifier<String?> pendingToken = ValueNotifier<String?>(null);

  /// The most recently captured-but-undrained TOURNAMENT share token (`/t/…`).
  /// Kept on a separate notifier + AuthService slot so a race link and a
  /// tournament link never clobber each other.
  final ValueNotifier<String?> pendingTournamentToken =
      ValueNotifier<String?>(null);

  /// Shared extraction of the `<token>` from a `/r/<token>` (https) or
  /// `bara://join|race/<token>` / `bara:///r/<token>` (custom scheme) link.
  /// Returns the raw (un-normalized) token, or null. The charset guard bounds
  /// characters + length; the backend is the source of truth (it 404s unknown
  /// tokens) — this just stops us persisting obvious garbage.
  static String? _extractRToken(Uri uri) {
    bool isValid(String t) =>
        t.isNotEmpty && RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(t);

    String? fromRPath(List<String> segments) {
      if (segments.length >= 2 && segments[0] == 'r' && isValid(segments[1])) {
        return segments[1];
      }
      return null;
    }

    if (uri.scheme == 'https' || uri.scheme == 'http') {
      // Universal/App Link: https://<host>/r/<token>
      return fromRPath(uri.pathSegments);
    }

    if (uri.scheme == kAppUrlScheme) {
      // Custom scheme: bara://join/<token> or bara://race/<token>. The action
      // lands in `host`, the token in the first path segment.
      if ((uri.host == 'join' || uri.host == 'race') &&
          uri.pathSegments.isNotEmpty &&
          isValid(uri.pathSegments.first)) {
        return uri.pathSegments.first;
      }
      // Also tolerate bara:///r/<token>.
      return fromRPath(uri.pathSegments);
    }

    return null;
  }

  /// Shared extraction of the `<token>` from a `/t/<token>` (https) or
  /// `bara://tournament/<token>` / `bara:///t/<token>` (custom scheme) link —
  /// the tournament analog of [_extractRToken]. Returns the raw token or null.
  static String? _extractTToken(Uri uri) {
    bool isValid(String t) =>
        t.isNotEmpty && RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(t);

    String? fromTPath(List<String> segments) {
      if (segments.length >= 2 && segments[0] == 't' && isValid(segments[1])) {
        return segments[1];
      }
      return null;
    }

    if (uri.scheme == 'https' || uri.scheme == 'http') {
      // Universal/App Link: https://<host>/t/<token>
      return fromTPath(uri.pathSegments);
    }

    if (uri.scheme == kAppUrlScheme) {
      // Custom scheme: bara://tournament/<token>. The action lands in `host`,
      // the token in the first path segment.
      if (uri.host == 'tournament' &&
          uri.pathSegments.isNotEmpty &&
          isValid(uri.pathSegments.first)) {
        return uri.pathSegments.first;
      }
      // Also tolerate bara:///t/<token>.
      return fromTPath(uri.pathSegments);
    }

    return null;
  }

  /// Pure URI -> tournament share-token extraction (`/t/<token>` or
  /// `bara://tournament/<token>`). Side-effect-free + unit-testable. Returns
  /// null for anything that isn't a tournament share link.
  static String? parseTournamentShareToken(Uri uri) => _extractTToken(uri);

  /// Pure URI -> race share-token extraction. Static + side-effect-free so it's
  /// trivially unit-testable. Returns null for any link that isn't a race share
  /// link — including a referral invite (`/r/BARA-…`), which [parseReferralCode]
  /// owns instead, so we never try to "join a race" with a referral code.
  static String? parseShareToken(Uri uri) {
    final token = _extractRToken(uri);
    if (token == null) return null;
    if (token.toUpperCase().startsWith(kReferralCodePrefix)) return null;
    return token;
  }

  /// Pure URI -> referral-code extraction. Returns the normalized (uppercased)
  /// referral code if [uri] is a referral invite (`/r/BARA-xxxx` or
  /// `bara://join/BARA-xxxx`), else null. Side-effect-free + unit-testable.
  static String? parseReferralCode(Uri uri) {
    final token = _extractRToken(uri);
    if (token == null) return null;
    final upper = token.toUpperCase();
    if (!upper.startsWith(kReferralCodePrefix)) return null;
    // Prefix + alphanumeric body, within the share-token charset.
    if (!RegExp(r'^BARA-[A-Z0-9]{2,32}$').hasMatch(upper)) return null;
    return upper;
  }

  /// Begins listening for links: the cold-start link (if the app was launched
  /// by a link) plus the warm stream (links tapped while running). Safe to call
  /// once at startup. Never throws — a deep-link failure must not block launch.
  Future<void> initialize() async {
    try {
      final initial = await _appLinks.getInitialLink();
      if (initial != null) {
        await handleLink(initial);
      }
    } catch (error) {
      debugPrint('DeepLinkService initial link error: $error');
    }

    _subscription = _appLinks.uriLinkStream.listen(
      (uri) {
        // Fire-and-forget: the persistence is idempotent and order-independent.
        handleLink(uri);
      },
      onError: (Object error) {
        debugPrint('DeepLinkService stream error: $error');
      },
    );
  }

  /// Parses [uri], and if it carries a share token, persists it and pushes it
  /// onto [pendingToken]. Public so it can be unit-tested directly without the
  /// platform plugin.
  Future<void> handleLink(Uri uri) async {
    // A referral invite and a race share link ride the same /r/ path; the
    // BARA- prefix routes them apart. Referral attribution is captured but does
    // NOT push pendingToken (there's no race to auto-join).
    final referralCode = parseReferralCode(uri);
    if (referralCode != null) {
      await _authService.setPendingReferralCode(referralCode);
      return;
    }

    // A tournament share link (`/t/<token>`) rides its own path + slot.
    final tournamentToken = parseTournamentShareToken(uri);
    if (tournamentToken != null) {
      await _authService.setPendingTournamentShareToken(tournamentToken);
      pendingTournamentToken.value = tournamentToken;
      return;
    }

    final token = parseShareToken(uri);
    if (token == null) return;
    await _authService.setPendingShareToken(token);
    pendingToken.value = token;
  }

  void dispose() {
    _subscription?.cancel();
    pendingToken.dispose();
    pendingTournamentToken.dispose();
  }
}
