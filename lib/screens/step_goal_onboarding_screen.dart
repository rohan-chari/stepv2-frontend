import 'package:flutter/material.dart';

import '../config/backend_config.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/wooden_tab_bar.dart';
import 'main_shell.dart';

class StepGoalOnboardingScreen extends StatefulWidget {
  const StepGoalOnboardingScreen({
    super.key,
    required this.authService,
    this.notificationService,
  });

  final AuthService authService;
  final NotificationService? notificationService;

  @override
  State<StepGoalOnboardingScreen> createState() =>
      _StepGoalOnboardingScreenState();
}

class _StepGoalOnboardingScreenState extends State<StepGoalOnboardingScreen> {
  final BackendApiService _backendApiService = BackendApiService();
  late final TextEditingController _controller;
  bool _isSaving = false;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: '${BackendConfig.minStepGoal}',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    final text = _controller.text.trim();
    final value = text.isEmpty
        ? BackendConfig.minStepGoal
        : int.tryParse(text);

    if (value == null || value < BackendConfig.minStepGoal) {
      showErrorToast(context, 'Minimum step goal is ${BackendConfig.minStepGoal}');
      return;
    }

    setState(() => _isSaving = true);

    await widget.authService.updateStepGoal(value);

    try {
      final token = widget.authService.authToken;
      if (token != null && token.isNotEmpty) {
        await _backendApiService.setStepGoal(
          identityToken: token,
          stepGoal: value,
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(
          context,
          'Couldn\u2019t save your step goal. Please try again.',
        );
        setState(() => _isSaving = false);
        return;
      }
    }

    if (!mounted) return;

    Navigator.of(context).pushReplacement(
      MaterialPageRoute(
        builder: (context) => MainShell(
          authService: widget.authService,
          notificationService: widget.notificationService,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          Container(
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
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Column(
                  children: [
                    // Header
                    Padding(
                      padding: const EdgeInsets.symmetric(vertical: 8),
                      child: Row(
                        children: [
                          Expanded(
                            child: Text(
                              'SET STEP GOAL',
                              style: PixelText.title(
                                      size: 20, color: AppColors.textDark)
                                  .copyWith(shadows: _textShadows),
                              textAlign: TextAlign.center,
                            ),
                          ),
                        ],
                      ),
                    ),

                    // Content
                    Expanded(
                      child: Center(
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'How many steps will you aim for each day?',
                              style: PixelText.body(color: AppColors.textMid)
                                  .copyWith(shadows: _textShadows),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _controller,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: PixelText.number(
                                  size: 28, color: AppColors.textDark),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppColors.parchmentLight,
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(
                                      color: AppColors.parchmentBorder),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                      color: AppColors.parchmentBorder),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                      color: AppColors.accent, width: 2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 14),
                              ),
                            ),
                            const SizedBox(height: 8),
                            Text(
                              'Minimum: 5,000 steps',
                              style: PixelText.body(
                                      size: 12, color: AppColors.textMid)
                                  .copyWith(shadows: _textShadows),
                            ),
                            const SizedBox(height: 24),
                            _isSaving
                                ? const CircularProgressIndicator(
                                    color: AppColors.accent)
                                : PillButton(
                                    label: 'CONTINUE',
                                    variant: PillButtonVariant.primary,
                                    fontSize: 16,
                                    fullWidth: true,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 48, vertical: 16),
                                    onPressed: _onContinue,
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),

          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: WoodenTabBar(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                WoodenTabItem(icon: Icons.home_rounded, label: 'Home'),
                WoodenTabItem(
                    icon: Icons.emoji_events_rounded, label: 'Challenges'),
                WoodenTabItem(icon: Icons.people_rounded, label: 'Friends'),
                WoodenTabItem(
                    icon: Icons.leaderboard_rounded, label: 'Leaderboard'),
                WoodenTabItem(icon: Icons.person_rounded, label: 'Profile'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
