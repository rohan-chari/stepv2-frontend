import 'package:flutter/material.dart';

import '../models/step_data.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/health_service.dart';
import '../styles.dart';
import '../widgets/capybara.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/game_button.dart';
import '../widgets/step_count_card.dart';
import '../widgets/trail_sign.dart';
import 'display_name_screen.dart';
import 'friends_screen.dart';
import 'settings_screen.dart';
import 'start_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final HealthService _healthService = HealthService();
  final BackendApiService _backendApiService = BackendApiService();

  bool _healthAuthorized = false;
  bool _isLoading = false;
  String? _error;
  StepData? _stepData;
  int? _stepGoal;
  int _incomingFriendRequests = 0;
  String? _displayName;
  List<Map<String, dynamic>> _friendsSteps = [];

  @override
  void initState() {
    super.initState();
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
    }
  }

  Future<void> _restoreAndFetch() async {
    setState(() {
      _stepGoal = widget.authService.stepGoal;
      _displayName = widget.authService.displayName;
    });

    final wasAuthorized = await _healthService.restoreHealthAuthState();
    if (!wasAuthorized || !mounted) return;

    setState(() => _healthAuthorized = true);
    await _fetchSteps();
    _refreshStepGoal();
    _fetchFriendsSteps();
  }

  Future<void> _enableHealthData() async {
    setState(() => _isLoading = true);

    try {
      final authorized = await _healthService.requestAuthorization();
      if (!authorized) {
        setState(() {
          _isLoading = false;
          _error = 'Health data access not granted.\nPlease allow access in Settings.';
        });
        return;
      }

      setState(() => _healthAuthorized = true);
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
        final identityToken = widget.authService.identityToken;

        if (identityToken == null || identityToken.isEmpty) {
          throw Exception('not signed in');
        }

        await _backendApiService.recordSteps(
          identityToken: identityToken,
          stepData: stepData,
        );
      } catch (e) {
        syncWarning = 'Steps loaded, but sync failed. Check your connection.';
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
      final identityToken = widget.authService.identityToken;
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

  Future<void> _refreshStepGoal() async {
    try {
      final identityToken = widget.authService.identityToken;
      if (identityToken == null || identityToken.isEmpty) return;

      final user = await _backendApiService.fetchMe(
        identityToken: identityToken,
      );
      final goal = user['stepGoal'] as int?;
      final incoming = user['incomingFriendRequests'] as int? ?? 0;
      final displayName = user['displayName'] as String?;
      await widget.authService.updateStepGoal(goal);
      await widget.authService.updateDisplayName(displayName);
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
    setState(() => _stepGoal = widget.authService.stepGoal);
  }

  Future<void> _showStepGoalDialog() async {
    final controller = TextEditingController(
      text: _stepGoal?.toString() ?? '',
    );

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
                      borderSide: BorderSide(
                        color: AppColors.accent,
                        width: 2,
                      ),
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
      final identityToken = widget.authService.identityToken;
      if (identityToken != null && identityToken.isNotEmpty) {
        await _backendApiService.setStepGoal(
          identityToken: identityToken,
          stepGoal: result,
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Couldn\u2019t save your step goal. Please try again.');
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
                    style: PixelText.title(
                      size: 20,
                      color: AppColors.textDark,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 14),
                  Text(
                    'Step Tracker needs access to your health data to count your daily steps.\n\n'
                    "That's all we use - just your step count.",
                    style: PixelText.body(
                      size: 14,
                      color: AppColors.textMid,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  if (_error != null) ...[
                    const SizedBox(height: 14),
                    Text(
                      _error!,
                      style: PixelText.body(
                        size: 13,
                        color: AppColors.error,
                      ),
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
              GameButton(
                label: 'ENABLE',
                onPressed: _enableHealthData,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendRow(Map<String, dynamic> friend) {
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
            child: Text(
              displayName,
              style: PixelText.title(size: 14, color: AppColors.textDark),
            ),
          ),
          Text(
            progressText,
            style: PixelText.body(size: 13, color: AppColors.textMid),
          ),
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
          padding: const EdgeInsets.only(left: 24, right: 24, top: 16, bottom: 40),
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

              // Friends steps
              const SizedBox(height: 16),
              ContentBoard(
                width: double.infinity,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Text(
                      'FRIENDS',
                      style: PixelText.title(size: 16, color: AppColors.textMid),
                      textAlign: TextAlign.center,
                    ),
                    Padding(
                      padding: const EdgeInsets.only(top: 10),
                      child: Text(
                        'Track your friends\u2019 progress and\nmotivate them to get their steps in!',
                        style: PixelText.body(size: 13, color: AppColors.textMid),
                        textAlign: TextAlign.center,
                      ),
                    ),
                    for (final friend in _friendsSteps)
                      _buildFriendRow(friend),
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
                  SizedBox(
                    width: double.infinity,
                    child: GameButton(
                      label: 'START A CHALLENGE',
                      fontSize: 16,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 48,
                        vertical: 16,
                      ),
                      onPressed: _displayName != null
                          ? () {
                              // TODO: implement challenge
                            }
                          : null,
                    ),
                  ),
                  const SizedBox(height: 12),
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
