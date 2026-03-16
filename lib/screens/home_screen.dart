import 'package:flutter/material.dart';

import '../models/step_data.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/background_sync_manager.dart';
import '../services/health_service.dart';
import '../styles.dart';
import '../widgets/capybara.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/game_button.dart';
import '../widgets/step_count_card.dart';
import '../widgets/trail_sign.dart';
import 'challenge_detail_screen.dart';
import 'display_name_screen.dart';
import 'friends_screen.dart';
import 'settings_screen.dart';
import 'stake_picker_screen.dart';
import 'start_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({
    super.key,
    required this.authService,
    this.healthService,
    this.backendApiService,
    this.scheduleBackgroundSync,
  });

  final AuthService authService;
  final HealthService? healthService;
  final BackendApiService? backendApiService;
  final Future<bool> Function()? scheduleBackgroundSync;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  late final HealthService _healthService;
  late final BackendApiService _backendApiService;
  late final Future<bool> Function() _scheduleBackgroundSync;

  bool _healthAuthorized = false;
  bool _isLoading = false;
  String? _error;
  StepData? _stepData;
  int? _stepGoal;
  int _incomingFriendRequests = 0;
  String? _displayName;
  List<Map<String, dynamic>> _friendsSteps = [];
  Map<String, dynamic>? _currentChallenge;

  @override
  void initState() {
    super.initState();
    _healthService = widget.healthService ?? HealthService();
    _backendApiService = widget.backendApiService ?? BackendApiService();
    _scheduleBackgroundSync =
        widget.scheduleBackgroundSync ?? BackgroundSyncManager.scheduleNextSync;
    WidgetsBinding.instance.addObserver(this);
    _restoreAndFetch();
  }

  @override
  void dispose() {
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
    }
  }

  Future<void> _restoreAndFetch() async {
    setState(() {
      _stepGoal = widget.authService.stepGoal;
      _displayName = widget.authService.displayName;
    });

    // Proactively refresh session token to keep it valid
    final sessionIsValid = await _refreshSessionToken();
    if (!sessionIsValid || !mounted) return;

    final wasAuthorized = await _healthService.restoreHealthAuthState();
    if (!wasAuthorized || !mounted) return;

    setState(() => _healthAuthorized = true);
    await _scheduleBackgroundSync();
    await _fetchSteps();
    _refreshStepGoal();
    _fetchFriendsSteps();
    _fetchCurrentChallenge();
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

      // Network errors should not force a sign-out.
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
      await _scheduleBackgroundSync();
      await _fetchSteps();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to request health access:\n$e';
      });
    }
  }

  Future<void> _fetchSteps() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final stepData = await _healthService.getStepsToday();
      String? syncWarning;

      try {
        final identityToken = widget.authService.authToken;

        if (identityToken == null || identityToken.isEmpty) {
          throw Exception('not signed in');
        }

        await _backendApiService.recordSteps(
          identityToken: identityToken,
          stepData: stepData,
        );
      } catch (e) {
        syncWarning = e is ApiException
            ? 'Steps loaded, but sync failed: ${e.message}'
            : 'Steps loaded, but sync failed. Check your connection.';
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
    } catch (_) {
      // Non-critical — keep whatever we had
    }
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
    } catch (_) {
      // Non-critical — keep whatever we had
    }
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
      final isAdmin = user['isAdmin'] as bool? ?? false;
      await widget.authService.updateStepGoal(goal);
      await widget.authService.updateDisplayName(displayName);
      await widget.authService.updateAdminAccess(isAdmin);
      if (mounted) {
        setState(() {
          _stepGoal = goal;
          _incomingFriendRequests = incoming;
          _displayName = displayName;
        });
      }
    } catch (_) {
      // Cached value is fine
    }
  }

  Future<void> _openSettings() async {
    await Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => SettingsScreen(authService: widget.authService),
      ),
    );
    if (!mounted) return;

    setState(() {
      _stepGoal = widget.authService.stepGoal;
      _displayName = widget.authService.displayName;
    });
    await _fetchCurrentChallenge();
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
                      child: GameButton(
                        label: 'CANCEL',
                        fontSize: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GameButton(
                        label: 'SAVE',
                        fontSize: 14,
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

    // Optimistic update
    setState(() => _stepGoal = result);
    await widget.authService.updateStepGoal(result);

    // Sync to backend in background
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

  Widget _buildPermissionView() {
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.only(left: 24, right: 24, top: 60),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            TrailSign(
              width: 340,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'HEALTH DATA',
                    style: PixelText.title(size: 20, color: AppColors.textDark),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Step Tracker needs access to your health data to count your daily steps.\n\n'
                    "That's all we use - just your step count.",
                    style: PixelText.body(size: 14, color: AppColors.textMid),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: PixelText.body(size: 13, color: AppColors.error),
                      textAlign: TextAlign.center,
                    ),
                  ],
                ],
              ),
            ),
            const SizedBox(height: 20),
            if (_isLoading)
              const CircularProgressIndicator(color: AppColors.accent)
            else
              GameButton(label: 'ENABLE', onPressed: _enableHealthData),
          ],
        ),
      ),
    );
  }

  bool _hasActiveChallenge() {
    return _currentChallenge != null && _currentChallenge!['challenge'] != null;
  }

  Future<void> _challengeFriend(String friendId, String friendName) async {
    try {
      final identityToken = widget.authService.authToken;
      if (identityToken == null || identityToken.isEmpty) return;

      final result = await _backendApiService.initiateChallenge(
        identityToken: identityToken,
        friendUserId: friendId,
      );

      if (!mounted) return;

      final instance = result['instance'] as Map<String, dynamic>?;
      if (instance == null) return;

      // Navigate to stake picker
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => StakePickerScreen(
            authService: widget.authService,
            instanceId: instance['id'] as String,
            friendName: friendName,
          ),
        ),
      );

      if (mounted) _fetchCurrentChallenge();
    } catch (e) {
      if (mounted) {
        showErrorToast(context, e.toString());
      }
    }
  }

  Map<String, dynamic>? _getInstanceForFriend(String friendId) {
    final instances = _currentChallenge?['instances'] as List? ?? [];
    for (final i in instances) {
      final inst = i as Map<String, dynamic>;
      final aId =
          inst['userAId'] as String? ??
          (inst['userA'] as Map<String, dynamic>?)?['id'] as String? ??
          '';
      final bId =
          inst['userBId'] as String? ??
          (inst['userB'] as Map<String, dynamic>?)?['id'] as String? ??
          '';
      if (aId == friendId || bId == friendId) return inst;
    }
    return null;
  }

  void _openChallengeDetail(Map<String, dynamic> instance) {
    final challenge =
        _currentChallenge?['challenge'] as Map<String, dynamic>? ?? {};
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (context) => ChallengeDetailScreen(
              authService: widget.authService,
              instance: instance,
              challenge: challenge,
            ),
          ),
        )
        .then((_) {
          if (mounted) _fetchCurrentChallenge();
        });
  }

  Widget _buildChallengeAction(String friendId, String displayName) {
    final instance = _getInstanceForFriend(friendId);
    if (instance == null) {
      return GameButton(
        label: 'CHALLENGE',
        fontSize: 11,
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
        onPressed: () => _challengeFriend(friendId, displayName),
      );
    }

    final status = instance['status'] as String? ?? '';
    final stakeStatus = instance['stakeStatus'] as String? ?? '';

    if (status == 'ACTIVE' || stakeStatus == 'AGREED') {
      return GestureDetector(
        onTap: () => _openChallengeDetail(instance),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
          decoration: BoxDecoration(
            color: AppColors.accent.withValues(alpha: 0.15),
            borderRadius: BorderRadius.circular(4),
          ),
          child: Text(
            'ACTIVE',
            style: PixelText.button(size: 11, color: AppColors.accent),
          ),
        ),
      );
    }

    // pending_stake / proposing
    return GestureDetector(
      onTap: () => _openChallengeDetail(instance),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        decoration: BoxDecoration(
          color: Colors.orange.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(4),
        ),
        child: Text(
          'NEGOTIATING',
          style: PixelText.button(size: 11, color: Colors.orange.shade800),
        ),
      ),
    );
  }

  Widget _buildFriendRow(Map<String, dynamic> friend) {
    final friendId = friend['id'] as String? ?? '';
    final displayName = friend['displayName'] as String? ?? '???';
    final steps = friend['steps'] as int? ?? 0;
    final stepGoal = friend['stepGoal'] as int?;

    String progressText;
    if (stepGoal != null && stepGoal > 0) {
      final pct = ((steps / stepGoal) * 100).round();
      progressText = '$steps / $stepGoal  ($pct%)';
    } else {
      progressText = '$steps steps';
    }

    final challengeActive = _hasActiveChallenge();

    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        border: Border.all(color: AppColors.parchmentBorder),
        borderRadius: BorderRadius.circular(6),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  displayName,
                  style: PixelText.title(size: 14, color: AppColors.textDark),
                ),
                const SizedBox(height: 2),
                Text(
                  progressText,
                  style: PixelText.body(size: 13, color: AppColors.textMid),
                ),
              ],
            ),
          ),
          if (challengeActive && _displayName != null)
            _buildChallengeAction(friendId, displayName),
        ],
      ),
    );
  }

  Widget _buildStepsView(double groundHeight) {
    final zeroHint = _stepData != null && _stepData!.steps == 0 && !_isLoading
        ? 'Showing 0 steps? Check Settings > Health > Data Access.'
        : null;

    return Positioned.fill(
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.only(
            left: 24,
            right: 24,
            top: 16,
            bottom: 40,
          ),
          child: Column(
            children: [
              StepCountCard(
                stepData: _stepData,
                isLoading: _isLoading,
                error: _error,
                hint: zeroHint,
                stepGoal: _stepGoal,
                onRefresh: _fetchSteps,
                onSettings: _openSettings,
              ),

              // Weekly challenge banner
              if (_hasActiveChallenge()) ...[
                const SizedBox(height: 16),
                ContentBoard(
                  width: double.infinity,
                  child: Column(
                    children: [
                      Text(
                        'THIS WEEK\u2019S CHALLENGE',
                        style: PixelText.title(
                          size: 14,
                          color: AppColors.accent,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 8),
                      Text(
                        _currentChallenge!['challenge']['title'] as String? ??
                            '',
                        style: PixelText.title(
                          size: 18,
                          color: AppColors.textDark,
                        ),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 6),
                      Text(
                        _currentChallenge!['challenge']['description']
                                as String? ??
                            '',
                        style: PixelText.body(
                          size: 13,
                          color: AppColors.textMid,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              ],

              // Friends steps
              const SizedBox(height: 16),
              ContentBoard(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'FRIENDS',
                      style: PixelText.title(
                        size: 16,
                        color: AppColors.textMid,
                      ),
                      textAlign: TextAlign.center,
                    ),
                    if (!_hasActiveChallenge())
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Track your friends\u2019 progress and\nmotivate them to get their steps in!',
                          style: PixelText.body(
                            size: 13,
                            color: AppColors.textMid,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    if (_hasActiveChallenge())
                      Padding(
                        padding: const EdgeInsets.only(top: 10),
                        child: Text(
                          'Challenge a friend to compete!',
                          style: PixelText.body(
                            size: 13,
                            color: AppColors.textMid,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    for (final friend in _friendsSteps) _buildFriendRow(friend),
                  ],
                ),
              ),

              const SizedBox(height: 20),

              // Action buttons
              Column(
                children: [
                  if (_displayName == null)
                    SizedBox(
                      width: double.infinity,
                      child: GameButton(
                        label: 'SET DISPLAY NAME',
                        fontSize: 16,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                        onPressed: () async {
                          await Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (context) => DisplayNameScreen(
                                authService: widget.authService,
                              ),
                            ),
                          );
                          if (mounted) {
                            setState(() {
                              _displayName = widget.authService.displayName;
                            });
                          }
                        },
                      ),
                    ),
                  if (_displayName == null) const SizedBox(height: 12),
                  if (_stepGoal == null)
                    SizedBox(
                      width: double.infinity,
                      child: GameButton(
                        label: 'SET STEP GOAL',
                        fontSize: 16,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 16,
                        ),
                        onPressed: _showStepGoalDialog,
                      ),
                    ),
                  if (_stepGoal == null) const SizedBox(height: 12),
                  Stack(
                    clipBehavior: Clip.none,
                    children: [
                      SizedBox(
                        width: double.infinity,
                        child: GameButton(
                          label: 'ADD FRIENDS',
                          fontSize: 16,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 16,
                          ),
                          onPressed: _displayName != null
                              ? () async {
                                  await Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (context) => FriendsScreen(
                                        authService: widget.authService,
                                      ),
                                    ),
                                  );
                                  if (mounted) {
                                    _refreshStepGoal();
                                    _fetchFriendsSteps();
                                  }
                                }
                              : null,
                        ),
                      ),
                      if (_incomingFriendRequests > 0)
                        Positioned(
                          top: -8,
                          right: -8,
                          child: Container(
                            padding: const EdgeInsets.all(6),
                            decoration: const BoxDecoration(
                              color: Color(0xFFE05040),
                              shape: BoxShape.circle,
                              boxShadow: [
                                BoxShadow(
                                  color: Color(0xFF8B2020),
                                  offset: Offset(0, 2),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                            child: Text(
                              '$_incomingFriendRequests',
                              style: PixelText.button(
                                size: 12,
                                color: Colors.white,
                              ),
                            ),
                          ),
                        ),
                    ],
                  ),
                ],
              ),

              // Bottom padding for capybara
              SizedBox(height: groundHeight + 40),
            ],
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groundHeight = MediaQuery.of(context).size.height * 0.22;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const StartScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                transitionDuration: const Duration(milliseconds: 600),
              ),
            );
          },
        ),
        title: Text(
          'Step Tracker',
          style: PixelText.body(size: 14, color: Colors.white),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GameBackground(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: groundHeight * 0.45,
              height: 128,
              child: const WalkingCapybara(
                walkDuration: Duration(seconds: 12),
                size: 128,
              ),
            ),
            _healthAuthorized
                ? _buildStepsView(groundHeight)
                : _buildPermissionView(),
          ],
        ),
      ),
    );
  }
}
