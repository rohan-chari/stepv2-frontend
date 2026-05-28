import 'package:flutter/material.dart';

import '../styles.dart';
import 'home_chrome.dart';
import 'pill_button.dart';

/// Full-screen onboarding step that asks the user to grant a permission
/// (health, notifications). Shared by the onboarding flow's steps.
class OnboardingPermissionGate extends StatelessWidget {
  const OnboardingPermissionGate({
    super.key,
    required this.label,
    required this.headline,
    required this.body,
    required this.icon,
    required this.onContinue,
    this.error,
    this.isLoading = false,
  });

  final String label;
  final String headline;
  final String body;
  final IconData icon;
  final VoidCallback onContinue;
  final String? error;
  final bool isLoading;

  @override
  Widget build(BuildContext context) {
    return ColoredBox(
      color: AppColors.roofLight,
      child: Stack(
        children: [
          const Positioned.fill(
            child: CustomPaint(
              painter: ArcadeCheckerPainter(drawBottomStripe: false),
            ),
          ),
          SafeArea(
            child: LayoutBuilder(
              builder: (context, constraints) {
                final compact = constraints.maxHeight < 680;
                return Stack(
                  children: [
                    Positioned.fill(
                      child: SingleChildScrollView(
                        physics: const ClampingScrollPhysics(),
                        padding: EdgeInsets.fromLTRB(
                          24,
                          compact ? 24 : 58,
                          24,
                          128,
                        ),
                        child: Column(
                          children: [
                            _OnboardingPermissionCapybara(
                              size: compact ? 196 : 246,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              label,
                              style: HomeText.label(
                                size: 13,
                                color: AppColors.parchmentLight.withValues(
                                  alpha: 0.86,
                                ),
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              headline,
                              style: HomeText.title(
                                size: 32,
                                color: AppColors.parchment,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            Text(
                              body,
                              style: HomeText.body(
                                size: 15,
                                color: AppColors.parchmentLight.withValues(
                                  alpha: 0.92,
                                ),
                                height: 1.38,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            if (error != null) ...[
                              const SizedBox(height: 18),
                              Text(
                                error!,
                                style: HomeText.body(
                                  size: 14,
                                  color: AppColors.parchment,
                                  weight: FontWeight.w800,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ],
                        ),
                      ),
                    ),
                    Align(
                      alignment: Alignment.bottomCenter,
                      child: Padding(
                        padding: const EdgeInsets.fromLTRB(24, 0, 24, 60),
                        child: isLoading
                            ? const SizedBox(
                                height: 52,
                                child: Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.parchment,
                                    strokeWidth: 3,
                                  ),
                                ),
                              )
                            : SizedBox(
                                width: double.infinity,
                                height: 54,
                                child: PillButton(
                                  label: 'CONTINUE',
                                  variant: PillButtonVariant.secondary,
                                  fullWidth: true,
                                  padding: EdgeInsets.zero,
                                  icon: icon,
                                  onPressed: onContinue,
                                ),
                              ),
                      ),
                    ),
                  ],
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}

class _OnboardingPermissionCapybara extends StatefulWidget {
  const _OnboardingPermissionCapybara({required this.size});

  final double size;

  @override
  State<_OnboardingPermissionCapybara> createState() =>
      _OnboardingPermissionCapybaraState();
}

class _OnboardingPermissionCapybaraState
    extends State<_OnboardingPermissionCapybara>
    with SingleTickerProviderStateMixin {
  static const int _frameCount = 6;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final frameIndex =
              (_controller.value * _frameCount).floor() % _frameCount;

          return ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: Offset(-frameIndex * size, 0),
                child: Image.asset(
                  'assets/images/capybara_walk_right.png',
                  width: size * _frameCount,
                  height: size,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}
