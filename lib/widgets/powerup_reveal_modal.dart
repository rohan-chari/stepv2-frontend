import 'dart:ui';

import 'package:flutter/material.dart';

import '../constants/powerup_copy.dart';
import '../styles.dart';
import 'game_container.dart';
import 'home_chrome.dart';
import 'pill_button.dart';
import 'powerup_icon.dart';

/// §7 powerups5 — the gamble/surprise reveal shown on the caster's own client
/// after a Coin Flip or Mystery Potion resolves.
///
/// Both outcomes are SERVER-rolled and ride back on the use-powerup response.
/// Every field is read defensively: an older backend that consumed the item but
/// returned no roll leaves the classifier `null`, and the race screen falls
/// back to the generic "activated" toast rather than showing a blank reveal.

/// A resolved Coin Flip, or `null` when the response carried no `flip` field.
class CoinFlipReveal {
  const CoinFlipReveal({required this.won});

  final bool won;

  /// Parses `{ "flip": "WIN" | "LOSE" }`. Returns `null` for a missing/unknown
  /// value so the caller can degrade to the generic toast.
  static CoinFlipReveal? fromResult(Map<String, dynamic>? result) {
    final flip = result?['flip'];
    if (flip is! String) return null;
    switch (flip.toUpperCase()) {
      case 'WIN':
        return const CoinFlipReveal(won: true);
      case 'LOSE':
        return const CoinFlipReveal(won: false);
    }
    return null;
  }
}

/// A resolved Mystery Potion, or `null` when the response carried no `rolled`
/// field.
class MysteryPotionReveal {
  const MysteryPotionReveal({required this.rolled, this.coins});

  /// The rolled outcome: an existing powerup TYPE string, or `COIN_REFUND`.
  final String rolled;

  /// Present only for the `COIN_REFUND` outcome.
  final int? coins;

  bool get isCoinRefund => rolled.toUpperCase() == 'COIN_REFUND';

  static MysteryPotionReveal? fromResult(Map<String, dynamic>? result) {
    final rolled = result?['rolled'];
    if (rolled is! String || rolled.trim().isEmpty) return null;
    final rawCoins = result?['coins'];
    final coins = rawCoins is num ? rawCoins.toInt() : null;
    return MysteryPotionReveal(rolled: rolled.trim(), coins: coins);
  }

  /// The icon type to spin in the reveal card — the rolled powerup's own icon,
  /// falling back to the potion itself for the coin refund.
  String get iconType => isCoinRefund ? 'MYSTERY_POTION' : rolled;

  /// Human phrase describing what the potion produced.
  String subtitle() {
    if (isCoinRefund) {
      final amount = coins;
      return amount != null
          ? 'The potion paid out $amount coins!'
          : 'The potion refunded your coins!';
    }
    return 'The potion brewed up a ${PowerupCopy.nameFor(rolled)}!';
  }
}

/// A reveal card styled like the mystery-box UNBOX reveal / attack-outcome
/// modal. Self-contained and testable: it takes plain strings + an icon type.
class PowerupRevealModal extends StatelessWidget {
  const PowerupRevealModal({
    super.key,
    required this.iconType,
    required this.title,
    required this.subtitle,
    required this.accent,
    required this.onDismiss,
  });

  final String iconType;
  final String title;
  final String subtitle;
  final Color accent;
  final VoidCallback onDismiss;

  @override
  Widget build(BuildContext context) {
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: GameContainer(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        frameColor: accent,
        surfaceColor: AppColors.of(context).parchmentLight,
        glowColor: accent,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              title,
              textAlign: TextAlign.center,
              style: HomeText.display(
                size: 32,
                color: AppColors.of(context).ink,
              ),
            ),
            const SizedBox(height: 14),
            Center(
              child: Container(
                width: 112,
                height: 112,
                decoration: BoxDecoration(
                  color: AppColors.of(context).parchmentDark,
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(color: accent, width: 2),
                ),
                alignment: Alignment.center,
                child: PowerupIcon(type: iconType, size: 82, spinning: true),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              subtitle,
              style: PixelText.body(
                size: 14,
                color: AppColors.of(context).textMid,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 22),
            PillButton(
              label: 'Continue',
              icon: Icons.check_rounded,
              onPressed: onDismiss,
              fullWidth: true,
            ),
          ],
        ),
      ),
    );
  }
}

/// Presents [PowerupRevealModal] as a blurred full-screen reveal overlay,
/// matching [showAttackOutcomeModal].
Future<void> showPowerupRevealModal(
  BuildContext context, {
  required String iconType,
  required String title,
  required String subtitle,
  Color? accent,
}) {
  final resolvedAccent = accent ?? AppColors.of(context).accent;
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Powerup reveal',
    barrierColor: Colors.transparent,
    transitionDuration: const Duration(milliseconds: 280),
    pageBuilder: (dialogContext, _, _) {
      return Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                child: ColoredBox(
                  color: AppColors.of(context).roofDark.withValues(alpha: 0.54),
                ),
              ),
            ),
            SafeArea(
              child: Center(
                child: SingleChildScrollView(
                  padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 460),
                    child: PowerupRevealModal(
                      iconType: iconType,
                      title: title,
                      subtitle: subtitle,
                      accent: resolvedAccent,
                      onDismiss: () => Navigator.of(dialogContext).pop(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      );
    },
    transitionBuilder: (_, anim, _, child) =>
        FadeTransition(opacity: anim, child: child),
  );
}
