import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../styles.dart';

class GameToastPalette {
  const GameToastPalette({
    required this.label,
    required this.icon,
    required this.face,
    required this.dark,
    required this.shadow,
    required this.messageColor,
  });

  final String label;
  final IconData icon;
  final Color face;
  final Color dark;
  final Color shadow;
  final Color messageColor;
}

void showGameToast(
  BuildContext context,
  String message, {
  required Key shellKey,
  required Key badgeKey,
  required GameToastPalette palette,
  Duration duration = const Duration(seconds: 3),
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late final OverlayEntry entry;
  var removed = false;

  void removeEntry() {
    if (removed) return;
    removed = true;
    if (entry.mounted) {
      entry.remove();
    }
  }

  entry = OverlayEntry(
    builder: (context) => _GameToastOverlay(
      shellKey: shellKey,
      badgeKey: badgeKey,
      message: message,
      palette: palette,
      duration: duration,
      onDismissed: removeEntry,
    ),
  );

  overlay.insert(entry);
}

class _GameToastOverlay extends StatefulWidget {
  const _GameToastOverlay({
    required this.shellKey,
    required this.badgeKey,
    required this.message,
    required this.palette,
    required this.duration,
    required this.onDismissed,
  });

  final Key shellKey;
  final Key badgeKey;
  final String message;
  final GameToastPalette palette;
  final Duration duration;
  final VoidCallback onDismissed;

  @override
  State<_GameToastOverlay> createState() => _GameToastOverlayState();
}

class _GameToastOverlayState extends State<_GameToastOverlay>
    with SingleTickerProviderStateMixin {
  static const double _dismissDragThreshold = 48;
  static const double _dismissVelocityThreshold = -500;
  static const double _maxDragOffset = -96;

  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  Timer? _dismissTimer;
  bool _dismissed = false;
  bool _entranceStarted = false;
  double _dragOffset = 0;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 420),
      reverseDuration: const Duration(milliseconds: 200),
    );
    // Springy drop-in: overshoots the resting spot slightly, then settles.
    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, -1.2), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _controller,
            curve: Curves.easeOutBack,
            reverseCurve: Curves.easeInCubic,
          ),
        );
    _startDismissTimer();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_entranceStarted) return;
    _entranceStarted = true;
    if (MediaQuery.of(context).disableAnimations) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _dismissTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  Future<void> _dismiss() async {
    if (_dismissed || !mounted) return;
    _dismissed = true;
    _dismissTimer?.cancel();
    if (_controller.status != AnimationStatus.dismissed) {
      await _controller.reverse();
    }
    if (mounted) {
      widget.onDismissed();
    }
  }

  void _startDismissTimer() {
    _dismissTimer?.cancel();
    _dismissTimer = Timer(widget.duration, _dismiss);
  }

  void _handleVerticalDragUpdate(DragUpdateDetails details) {
    if (_dismissed) return;
    _dismissTimer?.cancel();
    setState(() {
      _dragOffset = (_dragOffset + details.delta.dy).clamp(_maxDragOffset, 0.0);
    });
  }

  Future<void> _handleVerticalDragEnd(DragEndDetails details) async {
    final velocity = details.primaryVelocity ?? 0;
    if (velocity <= _dismissVelocityThreshold ||
        _dragOffset <= -_dismissDragThreshold) {
      await _dismiss();
      return;
    }

    if (!mounted) return;
    setState(() {
      _dragOffset = 0;
    });
    _startDismissTimer();
  }

  void _handleVerticalDragCancel() {
    if (_dismissed || !mounted) return;
    setState(() {
      _dragOffset = 0;
    });
    _startDismissTimer();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 18,
      right: 18,
      top: MediaQuery.of(context).padding.top + 42,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onVerticalDragUpdate: _handleVerticalDragUpdate,
          onVerticalDragEnd: _handleVerticalDragEnd,
          onVerticalDragCancel: _handleVerticalDragCancel,
          onTap: _dismiss,
          child: AnimatedSlide(
            offset: Offset(0, _dragOffset / 120),
            duration: const Duration(milliseconds: 150),
            curve: Curves.easeOutCubic,
            child: Container(
              key: widget.shellKey,
              decoration: BoxDecoration(
                color: widget.palette.shadow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(
                  color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
                  width: 2,
                ),
                boxShadow: const [
                  BoxShadow(
                    color: Color(0x66000000),
                    offset: Offset(0, 4),
                    blurRadius: 0,
                  ),
                ],
              ),
              child: Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(11),
                  child: DecoratedBox(
                    decoration: BoxDecoration(
                      color: AppColors.of(context).parchment,
                      borderRadius: BorderRadius.circular(11),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(12, 10, 12, 11),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.center,
                        children: [
                          // A couple of decaying wiggles as the toast lands —
                          // driven by the entrance controller, so no extra
                          // timers and it renders static under
                          // disableAnimations (controller pinned at 1).
                          AnimatedBuilder(
                            animation: _controller,
                            builder: (context, child) {
                              final t = _controller.value;
                              final angle = t >= 1
                                  ? 0.0
                                  : math.sin(t * math.pi * 4) * 0.16 * (1 - t);
                              return Transform.rotate(
                                angle: angle,
                                child: child,
                              );
                            },
                            child: _ToastBadge(
                              key: widget.badgeKey,
                              palette: widget.palette,
                            ),
                          ),
                          const SizedBox(width: 11),
                          Expanded(
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  widget.palette.label,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: PixelText.pill(
                                    size: 11,
                                    color: widget.palette.dark,
                                  ).copyWith(decoration: TextDecoration.none),
                                ),
                                const SizedBox(height: 2),
                                Text(
                                  widget.message,
                                  maxLines: 3,
                                  overflow: TextOverflow.ellipsis,
                                  style:
                                      PixelText.body(
                                        size: 14.5,
                                        color: widget.palette.messageColor,
                                      ).copyWith(
                                        height: 1.18,
                                        decoration: TextDecoration.none,
                                      ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _ToastBadge extends StatelessWidget {
  const _ToastBadge({super.key, required this.palette});

  final GameToastPalette palette;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 34,
      height: 34,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.face, palette.dark],
        ),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: palette.shadow, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            offset: const Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Icon(palette.icon, size: 18, color: Colors.white),
    );
  }
}
