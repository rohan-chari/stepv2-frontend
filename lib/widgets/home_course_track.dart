import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'goal_track.dart';
import 'home_chrome.dart';

class HomeCourseTrack extends StatefulWidget {
  const HomeCourseTrack({
    super.key,
    required this.runners,
    this.height = 236,
    this.goalSteps,
  });

  final List<GoalTrackRunner> runners;
  final double height;
  final int? goalSteps;

  @override
  State<HomeCourseTrack> createState() => _HomeCourseTrackState();
}

class _HomeCourseTrackState extends State<HomeCourseTrack>
    with SingleTickerProviderStateMixin {
  static const _courseAsset = 'assets/images/home_race_course_platformer.png';
  static const _capybaraAsset = 'assets/images/capybara_walk_right.png';
  static const _sourceWidth = 1942.0;
  static const _sourceHeight = 809.0;
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
        : '${target.runner.isUser ? 'You' : target.runner.name} • $progress%';

    return Positioned(
      left: (target.center.dx - 60).clamp(8.0, layout.courseWidth - 128),
      top: math.max(10, target.center.dy - target.radius - 42),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: HomeColors.ink,
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
          final capybaraSize = runner.isUser ? 46.0 : 40.0;
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
          previous[i].profilePhotoUrl != next[i].profilePhotoUrl) {
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
    final name = runner.isStealthed
        ? '???'
        : (runner.isUser ? 'You' : runner.name);

    return SizedBox(
      width: 96,
      height: capybaraSize + 38,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _RunnerNameTag(label: name, isUser: runner.isUser),
          Icon(
            Icons.arrow_drop_down_rounded,
            size: 18,
            color: runner.isUser ? HomeColors.gold : HomeColors.ink,
          ),
          SizedBox(
            width: capybaraSize,
            height: capybaraSize,
            child: ClipRect(
              child: OverflowBox(
                maxWidth: double.infinity,
                alignment: Alignment.topLeft,
                child: Transform.translate(
                  offset: Offset(-frameIndex * capybaraSize, 0),
                  child: Image.asset(
                    _HomeCourseTrackState._capybaraAsset,
                    width:
                        capybaraSize *
                        _HomeCourseTrackState._capybaraFrameCount,
                    height: capybaraSize,
                    filterQuality: FilterQuality.none,
                    fit: BoxFit.contain,
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

class _RunnerNameTag extends StatelessWidget {
  const _RunnerNameTag({required this.label, required this.isUser});

  final String label;
  final bool isUser;

  @override
  Widget build(BuildContext context) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: isUser ? HomeColors.ink : Colors.white.withValues(alpha: 0.92),
        borderRadius: BorderRadius.circular(6),
        border: Border.all(
          color: isUser
              ? HomeColors.ink
              : HomeColors.line.withValues(alpha: 0.12),
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
              color: isUser ? Colors.white : HomeColors.ink,
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
  });

  final double courseWidth;
  final double worldHeight;
  final double cropTop;

  @override
  Widget build(BuildContext context) {
    return ClipRRect(
      borderRadius: BorderRadius.circular(6),
      child: DecoratedBox(
        decoration: BoxDecoration(
          color: const Color(0xFFD6EEF8),
          border: Border.all(
            color: HomeColors.line.withValues(alpha: 0.14),
            width: 2,
          ),
        ),
        child: ClipRect(
          child: Transform.translate(
            offset: Offset(0, -cropTop),
            child: Image.asset(
              _HomeCourseTrackState._courseAsset,
              width: courseWidth,
              height: worldHeight,
              fit: BoxFit.fill,
            ),
          ),
        ),
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
                color: HomeColors.surfaceMuted,
                borderRadius: BorderRadius.circular(8),
                border: Border.all(
                  color: HomeColors.line.withValues(alpha: 0.10),
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
                        color: runners[i].color,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      runners[i].isStealthed
                          ? '???'
                          : (runners[i].isUser ? 'You' : runners[i].name),
                      style: HomeText.body(size: 12, color: HomeColors.inkSoft),
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
