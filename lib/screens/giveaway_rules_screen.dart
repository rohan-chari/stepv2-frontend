import 'package:flutter/material.dart';

import '../models/giveaway.dart';
import '../styles.dart';

/// Immutable in-app copy of the exact server-owned rules accepted by an
/// entrant. It intentionally never opens a browser: App Store and Play users
/// can always read the controlling terms inside the carrying binary.
class GiveawayRulesScreen extends StatelessWidget {
  const GiveawayRulesScreen({super.key, required this.contest});

  final GiveawayContest contest;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Scaffold(
      backgroundColor: colors.roofLight,
      body: SafeArea(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DecoratedBox(
              decoration: BoxDecoration(color: colors.roofLight),
              child: CustomPaint(
                painter: const ArcadeCheckerPainter(drawBottomStripe: false),
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(8, 6, 16, 14),
                  child: Row(
                    children: [
                      IconButton(
                        tooltip: 'Back',
                        onPressed: () => Navigator.of(context).pop(),
                        icon: Icon(Icons.arrow_back, color: colors.textLight),
                      ),
                      Expanded(
                        child: Text(
                          'OFFICIAL RULES',
                          style: PixelText.title(
                            size: 22,
                            color: colors.textLight,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            Expanded(
              child: ListView(
                padding: const EdgeInsets.fromLTRB(16, 16, 16, 36),
                children: [
                  _RulesCard(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          contest.title,
                          style: PixelText.title(
                            size: 20,
                            color: colors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Rules version ${contest.rules.version}',
                          style: PixelText.body(
                            size: 12,
                            color: colors.textMid,
                          ),
                        ),
                        const SizedBox(height: 10),
                        Text(
                          contest.eligibilityMode ==
                                  GiveawayEligibilityMode.baraAccount
                              ? contest.eligibilitySummary
                              : 'Open to legal residents of the 50 United States and D.C., age ${contest.minimumAge ?? 18}+. No purchase necessary.',
                          style: PixelText.body(
                            size: 14,
                            color: colors.textDark,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Contest window (UTC): ${_instant(contest.startsAt)} through ${_instant(contest.endsAt)}. Governing timezone: ${contest.governingTimeZone}.',
                          style: PixelText.body(
                            size: 13,
                            color: colors.textMid,
                          ),
                        ),
                        const SizedBox(height: 12),
                        Text(
                          'SPONSOR',
                          style: PixelText.title(
                            size: 13,
                            color: colors.textDark,
                          ),
                        ),
                        const SizedBox(height: 4),
                        SelectableText(
                          contest.sponsorName,
                          style: PixelText.body(
                            size: 13,
                            color: colors.textDark,
                          ),
                        ),
                        if (contest.sponsorMailingAddress case final address?)
                          SelectableText(
                            address,
                            style: PixelText.body(
                              size: 13,
                              color: colors.textMid,
                            ),
                          ),
                      ],
                    ),
                  ),
                  for (final section in contest.rules.sections) ...[
                    const SizedBox(height: 14),
                    _RulesCard(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            section.heading,
                            style: PixelText.title(
                              size: 16,
                              color: colors.textDark,
                            ),
                          ),
                          const SizedBox(height: 8),
                          SelectableText(
                            section.body,
                            style: PixelText.body(
                              size: 14,
                              color: colors.textDark,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 14),
                  _RulesCard(
                    child: Text(
                      'Apple and Google are not sponsors, administrators, endorsers, or otherwise involved in this promotion.',
                      style: PixelText.body(size: 13, color: colors.textDark),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _instant(DateTime value) => value.toUtc().toIso8601String();
}

class _RulesCard extends StatelessWidget {
  const _RulesCard({required this.child});
  final Widget child;

  @override
  Widget build(BuildContext context) => DecoratedBox(
    decoration: BoxDecoration(
      color: AppColors.of(context).parchment,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppColors.of(context).parchmentBorder,
        width: 2,
      ),
      boxShadow: const [
        BoxShadow(
          color: Color(0x66000000),
          offset: Offset(0, 4),
          blurRadius: 0,
        ),
      ],
    ),
    child: Padding(padding: const EdgeInsets.all(16), child: child),
  );
}
