import 'package:flutter/material.dart';

import '../styles.dart';

/// Every powerups-enabled race earns a box every 2,000 steps. The creator used
/// to pick this (2k–25k chips on the create and edit screens); it is now a
/// fixed rule the app decides and the backend pins, so the chips are replaced
/// by this note.
const int kFixedPowerupStepInterval = 2000;

/// The inset strip that sits under the POWERUPS toggle and says, in plain
/// language, how far apart powerup boxes are.
///
/// Reads the number from the race rather than assuming 2,000: a race created
/// before the rule changed keeps its original spacing for its whole life, and
/// the note must tell the truth about that race (spec §7.2).
class PowerupIntervalNote extends StatelessWidget {
  const PowerupIntervalNote({
    super.key,
    required this.enabled,
    this.stepInterval = kFixedPowerupStepInterval,
  });

  /// Mirrors the POWERUPS toggle, so the note describes what the toggle does
  /// when it is off instead of leaving the card with an empty half.
  final bool enabled;

  /// Steps between boxes for this race. Defaults to the fixed 2,000.
  final int stepInterval;

  static String formatSteps(int steps) {
    final digits = steps.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < digits.length; i++) {
      if (i > 0 && (digits.length - i) % 3 == 0) buffer.write(',');
      buffer.write(digits[i]);
    }
    return buffer.toString();
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final steps = '${formatSteps(stepInterval)} steps';

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: colors.parchmentDark,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colors.parchmentBorder, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(Icons.inventory_2_outlined, size: 16, color: colors.textAccent),
          const SizedBox(width: 10),
          Expanded(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: enabled
                        ? "You'll earn a powerup box every "
                        : 'Turn powerups on to earn a box every ',
                  ),
                  TextSpan(
                    text: steps,
                    style: PixelText.body(
                      size: 12.5,
                      color: colors.textDark,
                    ).copyWith(fontWeight: FontWeight.w800),
                  ),
                  const TextSpan(text: '.'),
                ],
              ),
              style: PixelText.body(size: 12.5, color: colors.textMid),
            ),
          ),
        ],
      ),
    );
  }
}
