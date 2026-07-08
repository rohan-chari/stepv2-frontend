import 'package:flutter/material.dart';
import '../styles.dart';

/// Game-themed replacement for CupertinoSwitch: chunky bordered track with a
/// hard offset shadow (same language as [PillButton]), a square sliding thumb,
/// and a tiny ON/OFF label on the vacant side of the track.
class PixelSwitch extends StatelessWidget {
  final bool value;
  final ValueChanged<bool>? onChanged;

  const PixelSwitch({super.key, required this.value, required this.onChanged});

  bool get _enabled => onChanged != null;

  @override
  Widget build(BuildContext context) {
    final trackFace = value ? AppColors.pillGreen : AppColors.parchmentDark;
    final trackDark = value ? AppColors.pillGreenDark : AppColors.parchmentBorder;
    final labelColor = value ? Colors.white : AppColors.textMid;

    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _enabled ? () => onChanged!(!value) : null,
      child: Opacity(
        opacity: _enabled ? 1 : 0.45,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 140),
          curve: Curves.easeOut,
          width: 58,
          height: 30,
          padding: const EdgeInsets.all(3),
          decoration: BoxDecoration(
            color: trackFace,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: trackDark, width: 2),
            boxShadow: [
              BoxShadow(
                color: trackDark.withValues(alpha: 0.24),
                offset: const Offset(2, 2),
                blurRadius: 0,
              ),
            ],
          ),
          child: Stack(
            children: [
              AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                alignment: value
                    ? Alignment.centerLeft
                    : Alignment.centerRight,
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Text(
                    value ? 'ON' : 'OFF',
                    style: PixelText.pill(size: 8, color: labelColor),
                  ),
                ),
              ),
              AnimatedAlign(
                duration: const Duration(milliseconds: 140),
                curve: Curves.easeOut,
                alignment: value
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    color: AppColors.parchmentLight,
                    borderRadius: BorderRadius.circular(5),
                    border: Border.all(color: trackDark, width: 2),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
