import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../config/animals.dart';
import '../config/backend_config.dart';
import '../config/start_cape_metadata.dart';
import '../models/loadable.dart';
import '../models/home_race_suggestion.dart';
import '../models/home_invite_preflight.dart';
import '../models/next_race.dart';
import '../models/race_handoff_result.dart';
import '../models/race_payout_double_offer.dart';
import '../models/step_data.dart';
import '../models/step_sample_data.dart';
import '../services/async_ttl_cache.dart';
import '../services/activation_analytics_service.dart';
import '../services/ad_service.dart';
import '../services/onboarding_state_service.dart';
import '../utils/onboarding_gate.dart';
import '../widgets/notification_ask_dialog.dart';
import '../widgets/steps_disconnected_banner.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/remote_asset_cache.dart';
import '../services/background_sync_bootstrap_service.dart';
import '../services/discovery_join_coordinator.dart';
import '../services/health_service.dart';
import '../services/install_attribution_service.dart';
import '../services/notification_service.dart';
import '../services/review_prompt_service.dart';
import '../services/race_results_ack_queue.dart';
import '../utils/team_race.dart';
import '../utils/tournament.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/info_toast.dart';
import '../widgets/invite_code_sheet.dart';
import '../widgets/quick_create_race_sheet.dart';
import '../widgets/home_invite_overlay.dart';
import '../widgets/team_side_picker.dart';
import '../widgets/step_milestones_section.dart';
import '../widgets/streak_chip.dart';
import 'package:package_info_plus/package_info_plus.dart';

import '../widgets/whats_new_sheet.dart';
import '../widgets/wooden_tab_bar.dart';
import '../content/whats_new.dart';
import 'race_results_summary_screen.dart';
import 'ranked_results_summary_screen.dart';
import 'start_screen.dart';
import 'onboarding_flow.dart';
import 'discoverable_identity_flow.dart';
import '../demo/demo_race_host.dart';
import '../tutorial/tutorial_gate.dart';
import '../tutorial/tutorial_screen.dart';
import 'tabs/friends_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/leaderboard_tab.dart';
import 'tabs/profile_tab.dart';
import 'create_race_screen.dart';
import 'daily_reward_screen.dart';
import 'race_detail_screen.dart';
import 'public_races_screen.dart';
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
    this.racePayoutDoubleAdController,
    this.raceResultsAcknowledgementQueue,
    this.forceHomeInviteEligibilityForTesting = false,
  });

  final AuthService authService;
  final HealthService? healthService;
  final BackendApiService? backendApiService;
  final BackgroundSyncBootstrapService? backgroundSyncBootstrapService;
  final NotificationService? notificationService;
  final ReviewPromptService? reviewPromptService;
  final RacePayoutDoubleAdController? racePayoutDoubleAdController;
  final RaceResultsAcknowledgementQueue? raceResultsAcknowledgementQueue;
  @visibleForTesting
  final bool forceHomeInviteEligibilityForTesting;

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
  late final ActivationAnalyticsService _activationAnalytics;
  late final RaceResultsAcknowledgementQueue _raceResultsAckQueue;

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

  // --- onboarding revamp (v3) -----------------------------------------------
  // All persisted (see OnboardingStateService) so the ladder and the degraded
  // state survive an app kill mid-onboarding, and all default to the value that
  // reproduces the pre-v3 behavior when the keys are absent.
  final OnboardingStateService _onboardingState = OnboardingStateService();
  int _healthAttempts = 0;

  /// Batch 2026-08-09 item 9 — tutorial entries started and never completed.
  /// Feeds the local circuit breaker that hands the skip control back after
  /// [kTutorialAbandonLimit] of them, even while the backend flag is on.
  int _tutorialAbandons = 0;
  bool _escapedHealthGate = false;
  bool _probeInconclusive = false;
  int? _probeArmedAtMs;
  bool _homeReachedRecorded = false;
  // --- invite-code step ------------------------------------------------------
  // Null until the device-local done-flag has been read: "unknown" must never
  // render as "not done", or a returning user flashes a step they already
  // answered.
  bool? _inviteCodeStepDone;
  // Part C: a probable invite URL was detected on the iOS pasteboard at launch
  // but could not be read. Only in that state does the step offer the
  // consented paste button.
  bool _canPasteInviteLink = false;
  late final InstallAttributionService _installAttribution;
  bool _notificationAskShowing = false;
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
  final HomeSuggestedRacesStore _homeSuggestions = HomeSuggestedRacesStore();
  String? _homeSuggestionsUserId;
  final Set<String> _joiningHomeSuggestionKeys = {};
  bool _homeSuggestionsImpressionRecorded = false;
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
  // Coalesces overlapping Races refreshes (tab reveal, pull, route-return,
  // profile-triggered). Home owns a separate suggestions request.
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
  bool _openingDailyReward = false;
  bool _drainingTournament = false;
  // Races whose results popup we've already surfaced this session, so a race
  // finishing mid-session (or a re-fetch) doesn't re-interrupt. The server ack
  // (markRaceResultsSeen) is the durable source of truth across sessions.
  final Set<String> _raceResultsShownThisSession = {};
  bool _raceResultsPopupOpen = false;
  bool _nextRaceHomeShownRecorded = false;
  bool _inviteSetupShownRecorded = false;
  bool _homeInvitePopupOpen = false;
  bool _homeInviteSequenceRunning = false;
  int _homeInviteRequestGeneration = 0;

  /// Item 8 — a results modal (race or ranked) took the screen this session,
  /// so the What's New sheet waits for the next launch rather than stacking.
  bool _resultsModalShownThisSession = false;
  bool _whatsNewShownThisSession = false;
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

  /// The single source of truth for "is this user still onboarding".
  ///
  /// This expression used to be inlined in four places, and three of the copies
  /// had silently dropped the tutorial term — a real bug that let share-link
  /// drains fire mid-tutorial under v1. It now lives in one pure function
  /// (`utils/onboarding_gate.dart`) with a structural test guarding against the
  /// duplication coming back.
  bool get _isOnboarding =>
      !widget.forceHomeInviteEligibilityForTesting &&
          widget.authService.requiresDiscoverableIdentityOnboarding ||
      (!widget.forceHomeInviteEligibilityForTesting &&
          isOnboardingGate(
            onboardingV3Enabled: widget.authService.onboardingV3Enabled,
            onboardingV2Enabled: widget.authService.onboardingV2Enabled,
            healthAuthorized: _healthAuthorized,
            escapedHealthGate: _escapedHealthGate,
            notificationsState: _notificationsState,
            tutorialOnboardingSeen: widget.authService.tutorialOnboardingSeen,
            firstRaceOnboardingSeen: widget.authService.firstRaceOnboardingSeen,
          ));

  /// Whether the onboarding invite-code step is still owed.
  ///
  /// Every term must hold, and each one exists for a reason:
  ///  * v3 — the step lives only inside the v3 branch of the flow.
  ///  * the `onboardingInviteCodeEnabled` kill switch is not explicitly false
  ///    (fail-open: an older backend that never heard of it keeps the step).
  ///  * `authPayloadApplied` — the NO-FLASH rule. Until a user envelope has
  ///    been applied, `referredByCode == null` means "unknown", not
  ///    "unattributed", and rendering on a guess flashes the step at a
  ///    just-attributed user and then yanks it away.
  ///  * `referredByCode == null` — server truth for "attributed by ANY path"
  ///    (provision body, IP fallback, an earlier redeem, an ops repair).
  ///    Deliberately NOT `welcomeReferralCode`: that slot is stashed on
  ///    provision SUCCESS, not attribution success, so a body code the backend
  ///    silently rejected would set it while leaving the account unattributed
  ///    — exactly the user this step exists to catch.
  ///  * the device-local done-flag is read (non-null) and false.
  bool get _showInviteCodePrompt =>
      widget.authService.setupInviteCodePromptEnabled &&
      widget.authService.authPayloadApplied &&
      widget.authService.referredByCode == null &&
      !widget.authService.inviteCodePromptResolvedThisSession &&
      _inviteCodeStepDone == false;

  /// Opens the shared Home invite-code sheet. Terminal outcomes resolve the
  /// device prompt; a successful attribution also refreshes auth and friends
  /// because the backend may have created a friendship.
  Future<void> _openInviteCodeFromHome() async {
    final outcome = await showInviteCodeSheet(
      context: context,
      authService: widget.authService,
      backendApiService: _backendApiService,
    );
    if (!mounted || outcome == null) return;
    if (outcome.attributed || outcome.terminal) {
      await _onboardingState.markInviteCodePromptResolved();
      if (mounted) setState(() => _inviteCodeStepDone = true);
      unawaited(
        _activationAnalytics.record(
          'invite_code_setup_applied',
          context: {'attributed': '${outcome.attributed}'},
        ),
      );
    }
    if (outcome.attributed) {
      await Future.wait([_refreshMe(), _fetchFriendsSteps()]);
      if (mounted) showInfoToast(context, outcome.message);
    } else if (outcome.terminal && mounted) {
      showErrorToast(context, outcome.message);
    }
  }

  Future<void> _skipInviteCodeFromHome() async {
    if (_inviteCodeStepDone == true) return;
    setState(() => _inviteCodeStepDone = true);
    widget.authService.markInviteCodePromptResolvedThisSession();
    await _onboardingState.markInviteCodePromptResolved();
    unawaited(_activationAnalytics.record('invite_code_setup_dismissed'));
    if (mounted) {
      showInfoToast(
        context,
        'You can always enter an invite code in Settings.',
      );
    }
  }

  Future<void> _showQuickCreateRaceSheet({String surface = 'home'}) async {
    unawaited(
      _activationAnalytics.record(
        'next_race_cta_tapped',
        context: {'surface': surface},
      ),
    );
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) => QuickCreateRaceSheet(
        onCreate: (preset) => _createQuickRace(sheetContext, preset),
        onCustomize: () {
          unawaited(_openCustomizedRaceFromSheet(sheetContext));
        },
      ),
    );
  }

  Future<void> _openCustomizedRaceFromSheet(BuildContext sheetContext) async {
    Navigator.of(sheetContext).pop();
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => CreateRaceScreen(authService: widget.authService),
      ),
    );
    if (mounted) await Future.wait([_fetchRaceCard(), _fetchRacesCore()]);
  }

  Future<void> _createQuickRace(
    BuildContext sheetContext,
    QuickRacePreset preset,
  ) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('Not signed in.');
    }
    final names = preset == QuickRacePreset.twoDay
        ? const ['Weekend Sprint', 'Step Showdown', 'Trail Mix']
        : const ['Seven Day Showdown', 'Long Haul', 'Trail Week'];
    final name = names[DateTime.now().millisecondsSinceEpoch % names.length];
    unawaited(
      _activationAnalytics.record(
        'quick_create_selected',
        context: {
          'preset': preset == QuickRacePreset.twoDay ? '2_day' : '7_day',
        },
      ),
    );
    try {
      final payload = await _backendApiService.quickCreateRace(
        identityToken: token,
        name: name,
        maxDurationDays: preset.days,
      );
      final rawRace = payload['race'];
      if (rawRace is! Map || rawRace['id'] is! String) {
        throw const ApiException('Race created. Find it in your Races tab.');
      }
      final id = rawRace['id'] as String;
      final persistedAsQuick =
          rawRace['creationSource'] == 'QUICK_CREATE' &&
          rawRace['startPolicy'] == 'ON_MINIMUM_PARTICIPANTS';
      unawaited(
        _activationAnalytics.record(
          'quick_create_succeeded',
          context: {
            'preset': preset == QuickRacePreset.twoDay ? '2_day' : '7_day',
            'race_id': id,
          },
        ),
      );
      await Future.wait([_fetchRaceCard(), _fetchRacesCore()]);
      if (!mounted || !sheetContext.mounted) return;
      Navigator.of(sheetContext).pop();
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => RaceDetailScreen(
            authService: widget.authService,
            raceId: id,
            friends: _friendsSteps,
            notificationService: widget.notificationService,
            showPostCreateSharePrompt: persistedAsQuick,
          ),
        ),
      );
    } catch (error) {
      final code = error is ApiException ? error.code : null;
      const knownCodes = {
        'INVALID_QUICK_CREATE_CONFIG',
        'QUICK_CREATE_DISABLED',
        'QUICK_RACE_ALREADY_LIVE',
        'QUICK_RACE_MEMBERSHIP_LIMIT',
      };
      unawaited(
        _activationAnalytics.record(
          'quick_create_failed',
          context: {
            'preset': preset == QuickRacePreset.twoDay ? '2_day' : '7_day',
            'error_code': knownCodes.contains(code) ? code! : 'UNKNOWN',
          },
        ),
      );
      rethrow;
    }
  }

  /// Part C: emits the single stashed install-attribution outcome (one event
  /// per install, name-encoded) now that a signed-in token exists, and learns
  /// whether a probable invite URL was detected but never read.
  ///
  /// Deliberately does NOT re-run `resolveOnFirstLaunch` — that stays
  /// at-most-once per install, and a second launch-time pasteboard read is the
  /// exact behavior part C is retiring.
  Future<void> _resolveInstallAttributionTelemetry() async {
    try {
      await _installAttribution.flushStashedOutcome(_activationAnalytics);
      final canPaste = await _installAttribution.hasUnreadDetectedInvite();
      if (mounted && canPaste != _canPasteInviteLink) {
        setState(() => _canPasteInviteLink = canPaste);
      }
    } catch (_) {
      // Telemetry must never break a launch.
    }
    unawaited(_activationAnalytics.flush(widget.authService.authToken));
  }

  /// Whether the persistent "steps aren't connected" banner should be showing.
  ///
  /// Deliberately independent of [_isOnboarding]: a degraded user is NOT
  /// onboarding, so the tab bar and the ad banner render exactly as they do for
  /// everyone else. Suppressing them would re-create the dead end this state
  /// exists to fix.
  bool get _stepsDisconnected => OnboardingStateService.degradedBannerVisible(
    onboardingV3Enabled: widget.authService.onboardingV3Enabled,
    healthAuthorized: _healthAuthorized,
    escapedHealthGate: _escapedHealthGate,
    probeInconclusive: _probeInconclusive,
    probeArmedAtMs: _probeArmedAtMs,
  );

  /// Loads the persisted v3 bookkeeping. Runs before anything reads
  /// [_escapedHealthGate] — notably `_restoreAndFetch`, which would otherwise
  /// hard-return and leave an escaped user staring at a fully empty app.
  Future<void> _loadOnboardingState() async {
    // Item 20 (batch 2026-08-08): four INDEPENDENT SharedPreferences reads that
    // used to await one at a time on the cold-start critical path. They read
    // four different keys and none feeds another, so they go out together.
    // Same values, same setState, one round of latency instead of four.
    final values = await Future.wait([
      _onboardingState.healthAttemptCount(),
      _onboardingState.escapedHealthGate(),
      _onboardingState.probeInconclusive(),
      _onboardingState.probeArmedAtMs(),
      _onboardingState.inviteCodeStepDone(),
      // Item 9: one more key on the same round trip.
      tutorialAbandonCount(),
    ]);
    final attempts = values[0] as int;
    final escaped = values[1] as bool;
    final inconclusive = values[2] as bool;
    final armedAt = values[3] as int?;
    final inviteDone = values[4] as bool;
    final abandons = values[5] as int;
    if (!mounted) return;
    setState(() {
      _healthAttempts = attempts;
      _escapedHealthGate = escaped;
      _probeInconclusive = inconclusive;
      _probeArmedAtMs = armedAt;
      _inviteCodeStepDone = inviteDone;
      _tutorialAbandons = abandons;
    });
  }

  /// The way out of a health gate the OS has stopped cooperating with.
  ///
  /// Both onboarding terms are closed here, not just the first-race one. The
  /// escape happens BEFORE the tutorial and the race intro, so leaving either
  /// flag false would drop the user straight back into a gate on the next
  /// rebuild — the escape would not be an escape.
  Future<void> _escapeHealthGate() async {
    await _onboardingState.setEscapedHealthGate(true);
    unawaited(_activationAnalytics.record('health_escaped'));
    if (mounted) setState(() => _escapedHealthGate = true);
    // Local first, network second. The escape must be instant and must not be
    // hostage to a request that may be slow or failing — this is the path a
    // user takes precisely because something already isn't working.
    await widget.authService.markFirstRaceOnboardingSeenLocally();
    // Item 8: a fresh install has just finished onboarding — record the
    // current version as seen so the changelog does not greet them for a
    // build they have never used. They meet it on session two.
    await markWhatsNewSeenForOnboarding();
    unawaited(_skipFirstRaceOnboarding());
    // Item 9 (ui-test-planner R3 audit): this escape hatch marked the TUTORIAL
    // seen too, which under mandatory mode would be a bypass — a user who
    // can't grant health access would land in the app having never seen it.
    // The health gate and the tutorial gate are independent; nothing about a
    // failed health permission stops a demo race from running.
    if (!_tutorialMandatory) {
      unawaited(widget.authService.markTutorialOnboardingSeen());
    }
    if (!mounted) return;
    // The degraded user still gets a real app: load every home surface that
    // does not depend on a local step read.
    unawaited(_loadHomeAndShowResults());
  }

  /// The banner's one action. A prompt the user can answer is always the
  /// shorter path, so retry first and only deep-link once that has stopped
  /// producing anything.
  Future<void> _fixDisconnectedSteps() async {
    if (_healthAttempts >= 2) {
      final launched = await _healthService.openPlatformHealthSettings();
      if (launched) return;
    }
    await _enableHealthData();
  }

  /// Re-probes an armed-but-latent (or visible) degraded state. The banner
  /// clears the moment steps appear, which is what makes the iOS
  /// false-positive case — a genuinely idle device — self-heal with no user
  /// action at all.
  Future<void> _reprobeSteps() async {
    if (!widget.authService.onboardingV3Enabled) return;
    if (!_probeInconclusive) return;
    final steps = await _healthService.probeTrailingSteps();
    if (steps <= 0 || !mounted) return;
    await _onboardingState.clearProbeInconclusive();
    unawaited(_activationAnalytics.record('health_recovered'));
    if (!mounted) return;
    setState(() {
      _probeInconclusive = false;
      _probeArmedAtMs = null;
    });
  }

  /// Fires the relocated notification ask (spec §5.4). Safe to call from any
  /// trigger: it self-guards on the OS permission state, the per-install cap,
  /// and whether this particular trigger has already been consumed.
  Future<void> maybeAskForNotifications(NotificationAskTrigger trigger) async {
    if (!widget.authService.onboardingV3Enabled) return;
    if (_notificationAskShowing) return;
    final ns = widget.notificationService;
    if (ns == null) return;
    final permission = await ns.getPermissionState();
    final should = await _onboardingState.shouldAskForNotifications(
      trigger: trigger,
      permissionState: permission,
    );
    if (!should || !mounted) return;

    _notificationAskShowing = true;
    unawaited(_activationAnalytics.record('notif_prompt_shown'));
    // Recorded before the await that opens the dialog so the context capture
    // below is the same frame as the mounted check above.
    final askFuture = NotificationAskDialog.show(context);
    await _onboardingState.recordNotificationAsk(trigger);
    try {
      final accepted = await askFuture;
      if (!accepted) {
        // Declining IN-APP leaves the OS permission undetermined, so the
        // backstop can still fire once. That is the point of the two-ask cap.
        unawaited(
          _activationAnalytics.record(
            'notif_result',
            context: const {'result': 'dismissed'},
          ),
        );
        return;
      }
      final granted = await ns.requestPermission(widget.authService.authToken);
      unawaited(
        _activationAnalytics.record(
          'notif_result',
          context: {'result': granted ? 'granted' : 'denied'},
        ),
      );
      if (mounted) setState(() => _notificationsState = granted);
    } finally {
      _notificationAskShowing = false;
    }
  }

  void _handleAuthServiceChanged() {
    if (!mounted) return;
    final nextUserId = widget.authService.userId;
    final userChanged = _homeSuggestionsUserId != nextUserId;
    setState(() {
      _homeSuggestionsUserId = nextUserId;
      _homeSuggestions.setUser(nextUserId);
    });
    // A cold-start suggestions request can begin before /me establishes the
    // backend user id. setUser intentionally invalidates that response so it
    // cannot cross accounts; immediately replace it for the newly known user.
    if (userChanged && nextUserId != null) {
      unawaited(_refreshHomeSuggestions());
    }
    // A share token may have just been captured (link tapped while running) or
    // the final onboarding step may have just completed — either way, try to
    // drain. Idempotent: no-ops when there's no token or onboarding isn't done.
    _maybeDrainPendingSharedRace();
    _maybeDrainPendingSharedTournament();
    _maybeCaptureInviterRace();
    _maybeOfferInviterRace();
    unawaited(_hydrateAndReplayRaceResultsAcks());
    if (!_isOnboarding) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) unawaited(_coordinateHomeOverlays());
      });
    }
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
    _activationAnalytics = ActivationAnalyticsService(
      backendApiService: _backendApiService,
    );
    _raceResultsAckQueue =
        widget.raceResultsAcknowledgementQueue ??
        RaceResultsAcknowledgementQueue(backendApiService: _backendApiService);
    _homeSuggestionsUserId = widget.authService.userId;
    _homeSuggestions.setUser(_homeSuggestionsUserId);
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
    widget.authService.addListener(_handleAuthServiceChanged);
    widget.notificationService?.pendingAction.addListener(
      _onNotificationAction,
    );
    _restoreAndFetch();
    // Extended past v2: the funnel needs a denominator on every flow, not only
    // the one that happened to be shipping when the event was added.
    if (!widget.authService.firstRaceOnboardingSeen) {
      unawaited(_activationAnalytics.record('onboarding_started'));
    }
    // Part C: flush the one stashed install-attribution outcome (recorded in
    // main() before any token existed) and learn whether the pasteboard was
    // detected-but-unread. Ends by flushing the queue, which is why the plain
    // flush that used to sit here is folded into it.
    _installAttribution = InstallAttributionService(
      authService: widget.authService,
    );
    unawaited(_resolveInstallAttributionTelemetry());
    unawaited(_startAppSession());
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

    switch (action.route) {
      case NotificationRoute.raceDetail:
        final raceId = action.params['raceId'];
        if (raceId is String && raceId.isNotEmpty) {
          widget.notificationService?.pendingAction.value = null;
          // Shares the tap guard so a notification tap can't stack a second
          // detail screen over one already opening.
          _openRaceFromCard(raceId);
        }
        break;
      case NotificationRoute.races:
        widget.notificationService?.pendingAction.value = null;
        _pageController.jumpToPage(_racesTabIndex);
        break;
      case NotificationRoute.friends:
        widget.notificationService?.pendingAction.value = null;
        // Friends is now a primary tab (index 2); jumping there also clears the
        // incoming-request badge via onPageChanged.
        _pageController.jumpToPage(_friendsTabIndex);
        break;
      case NotificationRoute.home:
        widget.notificationService?.pendingAction.value = null;
        _pageController.jumpToPage(_homeTabIndex);
        break;
      case NotificationRoute.tournamentDetail:
        final tournamentId = action.params['tournamentId'];
        if (tournamentId != null && tournamentId.isNotEmpty) {
          widget.notificationService?.pendingAction.value = null;
          _openTournament(tournamentId);
        }
        break;
      case NotificationRoute.dailyReward:
        widget.notificationService?.pendingAction.value = null;
        // Daily-reward reminder tap (spec §7): open the same blurred-overlay
        // daily-reward screen the home StreakChip / Get Coins hub push, so the
        // user lands directly on the unclaimed box.
        _openDailyReward();
        break;
    }
  }

  /// Opens the daily-reward reveal screen as a non-opaque overlay (matching the
  /// StreakChip / Get Coins entry points). Reached from a DAILY_REWARD_REMINDER
  /// push tap. The rewarded-ad extra spin is omitted here (no ad controller in
  /// the shell); the core claim flow is unaffected.
  void _openDailyReward() {
    if (_openingDailyReward) return;
    _openingDailyReward = true;
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            opaque: false,
            transitionDuration: const Duration(milliseconds: 250),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            pageBuilder: (_, _, _) => DailyRewardScreen(
              authService: widget.authService,
              backendApiService: _backendApiService,
              onClaimed: _markDailyRewardClaimed,
            ),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        )
        .whenComplete(() => _openingDailyReward = false);
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
    // onboarding overlay would be wrong. Shares build()'s gate exactly — this
    // used to be an inline copy that had drifted, which let a share-link drain
    // fire while the user was still on the tutorial step.
    if (_isOnboarding) return;

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

    if (_isOnboarding) return;

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

    if (_isOnboarding) return;

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
        showErrorToast(context, 'Couldn\'t join right now. Try again later.');
      }
      return;
    }
    if (!mounted) return;
    _fetchRaces();
    _openRaceFromCard(raceId);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // The escaped user has no local health read, but every server-side surface
    // still needs refreshing on resume — otherwise the degraded app is also a
    // stale one.
    if (state == AppLifecycleState.resumed &&
        (_healthAuthorized || _escapedHealthGate)) {
      if (_currentTab == _homeTabIndex) {
        _homeSuggestionsImpressionRecorded = false;
        // A resume begins an epoch immediately. Cached visible/empty data has
        // already reached a resolved state, so count the impression now; a
        // transient refresh must not erase this epoch's only impression.
        if (_homeSuggestions.state.isSuccess ||
            _homeSuggestions.state.hasData) {
          _recordHomeSuggestionsImpression();
        }
      }
      unawaited(_activationAnalytics.flush(widget.authService.authToken));
      // Re-probe on every resume: the banner clears the moment steps appear,
      // so a genuinely idle device heals itself with no user action.
      unawaited(_reprobeSteps());
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

  /// Bumps the app-session counter and runs the notification backstop for a
  /// user who never opens a box. Without this, moving the ask to first-box-open
  /// would leave a box-less subset never asked at all — a regression against
  /// today, where everyone is asked during onboarding.
  Future<void> _startAppSession() async {
    await _onboardingState.bumpSessionCount();
    if (!mounted) return;
    if (_isOnboarding) return;
    await maybeAskForNotifications(NotificationAskTrigger.session);
  }

  Future<void> _restoreAndFetch() async {
    setState(() {
      _displayName = widget.authService.displayName;
    });
    // Must land before the health check below, which branches on the escape.
    await _loadOnboardingState();
    if (!mounted) return;

    final sessionIsValid = await _refreshSessionToken();
    if (!sessionIsValid || !mounted) return;

    // Hydrate before the first race fetch/result detection. Matching queued
    // IDs are suppressed locally even when the atomic server ack is offline.
    await _hydrateAndReplayRaceResultsAcks();
    if (!mounted) return;

    final wasAuthorized = await _healthService.restoreHealthAuthState();
    if (!mounted) return;
    // This used to hard-return whenever health wasn't authorized, which would
    // have starved the degraded user: tabs present, and not one of them ever
    // loaded. An escaped user has no local step data but everything else —
    // races, friends, coins, boxes — is server-side and must still load.
    if (!wasAuthorized && !_escapedHealthGate) return;

    if (wasAuthorized) setState(() => _healthAuthorized = true);
    unawaited(_reprobeSteps());
    // Item 20: two INDEPENDENT platform-channel round trips (a HealthKit
    // background-delivery registration and an OS notification-permission
    // read). Neither reads the other's result, so they overlap. Both are
    // still awaited before the post-frame notification drain below, which is
    // the only thing downstream that cares.
    await Future.wait([
      _backgroundSyncBootstrapService.enableHealthKitBackgroundDelivery(),
      _checkNotificationState(),
    ]);
    // Notification initialization can finish before this shell exists on a
    // cold start. ValueNotifier retains that launch action but does not replay
    // it to listeners, so drain it once the authenticated shell can navigate.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _onNotificationAction();
    });
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
        await widget.authService.syncFromBackendUser(user, authoritative: true);
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
    unawaited(_activationAnalytics.record('health_cta_tapped'));
    setState(() => _isLoading = true);

    try {
      final result = await _healthService.setUpHealthAccess();

      // Not an attempt, deliberately: this already sent the user to the Play
      // Store and retrying is exactly what they should do next. Counting it
      // would hand out the escape hatch to someone who has not yet been asked.
      if (result == HealthSetupResult.needsHealthConnect) {
        unawaited(
          _activationAnalytics.record(
            'health_result',
            context: const {'result': 'unsupported'},
          ),
        );
        setState(() {
          _isLoading = false;
          _error =
              'Health Connect is required to track your steps.\n'
              'Install or update it, then tap Continue again.';
        });
        return;
      }

      if (result == HealthSetupResult.denied) {
        final attempts = await _onboardingState.bumpHealthAttemptCount();
        unawaited(
          _activationAnalytics.record(
            'health_result',
            context: const {'result': 'denied'},
          ),
        );
        if (!mounted) return;
        setState(() {
          _healthAttempts = attempts;
          _isLoading = false;
          _error = attempts >= 2
              ? 'Bara still can’t read your steps. Open Health Connect '
                    'settings and turn Steps on for Bara. You can also continue '
                    'without steps and connect later.'
              : 'Steps access wasn’t granted. Tap Try Again to show the '
                    'permission prompt again, then allow Bara to read your '
                    'steps.';
        });
        return;
      }

      // Inconclusive is iOS-only and means "we cannot tell a denial from an
      // idle device". Per the owner's call we do NOT re-block: the user goes
      // through, and the degraded state arms latently for six hours so a 6am
      // signup with an empty step history is never told their health is
      // broken seconds after onboarding.
      if (result == HealthSetupResult.inconclusive) {
        await _onboardingState.armProbeInconclusive();
        final armedAt = await _onboardingState.probeArmedAtMs();
        unawaited(_activationAnalytics.record('health_probe_inconclusive'));
        if (!mounted) return;
        setState(() {
          _probeInconclusive = true;
          _probeArmedAtMs = armedAt;
        });
      } else {
        unawaited(
          _activationAnalytics.record(
            'health_result',
            context: const {'result': 'granted'},
          ),
        );
        // A conclusive grant retires any earlier degraded state.
        if (_probeInconclusive || _escapedHealthGate) {
          await _onboardingState.clearProbeInconclusive();
          await _onboardingState.setEscapedHealthGate(false);
          unawaited(_activationAnalytics.record('health_recovered'));
          if (!mounted) return;
          setState(() {
            _probeInconclusive = false;
            _probeArmedAtMs = null;
            _escapedHealthGate = false;
          });
        }
      }

      setState(() => _healthAuthorized = true);
      await _backgroundSyncBootstrapService.enableHealthKitBackgroundDelivery();
      await _checkNotificationState();
      _fetchRaceCard();
      await _fetchSteps();
    } catch (e) {
      unawaited(
        _activationAnalytics.record(
          'health_result',
          context: const {'result': 'failed'},
        ),
      );
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

    // Decide off the REAL OS permission, not the SharedPreferences cache. The
    // cache goes stale (sign-out wipes it; a denied-once flag used to block
    // re-registration forever) and a user can sit for months with permission
    // granted but every push going to a dead token.
    final osState = await ns.getSystemPermissionState();
    if (!mounted) return;

    if (osState == true) {
      // OS-granted — always re-register the token this session (tokens rotate
      // across reinstall/restore/new phone). Outcome goes to analytics so the
      // next silent failure is diagnosable from the backend.
      setState(() => _notificationsState = true);
      final outcome = await ns.ensureTokenRegistered(
        widget.authService.authToken,
      );
      unawaited(
        _activationAnalytics.record(
          'push_token_sync',
          context: {'result': outcome},
        ),
      );
    } else if (osState == false) {
      // Denied at the OS level — don't nag
      setState(() => _notificationsState = false);
    } else {
      // OS says never determined. A cached "granted" is provably stale here
      // (reinstall) — clear it so the opt-in can run again instead of the app
      // pretending notifications work.
      final cached = await ns.getPermissionState();
      if (cached == true) await ns.clearCachedPermission();
      if (!mounted) return;
      setState(() => _notificationsState = cached == false ? false : null);
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
  Future<_StepSyncOutcome> _persistSteps({bool homePull = false}) async {
    final identityToken = widget.authService.authToken;
    final now = DateTime.now();
    final results = await Future.wait([
      _healthService.getStepsToday(),
      _healthService.getStepSamples(
        startTime: DateTime(now.year, now.month, now.day),
        endTime: now,
        bucketMinutes: widget.authService.stepSampleBucketMinutes,
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
      homePull: homePull,
    );

    // Local step display is always truthful from the device read, regardless of
    // the server outcome.
    if (mounted) setState(() => _stepData = stepData);

    if (v2.shouldLegacyFallback) {
      final ok = await _legacySyncSteps(identityToken, stepData, hourlySamples);
      return _StepSyncOutcome(persisted: ok, error: !ok);
    }

    if (v2.isCooldown) {
      return _StepSyncOutcome(
        persisted: false,
        cooldown: true,
        cooldownSeconds: v2.retryAfterSeconds,
      );
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
        at == null ||
        DateTime.now().difference(at) > const Duration(seconds: 60);
    if (_friendsSteps.isEmpty || stale) {
      unawaited(_fetchFriendsSteps());
    }
  }

  /// Shared personal-races refresh. Home and non-Races callers must not fan out
  /// into discovery; Races-tab entry owns [_refreshRacesDiscovery].
  Future<void> _fetchRaces() async {
    await _fetchRacesCore();
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

      await _hydrateAndReplayRaceResultsAcks();

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

  Future<void> _refreshHomeSuggestions() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    _homeSuggestions.setUser(widget.authService.userId);
    late final int generation;
    if (mounted) {
      setState(() => generation = _homeSuggestions.beginRefresh());
    } else {
      return;
    }
    final refresh = await _backendApiService.fetchHomeSuggestedRaces(
      identityToken: token,
    );
    if (!mounted) return;
    var applied = false;
    setState(() {
      applied = _homeSuggestions.apply(generation, refresh);
    });
    if (applied && refresh.anyResolved) {
      _recordHomeSuggestionsImpression();
    }
  }

  void _recordHomeSuggestionsImpression() {
    if (_homeSuggestionsImpressionRecorded || _currentTab != _homeTabIndex) {
      return;
    }
    final suggestions = _homeSuggestions.state.data ?? const [];
    int count(HomeRaceSuggestionKind kind) =>
        suggestions.where((item) => item.kind == kind).length;
    _homeSuggestionsImpressionRecorded = true;
    unawaited(
      _activationAnalytics.record(
        'home_suggested_races_shown',
        context: {
          'featured_count': '${count(HomeRaceSuggestionKind.featuredRace)}',
          'public_count': '${count(HomeRaceSuggestionKind.publicRace)}',
          'tournament_count': '${count(HomeRaceSuggestionKind.tournament)}',
        },
      ),
    );
  }

  Future<void> _joinHomeSuggestion(HomeRaceSuggestion suggestion) async {
    if (_joiningHomeSuggestionKeys.contains(suggestion.stableKey)) return;
    final suggestions = _homeSuggestions.state.data ?? const [];
    final position = suggestions.indexWhere(
      (item) => item.stableKey == suggestion.stableKey,
    );
    unawaited(
      _activationAnalytics.record(
        'home_suggested_race_tapped',
        context: {
          'suggestion_kind': suggestion.wireKind,
          'suggestion_id': suggestion.id,
          'position': '${position < 0 ? 0 : position}',
        },
      ),
    );
    setState(() => _joiningHomeSuggestionKeys.add(suggestion.stableKey));
    final coordinator = DiscoveryJoinCoordinator(
      authService: widget.authService,
      backendApiService: _backendApiService,
    );
    final result = suggestion.kind == HomeRaceSuggestionKind.tournament
        ? await coordinator.joinTournament(
            context,
            suggestion.raw,
            featured: suggestion.seedKind != null,
          )
        : await coordinator.joinRace(context, suggestion.raw);
    if (!mounted) return;
    if (result == null) {
      setState(() => _joiningHomeSuggestionKeys.remove(suggestion.stableKey));
      return;
    }

    // The successful command is authoritative. Hide it before any refresh or
    // route transition; the tombstone prevents stale/unresolved responses from
    // putting it back.
    setState(() {
      _homeSuggestions.tombstone(suggestion);
      _joiningHomeSuggestionKeys.remove(suggestion.stableKey);
    });
    unawaited(
      Future.wait([
        _refreshHomeSuggestions(),
        _fetchRaceCard(),
        _fetchRacesCore(),
      ]),
    );
    if (result.target == DiscoveryJoinTarget.tournament) {
      _openTournament(result.id);
    } else {
      _openRaceFromCard(result.id);
    }
  }

  Future<void> _openPublicRacesFromHome() async {
    final result = await Navigator.of(context).push<RaceHandoffResult>(
      MaterialPageRoute(
        builder: (_) => PublicRacesScreen(
          authService: widget.authService,
          backendApiService: _backendApiService,
        ),
      ),
    );
    if (!mounted) return;
    unawaited(
      Future.wait([
        _refreshHomeSuggestions(),
        _fetchRaceCard(),
        _fetchRacesCore(),
      ]),
    );
    if (result != null) _openRaceFromCard(result.raceId);
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
    return _homeLoadInFlight ??= _loadHomeAndShowResultsInner().whenComplete(
      () {
        _homeLoadInFlight = null;
      },
    );
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

    // Home discovery runs beside the modal-critical work but never gates result
    // or What's New presentation.
    unawaited(_refreshHomeSuggestions());
    await Future.wait([
      _fetchRaceCard(usePersistedTotals: outcome?.usePersistedHome ?? false),
      // Await ONLY the core race list — result-modal detection consumes
      // completed races. Discovery must not gate the load (§9.4).
      _fetchRacesCore(),
      _fetchShopCatalog(),
      _fetchFriendsSteps(),
      _refreshMe(),
    ]);

    if (outcome?.jobId != null && outcome?.generation != null) {
      _startJobPolling(outcome!.jobId!, outcome.generation!);
    }

    if (!mounted) return;
    // Item 8 — ordering is load-bearing. Results modals win; What's New only
    // gets the screen when neither of them took it, and it must run AFTER
    // both have had their chance (hence the awaits, which previously were
    // fire-and-forget). The share-race drain happens later in
    // `_restoreAndFetch`, so this stays ahead of it.
    await _coordinateHomeOverlays();
    if (!mounted) return;
    await _maybeShowRankedResults();
    if (!mounted) return;
    await _maybeShowWhatsNew();
  }

  /// Item 8 — the "What's New" sheet, at most once per version per device.
  ///
  /// Three suppression rules, all deliberate:
  ///  * NEVER stack on a results modal. If one showed this session the sheet
  ///    is deferred to the next launch — two modals over a cold start is a
  ///    wall, not a welcome.
  ///  * NEVER during the onboarding session. A fresh install is marked as
  ///    having seen the current version when onboarding completes
  ///    ([markWhatsNewSeenForOnboarding]), so fresh installs meet the sheet on
  ///    their SECOND session and updaters meet it immediately.
  ///  * Nothing at all when this build has no bundled changelog entry.
  Future<void> _maybeShowWhatsNew() async {
    if (!mounted) return;
    if (_whatsNewShownThisSession) return;
    if (_resultsModalShownThisSession) return;
    if (_isOnboarding) return;

    // Don't open over whatever else is on top of the shell.
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;

    final version = (await PackageInfo.fromPlatform()).version;
    final entry = whatsNewEntryFor(version);
    final lastSeen = await _onboardingState.lastSeenWhatsNewVersion();
    if (!OnboardingStateService.shouldShowWhatsNew(
      currentVersion: version,
      lastSeenVersion: lastSeen,
      hasEntryForVersion: entry != null,
    )) {
      return;
    }
    if (!mounted) return;

    _whatsNewShownThisSession = true;
    // Mark BEFORE showing: a user who force-quits mid-sheet has still been
    // told, and re-showing on every launch until they tap the button would be
    // worse than missing it once.
    await _onboardingState.setLastSeenWhatsNewVersion(version);
    if (!mounted) return;
    await WhatsNewSheet.show(context, entry!);
  }

  /// Records the current version as seen WITHOUT showing the sheet — called
  /// when onboarding completes so a fresh install isn't greeted by a changelog
  /// for a build it has never used.
  Future<void> markWhatsNewSeenForOnboarding() async {
    try {
      final version = (await PackageInfo.fromPlatform()).version;
      if (version.isEmpty) return;
      await _onboardingState.setLastSeenWhatsNewVersion(version);
      _whatsNewShownThisSession = true;
    } catch (_) {
      // Never let changelog bookkeeping break onboarding completion.
    }
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
      // `/tournaments/public` is additive. An older backend can reject it;
      // keep the ordinary/team count in that case instead of blanking the
      // whole affordance. Current backends return only joinable tournaments,
      // so adding its list length matches the public discovery surface.
      var tournamentCount = 0;
      try {
        final tournaments = await _backendApiService.fetchPublicTournaments(
          identityToken: identityToken,
        );
        // The legacy discovery response separates joinable tournament cards
        // into featured and browse lists. Both are visible from PUBLIC RACES.
        final featured = tournaments['featured'];
        final browse = tournaments['tournaments'];
        tournamentCount =
            (featured is List ? featured.length : 0) +
            (browse is List ? browse.length : 0);
      } catch (_) {
        // Legacy endpoint absent or transiently unavailable: races still win.
      }
      if (mounted) {
        setState(() => _publicRacesCount = races.length + tournamentCount);
      }
    } catch (_) {
      // Keep the last known count on error.
    }
  }

  /// Results always win over Home invitations. The coordinator is deliberately
  /// shell-owned: Home rebuilds, tab changes, and refreshes cannot tear down a
  /// modal route or stack it over a results/reward/quick-create route.
  Future<void> _coordinateHomeOverlays() async {
    await _maybeShowRaceResults();
    if (!mounted) return;
    await _maybeShowHomeInvites();
  }

  Future<void> _maybeShowHomeInvites() async {
    if (!mounted ||
        _isOnboarding ||
        _currentTab != _homeTabIndex ||
        _homeInvitePopupOpen ||
        _homeInviteSequenceRunning ||
        _raceResultsPopupOpen) {
      return;
    }
    final route = ModalRoute.of(context);
    if (route != null && !route.isCurrent) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    _homeInviteSequenceRunning = true;
    final generation = ++_homeInviteRequestGeneration;
    try {
      while (mounted && _currentTab == _homeTabIndex) {
        final payload = await _backendApiService.fetchHomeInvitePreflight(
          identityToken: token,
        );
        if (!mounted ||
            generation != _homeInviteRequestGeneration ||
            token != widget.authService.authToken ||
            _currentTab != _homeTabIndex) {
          return;
        }
        final preflight = HomeInvitePreflight.tryParse(payload);
        if (!preflight.supported || preflight.invites.isEmpty) return;

        final invite = preflight.invites.first;
        setState(() => _homeInvitePopupOpen = true);
        final answered = await Navigator.of(context).push<bool>(
          PageRouteBuilder(
            opaque: false,
            transitionDuration: const Duration(milliseconds: 250),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            pageBuilder: (_, _, _) => HomeInviteOverlay(
              invite: invite,
              onRespond: (accept) => _respondToHomeInvite(invite, accept),
            ),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        );
        if (!mounted) return;
        setState(() => _homeInvitePopupOpen = false);
        if (answered != true) {
          // X/back is non-mutating. Re-read the existing card to restore its
          // normal inline fallback after this route has fully popped.
          unawaited(_fetchRaceCard());
          return;
        }
        // Accept/decline/reconciliation is never optimistic. Refresh the
        // authoritative personal list + Home card before the next preflight.
        await Future.wait([_fetchRacesCore(), _fetchRaceCard()]);
      }
    } catch (_) {
      // Unsupported/offline/malformed preflight is intentionally invisible:
      // the established inline and detail invite routes remain usable.
    } finally {
      _homeInviteSequenceRunning = false;
    }
  }

  Future<void> _respondToHomeInvite(HomeInvite invite, bool accept) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      throw const ApiException('Sign in again to answer this invitation.');
    }
    try {
      if (invite.isTournament) {
        await _backendApiService.respondToTournamentInvite(
          identityToken: token,
          tournamentId: invite.id,
          accept: accept,
        );
      } else {
        await _backendApiService.respondToRaceInvite(
          identityToken: token,
          raceId: invite.id,
          accept: accept,
        );
      }
    } on ApiException catch (error) {
      // These mean a concurrent answer/withdrawal won. Route pop triggers the
      // required authoritative fresh preflight rather than retaining a stale
      // unanswerable card.
      if (error.code == 'ALREADY_RESPONDED' ||
          error.code == 'NOT_INVITED' ||
          error.statusCode == 404) {
        return;
      }
      throw ApiException(
        error.code == 'TEAM_FULL'
            ? 'That team is full. Try another invitation.'
            : error.code == 'INSUFFICIENT_COINS'
            ? 'You need more coins to accept this invitation.'
            : error.message,
        statusCode: error.statusCode,
        code: error.code,
      );
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
    if (!mounted || _raceResultsPopupOpen || _isOnboarding) return;

    final completed = _safeStringMaps(_racesData?['completed']);
    final userId = widget.authService.userId;
    final identityToken = widget.authService.authToken;
    final backendBaseUrl = BackendConfig.baseUrl;
    final suppressed = userId == null || userId.isEmpty
        ? const <String>{}
        : _raceResultsAckQueue.suppressedRaceIds(
            userId: userId,
            backendBaseUrl: backendBaseUrl,
          );
    final capable = _racePayoutDoubleCapability;

    // Parse against the complete returned page first. A non-null offer ID is
    // recovery and therefore selects its frozen races BEFORE resultsSeen.
    final allCompletedIds = completed
        .map((race) => race['id'])
        .whereType<String>()
        .toList(growable: false);
    final pageOffer = capable
        ? RacePayoutDoubleOffer.tryParse(
            _racesData?['payoutDoubleOffer'],
            popupRaceIds: allCompletedIds,
          )
        : null;

    List<Map<String, dynamic>> unseen;
    RacePayoutDoubleOffer? popupOffer;
    if (pageOffer?.offerId != null) {
      final frozenIds = pageOffer!.raceIds.toSet();
      if (frozenIds.any(suppressed.contains)) return;
      unseen = completed
          .where((race) {
            return race['myStatus'] == 'ACCEPTED' &&
                frozenIds.contains(race['id']);
          })
          .toList(growable: false);
      if (unseen.length != frozenIds.length) return;
      popupOffer = RacePayoutDoubleOffer.tryParse(
        _racesData?['payoutDoubleOffer'],
        popupRaceIds: unseen.map((race) => race['id']).whereType<String>(),
      );
      if (popupOffer?.offerId == null) return;
    } else {
      unseen = completed
          .where((race) {
            if (race['myStatus'] != 'ACCEPTED') return false;
            final seen = (race['myResultsSeen'] as bool?) ?? true;
            if (seen) return false;
            final id = race['id'];
            if (id is! String || id.isEmpty || suppressed.contains(id)) {
              return false;
            }
            return !_raceResultsShownThisSession.contains(id);
          })
          .toList(growable: false);
      popupOffer = capable
          ? RacePayoutDoubleOffer.tryParse(
              _racesData?['payoutDoubleOffer'],
              popupRaceIds: unseen
                  .map((race) => race['id'])
                  .whereType<String>(),
            )
          : null;
    }

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
    // Item 8: a results modal showed, so What's New defers to the next launch.
    _resultsModalShownThisSession = true;
    final nextRace = NextRaceState.tryParse(_racesData?['nextRace']);
    if (nextRace?.resolved == true &&
        nextRace?.eligible == true &&
        nextRace?.createEnabled == true) {
      unawaited(
        _activationAnalytics.record(
          'next_race_cta_shown',
          context: {'surface': 'results'},
        ),
      );
    }
    final startNext = await Navigator.of(context).push<bool>(
      PageRouteBuilder(
        opaque: false,
        pageBuilder: (_, _, _) => RaceResultsSummaryScreen(
          races: unseen,
          canStartNextRace:
              nextRace?.resolved == true &&
              nextRace?.eligible == true &&
              nextRace?.createEnabled == true,
          payoutDoubleOffer: popupOffer,
          authService: widget.authService,
          backendApiService: _backendApiService,
          adController: popupOffer == null
              ? null
              : widget.racePayoutDoubleAdController ??
                    (AdService.racePayoutDoubleSupported
                        ? AdService(
                            adUnitId: AdService.racePayoutDoubleAdUnitId,
                          )
                        : null),
          onBeforeDismiss: userId == null || userId.isEmpty
              ? null
              : () async {
                  await _raceResultsAckQueue.enqueue(
                    userId: userId,
                    backendBaseUrl: backendBaseUrl,
                    raceIds: shownIds,
                    racePayoutDoubleCapability: capable,
                    identityToken:
                        identityToken != null &&
                            identityToken.isNotEmpty &&
                            _raceResultsAuthContextMatches(
                              identityToken: identityToken,
                              userId: userId,
                              backendBaseUrl: backendBaseUrl,
                            )
                        ? identityToken
                        : null,
                  );
                },
        ),
        transitionsBuilder: (_, anim, _, child) =>
            FadeTransition(opacity: anim, child: child),
        transitionDuration: const Duration(milliseconds: 250),
      ),
    );
    _raceResultsPopupOpen = false;

    // The screen queued durably before route pop. Replay now without blocking
    // navigation/review/next-race sequencing.
    if (identityToken != null &&
        identityToken.isNotEmpty &&
        userId != null &&
        userId.isNotEmpty &&
        _raceResultsAuthContextMatches(
          identityToken: identityToken,
          userId: userId,
          backendBaseUrl: backendBaseUrl,
        )) {
      unawaited(
        _raceResultsAckQueue.replayMatching(
          identityToken: identityToken,
          userId: userId,
          backendBaseUrl: backendBaseUrl,
          isAuthenticatedContextCurrent: () => _raceResultsAuthContextMatches(
            identityToken: identityToken,
            userId: userId,
            backendBaseUrl: backendBaseUrl,
          ),
        ),
      );
    }
    // Session + durable queue suppression already hides these IDs. Avoid
    // mutating response maps here: injected/demo payloads may be immutable and
    // a backend-version-skewed map should never turn dismissal into a crash.

    // Happy-moment hook: the user just dismissed a results modal that included
    // a top-3 finish — or, for team races, a strict team WIN (TR-807: ties
    // and forfeited members never qualify). The service applies its own
    // warm-up/cooldown/never-again guards, so most calls are no-ops.
    final placedTop3 = unseen.any(raceCountsAsReviewHappyMoment);
    if (placedTop3 && mounted) {
      await _reviewPromptService.recordHappyMomentAndMaybePrompt(context);
    }
    if (startNext == true && mounted) {
      await _showQuickCreateRaceSheet(surface: 'results');
    }
  }

  bool get _racePayoutDoubleCapability =>
      widget.racePayoutDoubleAdController?.isSupported ??
      BackendApiService.racePayoutDoubleCapabilitySupported;

  List<Map<String, dynamic>> _safeStringMaps(Object? raw) {
    if (raw is! List) return const [];
    final result = <Map<String, dynamic>>[];
    for (final value in raw) {
      if (value is Map<String, dynamic>) {
        result.add(value);
        continue;
      }
      if (value is! Map) continue;
      final map = <String, dynamic>{};
      var valid = true;
      for (final entry in value.entries) {
        if (entry.key is! String) {
          valid = false;
          break;
        }
        map[entry.key as String] = entry.value;
      }
      if (valid) result.add(map);
    }
    return result;
  }

  Future<void> _hydrateAndReplayRaceResultsAcks() async {
    await _raceResultsAckQueue.hydrate();
    final token = widget.authService.authToken;
    final userId = widget.authService.userId;
    final backendBaseUrl = BackendConfig.baseUrl;
    if (token == null || token.isEmpty || userId == null || userId.isEmpty) {
      return;
    }
    unawaited(
      _raceResultsAckQueue.replayMatching(
        identityToken: token,
        userId: userId,
        backendBaseUrl: backendBaseUrl,
        isAuthenticatedContextCurrent: () => _raceResultsAuthContextMatches(
          identityToken: token,
          userId: userId,
          backendBaseUrl: backendBaseUrl,
        ),
      ),
    );
  }

  bool _raceResultsAuthContextMatches({
    required String identityToken,
    required String userId,
    required String backendBaseUrl,
  }) {
    return widget.authService.authToken == identityToken &&
        widget.authService.userId == userId &&
        BackendConfig.baseUrl == backendBaseUrl;
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
    // Item 8: same deferral as the race-results modal.
    _resultsModalShownThisSession = true;
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
      // This action originates on the Races tab, so refresh both its personal
      // list and its discovery surface. Home/non-Races refreshes intentionally
      // keep using the core-only path.
      await Future.wait([_fetchRacesCore(), _refreshRacesDiscovery()]);
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
      await Future.wait([_fetchRacesCore(), _refreshRacesDiscovery()]);
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
        if (mounted) {
          setState(() => _shopCatalogState = Loadable.success(cached));
        }
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

  /// Pulls the CDN art registry and warms the disk cache. Best-effort and
  /// never awaited by UI: an older backend with no `/assets/manifest` simply
  /// leaves every item on its bundled art.
  Future<void> _refreshRemoteAssetManifest() async {
    try {
      await RemoteAssetCache.instance.refreshManifest(
        releaseChannel: await _backendApiService.getReleaseChannel(),
      );
      if (mounted) setState(() {});
    } catch (_) {}
  }

  void _applyShopCatalog(Map<String, dynamic> catalog) {
    // The catalog funnel is the app's "cosmetics may have changed" event, so
    // it's also where a newly-shipped remote item's art gets picked up.
    unawaited(_refreshRemoteAssetManifest());

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

    // Keep the pre-auth start screen's cape in lockstep with the tuner: cache
    // the catalog's live cape renderMetadata for StartScreen to read next
    // launch. Best-effort — the cape is testOnly-filtered from prod-channel
    // catalogs, in which case the compiled fallback stays authoritative.
    final items = catalog['items'];
    if (items is List) {
      for (final item in items) {
        if (item is Map<String, dynamic> && item['assetKey'] == 'cape') {
          final metadata = item['renderMetadata'];
          if (metadata is Map<String, dynamic> && metadata.isNotEmpty) {
            unawaited(
              StartCapeMetadata.save(
                bobble: item['bobble'] == true,
                renderMetadata: metadata,
              ),
            );
          }
          break;
        }
      }
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

  /// Mutation-originated Races refresh: unlike a passive tab reveal, callers
  /// await discovery too so a newly created public race or tournament updates
  /// the visible PUBLIC RACES count before the next interaction.
  Future<void> _refreshRacesAfterMutation() =>
      Future.wait([_fetchRacesCore(), _refreshRacesDiscovery()]);

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
      outcome = await _persistSteps(homePull: true);
    } catch (_) {
      // Local health read failed: keep prior server-derived surfaces and end
      // the pull (existing error presentation lives in the step display).
      return;
    }

    // The authoritative server cooldown is deliberately a no-work result for
    // a deliberate Home pull. Keep every current card in place: do not fetch
    // Home/discovery, do not call legacy sync, and do not begin job polling.
    final cooldownSeconds = outcome.cooldownSeconds;
    if (outcome.cooldown) {
      if (mounted) {
        showInfoToast(
          context,
          cooldownSeconds == null
              ? 'You just synced. Try again shortly.'
              : 'You just synced. Try again in $cooldownSeconds seconds.',
        );
      }
      return;
    }

    // Stage 5: fetch the home batch AFTER persistence so milestones/reward use
    // the new daily total. Persisted-total path only when uploaderReconciliation
    // was CURRENT; otherwise the backend's live-computation fallback.
    await Future.wait([
      _fetchRaceCard(usePersistedTotals: outcome.usePersistedHome),
      _refreshHomeSuggestions(),
    ]);

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
        final next = NextRaceState.tryParse(data['nextRace']);
        if (!_nextRaceHomeShownRecorded && next?.visible == true) {
          _nextRaceHomeShownRecorded = true;
          unawaited(
            _activationAnalytics.record(
              'next_race_cta_shown',
              context: {'surface': 'home'},
            ),
          );
          if (next!.openRaces.isNotEmpty) {
            unawaited(
              _activationAnalytics.record(
                'open_race_discovery_shown',
                context: {'race_count': '${next.openRaces.length}'},
              ),
            );
          }
        }
        if (!_inviteSetupShownRecorded && _showInviteCodePrompt) {
          _inviteSetupShownRecorded = true;
          unawaited(_activationAnalytics.record('invite_code_setup_shown'));
        }
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
        .push<bool>(
          MaterialPageRoute<bool>(
            builder: (_) => RaceDetailScreen(
              authService: widget.authService,
              raceId: raceId,
              friends: _friendsSteps,
              notificationService: widget.notificationService,
              onBoxOpened: () =>
                  maybeAskForNotifications(NotificationAskTrigger.boxOpen),
            ),
          ),
        )
        .then((result) {
          // The detail screen pops `true` from its not-a-participant state's
          // "Find it on Races" button. This entry point (a push tap or a card
          // on the home tab) is the one that can be sitting on another tab.
          if (mounted && result == true) _openRacesTab();
        })
        .whenComplete(() => _openingRaceDetail = false);
  }

  Future<void> _joinDiscoveredRace(String raceId) async {
    final errorCode = await _joinRaceFromCardResult(raceId);
    if (errorCode == null) {
      unawaited(
        _activationAnalytics.record(
          'open_race_join_succeeded',
          context: {'source': 'next_race', 'race_id': raceId},
        ),
      );
    }
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
    await _joinRaceFromCardResult(raceId);
  }

  /// Returns null after a successful join, otherwise a bounded analytics code.
  /// The existing Home card callback intentionally keeps its void contract.
  Future<String?> _joinRaceFromCardResult(String raceId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return 'UNKNOWN';
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
      return null;
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
      return e.code == 'QUICK_RACE_MEMBERSHIP_LIMIT'
          ? 'QUICK_RACE_MEMBERSHIP_LIMIT'
          : 'UNKNOWN';
    } catch (_) {
      if (mounted) {
        showErrorToast(context, 'Could not join. Give it another try!');
      }
      return 'UNKNOWN';
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
        "You're all set. Find your races on the Races tab.",
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

  /// V2 requires proof that this user is already accepted in the active seeded
  /// Daily. Returning null is the safe fallback: no enrollment/reward claims.
  Future<Map<String, dynamic>?> _fetchVerifiedActiveDaily() async {
    // The daily intro is the step that fetches this, so a fetch IS a view.
    unawaited(_activationAnalytics.record('daily_intro_viewed'));
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return null;
    try {
      final featured = await _backendApiService.fetchFeaturedRaces(
        identityToken: identityToken,
      );
      for (final race in featured) {
        final isDaily = race['seedKind'] == 'DAILY_10K';
        final isAccepted = race['myStatus'] == 'ACCEPTED';
        final status = race['status'];
        final isActive = status == null || status == 'ACTIVE';
        final id = (race['raceId'] ?? race['id']) as String?;
        if (isDaily && isAccepted && isActive && id != null && id.isNotEmpty) {
          return race;
        }
      }
    } catch (_) {}
    return null;
  }

  Future<void> _enterVerifiedDaily(String raceId) async {
    unawaited(_activationAnalytics.record('daily_opened'));
    await _skipFirstRaceOnboarding();
    unawaited(_fetchRaces());
    if (!mounted) return;
    _openRaceFromCard(raceId);
  }

  Future<void> _openHealthSettings() async {
    final launched = await _healthService.openPlatformHealthSettings();
    if (launched || !mounted) return;
    // Nothing resolved the intent. Say so rather than appearing to do nothing —
    // an unresponsive button on a blocking gate is the worst possible read.
    showErrorToast(
      context,
      'Couldn’t open settings. Open Health Connect and turn Steps on for Bara.',
    );
  }

  /// Resolves the inviter's joinable race for the referral-first landing.
  /// Returns null on ANY failure — a 404 from a backend that predates the
  /// endpoint, a timeout, an error body — so the step falls through to the
  /// Daily intro. This is the single most important degradation path in the
  /// spec, because the backend and the app deploy independently.
  Future<Map<String, dynamic>?> _fetchInviterRace() async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return null;
    try {
      final payload = await _backendApiService.fetchInviterRace(
        identityToken: identityToken,
      );
      if (payload != null && payload['race'] is Map) {
        unawaited(_activationAnalytics.record('inviter_race_shown'));
      }
      return payload;
    } catch (_) {
      return null;
    }
  }

  /// Joins the inviter's race, closes the first-race gate, and opens it. A
  /// failed join still closes the gate: the user has done their part, and
  /// stranding them on an onboarding step because a race filled up would be a
  /// worse outcome than landing them on Home.
  Future<void> _joinInviterRace(String raceId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken != null && identityToken.isNotEmpty) {
      try {
        await _backendApiService.joinPublicRace(
          identityToken: identityToken,
          raceId: raceId,
          onboarding: true,
        );
      } catch (_) {
        // "Already in this race", full, closed — the race screen renders every
        // one of those states correctly, so continue to it either way.
      }
    }
    await _skipFirstRaceOnboarding();
    unawaited(_fetchRaces());
    if (!mounted) return;
    _openRaceFromCard(raceId);
  }

  Future<void> _finishOnboardingAndFindRace() async {
    await _skipFirstRaceOnboarding();
    if (!mounted) return;
    _pageController.jumpToPage(_racesTabIndex);
    showInfoToast(context, 'Choose a race to start walking.');
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
    // Item 8: a fresh install has just finished onboarding — record the
    // current version as seen so the changelog does not greet them for a
    // build they have never used. They meet it on session two.
    await markWhatsNewSeenForOnboarding();
  }

  /// Batch 2026-08-09 item 9 — whether the onboarding tutorial is currently
  /// un-skippable.
  ///
  /// TWO conditions, and both must hold: the backend flag is on (absent or
  /// false on any older backend, which is today's behavior), AND the local
  /// abandon circuit breaker has not tripped. The single source of truth for
  /// the intro button, the in-tutorial controls, the back handler and the
  /// seen-marking rule below, so they can never disagree.
  bool get _tutorialMandatory => !tutorialSkippable(
    mandatoryEnabled: widget.authService.tutorialMandatoryEnabled,
    abandonCount: _tutorialAbandons,
  );

  /// Launches the tutorial from the onboarding step. TutorialScreen claims the
  /// one-time reward itself on full completion. Marking the step seen is
  /// idempotent.
  ///
  /// Item 9 changes WHEN it is marked. With the tutorial optional, returning
  /// from the route marked it seen regardless of outcome (F8) — which is
  /// exactly the bypass "mandatory" has to close, since backgrounding the app
  /// at the first beat then counted as having done the tutorial. Under
  /// mandatory mode the mark is gated on `completed == true`; with the flag
  /// off the old unconditional mark is preserved byte-for-byte.
  /// Guards the async gap between the START tap and the route push below.
  /// Without it a double-tap pushes two tutorial routes and double-counts the
  /// abandon, which would trip the circuit breaker a third early.
  bool _launchingTutorial = false;

  Future<void> _startTutorialOnboarding() async {
    if (_launchingTutorial) return;
    _launchingTutorial = true;
    try {
      await _runTutorialOnboarding();
    } finally {
      _launchingTutorial = false;
    }
  }

  Future<void> _runTutorialOnboarding() async {
    final mandatory = _tutorialMandatory;
    // Captured before the first await — the route is pushed onto this
    // navigator, and reading it after the async gap trips
    // use_build_context_synchronously.
    final navigator = Navigator.of(context);

    // Counted BEFORE the push: an entry that crashes on its first frame, or an
    // app kill mid-tutorial, reaches no callback at all and must still count
    // toward the circuit breaker.
    await recordTutorialEntry();
    if (!mounted) return;
    setState(() => _tutorialAbandons = _tutorialAbandons + 1);

    var completed = false;
    await navigator.push(
      MaterialPageRoute(
        builder: (routeContext) => widget.authService.onboardingV3Enabled
            // Demo-race spec §5.8: under v3 the teaching step is a playable
            // demo race, not the spotlight walkthrough. The walkthrough is
            // untouched and still reachable from Profile → Settings.
            ? DemoRaceHost(
                authService: widget.authService,
                backendApiService: _backendApiService,
                mandatory: mandatory,
                onDone: (didComplete) {
                  completed = didComplete;
                  Navigator.of(routeContext).pop();
                },
              )
            : TutorialScreen(
                authService: widget.authService,
                mandatory: mandatory,
                // The spotlight screen reports finish and skip through the
                // same callback, but it now says WHICH — so the gate below is
                // structurally safe rather than safe-by-argument (it used to
                // rely on the skip pill being hidden and the back handler
                // being inert to know this could only be a completion).
                onComplete: (ctx, didComplete) {
                  completed = didComplete;
                  Navigator.of(ctx).pop();
                },
              ),
      ),
    );

    if (completed) {
      // Not an abandoned entry — reset the breaker.
      await clearTutorialAbandons();
      if (mounted) setState(() => _tutorialAbandons = 0);
    }

    // Under mandatory mode an incomplete run leaves the gate shut, so the
    // tutorial re-runs on the next build of the onboarding flow. The 100-coin
    // grant is idempotent server-side (one ledger key), so a re-completion
    // cannot double-pay.
    if (!mandatory || completed) {
      await widget.authService.markTutorialOnboardingSeen();
      await markWhatsNewSeenForOnboarding();
    }
  }

  /// Skips the tutorial onboarding step: marks it seen (backend + locally) with
  /// no reward. The user can still earn the 100 coins later by finishing a
  /// replay of the tutorial.
  ///
  /// Item 9 keeps this handler rather than deleting it: it is unreachable while
  /// the tutorial is mandatory (the intro renders no skip control at all), and
  /// it is still the live path both with the flag off and after the circuit
  /// breaker trips.
  Future<void> _skipTutorialOnboarding() async {
    await widget.authService.markTutorialOnboardingSeen();
    await markWhatsNewSeenForOnboarding();
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

  void _openFriendsTab() {
    _pageController.animateToPage(
      _friendsTabIndex,
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
      unawaited(_refreshRemoteAssetManifest());
      final incoming = user['incomingFriendRequests'] as int? ?? 0;
      final displayName = user['displayName'] as String?;
      final email = user['email'] as String?;
      await widget.authService.syncFromBackendUser(user, authoritative: true);
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
    // The funnel denominator's other end (§5.9): the first frame this user ever
    // renders with onboarding behind them. Guarded by a plain bool rather than
    // persistence because "reached home in this session" is the honest signal —
    // the session id is what makes it one funnel row, not many.
    if (!_isOnboarding && !_homeReachedRecorded) {
      _homeReachedRecorded = true;
      unawaited(_activationAnalytics.record('home_reached'));
    }

    // Once per render-session: the denominator for invite_code_applied /
    // invite_code_skipped. Guarded by a plain bool, like home_reached — a
    // rebuild is not a second impression. The extra terms match the
    // early-returns that render BEFORE the v3 branch (referral welcome,
    // health gate): while one of those is on screen the step is not, and
    // counting it would inflate the funnel denominator.
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Positioned.fill(child: const ArcadePageBackground(showHeader: false)),

          if (_isOnboarding)
            Positioned.fill(
              child:
                  widget.authService.requiresDiscoverableIdentityOnboarding &&
                      widget.authService.welcomeReferralCode == null
                  ? DiscoverableIdentityFlow(
                      authService: widget.authService,
                      backendApiService: _backendApiService,
                      initialFirstName: widget.authService.providerFirstName,
                      initialLastName: widget.authService.providerLastName,
                      onCompleted: () {
                        if (mounted) setState(() {});
                      },
                    )
                  : OnboardingFlow(
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
                      onboardingV2Enabled:
                          widget.authService.onboardingV2Enabled,
                      onboardingV3Enabled:
                          widget.authService.onboardingV3Enabled,
                      tutorialMandatory: _tutorialMandatory,
                      healthAttemptCount: _healthAttempts,
                      // The ladder: retrying stops being offered once the OS has
                      // refused twice, because it stops producing a prompt.
                      onOpenHealthSettings: _healthAttempts >= 2
                          ? _openHealthSettings
                          : null,
                      onEscapeHealthGate: _healthAttempts >= 2
                          ? _escapeHealthGate
                          : null,
                      onFetchInviterRace: _fetchInviterRace,
                      onJoinInviterRace: _joinInviterRace,
                      displayName:
                          _displayName ?? widget.authService.displayName,
                      onFetchActiveDaily: _fetchVerifiedActiveDaily,
                      onEnterVerifiedDaily: _enterVerifiedDaily,
                      onFindRace: _finishOnboardingAndFindRace,
                      firstRaceShareTokenPending:
                          widget.authService.pendingShareToken != null,
                      welcomeReferralCode:
                          widget.authService.welcomeReferralCode,
                      onWelcomeDismissed: () {
                        unawaited(
                          _activationAnalytics.record('referral_continued'),
                        );
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
                      key: const Key('main-shell-pages'),
                      controller: _pageController,
                      physics: const PageScrollPhysics(),
                      onPageChanged: (index) {
                        final enteringHome =
                            index == _homeTabIndex &&
                            _currentTab != _homeTabIndex;
                        setState(() {
                          _currentTab = index;
                          if (enteringHome) {
                            _homeSuggestionsImpressionRecorded = false;
                          }
                          // Clear the incoming-friend-request badge when the Friends
                          // tab is revealed (mirrors _openFriendsTab's old behavior).
                          if (index == _friendsTabIndex &&
                              _incomingFriendRequests != 0) {
                            _incomingFriendRequests = 0;
                          }
                        });
                        if (index == _racesTabIndex) _refreshRacesTab();
                        if (enteringHome &&
                            (_homeSuggestions.state.isSuccess ||
                                _homeSuggestions.state.hasData)) {
                          _recordHomeSuggestionsImpression();
                        }
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
                          onOpenFriendsTab: _openFriendsTab,
                          onOpenShop: _openShop,
                          onAddProfilePhoto: _addOrChangeProfilePhoto,
                          onDismissProfilePhotoPrompt:
                              _dismissProfilePhotoPrompt,
                          raceCard: _raceCard,
                          raceCardLoading: _raceCardLoading,
                          suggestedRacesState: _homeSuggestions.state,
                          joiningSuggestionKeys: _joiningHomeSuggestionKeys,
                          onJoinSuggestion: _joinHomeSuggestion,
                          onRetrySuggestedRaces: () {
                            unawaited(_refreshHomeSuggestions());
                          },
                          onOpenPublicRaces: () {
                            unawaited(_openPublicRacesFromHome());
                          },
                          onOpenRace: _openRaceFromCard,
                          onJoinRaceFromCard: _joinRaceFromCard,
                          onJoinDiscoveredRace: _joinDiscoveredRace,
                          onAcceptRaceInvite: _acceptRaceInviteFromCard,
                          onDeclineRaceInvite: _declineRaceInviteFromCard,
                          onChallengeFriendBack: _challengeFriendBack,
                          onDailyRewardClaimed: _markDailyRewardClaimed,
                          showInviteCodePrompt: _showInviteCodePrompt,
                          onEnterInviteCode: _openInviteCodeFromHome,
                          onSkipInviteCode: _skipInviteCodeFromHome,
                          onStartQuickRace: () {
                            unawaited(_showQuickCreateRaceSheet());
                          },
                          suppressPendingInvite: _homeInvitePopupOpen,
                        ),
                        RacesTab(
                          authService: widget.authService,
                          racesData: _racesData,
                          racesState: _racesState,
                          friendsSteps: _friendsSteps,
                          featuredRaces: _featuredRaces,
                          featuredTournaments: _featuredTournaments,
                          onRacesChanged: _refreshRacesAfterMutation,
                          onRefresh: _refreshRacesTab,
                          onJoinFeaturedRace: _joinFeaturedRace,
                          onJoinFeaturedTournament: _joinFeaturedTournament,
                          publicRacesCount: _publicRacesCount,
                          displayName: _displayName,
                          notificationService: widget.notificationService,
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
          // and sits directly above the tab bar. Collapsed on the home tab (and
          // while the keyboard is up). Not shown during onboarding.
          // The home tab passes `hidden` rather than unmounting the slot —
          // unmounting disposed the BannerAd, so every home-tab round trip
          // bought a fresh ad request for an ad we already had.
          if (!_isOnboarding)
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
                child: AdBannerSlot(
                  hideWhenKeyboardOpen: true,
                  hidden: _currentTab == _homeTabIndex,
                ),
              ),
            ),

          // Degraded state (spec §5.2): pinned directly above the tab bar,
          // non-dismissible, and NOT gated on onboarding — a user scoring 0
          // needs to be told so on every screen, forever, until it is fixed.
          if (!_isOnboarding && _stepsDisconnected)
            ValueListenableBuilder<double>(
              valueListenable: _bannerHeight,
              // Stacked ABOVE the ad slot, not on top of it: both are pinned to
              // the same tab-bar edge, so the measured ad height is what keeps
              // them from colliding on the tabs that show one.
              builder: (context, adHeight, child) => Positioned(
                left: 0,
                right: 0,
                bottom: 77.5 + MediaQuery.of(context).padding.bottom + adHeight,
                child: child!,
              ),
              child: StepsDisconnectedBanner(onFix: _fixDisconnectedSteps),
            ),

          if (!_isOnboarding)
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
    this.cooldown = false,
    this.cooldownSeconds,
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
  final bool cooldown;
  final int? cooldownSeconds;
}
