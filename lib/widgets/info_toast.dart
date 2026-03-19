import 'package:flutter/material.dart';

import '../styles.dart';

/// Shows a floating bulletin-board style info toast that slides down from the top
/// and auto-dismisses after [duration].
void showInfoToast(
  BuildContext context,
  String message, {
  Duration duration = const Duration(seconds: 3),
}) {
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
    builder: (context) => _InfoToastOverlay(
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

class _InfoToastOverlay extends StatelessWidget {
  final String message;
  final Animation<Offset> slideAnimation;
  final VoidCallback onDismiss;

  const _InfoToastOverlay({
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
              color: AppColors.woodDark,
              border: Border.all(color: AppColors.woodShadow, width: px),
              borderRadius: BorderRadius.circular(4),
              boxShadow: const [
                BoxShadow(
                  color: Colors.black38,
                  blurRadius: 8,
                  offset: Offset(0, 4),
                ),
              ],
            ),
            child: Padding(
              padding: const EdgeInsets.all(px * 2.5),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
                decoration: BoxDecoration(
                  color: AppColors.parchmentLight,
                  border: Border.all(
                    color: AppColors.parchmentBorder,
                    width: px,
                  ),
                  borderRadius: BorderRadius.circular(2),
                ),
                child: Text(
                  message,
                  style: PixelText.body(size: 14, color: AppColors.textDark),
                  textAlign: TextAlign.center,
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
