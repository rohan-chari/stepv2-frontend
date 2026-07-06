import 'package:flutter/material.dart';
import 'package:in_app_review/in_app_review.dart';
import 'package:shared_preferences/shared_preferences.dart';

import '../styles.dart';
import '../widgets/game_container.dart';
import '../widgets/home_chrome.dart';
import '../widgets/pill_button.dart';

/// Shows an "Enjoying Bara?" sentiment gate at happy moments (top-3 race
/// finishes) and, on a positive answer, requests the NATIVE store review
/// sheet. Never attaches any reward: both App Store and Play policy forbid
/// compensated reviews, and the native sheet gives no callback to verify one
/// anyway (iOS also silently rate-limits it to ~3 shows/year).
///
/// Anti-spam guards, persisted across launches:
/// - warm-up: no ask until the 2nd qualifying moment AND 3 days after this
///   install was first seen
/// - answered either way (yes or "not really") -> never ask again
/// - dismissed without answering -> 60-day cooldown, 3 asks lifetime max
/// - at most one ask per app session
class ReviewPromptService {
  ReviewPromptService({
    Future<void> Function()? requestNativeReview,
    DateTime Function()? clock,
  }) : _requestNativeReview = requestNativeReview ?? _defaultRequestReview,
       _clock = clock ?? DateTime.now;

  static const _keyFirstSeenMs = 'review_prompt_first_seen_ms';
  static const _keyHappyMoments = 'review_prompt_happy_moments';
  static const _keyAskCount = 'review_prompt_ask_count';
  static const _keyLastAskMs = 'review_prompt_last_ask_ms';
  static const _keyAnswered = 'review_prompt_answered';

  static const _minHappyMoments = 2;
  static const _minDaysBeforeFirstAsk = 3;
  static const _cooldownDays = 60;
  static const _maxLifetimeAsks = 3;

  final Future<void> Function() _requestNativeReview;
  final DateTime Function() _clock;
  bool _askedThisSession = false;

  static Future<void> _defaultRequestReview() async {
    final inAppReview = InAppReview.instance;
    if (await inAppReview.isAvailable()) {
      await inAppReview.requestReview();
    }
  }

  /// Records one qualifying happy moment and, if every guard passes, shows the
  /// sentiment dialog over [context]. Call this only when nothing else is
  /// about to be pushed on top (e.g. right after a results modal pops).
  Future<void> recordHappyMomentAndMaybePrompt(BuildContext context) async {
    final prefs = await SharedPreferences.getInstance();
    final now = _clock().millisecondsSinceEpoch;

    final firstSeen = prefs.getInt(_keyFirstSeenMs) ?? now;
    if (!prefs.containsKey(_keyFirstSeenMs)) {
      await prefs.setInt(_keyFirstSeenMs, now);
    }
    final happyMoments = (prefs.getInt(_keyHappyMoments) ?? 0) + 1;
    await prefs.setInt(_keyHappyMoments, happyMoments);

    if (_askedThisSession) return;
    if (prefs.getBool(_keyAnswered) ?? false) return;
    if (happyMoments < _minHappyMoments) return;
    if (now - firstSeen < _minDaysBeforeFirstAsk * Duration.millisecondsPerDay) {
      return;
    }
    final askCount = prefs.getInt(_keyAskCount) ?? 0;
    if (askCount >= _maxLifetimeAsks) return;
    final lastAsk = prefs.getInt(_keyLastAskMs) ?? 0;
    if (now - lastAsk < _cooldownDays * Duration.millisecondsPerDay) return;

    if (!context.mounted) return;

    _askedThisSession = true;
    await prefs.setInt(_keyAskCount, askCount + 1);
    await prefs.setInt(_keyLastAskMs, now);

    if (!context.mounted) return;
    final enjoying = await showDialog<bool>(
      context: context,
      builder: (_) => const _EnjoyingBaraDialog(),
    );

    // Tap-outside dismiss (null): leave only the cooldown ticking.
    if (enjoying == null) return;

    await prefs.setBool(_keyAnswered, true);
    if (enjoying) {
      await _requestNativeReview();
    } else if (context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Thanks for the feedback!')),
      );
    }
  }
}

class _EnjoyingBaraDialog extends StatelessWidget {
  const _EnjoyingBaraDialog();

  @override
  Widget build(BuildContext context) {
    return Dialog(
      backgroundColor: Colors.transparent,
      insetPadding: const EdgeInsets.symmetric(horizontal: 24),
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 380),
        child: GameContainer(
          padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
          frameColor: AppColors.accent,
          surfaceColor: AppColors.parchmentLight,
          glowColor: AppColors.coinMid,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'ENJOYING BARA?',
                textAlign: TextAlign.center,
                style: HomeText.display(size: 24, color: HomeColors.ink),
              ),
              const SizedBox(height: 6),
              Text(
                'A quick rating helps other racers find us.',
                textAlign: TextAlign.center,
                style: HomeText.body(
                  size: 13,
                  color: HomeColors.muted,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 16),
              PillButton(
                label: 'YES!',
                variant: PillButtonVariant.primary,
                fullWidth: true,
                onPressed: () => Navigator.of(context).pop(true),
              ),
              const SizedBox(height: 8),
              PillButton(
                label: 'NOT REALLY',
                variant: PillButtonVariant.secondary,
                fullWidth: true,
                onPressed: () => Navigator.of(context).pop(false),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
