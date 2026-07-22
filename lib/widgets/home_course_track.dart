import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../styles.dart';
import 'goal_track.dart';
import 'home_chrome.dart';
import '../config/animals.dart';
import '../utils/at_name.dart';

class HomeCourseTrack extends StatefulWidget {
  const HomeCourseTrack({
    super.key,
    required this.runners,
    this.height = 268,
    this.goalSteps,
    this.milestoneProgress,
    this.milestoneLabel,
    this.backdropAsset,
    this.frameless = false,
  });

  final List<GoalTrackRunner> runners;
  final double height;
  final int? goalSteps;

  /// Alternate course artwork (e.g. the race-day grandstand variant on the
  /// race detail hero). Must share the home course's dimensions and ground
  /// line so runner anchors stay valid. Null → the home course.
  final String? backdropAsset;

  /// When true the backdrop renders edge-to-edge: no rounded corners, no
  /// hairline border (for full-bleed hero placements).
  final bool frameless;

  /// Position of a "goal" milestone marker along the track, in the same
  /// leader-relative 0..1 space as runner progress. When null, no marker.
  /// The track's finish line represents the current leader (1.0), so the
  /// milestone may sit behind the leader if they've passed it.
  final double? milestoneProgress;

  /// Label rendered on the milestone marker (e.g. "50K").
  final String? milestoneLabel;

  @override
  State<HomeCourseTrack> createState() => _HomeCourseTrackState();
}

class _HomeCourseTrackState extends State<HomeCourseTrack>
    with SingleTickerProviderStateMixin {
  static const _sourceWidth = 1942.0;
  static const _sourceHeight = 809.0;
  // Drives the shared track walk cadence; per-runner sprites mod by their own
  // sheet's frame count inside CapybaraSpriteWithAccessories.
  static const _capybaraFrameCount = 6;
  static const _courseAnchors = <Offset>[
    Offset(0.060, 0.803),
    Offset(0.940, 0.803),
  ];
  static const _friendClusterOffsets = <Offset>[
    Offset.zero,
    Offset(-24, 0),
    Offset(24, 0),
    Offset(0, -8),
  ];
  static const _friendOffsetsNearUser = <Offset>[
    Offset(-28, 0),
    Offset(28, 0),
    Offset(0, -8),
  ];

  late final AnimationController _controller;
  late final Animation<double> _animation;
  final ScrollController _scrollController = ScrollController();
  _RunnerHitTarget? _selectedRunner;
  double? _scheduledScrollOffset;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 2200),
    );
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutCubic,
    );
    _controller.forward();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    for (final asset in const [AppThemeAssets.light, AppThemeAssets.night]) {
      precacheImage(AssetImage(asset.homeCourse), context);
      precacheImage(AssetImage(asset.raceDayCourse), context);
    }
  }

  @override
  void didUpdateWidget(covariant HomeCourseTrack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!_sameRunnerProgress(oldWidget.runners, widget.runners)) {
      _selectedRunner = null;
      _controller
        ..reset()
        ..forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final runners = widget.runners;

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        SizedBox(
          width: double.infinity,
          height: widget.height,
          child: AnimatedBuilder(
            animation: _animation,
            builder: (context, child) {
              return LayoutBuilder(
                builder: (context, constraints) {
                  final layout = _buildLayout(constraints.maxWidth);
                  _scheduleScrollToUser(layout, constraints.maxWidth);
                  final runnerLayouts = _buildRunnerLayouts(layout);

                  return Stack(
                    children: [
                      SingleChildScrollView(
                        key: const Key('home-course-track-scroll'),
                        controller: _scrollController,
                        scrollDirection: Axis.horizontal,
                        child: SizedBox(
                          width: layout.courseWidth,
                          height: widget.height,
                          child: Stack(
                            clipBehavior: Clip.none,
                            children: [
                              Positioned.fill(
                                child: _CourseBackdrop(
                                  courseWidth: layout.courseWidth,
                                  worldHeight: layout.worldHeight,
                                  cropTop: layout.cropTop,
                                  asset:
                                      widget.backdropAsset ??
                                      AppThemeAssets.of(context).homeCourse,
                                  frameless: widget.frameless,
                                ),
                              ),
                              if (_milestonePoint(layout) case final point?)
                                Positioned(
                                  left: point.dx - _MilestoneMarker.width / 2,
                                  top: point.dy - _MilestoneMarker.height,
                                  child: IgnorePointer(
                                    child: _MilestoneMarker(
                                      label: widget.milestoneLabel ?? 'GOAL',
                                    ),
                                  ),
                                ),
                              for (final runner in runnerLayouts)
                                Positioned(
                                  left:
                                      runner.shadowCenter.dx -
                                      runner.shadowSize.width / 2,
                                  top:
                                      runner.shadowCenter.dy -
                                      runner.shadowSize.height / 2,
                                  child: IgnorePointer(
                                    child: _RunnerShadow(
                                      size: runner.shadowSize,
                                    ),
                                  ),
                                ),
                              for (final runner in runnerLayouts)
                                Positioned(
                                  left:
                                      runner.center.dx - runner.markerWidth / 2,
                                  top: runner.center.dy - runner.markerHeight,
                                  child: GestureDetector(
                                    behavior: HitTestBehavior.opaque,
                                    onTap: () {
                                      setState(() {
                                        _selectedRunner =
                                            _selectedRunner?.runner ==
                                                runner.runner
                                            ? null
                                            : _RunnerHitTarget(
                                                runner: runner.runner,
                                                center: runner.center,
                                                radius: runner.markerWidth / 2,
                                              );
                                      });
                                    },
                                    child: _CapybaraRunnerMarker(
                                      runner: runner.runner,
                                      capybaraSize: runner.capybaraSize,
                                      frameIndex: runner.frameIndex,
                                    ),
                                  ),
                                ),
                              if (_selectedRunner != null)
                                _buildTooltip(_selectedRunner!, layout),
                            ],
                          ),
                        ),
                      ),
                    ],
                  );
                },
              );
            },
          ),
        ),
        if (runners.isNotEmpty) ...[
          const SizedBox(height: 10),
          _LegendRow(runners: runners),
        ],
      ],
    );
  }

  Widget _buildTooltip(_RunnerHitTarget target, _CourseLayout layout) {
    final progress = (target.runner.progress * 100).clamp(0, 100).round();
    final label = target.runner.isStealthed
        ? '??? • ?%'
        : '${target.runner.isUser ? 'You' : atName(target.runner.name)} • $progress%';

    return Positioned(
      left: (target.center.dx - 60).clamp(8.0, layout.courseWidth - 128),
      top: math.max(10, target.center.dy - target.radius - 42),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.of(context).ink,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: Colors.white.withValues(alpha: 0.18),
            width: 2,
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
          child: Text(
            label,
            style: HomeText.body(
              size: 11,
              color: Colors.white,
              weight: FontWeight.w700,
              height: 1.0,
            ),
          ),
        ),
      ),
    );
  }

  _CourseLayout _buildLayout(double viewportWidth) {
    final aspectRatio = _sourceWidth / _sourceHeight;
    final naturalWidth = widget.height * aspectRatio;
    final courseWidth = math.max(naturalWidth, viewportWidth * 1.45);
    final worldHeight = courseWidth / aspectRatio;
    final cropTop = math.max(0.0, worldHeight - widget.height);

    return _CourseLayout(
      courseWidth: courseWidth,
      worldHeight: worldHeight,
      cropTop: cropTop,
    );
  }

  void _scheduleScrollToUser(_CourseLayout layout, double viewportWidth) {
    final userRunner = _userRunner();
    final userProgress = userRunner == null
        ? 0.0
        : userRunner.progress.clamp(0.0, 1.0).toDouble();
    final userPoint = _coursePointForProgress(
      progress: userProgress,
      layout: layout,
    );
    final maxScroll = math.max(0.0, layout.courseWidth - viewportWidth);
    final targetOffset = (userPoint.dx - viewportWidth * 0.36).clamp(
      0.0,
      maxScroll,
    );

    if (_scheduledScrollOffset != null &&
        (targetOffset - _scheduledScrollOffset!).abs() < 1) {
      return;
    }
    _scheduledScrollOffset = targetOffset;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || !_scrollController.hasClients) return;
      final clamped = targetOffset.clamp(
        0.0,
        _scrollController.position.maxScrollExtent,
      );
      _scrollController.animateTo(
        clamped,
        duration: const Duration(milliseconds: 550),
        curve: Curves.easeOutCubic,
      );
    });
  }

  List<_RunnerLayout> _buildRunnerLayouts(_CourseLayout layout) {
    final sorted = [...widget.runners]
      ..sort((a, b) {
        if (a.isUser && !b.isUser) return 1;
        if (!a.isUser && b.isUser) return -1;
        return a.progress.compareTo(b.progress);
      });

    final friendClusterCounts = <int, int>{};
    final userClusterKey = _userClusterKey();

    return [
      for (final runner in sorted)
        () {
          final progress = runner.progress.clamp(0.0, 1.0).toDouble();
          final animatedProgress = progress * _animation.value;
          final basePoint = _coursePointForProgress(
            progress: animatedProgress,
            layout: layout,
          );
          final sizeScale = (widget.height / 236.0).clamp(1.0, 1.16);
          final capybaraSize = (runner.isUser ? 50.0 : 44.0) * sizeScale;
          final overlayOffset = runner.isUser
              ? const Offset(0, -1)
              : _friendOverlayOffset(
                  progress: progress,
                  userClusterKey: userClusterKey,
                  friendClusterCounts: friendClusterCounts,
                );
          final groundSink = capybaraSize * 0.44;
          final center = basePoint + overlayOffset + Offset(0, groundSink);
          final shadowCenter =
              basePoint + Offset(overlayOffset.dx * 0.62, groundSink + 2);
          final shadowSize = Size(capybaraSize * 0.78, runner.isUser ? 8 : 7);
          final frameIndex =
              (_animation.value * _capybaraFrameCount * 8).floor() %
              _capybaraFrameCount;

          return _RunnerLayout(
            runner: runner,
            center: center,
            capybaraSize: capybaraSize,
            frameIndex: frameIndex,
            shadowCenter: shadowCenter,
            shadowSize: shadowSize,
          );
        }(),
    ];
  }

  Offset _friendOverlayOffset({
    required double progress,
    required int? userClusterKey,
    required Map<int, int> friendClusterCounts,
  }) {
    final clusterKey = (progress * 14).round();
    final index = friendClusterCounts.update(
      clusterKey,
      (value) => value + 1,
      ifAbsent: () => 0,
    );
    final offsets = clusterKey == userClusterKey
        ? _friendOffsetsNearUser
        : _friendClusterOffsets;
    return offsets[index % offsets.length];
  }

  /// Course point for the goal milestone marker, or null if none should show.
  Offset? _milestonePoint(_CourseLayout layout) {
    final milestone = widget.milestoneProgress;
    if (milestone == null || !milestone.isFinite || milestone < 0) return null;
    final clamped = milestone.clamp(0.0, 1.0).toDouble();
    final point = _coursePointForProgress(progress: clamped, layout: layout);
    // Anchor sits at the ground line; nudge up so the flag stands on the path.
    return point + const Offset(0, 6);
  }

  Offset _coursePointForProgress({
    required double progress,
    required _CourseLayout layout,
  }) {
    final anchors = _scaledAnchors(layout);
    final pathLengths = _anchorDistances(anchors);
    final totalDistance = pathLengths.last;
    final targetDistance = totalDistance * progress.clamp(0.0, 1.0).toDouble();

    for (var i = 0; i < anchors.length - 1; i++) {
      final startDistance = pathLengths[i];
      final endDistance = pathLengths[i + 1];
      if (targetDistance <= endDistance) {
        final span = endDistance - startDistance;
        final localT = span == 0
            ? 0.0
            : (targetDistance - startDistance) / span;
        return Offset.lerp(anchors[i], anchors[i + 1], localT)!;
      }
    }

    return anchors.last;
  }

  List<Offset> _scaledAnchors(_CourseLayout layout) {
    return [
      for (final anchor in _courseAnchors)
        Offset(
          anchor.dx * layout.courseWidth,
          anchor.dy * layout.worldHeight - layout.cropTop,
        ),
    ];
  }

  List<double> _anchorDistances(List<Offset> anchors) {
    final distances = <double>[0];
    for (var i = 1; i < anchors.length; i++) {
      distances.add(distances.last + (anchors[i] - anchors[i - 1]).distance);
    }
    return distances;
  }

  GoalTrackRunner? _userRunner() {
    for (final runner in widget.runners) {
      if (runner.isUser) return runner;
    }
    return null;
  }

  int? _userClusterKey() {
    final userRunner = _userRunner();
    if (userRunner == null) return null;
    return (userRunner.progress.clamp(0.0, 1.0).toDouble() * 14).round();
  }

  bool _sameRunnerProgress(
    List<GoalTrackRunner> previous,
    List<GoalTrackRunner> next,
  ) {
    if (previous.length != next.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (previous[i].name != next[i].name ||
          previous[i].progress != next[i].progress ||
          previous[i].isUser != next[i].isUser ||
          previous[i].profilePhotoUrl != next[i].profilePhotoUrl ||
          previous[i].animal != next[i].animal ||
          !_sameAccessories(previous[i].accessories, next[i].accessories)) {
        return false;
      }
    }
    return true;
  }

  bool _sameAccessories(
    List<Map<String, dynamic>> previous,
    List<Map<String, dynamic>> next,
  ) {
    if (previous.length != next.length) return false;
    for (var i = 0; i < previous.length; i++) {
      if (previous[i]['id'] != next[i]['id'] ||
          previous[i]['slot'] != next[i]['slot'] ||
          previous[i]['assetKey'] != next[i]['assetKey']) {
        return false;
      }
    }
    return true;
  }
}

class _CapybaraRunnerMarker extends StatelessWidget {
  const _CapybaraRunnerMarker({
    required this.runner,
    required this.capybaraSize,
    required this.frameIndex,
  });

  final GoalTrackRunner runner;
  final double capybaraSize;
  final int frameIndex;

  @override
  Widget build(BuildContext context) {
    final name =
        runner.label ??
        (runner.isStealthed
            ? '???'
            : (runner.isUser ? 'You' : atName(runner.name)));

    final teamColor = runner.teamColor;

    return SizedBox(
      width: 96,
      height: capybaraSize + 38,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // TR-804: team pennant beside the name — UI chrome, not artwork.
          if (teamColor != null)
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.flag_rounded, size: 11, color: teamColor),
                const SizedBox(width: 2),
                Flexible(
                  child: _RunnerNameTag(label: name, isUser: runner.isUser),
                ),
              ],
            )
          else
            _RunnerNameTag(label: name, isUser: runner.isUser),
          Icon(
            Icons.arrow_drop_down_rounded,
            size: 18,
            color: runner.isUser
                ? AppColors.of(context).coinLight
                : AppColors.of(context).ink,
          ),
          Container(
            width: capybaraSize,
            height: capybaraSize,
            // TR-804: team-colored outline glow around the course capy.
            decoration: teamColor != null
                ? BoxDecoration(
                    shape: BoxShape.circle,
                    boxShadow: [
                      BoxShadow(
                        color: teamColor.withValues(alpha: 0.75),
                        blurRadius: 9,
                        spreadRadius: 1.5,
                      ),
                    ],
                  )
                : null,
            child: CapybaraSpriteWithAccessories(
              accessories: runner.accessories,
              capybaraSize: capybaraSize,
              frameIndex: frameIndex,
              animal: runner.animal,
            ),
          ),
        ],
      ),
    );
  }
}

class CapybaraCustomizationPreview extends StatefulWidget {
  const CapybaraCustomizationPreview({
    super.key,
    required this.accessories,
    this.size = 118,
    this.animal,
    this.showShadow = true,
  });

  final List<Map<String, dynamic>> accessories;
  final double size;
  final String? animal;

  /// The floating ellipse shadow under the sprite. Callers that stand the
  /// capybara on a drawn ground line (e.g. the home hero scene) turn it off.
  final bool showShadow;

  @override
  State<CapybaraCustomizationPreview> createState() =>
      _CapybaraCustomizationPreviewState();
}

class _CapybaraCustomizationPreviewState
    extends State<CapybaraCustomizationPreview>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 720),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: 'Customized capybara preview',
      image: true,
      child: SizedBox(
        width: widget.size * 1.18,
        height: widget.size * 1.02,
        child: AnimatedBuilder(
          animation: _controller,
          builder: (context, child) {
            final frames = animalSpriteFor(widget.animal).frameCount;
            final frameIndex = (_controller.value * frames).floor() % frames;

            return Stack(
              clipBehavior: Clip.none,
              alignment: Alignment.bottomCenter,
              children: [
                if (widget.showShadow)
                  Positioned(
                    bottom: widget.size * 0.08,
                    child: DecoratedBox(
                      decoration: BoxDecoration(
                        color: AppColors.of(
                          context,
                        ).ink.withValues(alpha: 0.18),
                        borderRadius: BorderRadius.circular(widget.size * 0.08),
                      ),
                      child: SizedBox(
                        width: widget.size * 0.78,
                        height: widget.size * 0.08,
                      ),
                    ),
                  ),
                Positioned(
                  bottom: 0,
                  child: CapybaraSpriteWithAccessories(
                    accessories: widget.accessories,
                    capybaraSize: widget.size,
                    frameIndex: frameIndex,
                    animal: widget.animal,
                  ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

class CapybaraSpriteWithAccessories extends StatelessWidget {
  const CapybaraSpriteWithAccessories({
    super.key,
    required this.accessories,
    required this.capybaraSize,
    required this.frameIndex,
    this.animal,
  });

  final List<Map<String, dynamic>> accessories;
  final double capybaraSize;
  final int frameIndex;

  /// Base character assetKey (e.g. 'corgi_puppy'); null/unknown = capybara.
  final String? animal;

  @override
  Widget build(BuildContext context) {
    final sprite = animalSpriteFor(animal);
    final bodyFrame = frameIndex % sprite.frameCount;
    return SizedBox(
      width: capybaraSize,
      height: capybaraSize,
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final accessory in accessories.where(_isBehindCapybaraAccessory))
            _BehindCapybaraAccessoryOverlay(
              accessory: accessory,
              capybaraSize: capybaraSize,
              frameIndex: frameIndex,
              animal: animal,
            ),
          ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.topLeft,
              child: Transform.translate(
                offset: Offset(-bodyFrame * capybaraSize, 0),
                child: Image.asset(
                  sprite.asset,
                  width: capybaraSize * sprite.frameCount,
                  height: capybaraSize,
                  filterQuality: FilterQuality.none,
                  fit: BoxFit.contain,
                ),
              ),
            ),
          ),
          for (final accessory in accessories.where(
            (accessory) => !_isBehindCapybaraAccessory(accessory),
          ))
            _AccessoryOverlay(
              accessory: accessory,
              capybaraSize: capybaraSize,
              frameIndex: frameIndex,
              animal: animal,
            ),
        ],
      ),
    );
  }

  static bool _isBehindCapybaraAccessory(Map<String, dynamic> accessory) {
    final renderMetadata = accessory['renderMetadata'];
    if (renderMetadata is! Map<String, dynamic>) return false;
    return renderMetadata['renderLayer'] == 'behind';
  }
}

/// [CapybaraSpriteWithAccessories] driven by the walk-cycle animation — a
/// capybara that walks in place wearing its equipped accessories. Used for
/// leaderboard / ranked podium spots.
class AnimatedCapybaraWithAccessories extends StatefulWidget {
  const AnimatedCapybaraWithAccessories({
    super.key,
    required this.accessories,
    required this.size,
    this.stepDuration = const Duration(milliseconds: 760),
    this.animal,
  });

  final List<Map<String, dynamic>> accessories;
  final double size;
  final Duration stepDuration;
  final String? animal;

  @override
  State<AnimatedCapybaraWithAccessories> createState() =>
      _AnimatedCapybaraWithAccessoriesState();
}

class _AnimatedCapybaraWithAccessoriesState
    extends State<AnimatedCapybaraWithAccessories>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.stepDuration,
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final frames = animalSpriteFor(widget.animal).frameCount;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, child) {
        final frameIndex = (_controller.value * frames).floor() % frames;
        return CapybaraSpriteWithAccessories(
          accessories: widget.accessories,
          capybaraSize: widget.size,
          frameIndex: frameIndex,
          animal: widget.animal,
        );
      },
    );
  }
}

class _AccessoryOverlay extends StatelessWidget {
  const _AccessoryOverlay({
    required this.accessory,
    required this.capybaraSize,
    required this.frameIndex,
    this.animal,
  });

  final Map<String, dynamic> accessory;
  final double capybaraSize;
  final int frameIndex;
  final String? animal;

  @override
  Widget build(BuildContext context) {
    final slot = accessory['slot'] as String? ?? '';
    final assetKey = accessory['assetKey'] as String? ?? '';
    final isHeadSlot = slot == 'HEAD';
    // Whether this accessory rides the head-bob. The backend now sends an explicit
    // per-item `bobble` flag; honor it when present. If it's absent (older backend,
    // or a hardcoded preview accessory), fall back to the historical slot rule so
    // behavior is unchanged — HEAD/FACE/NECK bobbed, BACK/FEET did not.
    final bobbleFlag = accessory['bobble'];
    final bobsWithHead = bobbleFlag is bool
        ? bobbleFlag
        : (slot == 'HEAD' || slot == 'FACE' || slot == 'NECK');
    final renderMetadata = accessory['renderMetadata'];
    final metadata = renderMetadataForAnimal(
      renderMetadata is Map<String, dynamic>
          ? renderMetadata
          : const <String, dynamic>{},
      animal,
    );
    final offsetX = _metadataOffset(
      _metadataDouble(metadata, 'offsetX'),
      capybaraSize,
      fallback: isHeadSlot ? -1 : 0,
    );
    final offsetY = _metadataOffset(
      _metadataDouble(metadata, 'offsetY'),
      capybaraSize,
      fallback: isHeadSlot ? 2 : 0,
    );
    final rotation =
        _metadataDouble(metadata, 'rotation') ?? (isHeadSlot ? -0.14 : 0.0);
    final scale = _metadataDouble(metadata, 'scale') ?? 1.0;
    final animationFrames = _metadataInt(metadata, 'animationFrames') ?? 1;

    // FEET items are stamped once per paw (shoes, skates). Single-object items
    // like the skateboard opt out with renderMetadata.perFoot: false and render
    // through the regular one-rect path below.
    if (slot == 'FEET' && metadata['perFoot'] != false) {
      return _FeetAccessoryOverlay(
        assetKey: assetKey,
        capybaraSize: capybaraSize,
        frameIndex: frameIndex,
        offset: Offset(offsetX, offsetY),
        rotation: rotation,
        scale: scale,
      );
    }

    final baseRect = _rectForSlot(slot, capybaraSize).shift(
      Offset(
        offsetX,
        offsetY + (bobsWithHead ? _headBobOffset(capybaraSize) : 0),
      ),
    );
    final rect = Rect.fromCenter(
      center: baseRect.center,
      width: baseRect.width * scale,
      height: baseRect.height * scale,
    );

    return Positioned.fromRect(
      rect: rect,
      child: Transform.rotate(
        angle: rotation,
        alignment: Alignment.center,
        child: _AccessoryImage(
          assetKey: assetKey,
          slot: slot,
          frameIndex: frameIndex,
          frameCount: animationFrames,
        ),
      ),
    );
  }

  double _headBobOffset(double size) {
    const frameOffsets = <double>[0, -1, 0, 1, 0, -1];
    final pixelScale = (size / 58).clamp(0.85, 1.2);
    return frameOffsets[frameIndex % frameOffsets.length] * pixelScale;
  }

  double? _metadataDouble(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _metadataInt(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double _metadataOffset(
    double? value,
    double size, {
    required double fallback,
  }) {
    if (value == null) return fallback;
    if (value.abs() <= 1) return value * size;
    return value;
  }

  Rect _rectForSlot(String slot, double size) {
    switch (slot) {
      case 'HEAD':
        return Rect.fromLTWH(
          size * 0.37,
          size * 0.04,
          size * 0.46,
          size * 0.26,
        );
      case 'FACE':
        return Rect.fromLTWH(
          size * 0.60,
          size * 0.28,
          size * 0.22,
          size * 0.14,
        );
      case 'NECK':
        return Rect.fromLTWH(
          size * 0.46,
          size * 0.44,
          size * 0.32,
          size * 0.16,
        );
      case 'BACK':
        return Rect.fromLTWH(
          size * 0.16,
          size * 0.30,
          size * 0.28,
          size * 0.26,
        );
      case 'FEET':
        return Rect.fromLTWH(
          size * 0.41,
          size * 0.72,
          size * 0.40,
          size * 0.16,
        );
      default:
        return Rect.fromLTWH(
          size * 0.37,
          size * 0.04,
          size * 0.46,
          size * 0.26,
        );
    }
  }
}

class _BehindCapybaraAccessoryOverlay extends StatelessWidget {
  const _BehindCapybaraAccessoryOverlay({
    required this.accessory,
    required this.capybaraSize,
    required this.frameIndex,
    this.animal,
  });

  final Map<String, dynamic> accessory;
  final double capybaraSize;
  final int frameIndex;
  final String? animal;

  @override
  Widget build(BuildContext context) {
    final assetKey = accessory['assetKey'] as String? ?? '';
    final renderMetadata = accessory['renderMetadata'];
    final metadata = renderMetadataForAnimal(
      renderMetadata is Map<String, dynamic>
          ? renderMetadata
          : const <String, dynamic>{},
      animal,
    );
    final offsetX = _metadataOffset(
      _metadataDouble(metadata, 'offsetX'),
      capybaraSize,
      fallback: 0,
    );
    final offsetY = _metadataOffset(
      _metadataDouble(metadata, 'offsetY'),
      capybaraSize,
      fallback: 0,
    );
    final rotation = _metadataDouble(metadata, 'rotation') ?? 0.0;
    final scale = _metadataDouble(metadata, 'scale') ?? 1.0;
    final animationFrames = _metadataInt(metadata, 'animationFrames') ?? 1;

    return Positioned.fill(
      child: Transform.translate(
        offset: Offset(offsetX, offsetY),
        child: Transform.rotate(
          angle: rotation,
          alignment: Alignment.center,
          child: Transform.scale(
            scale: scale,
            alignment: Alignment.center,
            child: ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: Alignment.topLeft,
                child: SizedBox(
                  width: capybaraSize,
                  height: capybaraSize,
                  child: _AccessoryImage(
                    assetKey: assetKey,
                    slot: accessory['slot'] as String? ?? 'BACK',
                    frameIndex: frameIndex,
                    frameCount: animationFrames,
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }

  double? _metadataDouble(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value is num) return value.toDouble();
    if (value is String) return double.tryParse(value);
    return null;
  }

  int? _metadataInt(Map<String, dynamic> metadata, String key) {
    final value = metadata[key];
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value);
    return null;
  }

  double _metadataOffset(
    double? value,
    double size, {
    required double fallback,
  }) {
    if (value == null) return fallback;
    if (value.abs() <= 1) return value * size;
    return value;
  }
}

class _AccessoryImage extends StatelessWidget {
  const _AccessoryImage({
    required this.assetKey,
    required this.slot,
    required this.frameIndex,
    required this.frameCount,
  });

  final String assetKey;
  final String slot;
  final int frameIndex;
  final int frameCount;

  @override
  Widget build(BuildContext context) {
    final assetPath = 'assets/images/accessories/$assetKey.png';
    final safeFrameCount = frameCount < 1 ? 1 : frameCount;

    if (safeFrameCount == 1) {
      return Image.asset(
        assetPath,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
        errorBuilder: (context, error, stackTrace) => CustomPaint(
          painter: _AccessoryPainter(slot: slot, assetKey: assetKey),
        ),
      );
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final frameWidth = constraints.maxWidth;
        final frameHeight = constraints.maxHeight;
        final frame = frameIndex % safeFrameCount;

        return ClipRect(
          child: OverflowBox(
            maxWidth: double.infinity,
            alignment: Alignment.topLeft,
            child: Transform.translate(
              offset: Offset(-frame * frameWidth, 0),
              child: Image.asset(
                assetPath,
                width: frameWidth * safeFrameCount,
                height: frameHeight,
                fit: BoxFit.contain,
                filterQuality: FilterQuality.none,
                errorBuilder: (context, error, stackTrace) => CustomPaint(
                  painter: _AccessoryPainter(slot: slot, assetKey: assetKey),
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}

class _FeetAccessoryOverlay extends StatelessWidget {
  const _FeetAccessoryOverlay({
    required this.assetKey,
    required this.capybaraSize,
    required this.frameIndex,
    required this.offset,
    required this.rotation,
    required this.scale,
  });

  final String assetKey;
  final double capybaraSize;
  final int frameIndex;
  final Offset offset;
  final double rotation;
  final double scale;

  static const _placements = <List<_ShoePlacement>>[
    [
      _ShoePlacement(0.27, 0.73, scale: 0.82, rotation: -0.11),
      _ShoePlacement(0.38, 0.79, rotation: 0.05),
      _ShoePlacement(0.56, 0.73, scale: 0.82, rotation: -0.1),
      _ShoePlacement(0.69, 0.79, rotation: 0.04),
    ],
    [
      _ShoePlacement(0.30, 0.71, scale: 0.78, rotation: -0.2),
      _ShoePlacement(0.42, 0.8, rotation: 0.09),
      _ShoePlacement(0.6, 0.71, scale: 0.78, rotation: -0.18),
      _ShoePlacement(0.7, 0.78, rotation: 0.07),
    ],
    [
      _ShoePlacement(0.31, 0.8, rotation: 0.13),
      _ShoePlacement(0.43, 0.72, scale: 0.8, rotation: -0.19),
      _ShoePlacement(0.54, 0.8, rotation: 0.11),
      _ShoePlacement(0.66, 0.71, scale: 0.8, rotation: -0.2),
    ],
    [
      _ShoePlacement(0.28, 0.73, scale: 0.82, rotation: -0.12),
      _ShoePlacement(0.39, 0.79, rotation: 0.06),
      _ShoePlacement(0.55, 0.73, scale: 0.82, rotation: -0.11),
      _ShoePlacement(0.68, 0.79, rotation: 0.05),
    ],
    [
      _ShoePlacement(0.25, 0.79, rotation: 0.09),
      _ShoePlacement(0.38, 0.72, scale: 0.8, rotation: -0.18),
      _ShoePlacement(0.56, 0.79, rotation: 0.1),
      _ShoePlacement(0.66, 0.72, scale: 0.8, rotation: -0.18),
    ],
    [
      _ShoePlacement(0.23, 0.8, rotation: 0.11),
      _ShoePlacement(0.37, 0.71, scale: 0.78, rotation: -0.21),
      _ShoePlacement(0.52, 0.8, rotation: 0.1),
      _ShoePlacement(0.64, 0.71, scale: 0.78, rotation: -0.2),
    ],
  ];

  @override
  Widget build(BuildContext context) {
    final placements = _placements[frameIndex % _placements.length];
    final shoeWidth = capybaraSize * 0.18 * scale;
    final shoeHeight = capybaraSize * 0.12 * scale;

    return Positioned.fill(
      child: Stack(
        clipBehavior: Clip.none,
        children: [
          for (final placement in placements)
            Positioned.fromRect(
              rect: Rect.fromCenter(
                center:
                    Offset(
                      placement.x * capybaraSize,
                      placement.y * capybaraSize,
                    ) +
                    offset,
                width: shoeWidth * placement.scale,
                height: shoeHeight * placement.scale,
              ),
              child: Transform.rotate(
                angle: rotation + placement.rotation,
                alignment: Alignment.center,
                child: Image.asset(
                  'assets/images/accessories/$assetKey.png',
                  fit: BoxFit.contain,
                  filterQuality: FilterQuality.none,
                  errorBuilder: (context, error, stackTrace) => CustomPaint(
                    painter: _AccessoryPainter(
                      slot: 'FEET',
                      assetKey: assetKey,
                    ),
                  ),
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _ShoePlacement {
  const _ShoePlacement(this.x, this.y, {this.scale = 1, this.rotation = 0});

  final double x;
  final double y;
  final double scale;
  final double rotation;
}

class _AccessoryPainter extends CustomPainter {
  const _AccessoryPainter({required this.slot, required this.assetKey});

  final String slot;
  final String assetKey;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..color = _colorForAsset(assetKey);
    final outline = Paint()
      ..color = AppColors.textDark.withValues(alpha: 0.55)
      ..style = PaintingStyle.stroke
      ..strokeWidth = 1.4;

    switch (slot) {
      case 'FACE':
        final y = size.height * 0.48;
        canvas.drawLine(
          Offset(size.width * 0.18, y),
          Offset(size.width * 0.82, y),
          outline,
        );
        canvas.drawCircle(
          Offset(size.width * 0.32, y),
          size.height * 0.28,
          outline,
        );
        canvas.drawCircle(
          Offset(size.width * 0.68, y),
          size.height * 0.28,
          outline,
        );
        break;
      case 'NECK':
        final rect = RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.height * 0.45),
        );
        canvas.drawRRect(rect, paint);
        canvas.drawRRect(rect, outline);
        break;
      case 'BACK':
        final rect = RRect.fromRectAndRadius(
          Offset.zero & size,
          Radius.circular(size.width * 0.18),
        );
        canvas.drawRRect(rect, paint);
        canvas.drawRRect(rect, outline);
        break;
      case 'FEET':
        final sole = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.04,
            size.height * 0.58,
            size.width * 0.92,
            size.height * 0.24,
          ),
          Radius.circular(size.height * 0.12),
        );
        final upper = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.16,
            size.height * 0.22,
            size.width * 0.54,
            size.height * 0.42,
          ),
          Radius.circular(size.width * 0.14),
        );
        canvas.drawRRect(upper, paint);
        canvas.drawRRect(upper, outline);
        canvas.drawRRect(sole, paint);
        canvas.drawRRect(sole, outline);
        break;
      case 'HEAD':
      default:
        final brim = RRect.fromRectAndRadius(
          Rect.fromLTWH(0, size.height * 0.58, size.width, size.height * 0.22),
          Radius.circular(size.height * 0.12),
        );
        final crown = RRect.fromRectAndRadius(
          Rect.fromLTWH(
            size.width * 0.18,
            0,
            size.width * 0.64,
            size.height * 0.68,
          ),
          Radius.circular(size.width * 0.14),
        );
        canvas.drawRRect(crown, paint);
        canvas.drawRRect(crown, outline);
        canvas.drawRRect(brim, paint);
        canvas.drawRRect(brim, outline);
        break;
    }
  }

  Color _colorForAsset(String assetKey) {
    if (assetKey.contains('gold')) return AppColors.pillGold;
    if (assetKey.contains('red')) return AppColors.pillTerra;
    if (assetKey.contains('green')) return AppColors.roofLight;
    if (assetKey.contains('blue')) return AppColors.roofRidge;
    return AppColors.parchmentDark;
  }

  @override
  bool shouldRepaint(covariant _AccessoryPainter oldDelegate) {
    return oldDelegate.slot != slot || oldDelegate.assetKey != assetKey;
  }
}

class _RunnerNameTag extends StatelessWidget {
  const _RunnerNameTag({required this.label, required this.isUser});

  final String label;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      key: isUser ? const Key('course-user-name-tag') : null,
      decoration: BoxDecoration(
        color: isUser
            ? AppColors.of(context).woodDarker
            : AppColors.of(context).parchment.withValues(alpha: 0.96),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isUser
              ? AppColors.of(context).coinLight
              : AppColors.of(context).line.withValues(alpha: 0.12),
          width: 2,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 4),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 76),
          child: Text(
            label,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: HomeText.body(
              size: 10,
              color: isUser
                  ? AppColors.of(context).textLight
                  : AppColors.of(context).textDark,
              weight: FontWeight.w800,
              height: 1,
            ),
          ),
        ),
      ),
    );
  }
}

class _CourseBackdrop extends StatelessWidget {
  const _CourseBackdrop({
    required this.courseWidth,
    required this.worldHeight,
    required this.cropTop,
    required this.asset,
    this.frameless = false,
  });

  final double courseWidth;
  final double worldHeight;
  final double cropTop;
  final String asset;
  final bool frameless;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(frameless ? 0 : 6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: AppColors.of(context).cloudShadow,
          border: frameless
              ? null
              : Border.all(
                  color: AppColors.of(context).line.withValues(alpha: 0.14),
                  width: 2,
                ),
        ),
        child: ClipRect(
          child: Transform.translate(
            offset: Offset(0, -cropTop),
            child: AnimatedSwitcher(
              duration: MediaQuery.disableAnimationsOf(context)
                  ? Duration.zero
                  : const Duration(milliseconds: 250),
              child: Image.asset(
                asset,
                key: ValueKey(asset),
                width: courseWidth,
                height: worldHeight,
                fit: BoxFit.fill,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _MilestoneMarker extends StatelessWidget {
  const _MilestoneMarker({required this.label});

  final String label;

  static const double width = 64;
  static const double height = 56;
  static const double _poleHeight = 34;

  @override
  Widget build(BuildContext context) {
    return SizedBox(
      width: width,
      height: height,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: AppColors.of(context).gold,
              borderRadius: BorderRadius.circular(5),
              border: Border.all(color: AppColors.of(context).ink, width: 2),
            ),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
              child: Text(
                label,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: HomeText.body(
                  size: 10,
                  color: AppColors.of(context).ink,
                  weight: FontWeight.w800,
                  height: 1,
                ),
              ),
            ),
          ),
          Container(
            width: 3,
            height: _poleHeight,
            color: AppColors.of(context).ink,
          ),
        ],
      ),
    );
  }
}

class _RunnerShadow extends StatelessWidget {
  const _RunnerShadow({required this.size});

  final Size size;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(999),
      ),
      child: SizedBox(width: size.width, height: size.height),
    );
  }
}

class _LegendRow extends StatelessWidget {
  const _LegendRow({required this.runners});

  final List<GoalTrackRunner> runners;

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      key: const Key('home-course-track-legend-scroll'),
      scrollDirection: Axis.horizontal,
      child: Row(
        children: [
          for (var i = 0; i < runners.length; i++) ...[
            if (i > 0) const SizedBox(width: 10),
            DecoratedBox(
              decoration: BoxDecoration(
                color: AppColors.of(context).surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: AppColors.of(context).line.withValues(alpha: 0.10),
                  width: 2,
                ),
              ),
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 7,
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Container(
                      width: 8,
                      height: 8,
                      decoration: BoxDecoration(
                        shape: BoxShape.circle,
                        color: runners[i].teamColor ?? runners[i].color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      runners[i].label ??
                          (runners[i].isStealthed
                              ? '???'
                              : (runners[i].isUser
                                    ? 'You'
                                    : atName(runners[i].name))),
                      style: HomeText.body(
                        size: 12,
                        color: AppColors.of(context).inkSoft,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

class _CourseLayout {
  const _CourseLayout({
    required this.courseWidth,
    required this.worldHeight,
    required this.cropTop,
  });

  final double courseWidth;
  final double worldHeight;
  final double cropTop;
}

class _RunnerLayout {
  const _RunnerLayout({
    required this.runner,
    required this.center,
    required this.capybaraSize,
    required this.frameIndex,
    required this.shadowCenter,
    required this.shadowSize,
  });

  final GoalTrackRunner runner;
  final Offset center;
  final double capybaraSize;
  final int frameIndex;
  final Offset shadowCenter;
  final Size shadowSize;

  double get markerWidth => 96;
  double get markerHeight => capybaraSize + 38;
}

class _RunnerHitTarget {
  const _RunnerHitTarget({
    required this.runner,
    required this.center,
    required this.radius,
  });

  final GoalTrackRunner runner;
  final Offset center;
  final double radius;
}
