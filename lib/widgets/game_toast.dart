import 'dart:async';

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
  final overlay = Overlay.of(context);
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
  late final AnimationController _controller;
  late final Animation<Offset> _slideAnimation;
  Timer? _dismissTimer;
  bool _dismissed = false;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 260),
      reverseDuration: const Duration(milliseconds: 220),
    );
    _slideAnimation = Tween<Offset>(
      begin: const Offset(0, -1),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(parent: _controller, curve: Curves.easeOutCubic),
    );
    _controller.forward();
    _dismissTimer = Timer(widget.duration, _dismiss);
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

  @override
  Widget build(BuildContext context) {
    return Positioned(
      left: 24,
      right: 24,
      top: MediaQuery.of(context).padding.top + 56,
      child: SlideTransition(
        position: _slideAnimation,
        child: GestureDetector(
          onTap: _dismiss,
          child: Container(
            key: widget.shellKey,
            decoration: BoxDecoration(
              color: AppColors.woodDark,
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: AppColors.woodShadow, width: 2.5),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.26),
                  blurRadius: 10,
                  offset: const Offset(0, 4),
                ),
                BoxShadow(
                  color: widget.palette.face.withValues(alpha: 0.20),
                  blurRadius: 12,
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(6),
              child: SizedBox(
                width: double.infinity,
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Container(
                    width: double.infinity,
                    decoration: BoxDecoration(
                      gradient: LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [widget.palette.face, widget.palette.dark],
                      ),
                      border: Border.all(
                        color: widget.palette.shadow,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Padding(
                      padding: const EdgeInsets.all(3),
                      child: Container(
                        width: double.infinity,
                        decoration: BoxDecoration(
                          color: AppColors.parchmentLight,
                          borderRadius: BorderRadius.circular(5),
                        ),
                        child: Padding(
                          padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            crossAxisAlignment: CrossAxisAlignment.center,
                            children: [
                              _ToastBadge(
                                key: widget.badgeKey,
                                palette: widget.palette,
                              ),
                              const SizedBox(height: 10),
                              SizedBox(
                                width: double.infinity,
                                child: Text(
                                  widget.message,
                                  style: PixelText.body(
                                    size: 14,
                                    color: widget.palette.messageColor,
                                  ),
                                  textAlign: TextAlign.center,
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
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [palette.face, palette.dark],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: palette.shadow, width: 1.5),
        boxShadow: [
          BoxShadow(
            color: palette.shadow,
            offset: const Offset(0, 2),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(palette.icon, size: 14, color: Colors.white),
          const SizedBox(width: 6),
          Text(
            palette.label,
            style: PixelText.pill(size: 11, color: Colors.white),
          ),
        ],
      ),
    );
  }
}
