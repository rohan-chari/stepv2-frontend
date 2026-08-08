import 'package:flutter/material.dart';

import '../styles.dart';

/// The step-multiplier chip that sits next to a racer's name.
///
/// Extracted from `LeaderboardPlank._multiplierChip` (batch 2026-08-08 item
/// 19) so the two-column TEAM scoreboard can render the same chip under the
/// same rules — team races were the one live surface where a buffed or frozen
/// racer looked identical to an untouched one.
///
/// Semantics of `currentMultiplier` (backend field, additive):
///  * `> 1`   buffed  → warm ember chip, "Nx"
///  * `== 1`  neutral → nothing
///  * `< 0.5` frozen  → frost chip (snowflake; the word is for screen readers)
///  * `<= 0`  reversed→ reversed chip, "Nx" of the absolute value
///
/// Suppression rules, identical on every surface:
///  * a **stealthed** racer never shows a chip (it would leak their state)
///  * an **absent/null** multiplier never shows a chip — an older backend
///    simply does not send the field, and a missing buff badge is the correct
///    degradation.
class MultiplierChip extends StatelessWidget {
  const MultiplierChip({
    super.key,
    required this.currentMultiplier,
    this.isStealthed = false,
  });

  final double? currentMultiplier;
  final bool isStealthed;

  /// Reads the field defensively off a participant row. Anything that is not
  /// a number reads as absent, so a retype on the backend cannot crash a
  /// frozen client.
  static double? multiplierOf(Map<String, dynamic> participant) {
    final raw = participant['currentMultiplier'];
    return raw is num ? raw.toDouble() : null;
  }

  /// Whether this multiplier renders anything at all. Callers use it to decide
  /// whether to reserve layout (a spacer) for the chip.
  static bool shouldShow(double? multiplier, {bool isStealthed = false}) {
    if (isStealthed || multiplier == null) return false;
    if (multiplier <= -0.001) return true;
    if (multiplier < 0.5) return true;
    if (multiplier > 1.001) return true;
    return false;
  }

  /// Returns the chip, or null when nothing should render. Convenience for
  /// call sites that build a children list conditionally.
  static Widget? maybe({
    required double? currentMultiplier,
    bool isStealthed = false,
  }) {
    if (!shouldShow(currentMultiplier, isStealthed: isStealthed)) return null;
    return MultiplierChip(
      currentMultiplier: currentMultiplier,
      isStealthed: isStealthed,
    );
  }

  static String _fmtMult(double v) {
    final rounded = v.roundToDouble();
    if ((v - rounded).abs() < 0.05) return rounded.toInt().toString();
    return v.toStringAsFixed(1);
  }

  @override
  Widget build(BuildContext context) {
    final m = currentMultiplier;
    if (!shouldShow(m, isStealthed: isStealthed)) {
      return const SizedBox.shrink();
    }

    if (m! <= -0.001) {
      // Reversed (e.g. Wrong Turn) — steps counting backward.
      return _chip(
        context,
        icon: Icons.u_turn_left_rounded,
        label: '${_fmtMult(m.abs())}x',
        bg: AppColors.of(context).feedAttack,
      );
    }
    if (m < 0.5) {
      // Frozen (e.g. Leg Cramp) — the snowflake is enough visually; retain
      // the word for screen readers.
      return _chip(
        context,
        icon: Icons.ac_unit_rounded,
        semanticsLabel: 'Frozen',
        bg: AppColors.of(context).feedShield,
      );
    }
    // Buffed — warm ember chip, number only (no flame). `pillTerra` is the
    // palette's ember, and it flips correctly for the night board.
    return _chip(
      context,
      label: '${_fmtMult(m)}x',
      bg: AppColors.of(context).pillTerra,
    );
  }

  Widget _chip(
    BuildContext context, {
    IconData? icon,
    String? label,
    String? semanticsLabel,
    required Color bg,
  }) {
    final iconOnly = icon != null && label == null;
    final chip = Container(
      padding: EdgeInsets.symmetric(
        horizontal: iconOnly ? 5 : 6,
        vertical: iconOnly ? 4 : 3,
      ),
      decoration: BoxDecoration(
        color: bg.withValues(alpha: 0.16),
        borderRadius: BorderRadius.circular(7),
        border: Border.all(color: bg.withValues(alpha: 0.85), width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: iconOnly ? 13 : 11, color: bg),
            if (label != null) const SizedBox(width: 3),
          ],
          if (label != null)
            Text(label, style: PixelText.title(size: 10, color: bg)),
        ],
      ),
    );
    if (semanticsLabel == null) return chip;
    return Semantics(
      label: semanticsLabel,
      child: ExcludeSemantics(child: chip),
    );
  }
}
