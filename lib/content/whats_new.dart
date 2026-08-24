/// Bundled changelog shown in the "What's New" sheet (feature batch
/// 2026-08-08, Item 8).
///
/// RELEASE PROCESS: add an entry here for every App Store / Play build that
/// has something worth telling users about. The sheet matches
/// `PackageInfo.version` EXACTLY — a build whose version has no entry shows
/// nothing at all (deliberate: a silent release is better than showing a
/// stale entry from an older version).
///
/// Keep this list newest-first. It is bundled into the binary, so a frozen
/// client only ever knows about its own entry — that is fine, the sheet only
/// ever shows the running version's entry.
library;

import 'package:flutter/foundation.dart';

@immutable
class WhatsNewEntry {
  const WhatsNewEntry({
    required this.version,
    required this.title,
    required this.bullets,
  });

  /// Must match `PackageInfo.version` exactly (e.g. '2.2.0' — no build
  /// number, which lives in `PackageInfo.buildNumber`).
  final String version;

  /// Short headline for the sheet, e.g. "Podiums & Payouts".
  final String title;

  final List<String> bullets;
}

/// Newest first.
const List<WhatsNewEntry> kWhatsNewEntries = <WhatsNewEntry>[
  WhatsNewEntry(
    version: '2.3.8',
    title: 'RACE WITH FRIENDS',
    bullets: <String>[
      'Find friends, send requests, and view public profiles from one place.',
      'Home now keeps notifications and race discovery close at hand.',
      'Leaderboard visibility and profile details are easier to manage.',
    ],
  ),
  WhatsNewEntry(
    version: '2.3.3',
    title: 'RACE TOGETHER',
    bullets: <String>[
      'Daily and Weekly Challenges now match you into a private, smaller race group.',
      'Bring a bigger crew: tournament brackets can now include up to 8 racers.',
      'Home and race updates are smoother, so your latest progress appears sooner.',
    ],
  ),
  WhatsNewEntry(
    version: '2.2.0',
    title: 'PODIUMS & PAYOUTS',
    bullets: <String>[
      'Finished races now end on a podium. See the top three with their coins.',
      'Discard a powerup you do not want and get coins back for it.',
      'Team races pay out a lot more to the winning side.',
      'Private races start on their own once everyone has joined.',
      'Loading spinners on every powerup action, so you know a tap landed.',
    ],
  ),
];

/// Returns the entry whose version matches [version] exactly, or null when
/// this build has no changelog entry (→ show nothing).
///
/// [entries] is injectable so tests do not depend on the shipped changelog.
WhatsNewEntry? whatsNewEntryFor(
  String? version, {
  List<WhatsNewEntry> entries = kWhatsNewEntries,
}) {
  if (version == null || version.isEmpty) return null;
  for (final entry in entries) {
    if (entry.version == version) return entry;
  }
  return null;
}
