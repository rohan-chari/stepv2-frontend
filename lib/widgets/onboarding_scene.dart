import 'dart:io' show Platform;

import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter/material.dart';

import '../styles.dart';
import 'home_hero_scene.dart';

/// True under `flutter test`. Perpetual scene animations (walk cycle) idle on
/// their first frame there so widget tests can pumpAndSettle; real devices are
/// unaffected.
bool get onboardingSceneInTestEnv {
  if (kIsWeb) return false;
  try {
    return Platform.environment.containsKey('FLUTTER_TEST');
  } catch (_) {
    return false;
  }
}

/// Shared scaffold for every onboarding step, mirroring the title screen's
/// composition exactly: the [HomeHeroScene] sky/moon/clouds with the walking
/// capybara standing on the ground strip up top, and a parchment dock (wood
/// top border + upward shadow) pinned to the bottom carrying the step's copy
/// and actions. Steps differ only in the headline floating in the sky, an
/// optional emblem hovering mid-scene, and the dock contents.
class OnboardingScene extends StatelessWidget {
  const OnboardingScene({
    super.key,
    required this.headline,
    required this.actions,
    this.emblem,
    this.sceneExtra,
    this.dockLabel,
    this.dockBody,
    this.dockExtra,
    this.error,
    this.showCapybara = true,
  });

  /// Display text floating in the sky, where the title screen draws "Bara".
  final String headline;

  /// Optional centerpiece hovering between the headline and the capybara
  /// (permission icon ring, coin ring, avatar, check emblem…).
  final Widget? emblem;

  /// Optional row rendered just under the emblem (e.g. enrollment chips).
  final Widget? sceneExtra;

  /// Uppercase eyebrow inside the dock — the "READY TO RACE?" slot.
  final String? dockLabel;

  /// Supporting copy inside the dock.
  final String? dockBody;

  /// Optional extra dock content between the copy and the actions.
  final Widget? dockExtra;

  /// Error line shown above the actions.
  final String? error;

  /// Action widgets stacked at the bottom of the dock (buttons / spinner).
  final List<Widget> actions;

  final bool showCapybara;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final groundHeight = compact ? 72.0 : 88.0;
        final capySize = compact ? 118.0 : 148.0;

        // Under `flutter test`, route the scene through its own reduced-motion
        // path (disableAnimations) so the ambient drift never blocks a
        // pumpAndSettle in the flow's tests. Devices are unaffected, and
        // HomeHeroScene itself stays untouched for tests that exercise its
        // real animation (cloud drift).
        Widget scene = Column(
          children: [
            Expanded(
              child: HomeHeroScene(
                groundHeight: groundHeight,
                skyAlignment: const Alignment(0.6, 1),
                child: SafeArea(
                  bottom: false,
                  child: Stack(
                    children: [
                      Positioned(
                        top: compact ? 14 : 26,
                        left: 24,
                        right: 24,
                        child: Text(
                          headline,
                          textAlign: TextAlign.center,
                          style:
                              PixelText.title(
                                size: compact ? 26 : 31,
                                color: colors.textLight,
                              ).copyWith(
                                height: 1.05,
                                fontWeight: FontWeight.w800,
                                shadows: const [
                                  Shadow(
                                    color: Color(0x40000000),
                                    blurRadius: 4,
                                    offset: Offset(0, 1),
                                  ),
                                ],
                              ),
                        ),
                      ),
                      if (emblem != null || sceneExtra != null)
                        Positioned.fill(
                          top: compact ? 78 : 108,
                          bottom:
                              groundHeight + capySize * (compact ? 0.62 : 0.7),
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              if (emblem != null) Flexible(child: emblem!),
                              if (sceneExtra != null) ...[
                                SizedBox(height: compact ? 12 : 16),
                                sceneExtra!,
                              ],
                            ],
                          ),
                        ),
                      if (showCapybara)
                        Positioned(
                          left: 0,
                          right: 0,
                          bottom: groundHeight - 4 - capySize * 0.22,
                          child: Center(
                            child: OnboardingSceneCapybara(size: capySize),
                          ),
                        ),
                    ],
                  ),
                ),
              ),
            ),
            _buildDock(context, compact: compact),
          ],
        );

        if (onboardingSceneInTestEnv) {
          scene = MediaQuery(
            data: MediaQuery.of(context).copyWith(disableAnimations: true),
            child: scene,
          );
        }

        return ColoredBox(color: colors.parchment, child: scene);
      },
    );
  }

  Widget _buildDock(BuildContext context, {required bool compact}) {
    final colors = AppColors.of(context);
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.parchment,
        border: Border(top: BorderSide(color: colors.woodDark, width: 3)),
        boxShadow: [
          BoxShadow(
            color: colors.woodShadow.withValues(alpha: 0.28),
            offset: const Offset(0, -5),
            blurRadius: 14,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, compact ? 13 : 16, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (dockLabel != null) ...[
                Text(
                  dockLabel!,
                  style: PixelText.title(
                    size: compact ? 15 : 17,
                    color: colors.textDark,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 4),
              ],
              if (dockBody != null)
                Text(
                  dockBody!,
                  style: PixelText.body(
                    size: compact ? 12.5 : 13.5,
                    color: colors.textMid,
                  ),
                  textAlign: TextAlign.center,
                ),
              if (dockExtra != null) ...[
                SizedBox(height: compact ? 10 : 12),
                dockExtra!,
              ],
              if (error != null) ...[
                SizedBox(height: compact ? 8 : 10),
                Text(
                  error!,
                  style: PixelText.body(
                    size: 12.5,
                    color: colors.error,
                  ).copyWith(fontWeight: FontWeight.w800),
                  textAlign: TextAlign.center,
                ),
              ],
              SizedBox(height: compact ? 10 : 13),
              ...actions,
            ],
          ),
        ),
      ),
    );
  }
}

/// Full-scene loading state (fetch/handoff moments): the same sky + ground with
/// a light spinner floating where the emblem would sit — never a flat color.
class OnboardingSceneLoading extends StatelessWidget {
  const OnboardingSceneLoading({super.key});

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    Widget scene = HomeHeroScene(
      groundHeight: 80,
      skyAlignment: const Alignment(0.6, 1),
      child: Center(
        child: CircularProgressIndicator(
          color: colors.textLight,
          strokeWidth: 3,
        ),
      ),
    );
    if (onboardingSceneInTestEnv) {
      scene = MediaQuery(
        data: MediaQuery.of(context).copyWith(disableAnimations: true),
        child: scene,
      );
    }
    return ColoredBox(color: colors.parchment, child: scene);
  }
}

/// The plain walking capybara, anchored to the scene's ground strip by
/// [OnboardingScene]. Same 6-frame sheet + cadence as the title screen.
class OnboardingSceneCapybara extends StatefulWidget {
  const OnboardingSceneCapybara({super.key, required this.size});

  final double size;

  @override
  State<OnboardingSceneCapybara> createState() =>
      _OnboardingSceneCapybaraState();
}

class _OnboardingSceneCapybaraState extends State<OnboardingSceneCapybara>
    with SingleTickerProviderStateMixin {
  static const int _frameCount = 6;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    );
    if (!onboardingSceneInTestEnv) {
      _controller.repeat();
    }
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
