import 'dart:async';

import 'package:flutter/cupertino.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:image_cropper/image_cropper.dart';
import 'package:image_picker/image_picker.dart';

import '../models/loadable.dart';
import '../models/step_data.dart';
import '../models/step_sample_data.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/background_sync_bootstrap_service.dart';
import '../services/health_service.dart';
import '../services/notification_service.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/info_toast.dart';
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
import 'tabs/ranked_tab.dart';
import 'create_race_screen.dart';
import 'race_detail_screen.dart';
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
  });

  final AuthService authService;
  final HealthService? healthService;
  final BackendApiService? backendApiService;
  final BackgroundSyncBootstrapService? backgroundSyncBootstrapService;
  final NotificationService? notificationService;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  static const _homeTabIndex = 0;
  static const _racesTabIndex = 1;
  static const _rankedTabIndex = 2;
  static const _boardsTabIndex = 3;
  static const _profileTabIndex = 4;

  late final HealthService _healthService;
  late final BackendApiService _backendApiService;
  late final BackgroundSyncBootstrapService _backgroundSyncBootstrapService;

  int _currentTab = 0;
  late final PageController _pageController;
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
  List<Map<String, dynamic>> _equippedAccessories = const [];
  Loadable<Map<String, dynamic>> _shopCatalogState = const Loadable.initial();
  Map<String, dynamic>? _raceCard;
  bool _raceCardLoading = true;
  final String _requestedLeaderboardType = 'steps';
  final String _requestedLeaderboardPeriod = 'today';
  int _leaderboardSelectionNonce = 0;
  int _rankedSelectionNonce = 0;
  Timer? _foregroundPollTimer;
  final GlobalKey<StreakChipState> _streakChipKey =
      GlobalKey<StreakChipState>();
  final GlobalKey<StepMilestonesSectionState> _stepMilestonesKey =
      GlobalKey<StepMilestonesSectionState>();
  static const Duration _foregroundPollInterval = Duration(minutes: 5);
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

  // Guards the shared-race drain so overlapping AuthService notifications can't
  // fire two concurrent joins for the same pending token.
  bool _draining = false;

  void _handleAuthServiceChanged() {
    if (!mounted) return;
    setState(() {});
    // A share token may have just been captured (link tapped while running) or
    // the final onboarding step may have just completed — either way, try to
    // drain. Idempotent: no-ops when there's no token or onboarding isn't done.
    _maybeDrainPendingSharedRace();
  }

  @override
  void initState() {
    super.initState();
    _healthService = widget.healthService ?? HealthService();
    _backendApiService = widget.backendApiService ?? BackendApiService();
    _backgroundSyncBootstrapService =
        widget.backgroundSyncBootstrapService ??
        BackgroundSyncBootstrapService();
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
    _pageController.dispose();
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
          Navigator.of(context).push(
            MaterialPageRoute(
              builder: (context) => RaceDetailScreen(
                authService: widget.authService,
                raceId: raceId,
                friends: _friendsSteps,
              ),
            ),
          );
        }
        break;
      case NotificationRoute.races:
        _pageController.jumpToPage(_racesTabIndex);
        break;
      case NotificationRoute.friends:
        _openFriendsTab();
        break;
      case NotificationRoute.home:
        _pageController.jumpToPage(_homeTabIndex);
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
      final result = await _backendApiService.joinRaceByShareToken(
        identityToken: identityToken,
        token: token,
        // Server-gated one-time welcome boxes: a fresh share-link user gets
        // them; anyone already in the ledger is a no-op. See joinRaceCore.
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

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _healthAuthorized) {
      // Mirror initial load: refresh every home surface, then surface the
      // results modals only once all calls have settled.
      unawaited(_loadHomeAndShowResults());
      _startForegroundPolling();
    } else if (state == AppLifecycleState.paused) {
      _stopForegroundPolling();
    }
  }

  void _startForegroundPolling() {
    _foregroundPollTimer?.cancel();
    _foregroundPollTimer = Timer.periodic(_foregroundPollInterval, (_) {
      if (_healthAuthorized) {
        _fetchSteps();
        _refreshMe();
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

  Future<void> _fetchSteps() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final identityToken = widget.authService.authToken;
      // Pre-read both HealthKit windows in parallel so we know whether samples
      // will follow before posting /steps. When samples are coming, /steps can
      // skip race-state resolution (the samples endpoint will re-resolve with
      // fresher sample data).
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
      final stepEntries = [stepData];
      bool syncFailed = false;

      if (identityToken != null && identityToken.isNotEmpty) {
        final willPostSamples = hourlySamples.isNotEmpty;

        Future<void> pushSteps() async {
          for (final dailyStep in stepEntries) {
            await _backendApiService.recordSteps(
              identityToken: identityToken,
              stepData: dailyStep,
              skipRaceResolution: willPostSamples,
            );
          }
        }

        try {
          await pushSteps();
        } catch (_) {
          // Cold-start blip from background → foreground is common.
          // Silently retry once before flagging the sync as stale.
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
            // Don't fail the main sync if hourly samples fail. Race resolution
            // will catch up on the next refresh because the next /steps call
            // will run with skipRaceResolution=false (no samples to follow) or
            // be paired with a successful /steps/samples.
          }
        }
      }

      setState(() {
        _stepData = stepData;
        _isLoading = false;
        _error = null;
      });

      _fetchFriendsSteps();
      _refreshMe();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to fetch steps:\n$e';
      });
    }
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

  Future<void> _fetchRaces() async {
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
        if (mounted) {
          setState(() {
            _racesState = Loadable.error('Not signed in.', data: previous);
          });
        }
        return;
      }

      final data = await _backendApiService.fetchRaces(
        identityToken: identityToken,
      );

      if (mounted) {
        setState(() {
          _racesData = data;
          _racesState = Loadable.success(data);
        });
      }

      // Featured strip rides along with the races list so it stays in sync
      // (e.g. after a join). Self-contained error handling — never disrupts the
      // races load above.
      await _fetchFeaturedRaces();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _racesState = Loadable.error(e.toString(), data: previous);
      });
    }
  }

  /// Loads every home-page surface in parallel and, once they have ALL
  /// settled, surfaces the race/ranked results modals. Gating the popups on
  /// completion keeps a results modal from appearing over sections that are
  /// still showing loading skeletons. Race results go first: it sets its open
  /// guard before its first await, so the ranked check then defers behind it,
  /// preserving the prior sequencing. Every fetch swallows its own errors, so
  /// the wait never throws and the modals always get their chance.
  Future<void> _loadHomeAndShowResults() async {
    await Future.wait([
      _fetchSteps(),
      _fetchRaceCard(),
      _refreshMe(),
      _fetchFriendsSteps(),
      _fetchRaces(),
      _fetchShopCatalog(),
    ]);
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
  }

  /// Fetches `/ranked/v2` and, if the caller's most recently settled week is
  /// unacknowledged, shows the post-settlement summary popup. Called only from
  /// resume + initial load (not the poll), mirroring [_maybeShowRaceResults].
  ///
  /// Defensive throughout: a backend that predates `/ranked/v2` (404) or omits
  /// `resultsSeen` yields no popup — `resultsSeen` defaults to SEEN (true), and
  /// only the three real settlement outcomes qualify.
  Future<void> _maybeShowRankedResults() async {
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

  Future<void> _fetchShopCatalog() async {
    final previous = _shopCatalogState.data;
    if (mounted) {
      setState(() {
        _shopCatalogState = previous == null
            ? const Loadable.loading()
            : Loadable.refreshing(previous);
      });
    }

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) {
        if (mounted) {
          setState(() {
            _shopCatalogState = Loadable.error(
              'Not signed in.',
              data: previous,
            );
          });
        }
        return;
      }

      final data = await _backendApiService.fetchShopCatalog(
        identityToken: identityToken,
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

  void _applyShopCatalog(Map<String, dynamic> catalog) {
    final equipped = catalog['equipped'] as Map<String, dynamic>? ?? {};
    final accessories = equipped.values
        .whereType<Map<String, dynamic>>()
        .toList(growable: false);
    final coins = catalog['coins'] as int?;

    if (coins != null) {
      widget.authService.updateCoins(coins);
    }

    if (mounted) {
      setState(() => _equippedAccessories = accessories);
    }
  }

  Future<void> _refreshRacesTab() async {
    await Future.wait([_fetchRaces(), _fetchFriendsSteps()]);
  }

  Future<void> _refreshHomeTab() async {
    await Future.wait([
      _fetchSteps(),
      _fetchShopCatalog(),
      _fetchRaceCard(),
      _streakChipKey.currentState?.refresh() ?? Future<void>.value(),
      _stepMilestonesKey.currentState?.refresh() ?? Future<void>.value(),
    ]);
  }

  Future<void> _fetchRaceCard() async {
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

  void _openRaceFromCard(String raceId) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => RaceDetailScreen(
          authService: widget.authService,
          raceId: raceId,
          friends: _friendsSteps,
        ),
      ),
    );
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
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Could not join: $e');
      }
    }
  }

  /// Fetches public races for the first-race onboarding step. Returns null on
  /// error so the step can auto-skip rather than dead-end.
  Future<List<Map<String, dynamic>>?> _fetchOnboardingRaces() async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return null;
    try {
      return await _backendApiService.fetchPublicRaces(
        identityToken: identityToken,
      );
    } catch (_) {
      return null;
    }
  }

  /// Joins a race during onboarding (grants mystery boxes server-side). On
  /// success: marks the step seen locally so onboarding exits, then navigates
  /// to the race detail. Returns true on success.
  Future<bool> _joinOnboardingRace(String raceId) async {
    final identityToken = widget.authService.authToken;
    if (identityToken == null || identityToken.isEmpty) return false;
    try {
      await _backendApiService.joinPublicRace(
        identityToken: identityToken,
        raceId: raceId,
        onboarding: true,
      );
      await widget.authService.markFirstRaceOnboardingSeenLocally();
      // Refresh surfaces that now include the joined race / new boxes.
      _fetchRaces();
      _fetchShopCatalog();
      _refreshMe();
      if (!mounted) return true;
      // Exiting onboarding rebuilds into the tab PageView; open the race on top.
      _openRaceFromCard(raceId);
      return true;
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not join: $e');
      return false;
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
    } catch (e) {
      if (mounted) showErrorToast(context, 'Could not accept: $e');
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

  void _openFriendsTab() {
    if (_incomingFriendRequests != 0) {
      setState(() => _incomingFriendRequests = 0);
    }
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => FriendsTab(
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
      ),
    );
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
          onShopChanged: _applyShopCatalog,
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
                onFetchOnboardingRaces: _fetchOnboardingRaces,
                onJoinOnboardingRace: _joinOnboardingRace,
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
              child: PageView(
                controller: _pageController,
                physics: const PageScrollPhysics(),
                onPageChanged: (index) {
                  setState(() {
                    _currentTab = index;
                    // Refresh Ranked each time it's revealed (mirrors the
                    // races refresh-on-reveal hook below).
                    if (index == _rankedTabIndex) _rankedSelectionNonce++;
                  });
                  if (index == _racesTabIndex) _fetchRaces();
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
                    shopCatalogState: _shopCatalogState,
                    onOpenFriendsTab: _openFriendsTab,
                    incomingFriendRequests: _incomingFriendRequests,
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
                  ),
                  RacesTab(
                    authService: widget.authService,
                    racesData: _racesData,
                    racesState: _racesState,
                    friendsSteps: _friendsSteps,
                    featuredRaces: _featuredRaces,
                    onRacesChanged: _fetchRaces,
                    onRefresh: _refreshRacesTab,
                    onJoinFeaturedRace: _joinFeaturedRace,
                    displayName: _displayName,
                    onOpenProfile: _openProfile,
                  ),
                  RankedTab(
                    authService: widget.authService,
                    backendApiService: _backendApiService,
                    refreshNonce: _rankedSelectionNonce,
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
                  const WoodenTabItem(
                    icon: Icons.shield_rounded,
                    label: 'Ranked',
                  ),
                  const WoodenTabItem(
                    icon: Icons.leaderboard_rounded,
                    label: 'Boards',
                  ),
                  WoodenTabItem(
                    icon: Icons.person_rounded,
                    label: 'Profile',
                    badgeCount: _incomingFriendRequests,
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
