import 'package:flutter/material.dart';
import '../styles.dart';

enum PillButtonVariant {
  primary,
  secondary,
  rewardedAd,
  accent,
  decision,
  destructive,
}

class PillButton extends StatefulWidget {
  final String label;
  final VoidCallback? onPressed;
  final PillButtonVariant variant;
  final double fontSize;
  final EdgeInsets padding;
  final bool fullWidth;
  final IconData? icon;

  /// A custom leading widget, sized to the same box the [icon] occupies.
  /// Takes precedence over [icon] when both are given — how a price button
  /// swaps Material's dollar-sign glyph for the app's paw coin without every
  /// other call site changing.
  final Widget? leading;
  final Widget? trailing;

  /// Shows an in-place spinner instead of the label while this button's action
  /// is in flight (batch 2026-08-08, item 12).
  ///
  /// Implies disabled — a loading button must not fire twice. The label is
  /// kept in the tree at zero opacity so the button's WIDTH DOES NOT CHANGE
  /// when it starts spinning; a row of buttons resizing mid-tap is the exact
  /// jank this item exists to remove.
  final bool loading;

  /// The side/vertical padding a button carries unless the caller overrides it.
  static const defaultPadding = EdgeInsets.symmetric(
    horizontal: 32,
    vertical: 14,
  );

  /// A full-width button is already centred by its parent, so 32pt of side
  /// padding buys nothing and costs the label ~24pt of room.
  static const fullWidthPadding = EdgeInsets.symmetric(
    horizontal: 20,
    vertical: 14,
  );

  const PillButton({
    super.key,
    required this.label,
    required this.onPressed,
    this.variant = PillButtonVariant.primary,
    this.fontSize = 15,
    this.padding = defaultPadding,
    this.fullWidth = false,
    this.icon,
    this.leading,
    this.trailing,
    this.loading = false,
  });

  @override
  State<PillButton> createState() => _PillButtonState();
}

class _PillButtonState extends State<PillButton> {
  bool _pressed = false;

  bool get _enabled => widget.onPressed != null && !widget.loading;

  (Color, Color, Color) _colors() {
    switch (widget.variant) {
      case PillButtonVariant.primary:
        return (
          AppColors.of(context).pillGreen,
          AppColors.of(context).pillGreenDark,
          AppColors.of(context).pillGreenShadow,
        );
      case PillButtonVariant.secondary:
      case PillButtonVariant.rewardedAd:
        return (
          AppColors.of(context).pillGold,
          AppColors.of(context).pillGoldDark,
          AppColors.of(context).pillGoldShadow,
        );
      case PillButtonVariant.accent:
        return (
          AppColors.of(context).pillTerra,
          AppColors.of(context).pillTerraDark,
          AppColors.of(context).pillTerraShadow,
        );
      case PillButtonVariant.decision:
        return (
          AppColors.of(context).feedGold,
          AppColors.of(context).coinEdge,
          AppColors.of(context).woodDarker,
        );
      case PillButtonVariant.destructive:
        return (
          AppColors.of(context).error,
          AppColors.of(context).pillTerraDark,
          AppColors.of(context).woodDarker,
        );
    }
  }

  /// Full-width buttons trade the default 32pt side padding for 20pt. An
  /// explicit padding from the caller always wins.
  EdgeInsets get _effectivePadding =>
      widget.fullWidth && widget.padding == PillButton.defaultPadding
      ? PillButton.fullWidthPadding
      : widget.padding;

  /// A full-width button is as wide as it will ever be, so a label that
  /// doesn't fit has nowhere else to go — it used to silently ellipsize
  /// ("EXTRA SPIN" → "EXTRA SP…"), which is why the bug shipped. Scaling the
  /// whole row down keeps the word intact. Auto-width buttons size themselves
  /// to their label, so they never need it.
  Widget _fit(Widget row) => widget.fullWidth
      ? FittedBox(
          fit: BoxFit.scaleDown,
          alignment: Alignment.center,
          child: row,
        )
      : row;

  /// `maxLines: 1` + ellipsis stay on as the last-resort backstop for the
  /// auto-width case, where the label is still laid out under real
  /// constraints.
  Widget _label(Color textColor) {
    final text = Text(
      widget.label,
      textAlign: TextAlign.center,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: PixelText.pill(size: widget.fontSize, color: textColor),
    );
    return widget.fullWidth ? text : Flexible(child: text);
  }

  /// The button's inner row. While [PillButton.loading] the same row stays in
  /// the tree at zero opacity and the spinner is stacked over it, so the
  /// button keeps its exact resting width.
  Widget _content(Color textColor) {
    final row = Row(
      mainAxisSize: MainAxisSize.min,
      mainAxisAlignment: MainAxisAlignment.center,
      children: [
        if (widget.leading != null) ...[
          SizedBox(
            width: widget.fontSize + 2,
            height: widget.fontSize + 2,
            child: Center(child: widget.leading),
          ),
          const SizedBox(width: 8),
        ] else if (widget.icon != null) ...[
          Icon(widget.icon, size: widget.fontSize + 2, color: textColor),
          const SizedBox(width: 8),
        ],
        // Inside the FittedBox the Row is measured unconstrained, and a
        // flex child under unbounded width is an error — so the label is
        // laid out at its natural size there and scaled to fit instead.
        _label(textColor),
        if (widget.trailing != null) ...[
          const SizedBox(width: 8),
          widget.trailing!,
        ],
      ],
    );

    if (!widget.loading) return row;

    return Stack(
      alignment: Alignment.center,
      children: [
        // Width-preserving ghost. Excluded from semantics so a screen reader
        // announces "Loading", not the stale label.
        Opacity(opacity: 0, child: ExcludeSemantics(child: row)),
        Semantics(
          label: 'Loading',
          child: PillButtonSpinner(color: textColor, size: widget.fontSize + 2),
        ),
      ],
    );
  }

  @override
  Widget build(BuildContext context) {
    final (face, dark, shadow) = _colors();
    final disabledFace = face.withValues(alpha: 0.45);
    final disabledDark = dark.withValues(alpha: 0.45);

    final activeFace = _enabled ? face : disabledFace;
    final activeDark = _enabled ? dark : disabledDark;

    final bool darkText =
        widget.variant == PillButtonVariant.secondary ||
        widget.variant == PillButtonVariant.rewardedAd ||
        widget.variant == PillButtonVariant.decision;
    final textColor = _enabled
        ? (darkText ? AppColors.of(context).textDark : Colors.white)
        : (darkText
              ? AppColors.of(context).textDark.withValues(alpha: 0.5)
              : Colors.white.withValues(alpha: 0.7));

    final child = GestureDetector(
      onTapDown: _enabled ? (_) => setState(() => _pressed = true) : null,
      onTapUp: _enabled
          ? (_) {
              setState(() => _pressed = false);
              widget.onPressed!();
            }
          : null,
      onTapCancel: _enabled ? () => setState(() => _pressed = false) : null,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 60),
        transform: Matrix4.translationValues(0, _pressed ? 4 : 0, 0),
        decoration: BoxDecoration(
          borderRadius: BorderRadius.circular(8),
          color: activeFace,
          border: Border.all(color: activeDark, width: 2),
          // Straight-down hard shadow: the press animation drops the button
          // 4px onto it, so it reads as a physical underside — no diagonal
          // smear on textured backgrounds.
          boxShadow: _pressed
              ? []
              : [
                  BoxShadow(
                    color: shadow.withValues(alpha: _enabled ? 0.55 : 0.25),
                    offset: const Offset(0, 4),
                    blurRadius: 0,
                  ),
                ],
        ),
        padding: _effectivePadding,
        alignment: Alignment.center,
        child: _fit(_content(textColor)),
      ),
    );

    if (widget.fullWidth) {
      return SizedBox(width: double.infinity, child: child);
    }
    return child;
  }
}

/// Three marching pixel blocks — the in-button busy indicator.
///
/// Deliberately NOT a [CircularProgressIndicator]: the app's chrome is carved
/// pixel plaques and hard shadows, and a Material sweep reads as a foreign
/// object inside a wooden pill. Public so widget tests can assert "this button
/// is spinning" by type.
class PillButtonSpinner extends StatefulWidget {
  const PillButtonSpinner({super.key, required this.color, this.size = 16});

  final Color color;
  final double size;

  @override
  State<PillButtonSpinner> createState() => _PillButtonSpinnerState();
}

class _PillButtonSpinnerState extends State<PillButtonSpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  )..repeat();

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final block = (widget.size * 0.34).clamp(3.0, 7.0);
    // Reduce-motion: a static row of blocks still reads as "busy" and the
    // button is disabled anyway.
    if (MediaQuery.disableAnimationsOf(context)) {
      return _row(block, (_) => 0.75);
    }
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        return _row(block, (i) {
          // Each block peaks a third of a cycle after the previous one.
          final phase = (_controller.value - i * 0.22) % 1.0;
          final wave = phase < 0.5 ? phase * 2 : (1 - phase) * 2;
          return 0.35 + wave * 0.65;
        });
      },
    );
  }

  Widget _row(double block, double Function(int) opacityOf) {
    return SizedBox(
      height: widget.size,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          for (var i = 0; i < 3; i++) ...[
            if (i > 0) SizedBox(width: block * 0.5),
            Opacity(
              opacity: opacityOf(i).clamp(0.0, 1.0),
              child: Container(
                width: block,
                height: block,
                decoration: BoxDecoration(
                  color: widget.color,
                  borderRadius: BorderRadius.circular(1),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}
