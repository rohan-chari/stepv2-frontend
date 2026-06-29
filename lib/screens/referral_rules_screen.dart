import 'package:flutter/material.dart';

import '../styles.dart';

/// Official referral-program rules. Google Play expects a reward program to
/// publish its terms in-app (eligibility, the qualifying action, caps, and the
/// no-incentivized-review/install clauses); this screen is that disclosure. It's
/// static copy — reachable from the referral screen — and intentionally states
/// the program's shape without hardcoding tunable coin amounts (those are shown
/// live on the referral/welcome surfaces), so it can't drift from config.
class ReferralRulesScreen extends StatelessWidget {
  const ReferralRulesScreen({super.key});

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const _sections = <(String, String)>[
    (
      'How it works',
      'Share your personal invite link with a friend who is new to Bara. When '
          'they install Bara, sign in, and finish their first qualifying race, '
          'you both earn coins.',
    ),
    (
      "What's a qualifying race",
      'A qualifying race is a genuine, completed race — either an official '
          'daily/weekly challenge, or a race with at least two real participants '
          'who actually logged steps. A solo race you create for yourself does '
          'not qualify. Coins are awarded by Bara’s servers after the race '
          'settles; finishing is required, not just joining.',
    ),
    (
      'Who can be referred',
      'Only people new to Bara. Each person can be referred once, ever — '
          'reinstalling or making a new account does not reset this. You cannot '
          'refer yourself, and review/demo accounts are excluded.',
    ),
    (
      'When you get paid',
      'The reward lands automatically once your friend completes their first '
          'qualifying race, within the eligibility window after they sign up. '
          'You’ll get a notification and your coin balance updates.',
    ),
    (
      'Limits & fair use',
      'There are caps on how many referral rewards can be earned in a day and '
          'in a month. Unusual activity (e.g. rings of low-engagement accounts) '
          'may be held for review, and rewards from abuse may be withheld or '
          'reversed.',
    ),
    (
      'No incentivized installs or reviews',
      'Rewards are for a real in-app action — finishing a race — never for '
          'simply installing the app, signing up, or leaving a rating or review.',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.parchment,
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DecoratedBox(
            decoration: const BoxDecoration(
              color: AppColors.roofLight,
              border: Border(
                bottom: BorderSide(color: AppColors.roofDark, width: 1),
              ),
            ),
            child: CustomPaint(
              painter: const ArcadeCheckerPainter(drawBottomStripe: false),
              child: Padding(
                padding: EdgeInsets.fromLTRB(16, topInset + 8, 16, 14),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Align(
                      alignment: Alignment.centerLeft,
                      child: IconButton(
                        padding: EdgeInsets.zero,
                        constraints: const BoxConstraints(),
                        icon: const Icon(
                          Icons.arrow_back,
                          color: AppColors.parchment,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      'PROGRAM RULES',
                      style: PixelText.title(
                        size: 26,
                        color: AppColors.parchment,
                      ).copyWith(shadows: _textShadows),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Expanded(
            child: ListView(
              padding: const EdgeInsets.fromLTRB(20, 18, 20, 40),
              children: [
                for (final (title, body) in _sections) ...[
                  Text(
                    title,
                    style: PixelText.title(size: 16, color: AppColors.textDark),
                  ),
                  const SizedBox(height: 6),
                  Text(
                    body,
                    style: PixelText.body(
                      size: 14,
                      color: AppColors.textMid,
                    ).copyWith(height: 1.4),
                  ),
                  const SizedBox(height: 18),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
