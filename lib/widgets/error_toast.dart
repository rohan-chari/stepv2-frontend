import 'package:flutter/material.dart';
import '../styles.dart';

/// Shows a red wooden bulletin board error toast that slides up from the bottom
/// and auto-dismisses after [duration].
void showErrorToast(BuildContext context, String message,
    {Duration duration = const Duration(seconds: 3)}) {
  final overlay = Overlay.of(context);
  late final OverlayEntry entry;

  final controller = AnimationController(
    vsync: overlay,
    duration: const Duration(milliseconds: 300),
    reverseDuration: const Duration(milliseconds: 250),
  );

  final slideAnimation = Tween<Offset>(
    begin: const Offset(0, -1),
    end: Offset.zero,
  ).animate(CurvedAnimation(parent: controller, curve: Curves.easeOut));

  entry = OverlayEntry(
    builder: (context) => _ErrorToastOverlay(
      message: message,
      slideAnimation: slideAnimation,
      onDismiss: () {
        controller.reverse().then((_) {
          entry.remove();
          controller.dispose();
        });
      },
    ),
  );

  overlay.insert(entry);
  controller.forward();

  Future.delayed(duration, () {
    if (entry.mounted) {
      controller.reverse().then((_) {
        if (entry.mounted) entry.remove();
        controller.dispose();
      });
    }
  });
}

class _ErrorToastOverlay extends StatelessWidget {
  final String message;
  final Animation<Offset> slideAnimation;
  final VoidCallback onDismiss;

  const _ErrorToastOverlay({
    required this.message,
    required this.slideAnimation,
    required this.onDismiss,
  });

  @override
  Widget build(BuildContext context) {
    const px = 2.5;

    return Positioned(
      left: 24,
      right: 24,
      top: MediaQuery.of(context).padding.top + 60,
      child: SlideTransition(
        position: slideAnimation,
        child: GestureDetector(
          onTap: onDismiss,
          child: Container(
            decoration: BoxDecoration(
              color: const Color(0xFF8B2020),
              border: Border.all(color: const Color(0xFF5C1010), width: px),
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Stack(
              children: [
                // Wood grain lines
                Positioned.fill(
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(2),
                    child: CustomPaint(
                      painter: _RedWoodGrainPainter(px: px),
                    ),
                  ),
                ),
                // Inner parchment area
                Padding(
                  padding: const EdgeInsets.all(px * 2.5),
                  child: Container(
                    width: double.infinity,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(0xFFFDE8E4),
                      border: Border.all(
                        color: const Color(0xFFD4A0A0),
                        width: px,
                      ),
                      borderRadius: BorderRadius.circular(2),
                    ),
                    child: Text(
                      message,
                      style: PixelText.body(
                        size: 14,
                        color: const Color(0xFF6B1A1A),
                      ),
                      textAlign: TextAlign.center,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RedWoodGrainPainter extends CustomPainter {
  final double px;
  _RedWoodGrainPainter({required this.px});

  @override
  void paint(Canvas canvas, Size size) {
    final grainPaint = Paint()
      ..color = const Color(0xFF701818).withValues(alpha: 0.3);
    final highlightPaint = Paint()
      ..color = const Color(0xFFAA4040).withValues(alpha: 0.2);

    for (double y = px * 3; y < size.height; y += px * 4) {
      canvas.drawRect(Rect.fromLTWH(0, y, size.width, px), grainPaint);
    }
    for (double y = px * 5; y < size.height; y += px * 7) {
      canvas.drawRect(
          Rect.fromLTWH(0, y, size.width, px * 0.5), highlightPaint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
