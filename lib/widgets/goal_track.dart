import 'dart:math' as math;
import 'package:flutter/material.dart';

import 'app_avatar.dart';
import '../styles.dart';

/// Palette of distinct colors for friend avatars on the track.
const _friendColors = [
  Color(0xFFE57373), // red
  Color(0xFF64B5F6), // blue
  Color(0xFFFFB74D), // orange
  Color(0xFFBA68C8), // purple
  Color(0xFF4DB6AC), // teal
  Color(0xFFFF8A65), // deep orange
  Color(0xFF7986CB), // indigo
  Color(0xFFA1887F), // brown
  Color(0xFF4DD0E1), // cyan
  Color(0xFFAED581), // lime
];

/// A runner on the goal track.
class GoalTrackRunner {
  final String name;
  final String? profilePhotoUrl;
  final double progress;
  final bool isUser;
  final bool isStealthed;

  const GoalTrackRunner({
    required this.name,
    this.profilePhotoUrl,
    required this.progress,
    this.isUser = false,
    this.isStealthed = false,
  });

  /// Deterministic color based on name hash.
  Color get color => isStealthed
      ? const Color(0xFF9E9E9E)
      : isUser
      ? AppColors.pillGreen
      : _friendColors[name.hashCode.abs() % _friendColors.length];
}

class GoalTrack extends StatefulWidget {
  final List<GoalTrackRunner> runners;
  final double height;

  const GoalTrack({super.key, required this.runners, this.height = 240});

  @override
  State<GoalTrack> createState() => _GoalTrackState();
}

class _GoalTrackState extends State<GoalTrack>
    with SingleTickerProviderStateMixin {
  late AnimationController _controller;
  late Animation<double> _animation;
  _RunnerHitTarget? _selectedRunner;

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
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
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
                  final layouts = _buildRunnerLayouts(
                    Size(constraints.maxWidth, widget.height),
                    _animation.value,
                  );

                  return Stack(
                    clipBehavior: Clip.none,
                    children: [
                      const Positioned.fill(
                        child: CustomPaint(painter: _GoalTrackPainter()),
                      ),
                      for (final layout in layouts)
                        Positioned(
                          left: layout.center.dx - layout.radius,
                          top: layout.center.dy - layout.radius,
                          child: GestureDetector(
                            onTap: () {
                              setState(() {
                                _selectedRunner =
                                    _selectedRunner == layout.target
                                    ? null
                                    : layout.target;
                              });
                            },
                            child: AppAvatar(
                              name: layout.runner.name,
                              imageUrl: layout.runner.profilePhotoUrl,
                              size: layout.radius * 2,
                              isUser: layout.runner.isUser,
                              isStealthed: layout.runner.isStealthed,
                              borderWidth: layout.runner.isUser ? 2.5 : 1.8,
                            ),
                          ),
                        ),
                      if (_selectedRunner != null)
                        _buildTooltip(_selectedRunner!),
                    ],
                  );
                },
              );
            },
          ),
        ),
        if (widget.runners.length > 1) ...[
          const SizedBox(height: 8),
          _buildLegend(),
        ],
      ],
    );
  }

  Widget _buildTooltip(_RunnerHitTarget target) {
    final label = target.isStealthed
        ? '??? \u2022 ?%'
        : '${target.name} \u2022 ${(target.progress * 100).clamp(0, 100).toStringAsFixed(0)}%';

    return Positioned(
      left: target.center.dx,
      top: target.center.dy - target.radius - 38,
      child: FractionalTranslation(
        translation: const Offset(-0.5, 0),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
          decoration: BoxDecoration(
            color: AppColors.woodDark,
            borderRadius: BorderRadius.circular(6),
            boxShadow: const [
              BoxShadow(
                color: Color(0x40000000),
                blurRadius: 4,
                offset: Offset(0, 2),
              ),
            ],
          ),
          child: Text(
            label,
            style: PixelText.title(size: 11, color: AppColors.parchment),
          ),
        ),
      ),
    );
  }

  Widget _buildLegend() {
    return Wrap(
      spacing: 12,
      runSpacing: 4,
      alignment: WrapAlignment.center,
      children: [
        for (final runner in widget.runners)
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 10,
                height: 10,
                decoration: BoxDecoration(
                  color: runner.color,
                  shape: BoxShape.circle,
                ),
              ),
              const SizedBox(width: 4),
              Text(
                runner.isStealthed
                    ? '???'
                    : (runner.isUser ? 'You' : runner.name),
                style: PixelText.body(size: 12, color: AppColors.textMid),
              ),
            ],
          ),
      ],
    );
  }

  List<_GoalTrackLayoutRunner> _buildRunnerLayouts(Size size, double t) {
    final painted = widget.runners
        .map(
          (runner) => _PaintedRunner(
            name: runner.isStealthed
                ? '???'
                : (runner.isUser ? 'You' : runner.name),
            profilePhotoUrl: runner.profilePhotoUrl,
            position: runner.progress.clamp(0.0, 1.0) * t,
            rawProgress: runner.progress,
            isUser: runner.isUser,
            isStealthed: runner.isStealthed,
            color: runner.color,
          ),
        )
        .toList();

    final trackPath = _buildGoalTrackPath(size);
    final metrics = trackPath.computeMetrics().first;
    final totalLength = metrics.length;
    final count = painted.length;
    final usableWidth =
        _GoalTrackPainter._trackWidth -
        _GoalTrackPainter._friendAvatarRadius * 2;

    final sorted = List.generate(count, (index) => index)
      ..sort((left, right) {
        if (painted[left].isUser && !painted[right].isUser) return 1;
        if (!painted[left].isUser && painted[right].isUser) return -1;
        return painted[left].position.compareTo(painted[right].position);
      });

    return [
      for (final index in sorted)
        () {
          final runner = painted[index];
          final frac = runner.position.clamp(0.0, 0.999);
          final tangent = metrics.getTangentForOffset(frac * totalLength);
          if (tangent == null) {
            return null;
          }

          final laneOffset = count > 1
              ? (index / (count - 1) - 0.5) * usableWidth
              : 0.0;
          final angle = tangent.angle;
          final center =
              tangent.position +
              Offset(
                -math.sin(angle) * laneOffset,
                math.cos(angle) * laneOffset,
              );
          final radius = runner.isUser
              ? _GoalTrackPainter._avatarRadius
              : _GoalTrackPainter._friendAvatarRadius;

          return _GoalTrackLayoutRunner(
            runner: runner,
            center: center,
            radius: radius,
            target: _RunnerHitTarget(
              center: center,
              radius: radius + _GoalTrackPainter._avatarBorder,
              name: runner.name,
              progress: runner.rawProgress,
              isStealthed: runner.isStealthed,
            ),
          );
        }(),
    ].whereType<_GoalTrackLayoutRunner>().toList(growable: false);
  }
}

class _PaintedRunner {
  final String name;
  final String? profilePhotoUrl;
  final double position;
  final double rawProgress;
  final bool isUser;
  final bool isStealthed;
  final Color color;

  const _PaintedRunner({
    required this.name,
    this.profilePhotoUrl,
    required this.position,
    required this.rawProgress,
    required this.isUser,
    this.isStealthed = false,
    required this.color,
  });
}

class _GoalTrackLayoutRunner {
  final _PaintedRunner runner;
  final Offset center;
  final double radius;
  final _RunnerHitTarget target;

  const _GoalTrackLayoutRunner({
    required this.runner,
    required this.center,
    required this.radius,
    required this.target,
  });
}

class _RunnerHitTarget {
  final Offset center;
  final double radius;
  final String name;
  final double progress;
  final bool isStealthed;

  const _RunnerHitTarget({
    required this.center,
    required this.radius,
    required this.name,
    required this.progress,
    this.isStealthed = false,
  });
}

class _GoalTrackPainter extends CustomPainter {
  static const double _trackWidth = 54.0;
  static const double _avatarRadius = 14.0;
  static const double _friendAvatarRadius = 11.0;
  static const double _avatarBorder = 2.5;

  const _GoalTrackPainter();

  @override
  void paint(Canvas canvas, Size size) {
    final trackPath = _buildGoalTrackPath(size);

    _drawGrass(canvas, size);
    _drawTrees(canvas, size);
    _drawCurbs(canvas, trackPath);
    _drawTrackSurface(canvas, trackPath);
    _drawDashedCenterLine(canvas, trackPath);
    _drawFinishLine(canvas, trackPath);
  }

  void _drawGrass(Canvas canvas, Size size) {
    // Bright green grass background
    final paint = Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter,
        end: Alignment.bottomCenter,
        colors: [Color(0xFF8BC34A), Color(0xFF7CB342), Color(0xFF689F38)],
      ).createShader(Offset.zero & size);

    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, 0, size.width, size.height),
        const Radius.circular(12),
      ),
      paint,
    );
  }

  void _drawTrees(Canvas canvas, Size size) {
    final rng = math.Random(77);
    final treePaint = Paint()
      ..color = AppColors.grassDark.withValues(alpha: 0.5);

    // Scatter some tree blobs
    for (int i = 0; i < 8; i++) {
      final x = rng.nextDouble() * size.width;
      final y = rng.nextDouble() * size.height;
      final r = 10.0 + rng.nextDouble() * 14;

      // Simple clover/tree shape: 3 overlapping circles
      canvas.drawCircle(Offset(x, y - r * 0.3), r * 0.6, treePaint);
      canvas.drawCircle(Offset(x - r * 0.4, y + r * 0.2), r * 0.5, treePaint);
      canvas.drawCircle(Offset(x + r * 0.4, y + r * 0.2), r * 0.5, treePaint);
    }
  }

  void _drawCurbs(Canvas canvas, Path trackPath) {
    // Outer curb: alternating red/white stripes
    final metrics = trackPath.computeMetrics().first;
    final totalLength = metrics.length;
    const stripeLen = 12.0;
    final redPaint = Paint()
      ..color = AppColors.accent
      ..style = PaintingStyle.stroke
      ..strokeWidth = _trackWidth + 12
      ..strokeCap = StrokeCap.round;
    final whitePaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = _trackWidth + 12
      ..strokeCap = StrokeCap.round;

    for (double d = 0; d < totalLength; d += stripeLen * 2) {
      // Red stripe
      final start = d;
      final end = (d + stripeLen).clamp(0.0, totalLength);
      final segment = metrics.extractPath(start, end);
      canvas.drawPath(segment, redPaint);

      // White stripe
      final start2 = end;
      final end2 = (end + stripeLen).clamp(0.0, totalLength);
      if (start2 < totalLength) {
        final segment2 = metrics.extractPath(start2, end2);
        canvas.drawPath(segment2, whitePaint);
      }
    }
  }

  void _drawTrackSurface(Canvas canvas, Path trackPath) {
    // Gray road surface
    canvas.drawPath(
      trackPath,
      Paint()
        ..color = const Color(0xFF9E9E9E)
        ..style = PaintingStyle.stroke
        ..strokeWidth = _trackWidth
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round,
    );
  }

  void _drawDashedCenterLine(Canvas canvas, Path trackPath) {
    final metrics = trackPath.computeMetrics().first;
    final totalLength = metrics.length;
    final dashPaint = Paint()
      ..color = Colors.white
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2.5
      ..strokeCap = StrokeCap.round;

    const dashLen = 10.0;
    const gapLen = 8.0;

    for (double d = 0; d < totalLength; d += dashLen + gapLen) {
      final end = (d + dashLen).clamp(0.0, totalLength);
      final segment = metrics.extractPath(d, end);
      canvas.drawPath(segment, dashPaint);
    }
  }

  void _drawFinishLine(Canvas canvas, Path trackPath) {
    final metrics = trackPath.computeMetrics().first;
    final tangent = metrics.getTangentForOffset(metrics.length - 6);
    if (tangent == null) return;

    final pos = tangent.position;
    final angle = tangent.angle;

    canvas.save();
    canvas.translate(pos.dx, pos.dy);
    canvas.rotate(angle);

    const checkerSize = 3.0;
    const rows = 3;
    final totalSpan = _trackWidth + 16;
    final cols = (totalSpan / checkerSize).floor();
    final startX = -rows * checkerSize / 2;
    final startY = -totalSpan / 2;

    for (int r = 0; r < rows; r++) {
      for (int c = 0; c < cols; c++) {
        final isBlack = (r + c) % 2 == 0;
        canvas.drawRect(
          Rect.fromLTWH(
            startX + r * checkerSize,
            startY + c * checkerSize,
            checkerSize,
            checkerSize,
          ),
          Paint()..color = isBlack ? Colors.black : Colors.white,
        );
      }
    }

    canvas.restore();
  }

  @override
  bool shouldRepaint(covariant _GoalTrackPainter oldDelegate) => false;
}

Path _buildGoalTrackPath(Size size) {
  final w = size.width;
  final h = size.height;
  final m = _GoalTrackPainter._trackWidth + 14;

  final path = Path();
  path.moveTo(m, h - m);
  path.lineTo(w / 2, h - m);
  path.cubicTo(w - m, h - m, w - m, h * 0.6, w - m, h * 0.55);
  path.cubicTo(w - m, h * 0.4, m, h * 0.45, m, h * 0.35);
  path.cubicTo(m, h * 0.2, w * 0.35, m, w * 0.5, m);
  path.lineTo(w - m, m);
  return path;
}
