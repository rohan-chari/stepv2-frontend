import 'package:flutter/material.dart';

import '../content/whats_new.dart';
import '../styles.dart';
import 'pill_button.dart';
import 'trail_sign.dart';

/// The "What's New" sheet (batch 2026-08-08, item 8) — a wooden trail sign
/// pinned over the home tab on the first launch of a new build.
///
/// Deliberately a bottom sheet, not a full screen: this is an aside, and the
/// user must be one dismissal away from the app they opened.
class WhatsNewSheet extends StatelessWidget {
  const WhatsNewSheet({super.key, required this.entry});

  final WhatsNewEntry entry;

  /// Presents the sheet. Returns when it is dismissed (by button or scrim).
  static Future<void> show(BuildContext context, WhatsNewEntry entry) {
    return showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (ctx) => WhatsNewSheet(entry: entry),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return SafeArea(
      key: const Key('whats-new-sheet'),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.7,
          ),
          child: SingleChildScrollView(
            child: TrailSign(
              width: double.infinity,
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Text(
                    "WHAT'S NEW",
                    textAlign: TextAlign.center,
                    style: PixelText.title(size: 12, color: colors.textMid),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    entry.title,
                    textAlign: TextAlign.center,
                    style: PixelText.title(size: 20, color: colors.textDark),
                  ),
                  const SizedBox(height: 3),
                  Text(
                    'v${entry.version}',
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 11, color: colors.textMid),
                  ),
                  const SizedBox(height: 14),
                  for (final bullet in entry.bullets) ...[
                    Padding(
                      padding: const EdgeInsets.only(bottom: 9),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // A carved tick rather than a bullet dot — the app's
                          // lists are signposts, not prose.
                          Padding(
                            padding: const EdgeInsets.only(top: 2),
                            child: Icon(
                              Icons.check_box_outlined,
                              size: 14,
                              color: colors.textAccent,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              bullet,
                              style: PixelText.body(
                                size: 13,
                                color: colors.textDark,
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                  const SizedBox(height: 6),
                  PillButton(
                    key: const Key('whats-new-dismiss'),
                    label: 'LET’S GO',
                    variant: PillButtonVariant.primary,
                    fullWidth: true,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 12,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
