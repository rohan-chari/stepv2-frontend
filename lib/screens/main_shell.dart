import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import '../models/step_data.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/background_sync_bootstrap_service.dart';
import '../services/challenge_week_step_sync_service.dart';
import '../services/health_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/capybara.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/trail_sign.dart';
import '../widgets/wooden_tab_bar.dart';
import 'start_screen.dart';
import 'tabs/challenges_tab.dart';
import 'tabs/friends_tab.dart';
import 'tabs/home_tab.dart';
import 'tabs/leaderboard_tab.dart';
import 'tabs/profile_tab.dart';

class MainShell extends StatefulWidget {
  const MainShell({
    super.key,
    required this.authService,
    this.healthService,
    this.backendApiService,
    this.backgroundSyncBootstrapService,
    this.challengeWeekStepSyncService,
    this.notificationService,
  });

  final AuthService authService;
  final HealthService? healthService;
  final BackendApiService? backendApiService;
  final BackgroundSyncBootstrapService? backgroundSyncBootstrapService;
  final ChallengeWeekStepSyncService? challengeWeekStepSyncService;
  final NotificationService? notificationService;

  @override
  State<MainShell> createState() => _MainShellState();
}

class _MainShellState extends State<MainShell> with WidgetsBindingObserver {
  late final HealthService _healthService;
  late final BackendApiService _backendApiService;
  late final BackgroundSyncBootstrapService _backgroundSyncBootstrapService;
  late final ChallengeWeekStepSyncService _challengeWeekStepSyncService;

  int _currentTab = 0;
  late final PageController _pageController;
  bool _healthAuthorized = false;
  bool?
  _notificationsState; // null = not prompted, true = granted, false = denied
  bool _isLoading = false;
  String? _error;
  StepData? _stepData;
  int? _stepGoal;
  int _incomingFriendRequests = 0;
  String? _displayName;
  String? _email;
  List<Map<String, dynamic>> _friendsSteps = [];
  Map<String, dynamic>? _currentChallenge;
  Map<String, dynamic>? _activeChallengeProgress;
  Timer? _foregroundPollTimer;
  static const Duration _foregroundPollInterval = Duration(minutes: 5);

  @override
  void initState() {
    super.initState();
    _healthService = widget.healthService ?? HealthService();
    _backendApiService = widget.backendApiService ?? BackendApiService();
    _backgroundSyncBootstrapService =
        widget.backgroundSyncBootstrapService ??
        BackgroundSyncBootstrapService();
    _challengeWeekStepSyncService =
        widget.challengeWeekStepSyncService ??
        ChallengeWeekStepSyncService(
          backendApiService: _backendApiService,
          healthService: _healthService,
        );
    _pageController = PageController();
    WidgetsBinding.instance.addObserver(this);
    _restoreAndFetch();
  }

  @override
  void dispose() {
    _foregroundPollTimer?.cancel();
    _pageController.dispose();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _healthAuthorized) {
      _fetchSteps();
      _refreshStepGoal();
      _fetchFriendsSteps();
      _fetchCurrentChallenge();
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
        _refreshStepGoal();
      }
    });
  }

  void _stopForegroundPolling() {
    _foregroundPollTimer?.cancel();
    _foregroundPollTimer = null;
  }

  Future<void> _restoreAndFetch() async {
    setState(() {
      _stepGoal = widget.authService.stepGoal;
      _displayName = widget.authService.displayName;
    });

    final sessionIsValid = await _refreshSessionToken();
    if (!sessionIsValid || !mounted) return;

    final wasAuthorized = await _healthService.restoreHealthAuthState();
    if (!wasAuthorized || !mounted) return;

    setState(() => _healthAuthorized = true);
    await _backgroundSyncBootstrapService.enableHealthKitBackgroundDelivery();
    await _checkNotificationState();
    await _fetchSteps();
    _refreshStepGoal();
    _fetchFriendsSteps();
    _fetchCurrentChallenge();
    _startForegroundPolling();
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
        await widget.authService.updateAdminAccess(
          user['isAdmin'] as bool? ?? false,
        );
        await widget.authService.updateCoins(
          user['coins'] as int? ?? 0,
        );
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
      final authorized = await _healthService.requestAuthorization();
      if (!authorized) {
        setState(() {
          _isLoading = false;
          _error =
              'Health data access not granted.\nPlease allow access in Settings.';
        });
        return;
      }

      setState(() => _healthAuthorized = true);
      await _backgroundSyncBootstrapService.enableHealthKitBackgroundDelivery();
      await _checkNotificationState();
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
    if (ns == null) return;

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
      final stepEntries =
          identityToken != null && identityToken.isNotEmpty
          ? await _challengeWeekStepSyncService.loadCurrentChallengeWeekSteps(
              identityToken: identityToken,
            )
          : [await _healthService.getStepsToday()];
      final stepData = stepEntries.last;
      String? syncWarning;

      if (identityToken != null && identityToken.isNotEmpty) {
        try {
          for (final dailyStep in stepEntries) {
            await _backendApiService.recordSteps(
              identityToken: identityToken,
              stepData: dailyStep,
            );
          }
        } catch (e) {
          syncWarning = e is ApiException
              ? 'Steps loaded, but sync failed: ${e.message}'
              : 'Steps loaded, but sync failed. Check your connection.';
        }
      }

      setState(() {
        _stepData = stepData;
        _isLoading = false;
        _error = null;
      });

      if (syncWarning != null && mounted) {
        showErrorToast(context, syncWarning);
      }

      _fetchFriendsSteps();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to fetch steps:\n$e';
      });
    }
  }

  Future<void> _fetchFriendsSteps() async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      final now = DateTime.now();
      final date =
          '${now.year}-${now.month.toString().padLeft(2, '0')}-${now.day.toString().padLeft(2, '0')}';

      final friends = await _backendApiService.fetchFriendsSteps(
        identityToken: identityToken,
        date: date,
      );

      if (mounted) {
        setState(() => _friendsSteps = friends);
      }
    } catch (_) {}
  }

  Future<void> _refreshChallengesTab() async {
    await Future.wait([_fetchCurrentChallenge(), _fetchFriendsSteps()]);
  }

  Future<void> _refreshFriendsTab() async {
    await _refreshStepGoal();
  }

  Future<void> _refreshProfileTab() async {
    await _refreshStepGoal();
  }

  void _openFriendsTab() {
    _pageController.animateToPage(
      2,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOutCubic,
    );
  }

  Future<void> _fetchCurrentChallenge() async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      final data = await _backendApiService.fetchCurrentChallenge(
        identityToken: identityToken,
      );

      if (mounted) {
        setState(() => _currentChallenge = data);
      }

      // Fetch progress for first active instance (for Home tab summary)
      final instances = data['instances'] as List? ?? [];
      for (final i in instances) {
        final inst = i as Map<String, dynamic>;
        if (inst['status'] == 'ACTIVE') {
          try {
            final progress = await _backendApiService.fetchChallengeProgress(
              identityToken: identityToken,
              instanceId: inst['id'] as String,
            );
            if (mounted) {
              setState(() => _activeChallengeProgress = progress);
            }
          } catch (_) {}
          break;
        }
      }
    } catch (_) {}
  }

  Future<void> _refreshStepGoal() async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      final user = await _backendApiService.fetchMe(
        identityToken: identityToken,
      );
      final goal = user['stepGoal'] as int?;
      final incoming = user['incomingFriendRequests'] as int? ?? 0;
      final displayName = user['displayName'] as String?;
      final email = user['email'] as String?;
      final isAdmin = user['isAdmin'] as bool? ?? false;
      await widget.authService.updateStepGoal(goal);
      await widget.authService.updateDisplayName(displayName);
      await widget.authService.updateAdminAccess(isAdmin);
      if (mounted) {
        setState(() {
          _stepGoal = goal;
          _incomingFriendRequests = incoming;
          _displayName = displayName;
          _email = email;
        });
      }
    } catch (_) {}
  }

  Future<void> _showStepGoalDialog() async {
    final controller = TextEditingController(text: _stepGoal?.toString() ?? '');

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: TrailSign(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'STEP GOAL',
                  style: PixelText.title(size: 18, color: AppColors.textDark),
                ),
                const SizedBox(height: 8),
                Text(
                  'How many steps per day?',
                  style: PixelText.body(size: 14, color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: PixelText.number(size: 24, color: AppColors.textDark),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.parchmentLight,
                    border: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.parchmentBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.parchmentBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(color: AppColors.accent, width: 2),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: PillButton(
                        label: 'CANCEL',
                        variant: PillButtonVariant.secondary,
                        fontSize: 13,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: PillButton(
                        label: 'SAVE',
                        variant: PillButtonVariant.primary,
                        fontSize: 13,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        onPressed: () {
                          final value = int.tryParse(controller.text);
                          if (value != null && value > 0) {
                            Navigator.of(context).pop(value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null || !mounted) return;

    setState(() => _stepGoal = result);
    await widget.authService.updateStepGoal(result);

    try {
      final identityToken = widget.authService.authToken;
      if (identityToken != null && identityToken.isNotEmpty) {
        await _backendApiService.setStepGoal(
          identityToken: identityToken,
          stepGoal: result,
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          'Couldn\u2019t save your step goal. Please try again.',
        );
      }
    }
  }

  void _syncSettingsState() {
    setState(() {
      _stepGoal = widget.authService.stepGoal;
      _displayName = widget.authService.displayName;
    });
    _fetchCurrentChallenge();
  }

  @override
  Widget build(BuildContext context) {
    final bottomPadding = MediaQuery.of(context).padding.bottom;
    // Tab bar height: top border(2) + bevel(1.5) + grain(2) + padding(8) + board(54) + padding(10) + safe area
    final tabBarHeight = 77.5 + bottomPadding;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Sky gradient background
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [
                    Color(0xFF87CEEB),
                    Color(0xFFB0E0F0),
                    Color(0xFFD4F1F9),
                  ],
                ),
              ),
            ),
          ),
          // Tab content — swipeable
          Positioned.fill(
            child: PageView(
              controller: _pageController,
              onPageChanged: (index) {
                setState(() => _currentTab = index);
                if (index == 1) _fetchCurrentChallenge();
              },
              children: [
                HomeTab(
                  stepData: _stepData,
                  isLoading: _isLoading,
                  error: _error,
                  stepGoal: _stepGoal,
                  healthAuthorized: _healthAuthorized,
                  notificationsState: _notificationsState,
                  displayName: _displayName,
                  authService: widget.authService,
                  onRefresh: _fetchSteps,
                  onEnableHealth: _enableHealthData,
                  onEnableNotifications: _enableNotifications,
                  onSetStepGoal: _showStepGoalDialog,
                  onDisplayNameChanged: _syncSettingsState,
                  currentChallenge: _currentChallenge,
                  friendsSteps: _friendsSteps,
                  activeChallengeProgress: _activeChallengeProgress,
                  onChallengeChanged: _fetchCurrentChallenge,
                  onOpenFriendsTab: _openFriendsTab,
                ),
                ChallengesTab(
                  authService: widget.authService,
                  currentChallenge: _currentChallenge,
                  friendsSteps: _friendsSteps,
                  onChallengeChanged: _fetchCurrentChallenge,
                  onOpenFriendsTab: _openFriendsTab,
                  onRefresh: _refreshChallengesTab,
                ),
                FriendsTab(
                  authService: widget.authService,
                  onFriendsChanged: () {
                    _refreshStepGoal();
                    _fetchFriendsSteps();
                  },
                  onRefresh: _refreshFriendsTab,
                  backendApiService: _backendApiService,
                ),
                LeaderboardTab(
                  authService: widget.authService,
                  backendApiService: _backendApiService,
                ),
                ProfileTab(
                  authService: widget.authService,
                  displayName: _displayName,
                  stepGoal: _stepGoal,
                  email: _email,
                  onSettingsChanged: _syncSettingsState,
                  onRefresh: _refreshProfileTab,
                  backendApiService: _backendApiService,
                  notificationService: widget.notificationService,
                ),
              ],
            ),
          ),

          // Grass ground strip above the nav bar
          Positioned(
            left: 0,
            right: 0,
            bottom: tabBarHeight,
            height: 110,
            child: CustomPaint(
              painter: _GrassStripPainter(),
            ),
          ),

          // Capybara walking on the grass
          Positioned(
            left: 0,
            right: 0,
            bottom: tabBarHeight + 10,
            height: 112,
            child: const WalkingCapybara(
              walkDuration: Duration(seconds: 10),
              size: 112,
            ),
          ),

          // Bottom tab bar
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
                  icon: Icons.emoji_events_rounded,
                  label: 'Challenges',
                ),
                WoodenTabItem(
                  icon: Icons.people_rounded,
                  label: 'Friends',
                  badgeCount: _incomingFriendRequests,
                ),
                const WoodenTabItem(
                  icon: Icons.leaderboard_rounded,
                  label: 'Leaderboard',
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

class _GrassStripPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    // Dirt layer
    final dirtPath = Path()
      ..moveTo(0, size.height * 0.3);
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height * 0.3 +
          sin(x * 0.008) * 6 +
          cos(x * 0.015) * 4;
      dirtPath.lineTo(x, y);
    }
    dirtPath.lineTo(size.width, size.height);
    dirtPath.lineTo(0, size.height);
    dirtPath.close();

    canvas.drawPath(
      dirtPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [AppColors.dirtLight, AppColors.dirtMid, AppColors.dirtDark],
        ).createShader(Offset.zero & size),
    );

    // Grass layer
    final grassPath = Path()
      ..moveTo(0, size.height * 0.2);
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height * 0.2 +
          sin(x * 0.008) * 6 +
          cos(x * 0.015) * 4;
      grassPath.lineTo(x, y);
    }
    grassPath.lineTo(size.width, size.height * 0.4);
    for (double x = size.width; x >= 0; x -= 4) {
      final y = size.height * 0.4 +
          sin(x * 0.008) * 4 +
          cos(x * 0.015) * 3;
      grassPath.lineTo(x, y);
    }
    grassPath.close();

    canvas.drawPath(
      grassPath,
      Paint()
        ..shader = const LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [
            AppColors.grassBright,
            AppColors.grassMid,
            AppColors.grassDark,
          ],
        ).createShader(Offset.zero & size),
    );

    // Grass highlight line
    final highlightPath = Path();
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height * 0.2 +
          sin(x * 0.008) * 6 +
          cos(x * 0.015) * 4;
      if (x == 0) {
        highlightPath.moveTo(x, y);
      } else {
        highlightPath.lineTo(x, y);
      }
    }
    canvas.drawPath(
      highlightPath,
      Paint()
        ..color = const Color(0xFFA5D6A7)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2,
    );
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
