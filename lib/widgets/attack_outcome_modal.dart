import 'dart:ui';

import 'package:flutter/material.dart';

import '../styles.dart';
import 'game_container.dart';
import 'home_chrome.dart';
import 'pill_button.dart';
import 'powerup_icon.dart';
import '../constants/powerup_copy.dart';

/// How an offensive powerup landed on the target, from the use-powerup result.
enum AttackOutcome { applied, blocked, reflected }

/// Friendly display names for the powerups that can intercept an attack.

/// Classifies a use-powerup result DEFENSIVELY.
///
/// Prefers the additive `outcome` discriminator, but falls back to the legacy
/// `blocked` / `reflected` boolean flags so that a response from an older
/// backend (which has no `outcome`) still surfaces the right modal. Never throws
/// on missing/null fields.
AttackOutcome attackOutcomeFromResult(Map<String, dynamic>? result) {
  if (result == null) return AttackOutcome.applied;

  final outcome = result['outcome'];
  if (outcome is String) {
    switch (outcome.toUpperCase()) {
      case 'BLOCKED':
        return AttackOutcome.blocked;
      case 'REFLECTED':
        return AttackOutcome.reflected;
      case 'APPLIED':
        return AttackOutcome.applied;
    }
  }

  // Legacy / older-backend fallback: no (recognized) outcome discriminator.
  if (result['reflected'] == true) return AttackOutcome.reflected;
  if (result['blocked'] == true) return AttackOutcome.blocked;

  return AttackOutcome.applied;
}

/// A reveal-style modal — styled like the mystery-box UNBOX reveal card
/// ([CaseOpeningScreen]) — shown on the attacker's client when their offensive
/// powerup is intercepted (blocked by Compression Socks, or reflected by a
/// Mirror).
///
/// Self-contained and testable: it takes the raw use-powerup result map and an
/// [onDismiss] callback, so it can be exercised without a Navigator.
class AttackOutcomeModal extends StatelessWidget {
  const AttackOutcomeModal({
    super.key,
    required this.result,
    required this.onDismiss,
  });

  /// The raw use-powerup result (the inner `result` object).
  final Map<String, dynamic> result;

  /// Called when the user dismisses the modal.
  final VoidCallback onDismiss;

  bool get _isReflected =>
      attackOutcomeFromResult(result) == AttackOutcome.reflected;

  String get _interceptorType {
    if (_isReflected) {
      final by = result['reflectedBy'];
      return by is String && by.isNotEmpty ? by : 'MIRROR';
    }
    final by = result['blockedBy'];
    return by is String && by.isNotEmpty ? by : 'COMPRESSION_SOCKS';
  }

  String get _title => _isReflected ? 'REFLECTED!' : 'BLOCKED!';

  String get _subtitle => _isReflected
      ? 'Your attack was reflected back at you'
      : 'Your attack was blocked';

  @override
  Widget build(BuildContext context) {
    final interceptorType = _interceptorType;
    final interceptorName = PowerupCopy.nameFor(interceptorType);
    final accent = _isReflected
        ? AppColors.of(context).coinDark
        : AppColors.of(context).error;

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
              _title,
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
                child: PowerupIcon(
                  type: interceptorType,
                  size: 82,
                  spinning: true,
                ),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              interceptorName,
              style: PixelText.title(
                size: 24,
                color: AppColors.of(context).textDark,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 8),
            Text(
              _subtitle,
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

/// Presents [AttackOutcomeModal] as a blurred, full-screen reveal overlay,
/// matching the mystery-box case-opening presentation.
Future<void> showAttackOutcomeModal(
  BuildContext context,
  Map<String, dynamic> result,
) {
  return showGeneralDialog(
    context: context,
    barrierDismissible: true,
    barrierLabel: 'Attack outcome',
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
                    child: AttackOutcomeModal(
                      result: result,
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
