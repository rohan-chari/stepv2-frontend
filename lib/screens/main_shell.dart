import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../config/animals.dart';
import '../models/loadable.dart';
import '../models/step_data.dart';
import '../models/step_sample_data.dart';
import '../services/async_ttl_cache.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/background_sync_bootstrap_service.dart';
import '../services/health_service.dart';
import '../services/notification_service.dart';
import '../services/review_prompt_service.dart';
import '../utils/team_race.dart';
import '../utils/tournament.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/info_toast.dart';
import '../widgets/team_side_picker.dart';
import '../widgets/step_milestones_section.dart';
import '../widgets/streak_chip.dart';
import '../widgets/wooden_tab_bar.dart';
import 'race_results_summary_screen.dart';
import 'ranked_results_summary_screen.dart';
import 'start_screen.dart';
import 'onboarding_flow.dart';
import '../tutorial/tutorial_screen.dart';
import 'tabs/friends_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/leaderboard_tab.dart';
import 'tabs/profile_tab.dart';
import 'create_race_screen.dart';
import 'race_detail_screen.dart';
import 'tournament_detail_screen.dart';
import 'tabs/races_tab.dart';
import 'tabs/shop_tab.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.authService,
    this.healthService,
    this.backendApiService,
    this.backgroundSyncBootstrapService,
    this.notificationService,
    this.reviewPromptService,
  });

  final AuthService authService;
  final HealthService? healthService;
  final BackendApiService? backendApiService;
  final BackgroundSyncBootstrapService? backgroundSyncBootstrapService;
  final NotificationService? notificationService;
  final ReviewPromptService? reviewPromptService;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const _homeTabIndex = 0;
  static const _racesTabIndex = 1;
  static const _friendsTabIndex = 2;
  static const _boardsTabIndex = 3;
  static const _profileTabIndex = 4;

  late final HealthService _healthService;
  late final BackendApiService _backendApiService;
  late final BackgroundSyncBootstrapService _backgroundSyncBootstrapService;
  late final ReviewPromptService _reviewPromptService;

  int _currentTab = 0;
  late final PageController _pageController;

  /// Visual height of the single shell-level footer banner (0 while it is
  /// collapsed / unloaded / hidden). The nav tabs inflate their bottom inset by
  /// this much so the banner — an overlay pinned above the tab bar — never
  /// covers scroll content. Reported by the [_MeasureSize] wrapper around the
  /// shell's one [AdBannerSlot].
  final ValueNotifier<double> _bannerHeight = ValueNotifier<double>(0);
  bool _healthAuthorized = false;
  bool?
  _notificationsState; // null = not prompted, true = granted, false = denied
  bool _isLoading = false;
  String? _error;
  StepData? _stepData;
  int _incomingFriendRequests = 0;
  String? _displayName;
  String? _email;
  List<Map<String, dynamic>> _friendsSteps = [];
  Loadable<List<Map<String, dynamic>>> _friendsStepsState =
      const Loadable.initial();
  Map<String, dynamic>? _racesData;
  Loadable<Map<String, dynamic>> _racesState = const Loadable.initial();
  // Live seeded daily/weekly races for the Featured strip on the Races tab.
  List<Map<String, dynamic>> _featuredRaces = const [];
  // D13: featured (seeded) tournaments merged into the races-tab featured row.
  // Best-effort — an older backend / missing `featured` key → empty, so the row
  // simply shows only featured races (no crash, the #1 rule).
  List<Map<String, dynamic>> _featuredTournaments = const [];
  // Count of joinable public races, surfaced inline on the Races tab's PUBLIC
  // RACES button. Defaults to 0; on a fetch error we keep the last known value.
  int _publicRacesCount = 0;
  List<Map<String, dynamic>> _equippedAccessories = const [];
  // Equipped base character assetKey (e.g. 'corgi_puppy'); null = capybara.
  String? _equippedAnimal;
  Loadable<Map<String, dynamic>> _shopCatalogState = const Loadable.initial();
  Map<String, dynamic>? _raceCard;
  bool _raceCardLoading = true;
  final String _requestedLeaderboardType = 'steps';
  final String _requestedLeaderboardPeriod = 'today';
  int _leaderboardSelectionNonce = 0;
  Timer? _foregroundPollTimer;
  final GlobalKey<StreakChipState> _streakChipKey =
      GlobalKey<StreakChipState>();
  final GlobalKey<StepMilestonesSectionState> _stepMilestonesKey =
      GlobalKey<StepMilestonesSectionState>();
  static const Duration _foregroundPollInterval = Duration(minutes: 5);
  // In-flight coalescing for the two full home loads (see the methods): a
  // second trigger while one runs shares its future instead of re-fanning out.
  Future<void>? _homeLoadInFlight;
  Future<void>? _homeRefreshInFlight;
  // Coalesces overlapping Races refreshes (tab reveal, pull, route-return, Home
  // initial load, profile-triggered). A trigger while one runs rides it (§9.4).
  Future<void>? _racesRefreshInFlight;
  // Monotonic generation guarding race-list/discovery state commits so a slower
  // old response can never overwrite a newer refresh (§9.4).
  int _racesGeneration = 0;
  int _discoveryGeneration = 0;
  DateTime? _friendsFetchedAt;
  // 15-minute authenticated-session shop catalog cache (§9.3): fresh reads skip
  // the network, concurrent misses share one request, invalidated on
  // purchase/equip/character change and cleared on sign-out.
  final AsyncTtlCache<Map<String, dynamic>> _shopCatalogCache =
      AsyncTtlCache<Map<String, dynamic>>(ttl: const Duration(minutes: 15));
  // Bounded foreground poll of the durable race-resolution job (§6.5). Never
  // blocks any indicator; stops on terminal state, navigation, pause, or the
  // fourth poll.
  int _jobPollToken = 0;
  // Guards against double-pushing RaceDetailScreen from rapid taps.
  bool _openingRaceDetail = false;
  bool _openingTournament = false;
  bool _drainingTournament = false;
  // Races whose results popup we've already surfaced this session, so a race
  // finishing mid-session (or a re-fetch) doesn't re-interrupt. The server ack
  // (markRaceResultsSeen) is the durable source of truth across sessions.
  final Set<String> _raceResultsShownThisSession = {};
  bool _raceResultsPopupOpen = false;
  // Settled ranked weeks whose summary popup we've surfaced this session, keyed
  // by week index. The server ack (markRankedResultsSeen) is the durable source
  // of truth across sessions; this just prevents a re-fetch re-interrupting.
  final Set<int> _rankedResultsShownThisSession = {};
  bool _rankedResultsPopupOpen = false;
  // The in-app ranked-results popup is intentionally suppressed: settled weeks
  // should never interrupt users (settlement still runs server-side). The
  // detection/popup code below is kept wired (not deleted) behind this flag so
  // it can be re-enabled by flipping it. A non-const field keeps the body live
  // (no dead-code) while making it a no-op.
  final bool _showRankedResultsPopup = false;

  // Guards the shared-race drain so overlapping AuthService notifications can't
  // fire two concurrent joins for the same pending token.
  bool _draining = false;
  // Guards for the referred-install "race your friend" capture + one-tap offer.
  bool _capturingInviterRace = false;
  bool _inviterOfferShowing = false;

  void _handleAuthServiceChanged() {
    if (!mounted) return;
    setState(() {});
    // A share token may have just been captured (link tapped while running) or
    // the final onboarding step may have just completed — either way, try to
    // drain. Idempotent: no-ops when there's no token or onboarding isn't done.
    _maybeDrainPendingSharedRace();
    _maybeDrainPendingSharedTournament();
    _maybeCaptureInviterRace();
    _maybeOfferInviterRace();
  }

  @override
  void initState() {
    super.initState();
    _healthService = widget.healthService ?? HealthService();
    _backendApiService = widget.backendApiService ?? BackendApiService();
    _backgroundSyncBootstrapService =
        widget.backgroundSyncBootstrapService ??
        BackgroundSyncBootstrapService();
    _reviewPromptService = widget.reviewPromptService ?? ReviewPromptService();
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
    widget.authService.addListener(_handleAuthServiceChanged);
    widget.notificationService?.pendingAction.addListener(
      _onNotificationAction,
    );
    _restoreAndFetch();
  }

  @override
  void didUpdateWidget(covariant MainShell oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authService == widget.authService) return;
    oldWidget.authService.removeListener(_handleAuthServiceChanged);
    widget.authService.addListener(_handleAuthServiceChanged);
  }

  @override
  void dispose() {
    widget.authService.removeListener(_handleAuthServiceChanged);
    widget.notificationService?.pendingAction.removeListener(
      _onNotificationAction,
    );
    _foregroundPollTimer?.cancel();
    _jobPollToken += 1; // invalidate any in-flight job polling loop
    _pageController.dispose();
    _bannerHeight.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  void _onNotificationAction() {
    final action = widget.notificationService?.pendingAction.value;
    if (action == null) return;
    widget.notificationService?.pendingAction.value = null;

    switch (action.route) {
      case NotificationRoute.raceDetail:
        final raceId = action.params['raceId'];
        if (raceId != null) {
          // Shares the tap guard so a notification tap can't stack a second
          // detail screen over one already opening.
          _openRaceFromCard(raceId);
        }
        break;
      case NotificationRoute.races:
        _pageController.jumpToPage(_racesTabIndex);
        break;
      case NotificationRoute.friends:
        // Friends is now a primary tab (index 2); jumping there also clears the
        // incoming-request badge via onPageChanged.
        _pageController.jumpToPage(_friendsTabIndex);
        break;
      case NotificationRoute.home:
        _pageController.jumpToPage(_homeTabIndex);
        break;
      case NotificationRoute.tournamentDetail:
        final tournamentId = action.params['tournamentId'];
        if (tournamentId != null && tournamentId.isNotEmpty) {
          _openTournament(tournamentId);
        }
        break;
    }
  }

  /// Joins the race behind a pending share-link token (captured by
  /// [DeepLinkService]) once the user is past onboarding and on the tabs, then
  /// opens it. This is the SINGLE drain point for every capture path — a
  /// cold-start link, a link tapped while the app runs, and the post-onboarding
  /// fresh-install case — because the token flows through [AuthService], which
  /// this shell already observes.
  Future<void> _maybeDrainPendingSharedRace() async {
    if (_draining) return;
    final token = widget.authService.pendingShareToken;
    if (token == null || token.isEmpty) return;

    // Wait until onboarding is fully complete; joining + navigating over the
    // onboarding overlay would be wrong. Mirrors build()'s isOnboarding gate.
    final isOnboarding =
        !_healthAuthorized ||
        _notificationsState == null ||
        !widget.authService.firstRaceOnboardingSeen;
    if (isOnboarding) return;

    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;

    _draining = true;
    String? raceId;
    String? errorMessage;
    try {
      // TR-201/204: a team race needs a side before the join call, and a team
      // race that already started can't be joined at all. Resolve the public
      // preview first — share-link opens are rare, so the extra GET is cheap,
      // and it lets us branch without relying on an error response. Failure
      // here falls through to the plain join (older backends, individual
      // races), preserving today's behavior.
      Map<String, dynamic>? preview;
      try {
        preview = await _backendApiService.fetchSharedRace(
          token: token,
          identityToken: identityToken,
        );
      } catch (_) {}

      String? team;
      if (preview != null && TeamRace.isTeamRace(preview)) {
        final status = preview['status'] as String?;
        if (status != null && status != 'PENDING') {
          // TR-204: locked at start — land them on the race with a friendly
          // note instead of a failed join.
          raceId = preview['id'] as String?;
          errorMessage = raceId == null
              ? teamRaceErrorCopy('RACE_ALREADY_STARTED')
              : null;
          if (raceId != null && mounted) {
            showInfoToast(context, teamRaceErrorCopy('RACE_ALREADY_STARTED'));
          }
          return;
        }
        if (!mounted) return;
        team = await showTeamSidePicker(context: context, race: preview);
        if (team == null) {
          // Dismissed the side picker: leave them where they are. The token is
          // still consumed below so the drain can't loop.
          raceId = preview['id'] as String?;
          return;
        }
      }

      final result = team != null
          ? await _backendApiService.joinRaceByShareTokenOnTeam(
              identityToken: identityToken,
              token: token,
              team: team,
              onboarding: true,
            )
          : await _backendApiService.joinRaceByShareToken(
              identityToken: identityToken,
              token: token,
              // Server-gated one-time welcome boxes: a fresh share-link user
              // gets them; anyone already in the ledger is a no-op. See
              // joinRaceCore.
              onboarding: true,
            );
      raceId = result['raceId'] as String?;
    } on ApiException catch (e) {
      // Already a member / full / closed: still try to land them on the race by
      // resolving its id from the public preview.
      try {
        final preview = await _backendApiService.fetchSharedRace(
          token: token,
          identityToken: identityToken,
        );
        raceId = preview['id'] as String?;
      } catch (_) {}
      if (raceId == null) errorMessage = e.message;
    } catch (_) {
      // Network/transient: drop the token (it's re-tappable) rather than loop.
    } finally {
      // Consume the token on every outcome so the drain can't loop.
      await widget.authService.setPendingShareToken(null);
      _draining = false;
    }

    if (!mounted) return;
    if (raceId != null) {
      _fetchRaces();
      _openRaceFromCard(raceId);
    } else if (errorMessage != null) {
      showErrorToast(context, errorMessage);
    }
  }

  /// The tournament analog of [_maybeDrainPendingSharedRace] — joins the bracket
  /// behind a `/t/<token>` share link (captured by [DeepLinkService]) once past
  /// onboarding, then opens it. Runs on its own guard so it can't collide with
  /// the race-share drain. Best-effort: any failure consumes the token (it's
  /// re-tappable) rather than looping, and maps tournament error codes.
  Future<void> _maybeDrainPendingSharedTournament() async {
    if (_drainingTournament) return;
    final token = widget.authService.pendingTournamentShareToken;
    if (token == null || token.isEmpty) return;

    final isOnboarding =
        !_healthAuthorized ||
        _notificationsState == null ||
        !widget.authService.firstRaceOnboardingSeen;
    if (isOnboarding) return;

    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;

    _drainingTournament = true;
    String? tournamentId;
    String? errorMessage;
    try {
      final result = await _backendApiService.joinTournamentByShareToken(
        identityToken: identityToken,
        token: token,
      );
      final t = result['tournament'];
      tournamentId = t is Map ? t['id'] as String? : null;
    } on ApiException catch (e) {
      // Already a member / full / started: still try to land them on the
      // bracket by resolving its id from the share preview.
      try {
        final preview = await _backendApiService.fetchSharedTournament(
          token: token,
          identityToken: identityToken,
        );
        tournamentId = preview['id'] as String?;
      } catch (_) {}
      if (tournamentId == null) {
        errorMessage = e.code != null ? tournamentErrorCopy(e.code) : e.message;
      }
    } catch (_) {
      // Network/transient: drop the token (re-tappable) rather than loop.
    } finally {
      await widget.authService.setPendingTournamentShareToken(null);
      _drainingTournament = false;
    }

    if (!mounted) return;
    if (tournamentId != null) {
      _fetchRaces();
      _openTournament(tournamentId);
    } else if (errorMessage != null) {
      showErrorToast(context, errorMessage);
    }
  }

  /// While the referred-install welcome code is live (onboarding), resolve the
  /// inviter's joinable race from the public referral preview and stash it on
  /// [AuthService] (persisted), so the one-tap offer survives an app restart
  /// mid-onboarding. Best-effort: no race in the preview means no offer.
  Future<void> _maybeCaptureInviterRace() async {
    if (_capturingInviterRace) return;
    final code = widget.authService.welcomeReferralCode;
    if (code == null || code.isEmpty) return;
    if (widget.authService.pendingInviterRace != null) return;

    _capturingInviterRace = true;
    try {
      final preview = await _backendApiService.fetchReferralPreview(code: code);
      final race = preview['inviterRace'];
      final raceId = race is Map ? race['id'] as String? : null;
      if (raceId == null || raceId.isEmpty) return;
      await widget.authService.setPendingInviterRace({
        'raceId': raceId,
        'raceName': (race as Map)['name'] as String? ?? 'their race',
        'inviterName': preview['inviterName'] as String? ?? 'Your friend',
      });
    } catch (_) {
      // Preview is best-effort; the invitee still gets the normal flow.
    } finally {
      _capturingInviterRace = false;
    }
  }

  /// One-tap "race your friend now" for a referred install, shown once,
  /// immediately after onboarding completes (same gate as the share-token
  /// drain). Joining is server-tolerant: if they're somehow already in the
  /// race (e.g. it's the seeded race signup auto-enrolled them into), we just
  /// open it.
  Future<void> _maybeOfferInviterRace() async {
    if (_inviterOfferShowing || _draining) return;
    final pending = widget.authService.pendingInviterRace;
    if (pending == null) return;
    // Share-token flow wins when both are somehow pending.
    if (widget.authService.pendingShareToken != null) return;

    final isOnboarding =
        !_healthAuthorized ||
        _notificationsState == null ||
        !widget.authService.firstRaceOnboardingSeen;
    if (isOnboarding) return;

    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;

    final raceId = pending['raceId'];
    if (raceId == null || raceId.isEmpty) {
      await widget.authService.setPendingInviterRace(null);
      return;
    }

    _inviterOfferShowing = true;
    final inviterName = pending['inviterName'] ?? 'Your friend';
    final raceName = pending['raceName'] ?? 'their race';
    final accepted = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text('$inviterName challenged you!'),
        content: Text('Jump into "$raceName" and race them right now.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Later'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Race now'),
          ),
        ],
      ),
    );
    // One-shot on every outcome — the offer never nags twice.
    await widget.authService.setPendingInviterRace(null);
    _inviterOfferShowing = false;
    if (!mounted || accepted != true) return;

    try {
      await _backendApiService.joinPublicRace(
        identityToken: identityToken,
        raceId: raceId,
        // Server-gated one-time welcome boxes; a no-op if already granted.
        onboarding: true,
      );
    } on ApiException {
      // "Already in this race" (signup auto-enroll) or full/closed — either
      // way the race screen is the right destination; it renders any state.
    } catch (_) {
      if (mounted) {
        showErrorToast(context, 'Couldn\'t join right now — try again later.');
      }
      return;
    }
    if (!mounted) return;
    _fetchRaces();
    _openRaceFromCard(raceId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _healthAuthorized) {
      // Mirror initial load: refresh every home surface, then surface the
      // results modals only once all calls have settled.
      unawaited(_loadHomeAndShowResults());
      _startForegroundPolling();
    } else if (state == AppLifecycleState.paused) {
      _stopForegroundPolling();
      // Stop background job polling so a paused app issues no requests / leaks
      // no timers (§6.5).
      _jobPollToken += 1;
    }
  }

  void _startForegroundPolling() {
    _foregroundPollTimer?.cancel();
    _foregroundPollTimer = Timer.periodic(_foregroundPollInterval, (_) {
      if (_healthAuthorized) {
        // _fetchSteps refreshes friends + me at its tail; no separate call.
        _fetchSteps();
      }
    });
  }

  void _stopForegroundPolling() {
    _foregroundPollTimer?.cancel();
    _foregroundPollTimer = null;
  }

  Future<void> _restoreAndFetch() async {
    setState(() {
      _displayName = widget.authService.displayName;
    });

    final sessionIsValid = await _refreshSessionToken();
    if (!sessionIsValid || !mounted) return;

    final wasAuthorized = await _healthService.restoreHealthAuthState();
    if (!wasAuthorized || !mounted) return;

    setState(() => _healthAuthorized = true);
    await _backgroundSyncBootstrapService.enableHealthKitBackgroundDelivery();
    await _checkNotificationState();
    _startForegroundPolling();
    // Load all home-page surfaces, then show the race/ranked results modals
    // only after every call has settled — never over still-loading sections.
    unawaited(_loadHomeAndShowResults());
    // Cold start with a share link tapped before launch: now that the session
    // is valid and onboarding state is loaded, join + open the shared race.
    _maybeDrainPendingSharedRace();
    // Referred install: resolve/offer the inviter's race (each no-ops unless
    // its precondition holds — see the methods).
    _maybeCaptureInviterRace();
    _maybeOfferInviterRace();
  }

  Future<bool> _refreshSessionToken() async {
    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return false;

      final data = await _backendApiService.refreshSessionToken(
        authToken: token,
      );
      final newToken = data['sessionToken'] as String?;
      final user = data['user'] as Map<String, dynamic>?;
      if (newToken != null) {
        await widget.authService.updateSessionToken(newToken);
      }
      if (user != null) {
        await widget.authService.syncFromBackendUser(user);
      }
      return true;
    } catch (error) {
      if (isAuthenticationFailure(error)) {
        // Sign-out clears every session-scoped cache: shop catalog + additive
        // endpoint capability states (§9.1/§9.3).
        _shopCatalogCache.clear();
        _backendApiService.resetSessionCapabilities();
        _jobPollToken += 1; // cancel any in-flight job polling
        await widget.authService.signOut();
        if (!mounted) return false;

        showErrorToast(context, 'Session expired. Please sign in again.');
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const StartScreen()),
          (route) => false,
        );
        return false;
      }
      return true;
    }
  }

  Future<void> _enableHealthData() async {
    setState(() => _isLoading = true);

    try {
      final result = await _healthService.setUpHealthAccess();
      if (result == HealthSetupResult.needsHealthConnect) {
        setState(() {
          _isLoading = false;
          _error =
              'Health Connect is required to track your steps.\n'
              'Install or update it, then tap Continue again.';
        });
        return;
      }
      if (result == HealthSetupResult.denied) {
        setState(() {
          _isLoading = false;
          _error =
              'Steps access wasn’t granted. Tap Try Again to show the '
              'permission prompt again, then allow Bara to read your steps. '
              'If the prompt no longer appears, enable Steps for Bara in your '
              'Health Connect settings.';
        });
        return;
      }

      setState(() => _healthAuthorized = true);
      await _backgroundSyncBootstrapService.enableHealthKitBackgroundDelivery();
      await _checkNotificationState();
      _fetchRaceCard();
      await _fetchSteps();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to request health access:\n$e';
      });
    }
  }

  Future<void> _checkNotificationState() async {
    final ns = widget.notificationService;
    if (ns == null) {
      if (mounted) {
        setState(() => _notificationsState = true);
      }
      return;
    }

    final state = await ns.getPermissionState();
    if (!mounted) return;

    if (state == true) {
      // Already granted — silently re-register token for this session
      ns.requestPermission(widget.authService.authToken);
      setState(() => _notificationsState = true);
    } else if (state == false) {
      // Previously denied — don't nag
      setState(() => _notificationsState = false);
    } else {
      // Never prompted — show the opt-in screen
      setState(() => _notificationsState = null);
    }
  }

  Future<void> _enableNotifications() async {
    final ns = widget.notificationService;
    if (ns == null) return;

    final granted = await ns.requestPermission(widget.authService.authToken);
    if (!mounted) return;
    setState(() => _notificationsState = granted);
  }

  /// Reads local health (daily total + hourly samples) and persists it, then
  /// refreshes friends + me. This preserves the original `_fetchSteps` contract
  /// (used by initial load, resume, the 5-minute foreground poll, and the health
  /// enable flow) while routing persistence through the shared [_persistSteps]
  /// v2/legacy orchestration. It intentionally does NOT fetch the home batch —
  /// the poll keeps its narrow behavior (§9.2).
  Future<void> _fetchSteps() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final outcome = await _persistSteps();
      setState(() {
        _isLoading = false;
        _error = null;
      });
      // Post-settlement refresh of friends + me (coins/boxes). Preserved as the
      // one place a steps sync refreshes those two surfaces.
      await Future.wait([_fetchFriendsSteps(), _refreshMe()]);
      // Job success can update an already-loaded home surface; the placement job
      // remains the worst-case safety net, so this is best-effort.
      if (outcome.jobId != null && outcome.generation != null) {
        _startJobPolling(outcome.jobId!, outcome.generation!);
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to fetch steps:\n$e';
      });
    }
  }

  /// Shared step persistence (§9.2). Reads device health, then tries
  /// `POST /steps/sync-v2` with one immutable normalized payload and a fresh
  /// idempotency key. Falls back to legacy `/steps` (+ `/steps/samples`) ONLY on
  /// a definite 404 or pre-persistence `ASYNC_DISABLED`; every ambiguous or
  /// persisted-unknown outcome forbids a legacy write. Always updates
  /// [_stepData] from the truthful local read. May throw if the local health
  /// read fails — callers decide how to surface that.
  Future<_StepSyncOutcome> _persistSteps() async {
    final identityToken = widget.authService.authToken;
    final now = DateTime.now();
    final results = await Future.wait([
      _healthService.getStepsToday(),
      _healthService.getHourlySteps(
        startTime: DateTime(now.year, now.month, now.day),
        endTime: now,
      ),
    ]);
    final stepData = results[0] as StepData;
    final hourlySamples = results[1] as List<StepSampleData>;

    if (identityToken == null || identityToken.isEmpty) {
      if (mounted) setState(() => _stepData = stepData);
      return const _StepSyncOutcome(persisted: false, error: true);
    }

    final payload = BackendApiService.buildStepSyncV2Payload(
      stepData: stepData,
      samples: hourlySamples,
    );
    final key = BackendApiService.generateIdempotencyKey();

    final v2 = await _backendApiService.recordStepSyncV2(
      identityToken: identityToken,
      idempotencyKey: key,
      payload: payload,
    );

    // Local step display is always truthful from the device read, regardless of
    // the server outcome.
    if (mounted) setState(() => _stepData = stepData);

    if (v2.shouldLegacyFallback) {
      final ok = await _legacySyncSteps(identityToken, stepData, hourlySamples);
      return _StepSyncOutcome(persisted: ok, error: !ok);
    }

    if (v2.diagnostic != null) {
      debugPrint('[sync-v2 contract alarm] ${v2.diagnostic}');
    }

    return _StepSyncOutcome(
      persisted: v2.persisted,
      usePersistedHome: v2.usePersistedHome,
      error: v2.isError,
      jobId: v2.jobId,
      generation: v2.generation,
    );
  }

  /// The pre-existing synchronous step flow, reused only when sync-v2 is
  /// unsupported or async is disabled. Retries the daily post once on a
  /// cold-start blip, then posts hourly samples best-effort.
  Future<bool> _legacySyncSteps(
    String identityToken,
    StepData stepData,
    List<StepSampleData> hourlySamples,
  ) async {
    final willPostSamples = hourlySamples.isNotEmpty;

    Future<void> pushSteps() => _backendApiService.recordSteps(
      identityToken: identityToken,
      stepData: stepData,
      skipRaceResolution: willPostSamples,
    );

    var syncFailed = false;
    try {
      await pushSteps();
    } catch (_) {
      await Future<void>.delayed(const Duration(seconds: 1));
      try {
        await pushSteps();
      } catch (_) {
        syncFailed = true;
      }
    }

    if (!syncFailed && willPostSamples) {
      try {
        await _backendApiService.recordStepSamples(
          identityToken: identityToken,
          samples: hourlySamples,
        );
      } catch (_) {
        // Don't fail the main sync if hourly samples fail; the next sync
        // re-resolves.
      }
    }
    return !syncFailed;
  }

  /// Polls the durable race-resolution job at 750 ms, 1.5 s, 3 s, 5 s while
  /// foregrounded (§6.5). Never blocks any indicator. Stops on a terminal state,
  /// navigation/pause/sign-out (via the token guard), or the fourth poll. On
  /// SUCCEEDED it silently refreshes home cards, personal races (if loaded), and
  /// profile — coalesced, no new indicator.
  void _startJobPolling(String jobId, int generation) {
    final token = ++_jobPollToken;
    const schedule = [
      Duration(milliseconds: 750),
      Duration(milliseconds: 1500),
      Duration(seconds: 3),
      Duration(seconds: 5),
    ];

    Future<void> poll(int index) async {
      if (index >= schedule.length) return;
      await Future<void>.delayed(schedule[index]);
      if (!mounted || token != _jobPollToken) return;
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      final status = await _backendApiService.fetchRaceResolutionStatus(
        identityToken: identityToken,
        jobId: jobId,
        generation: generation,
      );
      if (!mounted || token != _jobPollToken) return;

      if (status.isSucceeded) {
        // Silent catch-up: cached rival totals close the gap.
        unawaited(_fetchRaceCard());
        if (_racesData != null) unawaited(_fetchRacesCore());
        unawaited(_refreshMe());
        return;
      }
      if (status.isTerminal) return; // FAILED/SUPERSEDED/notFound: stop.
      await poll(index + 1);
    }

    unawaited(poll(0));
  }

  Future<void> _fetchFriendsSteps() async {
    final previous = _friendsSteps;
    if (mounted) {
      setState(() {
        _friendsStepsState = previous.isEmpty
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) {
        if (mounted) {
          setState(() {
            _friendsStepsState = Loadable.error(
              'Not signed in.',
              data: previous,
            );
          });
        }
        return;
      }

      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final friends = await _backendApiService.fetchFriendsSteps(
        identityToken: identityToken,
        date: date,
      );

      _friendsFetchedAt = DateTime.now();
      if (mounted) {
        setState(() {
          _friendsSteps = friends;
          _friendsStepsState = Loadable.success(friends);
        });
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _friendsStepsState = Loadable.error(e.toString(), data: previous);
      });
    }
  }

  /// Refreshes friends only when the data is absent, older than 60 s, or was
  /// invalidated (§9.4). Never awaited from a Races pull.
  void _maybeRefreshFriends() {
    final at = _friendsFetchedAt;
    final stale =
        at == null || DateTime.now().difference(at) > const Duration(seconds: 60);
    if (_friendsSteps.isEmpty || stale) {
      unawaited(_fetchFriendsSteps());
    }
  }

  /// Public races entrypoint (§9.4). Awaits ONLY the core `GET /races` list and
  /// fires discovery (featured/public/tournaments) in the background so callers
  /// never block on non-critical discovery data. Kept as the shared entrypoint
  /// for the many existing triggers (joins, tournament return, onboarding, etc.).
  Future<void> _fetchRaces() async {
    await _fetchRacesCore();
    unawaited(_refreshRacesDiscovery());
  }

  /// Loads and commits only the user's core personal race list. Guarded by a
  /// monotonic generation so a slower old response cannot overwrite a newer
  /// refresh (§9.4). No database await for discovery here.
  Future<void> _fetchRacesCore() async {
    final gen = ++_racesGeneration;
    final previous = _racesData;
    if (mounted) {
      setState(() {
        _racesState = previous == null
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) {
        if (mounted && gen == _racesGeneration) {
          setState(() {
            _racesState = Loadable.error('Not signed in.', data: previous);
          });
        }
        return;
      }

      final data = await _backendApiService.fetchRaces(
        identityToken: identityToken,
      );

      // Drop a stale response: a newer refresh generation already started.
      if (!mounted || gen != _racesGeneration) return;
      setState(() {
        _racesData = data;
        _racesState = Loadable.success(data);
      });
    } catch (e) {
      if (!mounted || gen != _racesGeneration) return;
      setState(() {
        _racesState = Loadable.error(e.toString(), data: previous);
      });
    }
  }

  /// Background discovery refresh (§9.4). One compact `discovery-summary` request
  /// replaces three legacy calls; on a cached 404 it falls back to the legacy
  /// featured/public/tournament calls IN PARALLEL. Each field is committed only
  /// when its `resolved` bit was true (via the null fields of the parsed
  /// summary), so a partial backend failure never erases last-known values.
  Future<void> _refreshRacesDiscovery() async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;

    final gen = ++_discoveryGeneration;
    final summary = await _backendApiService.fetchRaceDiscoverySummary(
      identityToken: identityToken,
    );
    if (!mounted || gen != _discoveryGeneration) return;

    if (summary.unsupported) {
      // Legacy discovery — parallel, never serial, never awaited by a pull.
      await Future.wait([
        _fetchFeaturedRaces(),
        _fetchPublicRaces(),
        _fetchFeaturedTournaments(),
      ]);
      return;
    }

    setState(() {
      if (summary.publicRaceCount != null) {
        _publicRacesCount = summary.publicRaceCount!;
      }
      if (summary.featuredRaces != null) {
        _featuredRaces = summary.featuredRaces!;
      }
      if (summary.featuredTournaments != null) {
        _featuredTournaments = summary.featuredTournaments!;
      }
    });
  }

  /// Loads every home-page surface in parallel and, once they have ALL
  /// settled, surfaces the race/ranked results modals. Gating the popups on
  /// completion keeps a results modal from appearing over sections that are
  /// still showing loading skeletons. Race results go first: it sets its open
  /// guard before its first await, so the ranked check then defers behind it,
  /// preserving the prior sequencing. Every fetch swallows its own errors, so
  /// the wait never throws and the modals always get their chance.
  Future<void> _loadHomeAndShowResults() {
    // Coalesce: iOS fires a `resumed` lifecycle event right after cold start,
    // which used to double the entire home load (every endpoint hit twice).
    // While a load is in flight, all triggers share the same future.
    return _homeLoadInFlight ??= _loadHomeAndShowResultsInner().whenComplete(() {
      _homeLoadInFlight = null;
    });
  }

  Future<void> _loadHomeAndShowResultsInner() async {
    // Persist first so the home batch and persisted-total opt-in reflect the new
    // daily total. A local health-read failure still lets the other surfaces load.
    _StepSyncOutcome? outcome;
    try {
      outcome = await _persistSteps();
    } catch (_) {
      // Keep prior surfaces; continue loading the rest.
    }

    await Future.wait([
      _fetchRaceCard(usePersistedTotals: outcome?.usePersistedHome ?? false),
      // Await ONLY the core race list — result-modal detection consumes
      // completed races. Discovery must not gate the load (§9.4).
      _fetchRacesCore(),
      _fetchShopCatalog(),
      _fetchFriendsSteps(),
      _refreshMe(),
    ]);

    // Discovery runs in the background; never blocks the home load.
    unawaited(_refreshRacesDiscovery());
    if (outcome?.jobId != null && outcome?.generation != null) {
      _startJobPolling(outcome!.jobId!, outcome.generation!);
    }

    if (!mounted) return;
    _maybeShowRaceResults();
    _maybeShowRankedResults();
  }

  Future<void> _fetchFeaturedRaces() async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;
    try {
      final featured = await _backendApiService.fetchFeaturedRaces(
        identityToken: identityToken,
      );
      if (mounted) setState(() => _featuredRaces = featured);
    } catch (_) {
      // Featured is a non-critical discovery surface; on error keep the last
      // known list rather than disturbing the races page.
    }
  }

  /// D13: pulls featured (seeded) tournaments for the merged featured row. Kept
  /// SEPARATE from [_fetchFeaturedRaces] and invoked fire-and-forget so it never
  /// serializes ahead of the public-races count fetch. Best-effort: an older
  /// backend / missing `featured` key keeps the last known list.
  Future<void> _fetchFeaturedTournaments() async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;
    try {
      final res = await _backendApiService.fetchPublicTournaments(
        identityToken: identityToken,
      );
      final featured =
          (res['featured'] as List?)?.cast<Map<String, dynamic>>() ?? const [];
      if (mounted) setState(() => _featuredTournaments = featured);
    } catch (_) {
      // Older backend / missing key → keep the last known list (usually empty).
    }
  }

  /// Fetches the joinable public races just to surface their count on the Races
  /// tab's PUBLIC RACES button. Mirrors [_fetchFeaturedRaces]: non-critical, so
  /// on any error (older backend, transient failure) we keep the last known
  /// count rather than disturbing the races page.
  Future<void> _fetchPublicRaces() async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;
    try {
      final races = await _backendApiService.fetchPublicRaces(
        identityToken: identityToken,
      );
      if (mounted) setState(() => _publicRacesCount = races.length);
    } catch (_) {
      // Keep the last known count on error.
    }
  }

  /// Detects races the user ran (myStatus == 'ACCEPTED') that finished and
  /// haven't had their results acknowledged, then shows a single combined
  /// summary popup. Called only from resume + initial load (not the poll).
  ///
  /// Defensive default: a missing/null `myResultsSeen` is treated as SEEN
  /// (true), so an older backend that doesn't send the field never triggers a
  /// spurious popup.
  Future<void> _maybeShowRaceResults() async {
    if (!mounted || _raceResultsPopupOpen) return;

    final completed =
        (_racesData?['completed'] as List?)?.cast<Map<String, dynamic>>() ??
        const [];

    final unseen = completed.where((race) {
      if (race['myStatus'] != 'ACCEPTED') return false;
      final seen = (race['myResultsSeen'] as bool?) ?? true;
      if (seen) return false;
      final id = race['id'] as String?;
      if (id == null) return false;
      return !_raceResultsShownThisSession.contains(id);
    }).toList();

    if (unseen.isEmpty) return;

    // Sequence after the daily-reward popup: that modal opens on tap and lives
    // on a route above this shell, so if anything is already on top of us, hold
    // off — the next resume/load will re-detect and show then.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final shownIds = unseen
        .map((race) => race['id'] as String)
        .toList(growable: false);
    _raceResultsShownThisSession.addAll(shownIds);

    _raceResultsPopupOpen = true;
    await Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) => RaceResultsSummaryScreen(races: unseen),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
    _raceResultsPopupOpen = false;

    // On dismiss: ack server-side and optimistically flip the local flag so a
    // re-fetch in this session doesn't re-show them.
    final identityToken = widget.authService.authToken;
    if (identityToken != null && identityToken.isNotEmpty) {
      _backendApiService.markRaceResultsSeen(
        identityToken: identityToken,
        raceIds: shownIds,
      );
    }
    if (mounted) {
      setState(() {
        final shownSet = shownIds.toSet();
        for (final race in completed) {
          if (shownSet.contains(race['id'])) {
            race['myResultsSeen'] = true;
          }
        }
      });
    }

    // Happy-moment hook: the user just dismissed a results modal that included
    // a top-3 finish — or, for team races, a strict team WIN (TR-807: ties
    // and forfeited members never qualify). The service applies its own
    // warm-up/cooldown/never-again guards, so most calls are no-ops.
    final placedTop3 = unseen.any(raceCountsAsReviewHappyMoment);
    if (placedTop3 && mounted) {
      await _reviewPromptService.recordHappyMomentAndMaybePrompt(context);
    }
  }

  /// Fetches `/ranked/v2` and, if the caller's most recently settled week is
  /// unacknowledged, shows the post-settlement summary popup. Called only from
  /// resume + initial load (not the poll), mirroring [_maybeShowRaceResults].
  ///
  /// Defensive throughout: a backend that predates `/ranked/v2` (404) or omits
  /// `resultsSeen` yields no popup — `resultsSeen` defaults to SEEN (true), and
  /// only the three real settlement outcomes qualify.
  Future<void> _maybeShowRankedResults() async {
    // Suppressed in-app (see [_showRankedResultsPopup]): no fetch, no popup, so
    // a settled week never interrupts the user. Settlement still runs server-
    // side; the user sees their new tier the next time they open Ranked.
    if (!_showRankedResultsPopup) return;
    if (!mounted || _rankedResultsPopupOpen || _raceResultsPopupOpen) return;

    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;

    Map<String, dynamic>? lastWeek;
    try {
      final data = await _backendApiService.fetchRankedV2(
        identityToken: identityToken,
      );
      lastWeek = data['lastWeek'] as Map<String, dynamic>?;
    } catch (_) {
      // Legacy backend (no /ranked/v2) or a transient error — no popup.
      return;
    }
    if (lastWeek == null || !mounted) return;

    final seen = (lastWeek['resultsSeen'] as bool?) ?? true;
    if (seen) return;
    final outcome = lastWeek['outcome'] as String?;
    if (outcome != 'PROMOTE' && outcome != 'HOLD' && outcome != 'DEMOTE') {
      return;
    }
    final weekIndex = (lastWeek['weekIndex'] as num?)?.toInt();
    if (weekIndex == null) return;
    if (_rankedResultsShownThisSession.contains(weekIndex)) return;

    // Re-check the open guards: the awaited fetch above may have let the race
    // popup open in the meantime. Sequence behind it (and the daily-reward
    // modal) — if anything's on top of the shell, hold off and let the next
    // resume/load re-detect and show.
    if (_rankedResultsPopupOpen || _raceResultsPopupOpen) return;
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    _rankedResultsShownThisSession.add(weekIndex);
    _rankedResultsPopupOpen = true;
    await Navigator.of(context).push<void>(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) => RankedResultsSummaryScreen(result: lastWeek!),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
    _rankedResultsPopupOpen = false;

    // On dismiss: ack server-side so it never re-shows across sessions. The
    // session set already guards re-show before this round-trips.
    final token = widget.authService.authToken;
    if (token != null && token.isNotEmpty) {
      _backendApiService.markRankedResultsSeen(
        identityToken: token,
        weekIndex: weekIndex,
      );
    }
  }

  Future<bool> _joinFeaturedRace(String raceId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return false;
    try {
      await _backendApiService.joinPublicRace(
        identityToken: identityToken,
        raceId: raceId,
      );
      // Refresh both surfaces: the featured card flips to VIEW and the race
      // drops into ACTIVE below. (_fetchRaces also refreshes featured.)
      await _fetchRaces();
      return true;
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not join: $e');
      return false;
    }
  }

  /// D13 join-featured-tournament callback (mirrors [_joinFeaturedRace]): joins
  /// the free featured bracket, refreshes, then opens its lobby. Maps tournament
  /// error codes (e.g. ALREADY_IN_FEATURED → the D12 copy).
  Future<bool> _joinFeaturedTournament(String tournamentId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return false;
    try {
      await _backendApiService.joinTournament(
        identityToken: identityToken,
        tournamentId: tournamentId,
      );
      await _fetchRaces();
      await _fetchFeaturedTournaments();
      if (mounted) _openTournament(tournamentId);
      return true;
    } on ApiException catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          e.code != null ? tournamentErrorCopy(e.code) : e.message,
        );
      }
      return false;
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not join: $e');
      return false;
    }
  }

  /// Fetches the shop catalog through the 15-minute session cache (§9.3): a fresh
  /// value renders without a network call, concurrent misses share one request,
  /// and the last catalog stays visible while a refresh runs. [force] bypasses
  /// the TTL (used after an invalidation event).
  Future<void> _fetchShopCatalog({bool force = false}) async {
    final previous = _shopCatalogState.data;

    // Serve a fresh cached catalog without touching the network or the loading
    // state (stale-while-revalidate is handled by the Loadable below only when
    // an actual fetch runs).
    if (!force && _shopCatalogCache.isFresh) {
      final cached = _shopCatalogCache.value;
      if (cached != null) {
        _applyShopCatalog(cached);
        if (mounted) setState(() => _shopCatalogState = Loadable.success(cached));
        return;
      }
    }

    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) {
      if (mounted) {
        setState(() {
          _shopCatalogState = Loadable.error('Not signed in.', data: previous);
        });
      }
      return;
    }

    if (mounted) {
      setState(() {
        _shopCatalogState = previous == null
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      final data = await _shopCatalogCache.get(
        () => _backendApiService.fetchShopCatalog(identityToken: identityToken),
        forceRefresh: force,
      );
      _applyShopCatalog(data);
      if (mounted) {
        setState(() => _shopCatalogState = Loadable.success(data));
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _shopCatalogState = Loadable.error(e.toString(), data: previous);
      });
    }
  }

  /// The shop tab pushes a fresh catalog after any load/purchase/equip/character
  /// change. That is the §9.3 invalidation event: rather than dropping the cache
  /// and refetching, we seed it with the authoritative post-change catalog so the
  /// home surfaces stay current and the TTL window resets.
  void _onShopCatalogChanged(Map<String, dynamic> catalog) {
    _shopCatalogCache.set(catalog);
    _applyShopCatalog(catalog);
    if (mounted) {
      setState(() => _shopCatalogState = Loadable.success(catalog));
    }
  }

  void _applyShopCatalog(Map<String, dynamic> catalog) {
    final equipped = catalog['equipped'] as Map<String, dynamic>? ?? {};
    // The CHARACTER entry is the base animal, not a wearable — keep it out of
    // the accessory overlay list.
    final accessories = equipped.entries
        .where((entry) => entry.key != 'CHARACTER')
        .map((entry) => entry.value)
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final character = equipped['CHARACTER'];
    final animal = character is Map<String, dynamic>
        ? animalFromJson(character['assetKey'])
        : null;
    final coins = catalog['coins'] as int?;

    if (coins != null) {
      widget.authService.updateCoins(coins);
    }

    if (mounted) {
      setState(() {
        _equippedAccessories = accessories;
        _equippedAnimal = animal;
      });
    }
  }

  Future<void> _refreshRacesTab() {
    // Coalesce overlapping Races refreshes (tab reveal, pull, route-return,
    // Home initial load, profile-triggered). A trigger while one runs rides it.
    return _racesRefreshInFlight ??= _refreshRacesTabInner().whenComplete(() {
      _racesRefreshInFlight = null;
    });
  }

  Future<void> _refreshRacesTabInner() async {
    // The pull awaits ONLY the core personal race list (§9.4/D3).
    await _fetchRacesCore();
    // Discovery + friends are stale-while-revalidate; never block the pull.
    unawaited(_refreshRacesDiscovery());
    _maybeRefreshFriends();
  }

  Future<void> _refreshHomeTab() {
    // Coalesce rapid pull-to-refreshes: each swipe triggers a steps/samples
    // POST whose server-side settlement recompute is expensive; stacking them
    // concurrently just makes every request slower. A swipe while a refresh is
    // in flight rides that refresh instead of starting another.
    return _homeRefreshInFlight ??= _refreshHomeTabInner().whenComplete(() {
      _homeRefreshInFlight = null;
    });
  }

  Future<void> _refreshHomeTabInner() async {
    if (mounted) setState(() => _error = null);
    _StepSyncOutcome outcome;
    try {
      // Stages 2-4: read health, persist (v2/legacy), update _stepData.
      outcome = await _persistSteps();
    } catch (_) {
      // Local health read failed: keep prior server-derived surfaces and end
      // the pull (existing error presentation lives in the step display).
      return;
    }

    // Stage 5: fetch the home batch AFTER persistence so milestones/reward use
    // the new daily total. Persisted-total path only when uploaderReconciliation
    // was CURRENT; otherwise the backend's live-computation fallback.
    await _fetchRaceCard(usePersistedTotals: outcome.usePersistedHome);

    // Stage 6: the refresh indicator completes when this method returns.
    // Stage 7: background, coalesced, non-blocking. The streak/milestone widgets
    // now consume dailyReward/stepMilestones from the batch above; their
    // standalone fallback only runs when the field is absent (see the widgets).
    unawaited(_refreshMe());
    unawaited(_fetchFriendsSteps());
    // Shop only touches the network when the 15-minute cache is absent/expired.
    unawaited(_fetchShopCatalog());
    if (outcome.jobId != null && outcome.generation != null) {
      _startJobPolling(outcome.jobId!, outcome.generation!);
    }
  }

  Future<void> _fetchRaceCard({bool usePersistedTotals = false}) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) {
      if (mounted) setState(() => _raceCardLoading = false);
      return;
    }
    if (mounted && _raceCard == null) {
      setState(() => _raceCardLoading = true);
    }
    try {
      final data = await _backendApiService.fetchHomeRaceCard(
        identityToken: identityToken,
        usePersistedTotals: usePersistedTotals,
      );
      if (mounted) {
        setState(() {
          _raceCard = data;
          _raceCardLoading = false;
        });
      }
    } catch (_) {
      // Card is non-critical; ignore fetch errors and keep last value.
      if (mounted) {
        setState(() => _raceCardLoading = false);
      }
    }
  }

  // Keep the cached race-card batch truthful after a claim, so a remounted
  // StreakChip (home page disposed by the PageView) doesn't briefly show a
  // stale CLAIM state. No setState: nothing on screen reads this until the
  // next HomeTab build.
  void _markDailyRewardClaimed() {
    final dailyReward = _raceCard?['dailyReward'];
    if (dailyReward is Map) {
      dailyReward['claimedToday'] = true;
    }
  }

  void _openRaceFromCard(String raceId) {
    // Rapid taps during the push transition used to stack duplicate detail
    // screens, each running the full details/progress/chat load.
    if (_openingRaceDetail) return;
    _openingRaceDetail = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => RaceDetailScreen(
              authService: widget.authService,
              raceId: raceId,
              friends: _friendsSteps,
            ),
          ),
        )
        .whenComplete(() => _openingRaceDetail = false);
  }

  /// Opens a tournament bracket screen (from a push tap or a share-link drain),
  /// guarding against rapid double-pushes like [_openRaceFromCard].
  void _openTournament(String tournamentId) {
    if (_openingTournament) return;
    _openingTournament = true;
    Navigator.of(context)
        .push(
          MaterialPageRoute(
            builder: (_) => TournamentDetailScreen(
              authService: widget.authService,
              tournamentId: tournamentId,
              friends: _friendsSteps,
            ),
          ),
        )
        .whenComplete(() {
          _openingTournament = false;
          if (mounted) _fetchRaces();
        });
  }

  Future<void> _joinRaceFromCard(String raceId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;
    try {
      await _backendApiService.joinPublicRace(
        identityToken: identityToken,
        raceId: raceId,
      );
      if (mounted) {
        showInfoToast(context, 'Joined the race.');
      }
      await _fetchRaceCard();
      _openRaceFromCard(raceId);
    } on ApiException catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          e.code != null
              ? teamRaceErrorCopy(e.code)
              : (e.message.trim().isNotEmpty
                    ? e.message
                    : 'Could not join. Give it another try!'),
        );
      }
    } catch (_) {
      if (mounted) {
        showErrorToast(context, 'Could not join. Give it another try!');
      }
    }
  }

  /// Confirms the (already server-side) auto-enrollment from the onboarding step
  /// and drops the user into the live Daily race. Enrollment into the daily +
  /// weekly seeded races already happened on account creation
  /// (`autoEnrollNewUser.js`), so this NEVER joins a race — it only closes the
  /// first-race gate and routes. Falls back to Home with a gentle toast when no
  /// active Daily race is available (backend variance / version) so onboarding
  /// never blocks on a missing race.
  Future<void> _enterDailyRaceOnboarding() async {
    // Resolve the destination before closing the gate so we know where to land.
    final dailyRaceId = await _fetchActiveDailyRaceId();
    // Close the gate (backend idempotent + local) so onboarding exits to tabs.
    await _skipFirstRaceOnboarding();
    // Refresh surfaces that now reflect the enrolled races / welcome boxes.
    _fetchRaces();
    _fetchShopCatalog();
    _refreshMe();
    if (!mounted) return;
    if (dailyRaceId != null && dailyRaceId.isNotEmpty) {
      // Exiting onboarding rebuilds into the tab PageView; open the race on top.
      _openRaceFromCard(dailyRaceId);
    } else {
      // Safe fallback: land Home rather than blocking on a missing daily race.
      _pageController.jumpToPage(_homeTabIndex);
      showInfoToast(
        context,
        "You're all set — find your races on the Races tab.",
      );
    }
  }

  /// Finds the id of the currently ACTIVE featured Daily (`DAILY_10K`) race, or
  /// null when the backend returns none (older backend / seeding gap). The
  /// featured payload exposes the race id as `raceId` and the stable seed
  /// identity as `seedKind`. Best-effort: any error yields null so the caller
  /// falls back to Home.
  Future<String?> _fetchActiveDailyRaceId() async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return null;
    try {
      final featured = await _backendApiService.fetchFeaturedRaces(
        identityToken: identityToken,
      );
      for (final race in featured) {
        if (race['seedKind'] == 'DAILY_10K') {
          final raceId = race['raceId'] as String?;
          if (raceId != null && raceId.isNotEmpty) return raceId;
        }
      }
      return null;
    } catch (_) {
      return null;
    }
  }

  /// Skips the first-race onboarding step: marks it seen on the backend
  /// (idempotent) and locally so onboarding exits to home. Marks locally even
  /// if the network call fails so the user isn't stuck on this step.
  Future<void> _skipFirstRaceOnboarding() async {
    final identityToken = widget.authService.authToken;
    if (identityToken != null && identityToken.isNotEmpty) {
      try {
        await _backendApiService.markFirstRaceOnboardingSeen(
          identityToken: identityToken,
        );
      } catch (_) {
        // Best-effort: still advance locally below.
      }
    }
    await widget.authService.markFirstRaceOnboardingSeenLocally();
  }

  /// Launches the tutorial from the onboarding step. TutorialScreen claims the
  /// one-time reward itself on full completion (and marks the step seen). On
  /// return — whether the user finished or bailed — we mark the step seen so
  /// onboarding advances to the first-race step. Marking seen is idempotent.
  Future<void> _startTutorialOnboarding() async {
    final navigator = Navigator.of(context);
    await navigator.push(
      MaterialPageRoute(
        builder: (_) => TutorialScreen(
          authService: widget.authService,
          onComplete: (ctx) => Navigator.of(ctx).pop(),
        ),
      ),
    );
    await widget.authService.markTutorialOnboardingSeen();
  }

  /// Skips the tutorial onboarding step: marks it seen (backend + locally) with
  /// no reward. The user can still earn the 100 coins later by finishing a
  /// replay of the tutorial.
  Future<void> _skipTutorialOnboarding() async {
    await widget.authService.markTutorialOnboardingSeen();
  }

  Future<void> _acceptRaceInviteFromCard(String raceId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;
    try {
      await _backendApiService.respondToRaceInvite(
        identityToken: identityToken,
        raceId: raceId,
        accept: true,
      );
      if (mounted) showInfoToast(context, 'Accepted.');
      await _fetchRaceCard();
      _openRaceFromCard(raceId);
    } on ApiException catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          e.code != null
              ? teamRaceErrorCopy(e.code)
              : (e.message.trim().isNotEmpty
                    ? e.message
                    : 'Could not accept. Give it another try!'),
        );
      }
    } catch (_) {
      if (mounted) {
        showErrorToast(context, 'Could not accept. Give it another try!');
      }
    }
  }

  Future<void> _declineRaceInviteFromCard(String raceId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return;
    try {
      await _backendApiService.respondToRaceInvite(
        identityToken: identityToken,
        raceId: raceId,
        accept: false,
      );
      if (mounted) showInfoToast(context, 'Declined.');
      await _fetchRaceCard();
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not decline: $e');
    }
  }

  void _challengeFriendBack(String friendUserId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateRaceScreen(
          authService: widget.authService,
          backendApiService: _backendApiService,
          presetInviteeIds: [friendUserId],
        ),
      ),
    );
  }

  Future<void> _refreshFriendsTab() async {
    await _refreshMe();
  }

  Future<void> _refreshProfileTab() async {
    await _refreshMe();
  }

  void _openLeaderboardTab() {
    _pageController.animateToPage(
      _boardsTabIndex,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _openRacesTab() {
    _pageController.animateToPage(
      _racesTabIndex,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<ImageSource?> _showProfilePhotoSourceSheet() async {
    return showCupertinoModalPopup<ImageSource>(
      context: context,
      builder: (sheetContext) => CupertinoActionSheet(
        title: const Text('Add a profile photo'),
        actions: [
          CupertinoActionSheetAction(
            onPressed: () => Navigator.of(sheetContext).pop(ImageSource.camera),
            child: const Text('Take Photo'),
          ),
          CupertinoActionSheetAction(
            onPressed: () =>
                Navigator.of(sheetContext).pop(ImageSource.gallery),
            child: const Text('Choose from Library'),
          ),
        ],
        cancelButton: CupertinoActionSheetAction(
          onPressed: () => Navigator.of(sheetContext).pop(),
          isDefaultAction: true,
          child: const Text('Cancel'),
        ),
      ),
    );
  }

  Future<void> _addOrChangeProfilePhoto() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    final source = await _showProfilePhotoSourceSheet();
    if (source == null) return;

    try {
      final picked = await ImagePicker().pickImage(
        source: source,
        preferredCameraDevice: CameraDevice.front,
      );
      if (picked == null) return;

      final cropped = await ImageCropper().cropImage(
        sourcePath: picked.path,
        compressFormat: ImageCompressFormat.jpg,
        compressQuality: 85,
        maxWidth: 1024,
        maxHeight: 1024,
        aspectRatio: const CropAspectRatio(ratioX: 1, ratioY: 1),
        uiSettings: [
          IOSUiSettings(
            title: 'Crop Photo',
            aspectRatioLockEnabled: true,
            aspectRatioPickerButtonHidden: true,
            resetAspectRatioEnabled: false,
          ),
        ],
      );
      if (cropped == null) return;

      final bytes = await cropped.readAsBytes();
      const contentType = 'image/jpeg';
      final upload = await _backendApiService.requestProfilePhotoUpload(
        identityToken: token,
        contentType: contentType,
      );

      await _backendApiService.uploadProfilePhotoBytes(
        uploadUrl: upload['uploadUrl'] as String,
        bytes: bytes,
        contentType: contentType,
      );

      final user = await _backendApiService.saveProfilePhoto(
        identityToken: token,
        key: upload['key'] as String,
        url: upload['publicUrl'] as String,
      );

      await widget.authService.syncFromBackendUser(user);
      if (mounted) {
        setState(() {});
      }
      await _refreshProfileSurfaces();

      if (mounted) {
        showInfoToast(context, 'Profile photo updated.');
      }
    } on PlatformException {
      if (!mounted) return;
      final message = source == ImageSource.camera
          ? 'Camera access is off. Enable it in Settings to take a profile photo.'
          : 'Photo access is off. Enable it in Settings to choose a profile photo.';
      showErrorToast(context, message);
    } on ApiException catch (error) {
      if (!mounted) return;
      showErrorToast(context, error.message);
    } catch (_) {
      if (!mounted) return;
      showErrorToast(
        context,
        'Couldn’t update your profile photo. Please try again.',
      );
    }
  }

  Future<void> _removeProfilePhoto() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    try {
      final user = await _backendApiService.removeProfilePhoto(
        identityToken: token,
      );
      await widget.authService.syncFromBackendUser(user);
      if (mounted) {
        setState(() {});
      }
      await _refreshProfileSurfaces();

      if (mounted) {
        showInfoToast(context, 'Profile photo removed.');
      }
    } on ApiException catch (error) {
      if (!mounted) return;
      showErrorToast(context, error.message);
    } catch (_) {
      if (!mounted) return;
      showErrorToast(
        context,
        'Couldn’t remove your profile photo. Please try again.',
      );
    }
  }

  Future<bool> _dismissProfilePhotoPrompt() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return false;

    try {
      final user = await _backendApiService.dismissProfilePhotoPrompt(
        identityToken: token,
      );
      await widget.authService.syncFromBackendUser(user);
      if (mounted) {
        setState(() {});
      }
      return true;
    } catch (_) {
      if (!mounted) return false;
      showErrorToast(
        context,
        'Couldn’t save that preference. Please try again.',
      );
      return false;
    }
  }

  void _openProfile() {
    _pageController.animateToPage(
      _profileTabIndex,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  void _openShop() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => ShopTab(
          authService: widget.authService,
          backendApiService: _backendApiService,
          onShopChanged: _onShopCatalogChanged,
        ),
      ),
    );
  }

  Future<void> _refreshMe() async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      final user = await _backendApiService.fetchMe(
        identityToken: identityToken,
      );
      // Key session capability caches to the authenticated user; a plain token
      // rotation for the same user is a no-op (§9.1).
      final userId = user['id'] as String?;
      if (userId != null && userId.isNotEmpty) {
        _backendApiService.onAuthenticatedUser(userId);
      }
      final incoming = user['incomingFriendRequests'] as int? ?? 0;
      final displayName = user['displayName'] as String?;
      final email = user['email'] as String?;
      await widget.authService.syncFromBackendUser(user);
      if (mounted) {
        setState(() {
          _incomingFriendRequests = incoming;
          _displayName = displayName;
          _email = email;
        });
      }
    } catch (_) {}
  }

  Future<void> _refreshProfileSurfaces() async {
    await Future.wait([_refreshMe(), _fetchFriendsSteps(), _fetchRaces()]);

    if (mounted) {
      setState(() {
        _leaderboardSelectionNonce += 1;
      });
    }
  }

  void _syncSettingsState() {
    setState(() {
      _displayName = widget.authService.displayName;
    });
  }

  @override
  Widget build(BuildContext context) {
    final isOnboarding =
        !_healthAuthorized ||
        _notificationsState == null ||
        !widget.authService.tutorialOnboardingSeen ||
        !widget.authService.firstRaceOnboardingSeen;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: const ArcadePageBackground(showHeader: false)),

          if (isOnboarding)
            Positioned.fill(
              child: OnboardingFlow(
                healthAuthorized: _healthAuthorized,
                notificationsState: _notificationsState,
                tutorialOnboardingSeen:
                    widget.authService.tutorialOnboardingSeen,
                firstRaceOnboardingSeen:
                    widget.authService.firstRaceOnboardingSeen,
                onEnableHealth: _enableHealthData,
                onEnableNotifications: _enableNotifications,
                onStartTutorial: _startTutorialOnboarding,
                onSkipTutorial: _skipTutorialOnboarding,
                onEnterDaily: _enterDailyRaceOnboarding,
                onSkipFirstRace: _skipFirstRaceOnboarding,
                firstRaceShareTokenPending:
                    widget.authService.pendingShareToken != null,
                welcomeReferralCode: widget.authService.welcomeReferralCode,
                onWelcomeDismissed: () {
                  widget.authService.clearWelcomeReferralCode();
                },
                onFetchReferralPreview: (code) =>
                    _backendApiService.fetchReferralPreview(code: code),
                error: _error,
                isLoading: _isLoading,
              ),
            )
          else
            Positioned.fill(
              child: ValueListenableBuilder<double>(
                valueListenable: _bannerHeight,
                builder: (context, bannerH, _) {
                  final mq = MediaQuery.of(context);
                  // Home shows no shell banner, so it keeps its normal inset;
                  // every other tab reserves room for the banner overlay (pinned
                  // above the tab bar) by inflating the bottom padding the tabs
                  // read when they clear the tab bar.
                  final extraBottom = _currentTab == _homeTabIndex
                      ? 0.0
                      : bannerH;
                  return MediaQuery(
                    data: mq.copyWith(
                      padding: mq.padding.copyWith(
                        bottom: mq.padding.bottom + extraBottom,
                      ),
                    ),
                    child: PageView(
                      controller: _pageController,
                physics: const PageScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentTab = index;
                    // Clear the incoming-friend-request badge when the Friends
                    // tab is revealed (mirrors _openFriendsTab's old behavior).
                    if (index == _friendsTabIndex &&
                        _incomingFriendRequests != 0) {
                      _incomingFriendRequests = 0;
                    }
                  });
                  if (index == _racesTabIndex) _fetchRaces();
                  // Refresh the friends surface each time it's revealed (mirrors
                  // the races refresh-on-reveal hook). We intentionally refresh
                  // only the friends-steps data here, not _refreshMe, so the
                  // badge we just cleared isn't immediately re-read from /me.
                  if (index == _friendsTabIndex) _fetchFriendsSteps();
                },
                children: [
                  HomeTab(
                    streakChipKey: _streakChipKey,
                    stepMilestonesKey: _stepMilestonesKey,
                    stepData: _stepData,
                    isLoading: _isLoading,
                    error: _error,
                    backendApiService: _backendApiService,
                    healthAuthorized: _healthAuthorized,
                    notificationsState: _notificationsState,
                    displayName: _displayName,
                    authService: widget.authService,
                    onRefresh: _refreshHomeTab,
                    onEnableHealth: _enableHealthData,
                    onEnableNotifications: _enableNotifications,
                    onDisplayNameChanged: _syncSettingsState,
                    friendsSteps: _friendsSteps,
                    friendsStepsState: _friendsStepsState,
                    equippedAccessories: _equippedAccessories,
                    equippedAnimal: _equippedAnimal,
                    shopCatalogState: _shopCatalogState,
                    onOpenRacesTab: _openRacesTab,
                    onOpenLeaderboardTab: _openLeaderboardTab,
                    onOpenShop: _openShop,
                    onAddProfilePhoto: _addOrChangeProfilePhoto,
                    onDismissProfilePhotoPrompt: _dismissProfilePhotoPrompt,
                    raceCard: _raceCard,
                    raceCardLoading: _raceCardLoading,
                    onOpenRace: _openRaceFromCard,
                    onJoinRaceFromCard: _joinRaceFromCard,
                    onAcceptRaceInvite: _acceptRaceInviteFromCard,
                    onDeclineRaceInvite: _declineRaceInviteFromCard,
                    onChallengeFriendBack: _challengeFriendBack,
                    onDailyRewardClaimed: _markDailyRewardClaimed,
                  ),
                  RacesTab(
                    authService: widget.authService,
                    racesData: _racesData,
                    racesState: _racesState,
                    friendsSteps: _friendsSteps,
                    featuredRaces: _featuredRaces,
                    featuredTournaments: _featuredTournaments,
                    onRacesChanged: _fetchRaces,
                    onRefresh: _refreshRacesTab,
                    onJoinFeaturedRace: _joinFeaturedRace,
                    onJoinFeaturedTournament: _joinFeaturedTournament,
                    publicRacesCount: _publicRacesCount,
                    displayName: _displayName,
                    onOpenProfile: _openProfile,
                  ),
                  FriendsTab(
                    authService: widget.authService,
                    onFriendsChanged: () {
                      _refreshMe();
                      _fetchFriendsSteps();
                    },
                    onRefresh: _refreshFriendsTab,
                    backendApiService: _backendApiService,
                    stepData: _stepData,
                    displayName: _displayName,
                    onOpenProfile: _openProfile,
                  ),
                  LeaderboardTab(
                    authService: widget.authService,
                    backendApiService: _backendApiService,
                    stepData: _stepData,
                    displayName: _displayName,
                    requestedType: _requestedLeaderboardType,
                    requestedPeriod: _requestedLeaderboardPeriod,
                    selectionNonce: _leaderboardSelectionNonce,
                    onOpenProfile: _openProfile,
                  ),
                  ProfileTab(
                    authService: widget.authService,
                    backendApiService: _backendApiService,
                    displayName: _displayName,
                    email: _email,
                    onSettingsChanged: _syncSettingsState,
                    onRefresh: _refreshProfileTab,
                    notificationService: widget.notificationService,
                    stepData: _stepData,
                    onAddProfilePhoto: _addOrChangeProfilePhoto,
                    onRemoveProfilePhoto: _removeProfilePhoto,
                    showBackButton: false,
                  ),
                ],
                    ),
                  );
                },
              ),
            ),

          // Single shell-level footer banner: loads once, survives tab switches,
          // and sits directly above the tab bar. Hidden on the home tab (and
          // while the keyboard is up). Not shown during onboarding.
          if (!isOnboarding && _currentTab != _homeTabIndex)
            Positioned(
              left: 0,
              right: 0,
              bottom: 77.5 + MediaQuery.of(context).padding.bottom,
              child: _MeasureSize(
                onChange: (size) {
                  final h = size.height;
                  if (_bannerHeight.value != h) {
                    _bannerHeight.value = h;
                  }
                },
                child: const AdBannerSlot(hideWhenKeyboardOpen: true),
              ),
            ),

          if (!isOnboarding)
            Positioned(
              left: 0,
              right: 0,
              bottom: 0,
              child: WoodenTabBar(
                currentIndex: _currentTab,
                onTap: (index) {
                  _pageController.animateToPage(
                    index,
                    duration: const Duration(milliseconds: 250),
                    curve: Curves.easeOutCubic,
                  );
                },
                items: [
                  const WoodenTabItem(icon: Icons.home_rounded, label: 'Home'),
                  const WoodenTabItem(
                    icon: Icons.directions_run_rounded,
                    label: 'Races',
                  ),
                  WoodenTabItem(
                    icon: Icons.people_rounded,
                    label: 'Friends',
                    badgeCount: _incomingFriendRequests,
                  ),
                  const WoodenTabItem(
                    icon: Icons.leaderboard_rounded,
                    label: 'Boards',
                  ),
                  const WoodenTabItem(
                    icon: Icons.person_rounded,
                    label: 'Profile',
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

/// Reports its child's laid-out size via [onChange]. Used to measure the shell
/// footer banner so the nav tabs can reserve exactly its rendered height (0
/// while it is collapsed) without hard-coding a banner height. The callback is
/// deferred to after the frame so it is safe to drive layout-affecting state.
class _MeasureSize extends SingleChildRenderObjectWidget {
  const _MeasureSize({required this.onChange, required super.child});

  final ValueChanged<Size> onChange;

  @override
  _MeasureSizeRenderObject createRenderObject(BuildContext context) =>
      _MeasureSizeRenderObject(onChange);

  @override
  void updateRenderObject(
    BuildContext context,
    _MeasureSizeRenderObject renderObject,
  ) {
    renderObject.onChange = onChange;
  }
}

class _MeasureSizeRenderObject extends RenderProxyBox {
  _MeasureSizeRenderObject(this.onChange);

  ValueChanged<Size> onChange;
  Size? _oldSize;

  @override
  void performLayout() {
    super.performLayout();
    final newSize = child?.size ?? Size.zero;
    if (_oldSize == newSize) return;
    _oldSize = newSize;
    WidgetsBinding.instance.addPostFrameCallback((_) => onChange(newSize));
  }
}

/// Result of the shared step-persistence orchestration ([_persistSteps], §9.2):
/// what the Home flow needs to decide its home-batch strategy and job polling.
class _StepSyncOutcome {
  const _StepSyncOutcome({
    required this.persisted,
    this.usePersistedHome = false,
    this.error = false,
    this.jobId,
    this.generation,
  });

  /// Step/sample data is (very likely) on the server.
  final bool persisted;

  /// The uploader's own totals/box state are CURRENT -> fetch Home with
  /// `homePersistedTotals=1`.
  final bool usePersistedHome;

  /// The sync could not be acknowledged as successful.
  final bool error;

  final String? jobId;
  final int? generation;
}
