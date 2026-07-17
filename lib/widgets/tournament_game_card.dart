import 'package:flutter/material.dart';

import '../styles.dart';
import 'arcade_fx.dart';
import 'pill_button.dart';
import 'race_ui.dart';
import 'spinning_coin.dart';

/// The shared "game-piece" card for a tournament, used on BOTH the races-tab
/// featured row and the Public Races screen so the two surfaces are visually
/// indistinguishable in polish from [FeaturedRaceCard]. Same card treatment
/// (`raceCardDecoration`), the "BRACKET" [Pill] marker, `PixelText.title`
/// name, `PixelText.body` meta, and a `coinDark` prize/pot value.
///
/// Callers pass pre-formatted display strings (name casing, labels) so each
/// surface keeps its own conventions while sharing one layout + style.
class TournamentGameCard extends StatelessWidget {
  const TournamentGameCard({
    super.key,
    required this.name,
    required this.metaLine,
    required this.filledLabel,
    required this.prizeLabel,
    required this.prizeValue,
    required this.ctaLabel,
    required this.ctaVariant,
    required this.onPressed,
    this.ctaGlow = false,
    this.ctaKey,
    this.width,
  });

  /// Display name (caller controls casing).
  final String name;

  /// e.g. "4 RACERS · 1-DAY KNOCKOUTS".
  final String metaLine;

  /// e.g. "3/4 IN".
  final String filledLabel;

  /// e.g. "CHAMPION WINS" / "WINNER TAKES"; the prize row is hidden when
  /// [prizeValue] is 0.
  final String prizeLabel;
  final int prizeValue;

  final String ctaLabel;
  final PillButtonVariant ctaVariant;
  final VoidCallback? onPressed;

  /// Wraps the CTA in the arcade [PulseGlow] (used for the one actionable JOIN).
  final bool ctaGlow;
  final Key? ctaKey;

  /// Fixed width for the horizontal featured row; null = fill the parent (the
  /// full-width Public Races list).
  final double? width;

  @override
  Widget build(BuildContext context) {
    final card = Container(
      decoration: raceCardDecoration(),
      padding: const EdgeInsets.all(14),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.center,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Pill(
                label: 'BRACKET',
                background: AppColors.pillGold,
                fontSize: 11,
              ),
              const SizedBox(height: 8),
              Text(
                name,
                textAlign: TextAlign.center,
                style: PixelText.title(size: 17, color: AppColors.textDark),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 10),
              if (prizeValue > 0)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const SpinningCoin(size: 15),
                    const SizedBox(width: 5),
                    Flexible(
                      child: Text(
                        prizeLabel,
                        textAlign: TextAlign.center,
                        style: PixelText.body(size: 11, color: AppColors.textMid),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                    const SizedBox(width: 6),
                    Text(
                      '$prizeValue',
                      style: PixelText.title(size: 15, color: AppColors.coinDark),
                    ),
                  ],
                ),
              const SizedBox(height: 6),
              Text(
                metaLine,
                textAlign: TextAlign.center,
                style: PixelText.body(size: 11.5, color: AppColors.textMid),
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: 2),
              Text(
                filledLabel,
                textAlign: TextAlign.center,
                style: PixelText.body(size: 12, color: AppColors.textMid),
              ),
            ],
          ),
          Padding(padding: const EdgeInsets.only(top: 12), child: _cta()),
        ],
      ),
    );

    if (width == null) return card;
    return SizedBox(width: width, child: card);
  }

  Widget _cta() {
    final button = PillButton(
      key: ctaKey,
      label: ctaLabel,
      variant: ctaVariant,
      fontSize: 13,
      fullWidth: true,
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 11),
      onPressed: onPressed,
    );
    return ctaGlow ? PulseGlow(child: button) : button;
  }
}
