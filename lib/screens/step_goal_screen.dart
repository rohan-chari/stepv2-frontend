import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/wooden_tab_bar.dart';

class StepGoalScreen extends StatefulWidget {
  final AuthService authService;

  const StepGoalScreen({super.key, required this.authService});

  @override
  State<StepGoalScreen> createState() => _StepGoalScreenState();
}

class _StepGoalScreenState extends State<StepGoalScreen> {
  final BackendApiService _api = BackendApiService();
  late final TextEditingController _controller;
  bool _isSaving = false;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.authService.stepGoal?.toString() ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onSave() async {
    final value = int.tryParse(_controller.text);
    if (value == null || value <= 0) return;

    setState(() => _isSaving = true);

    await widget.authService.updateStepGoal(value);

    try {
      final token = widget.authService.authToken;
      if (token != null && token.isNotEmpty) {
        await _api.setStepGoal(identityToken: token, stepGoal: value);
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Couldn\u2019t save your step goal. Please try again.');
      }
    }

    if (mounted) {
      Navigator.of(context).pop(true);
    }
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
                          GestureDetector(
                            onTap: () => Navigator.of(context).pop(),
                            child: Container(
                              padding: const EdgeInsets.all(8),
                              child: const Icon(Icons.arrow_back,
                                  color: AppColors.textDark, size: 24),
                            ),
                          ),
                          Expanded(
                            child: Text(
                              'SET STEP GOAL',
                              style: PixelText.title(size: 20, color: AppColors.textDark)
                                  .copyWith(shadows: _textShadows),
                              textAlign: TextAlign.center,
                            ),
                          ),
                          const SizedBox(width: 40),
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
                              'How many steps per day?',
                              style: PixelText.body(color: AppColors.textMid)
                                  .copyWith(shadows: _textShadows),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 20),
                            TextField(
                              controller: _controller,
                              keyboardType: TextInputType.number,
                              textAlign: TextAlign.center,
                              style: PixelText.number(size: 28, color: AppColors.textDark),
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
                                    horizontal: 16, vertical: 14),
                              ),
                            ),
                            const SizedBox(height: 24),
                            _isSaving
                                ? const CircularProgressIndicator(
                                    color: AppColors.accent)
                                : PillButton(
                                    label: 'SAVE',
                                    variant: PillButtonVariant.primary,
                                    fontSize: 16,
                                    fullWidth: true,
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 48, vertical: 16),
                                    onPressed: _onSave,
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
              currentIndex: 4,
              onTap: (_) => Navigator.of(context).pop(),
              items: const [
                WoodenTabItem(icon: Icons.home_rounded, label: 'Home'),
                WoodenTabItem(icon: Icons.emoji_events_rounded, label: 'Challenges'),
                WoodenTabItem(icon: Icons.people_rounded, label: 'Friends'),
                WoodenTabItem(icon: Icons.leaderboard_rounded, label: 'Leaderboard'),
                WoodenTabItem(icon: Icons.person_rounded, label: 'Profile'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
