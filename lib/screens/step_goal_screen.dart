import 'dart:math';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/capybara.dart';
import '../widgets/content_board.dart';
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
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final tabBarHeight = 77.5 + bottomInset;
    const grassHeight = 110.0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Sky
          Positioned.fill(
            child: Container(
              decoration: const BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF87CEEB), Color(0xFFB0E0F0), Color(0xFFD4F1F9)],
                ),
              ),
            ),
          ),

          // Board
          Positioned(
            left: 0,
            right: 0,
            top: topInset + 24,
            bottom: tabBarHeight + grassHeight,
            child: ContentBoard(
              expand: true,
              child: Column(
                children: [
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'SET STEP GOAL',
                      style: PixelText.title(size: 24, color: AppColors.textDark),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Container(
                    height: 1,
                    color: AppColors.parchmentBorder.withValues(alpha: 0.5),
                  ),
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'How many steps per day?',
                              style: PixelText.body(color: AppColors.textMid),
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
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                            ),
                            const SizedBox(height: 24),
                            _isSaving
                                ? const CircularProgressIndicator(color: AppColors.accent)
                                : PillButton(
                                    label: 'SAVE',
                                    variant: PillButtonVariant.primary,
                                    fontSize: 16,
                                    fullWidth: true,
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 48,
                                      vertical: 16,
                                    ),
                                    onPressed: _onSave,
                                  ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Grass
          Positioned(
            left: 0,
            right: 0,
            bottom: tabBarHeight,
            height: grassHeight,
            child: CustomPaint(painter: _GrassPainter()),
          ),

          // Capybara
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

          // Nav bar
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: WoodenTabBar(
              currentIndex: 4,
              onTap: (_) {},
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

class _GrassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dirtPath = Path()..moveTo(0, size.height * 0.3);
    for (double x = 0; x <= size.width; x += 4) {
      dirtPath.lineTo(x, size.height * 0.3 + sin(x * 0.008) * 6 + cos(x * 0.015) * 4);
    }
    dirtPath.lineTo(size.width, size.height);
    dirtPath.lineTo(0, size.height);
    dirtPath.close();
    canvas.drawPath(dirtPath, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [AppColors.dirtLight, AppColors.dirtMid, AppColors.dirtDark],
      ).createShader(Offset.zero & size));

    final grassPath = Path()..moveTo(0, size.height * 0.2);
    for (double x = 0; x <= size.width; x += 4) {
      grassPath.lineTo(x, size.height * 0.2 + sin(x * 0.008) * 6 + cos(x * 0.015) * 4);
    }
    grassPath.lineTo(size.width, size.height * 0.4);
    for (double x = size.width; x >= 0; x -= 4) {
      grassPath.lineTo(x, size.height * 0.4 + sin(x * 0.008) * 4 + cos(x * 0.015) * 3);
    }
    grassPath.close();
    canvas.drawPath(grassPath, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [AppColors.grassBright, AppColors.grassMid, AppColors.grassDark],
      ).createShader(Offset.zero & size));

    final hlPath = Path();
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height * 0.2 + sin(x * 0.008) * 6 + cos(x * 0.015) * 4;
      if (x == 0) hlPath.moveTo(x, y); else hlPath.lineTo(x, y);
    }
    canvas.drawPath(hlPath, Paint()
      ..color = const Color(0xFFA5D6A7)..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
