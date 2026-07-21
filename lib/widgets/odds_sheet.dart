import 'package:flutter/material.dart';

import '../constants/powerup_copy.dart';
import '../styles.dart';
import 'case_opening_strip.dart' show caseRarityColor;
import 'home_chrome.dart';
import 'game_container.dart';
import 'powerup_icon.dart';

/// Player-facing exact-odds transparency (spec §5.3 / §6.3.B.10).
///
/// The backend serving this build may be older than it and omit `dropOdds` /
/// `itemOdds` entirely, or newer and send a shape this build doesn't fully
/// understand. Both are handled the same way: [OddsBreakdown.parseDropOdds] /
/// [OddsBreakdown.parseItemOdds] return **null** unless the payload is
/// well-formed, and a null breakdown hides the affordance completely.
///
/// A wrong odds display is worse than no odds display, so there is deliberately
/// no "partial" rendering mode: either every distribution the payload claims to
/// carry is coherent, or the player sees nothing at all.

/// One labelled probability, already validated to be finite and non-negative.
class OddsSlice {
  const OddsSlice(this.key, this.label, this.p);

  final String key;
  final String label;
  final double p;
}

/// A parsed, VALIDATED odds payload. Construction is only possible through the
/// parsers, so holding one of these means the numbers are safe to render.
class OddsBreakdown {
  const OddsBreakdown._({
    required this.rarity,
    this.configVersion,
    this.position,
    this.totalParticipants,
    this.byType,
    this.rareMix,
    this.accessories,
    this.powerups,
  });

  /// Rarity → probability. Guaranteed non-empty and summing to 1.0 ± 0.01.
  final List<OddsSlice> rarity;

  /// The config version that produced these numbers (spec D9 provenance).
  final int? configVersion;
  final int? position;
  final int? totalParticipants;

  /// Per-powerup-type drop probability. Null when the backend omitted it —
  /// §5.3 omits the key entirely rather than sending an empty object.
  final List<OddsSlice>? byType;

  /// Daily box: the RARE sub-roll INCLUDING the coins slice.
  final List<OddsSlice>? rareMix;
  final List<OddsSlice>? accessories;
  final List<OddsSlice>? powerups;

  /// `powerupData.dropOdds` (§5.3). Null unless well-formed.
  static OddsBreakdown? parseDropOdds(dynamic raw) {
    if (raw is! Map) return null;
    final rarity = _parseDistribution(raw['rarity'], _rarityLabel);
    if (rarity == null) return null;
    return OddsBreakdown._(
      rarity: rarity,
      configVersion: _readInt(raw['configVersion']),
      position: _readInt(raw['position']),
      totalParticipants: _readInt(raw['totalParticipants']),
      // byType is a set of per-type slices of the whole, NOT its own
      // distribution — it does not sum to 1, so it is only sanity-checked.
      byType: _parseSlices(raw['byType'], PowerupCopy.nameFor),
    );
  }

  /// `box.itemOdds` (§5.3). Null unless well-formed. A present-but-incoherent
  /// `rareMix` invalidates the WHOLE payload rather than silently dropping the
  /// sub-table, because the rarity row alone would then over-promise.
  static OddsBreakdown? parseItemOdds(dynamic raw) {
    if (raw is! Map) return null;
    final rarity = _parseDistribution(raw['rarity'], _rarityLabel);
    if (rarity == null) return null;

    List<OddsSlice>? rareMix;
    if (raw.containsKey('rareMix')) {
      rareMix = _parseDistribution(raw['rareMix'], (k) => k);
      if (rareMix == null) return null;
    }

    return OddsBreakdown._(
      rarity: rarity,
      configVersion: _readInt(raw['configVersion']),
      rareMix: rareMix,
      accessories: _parseEntryList(raw['accessories'], 'sku', (k) => k),
      powerups: _parseEntryList(raw['powerups'], 'type', PowerupCopy.nameFor),
    );
  }

  static int? _readInt(dynamic raw) =>
      raw is num && raw.isFinite ? raw.toInt() : null;

  static String _rarityLabel(String key) => key.toUpperCase();

  /// A map that must be a real probability distribution: at least one entry,
  /// every value finite and >= 0, summing to 1.0 ± 0.01.
  static List<OddsSlice>? _parseDistribution(
    dynamic raw,
    String Function(String key) label,
  ) {
    final slices = _parseSlices(raw, label);
    if (slices == null) return null;
    final sum = slices.fold<double>(0, (acc, s) => acc + s.p);
    if ((sum - 1.0).abs() > 0.01) return null;
    return slices;
  }

  /// A `{key: number}` map with no distribution requirement. Null when the
  /// value isn't a map, is empty, or contains any unusable number — a single
  /// bad entry means the table can't be trusted.
  static List<OddsSlice>? _parseSlices(
    dynamic raw,
    String Function(String key) label,
  ) {
    if (raw is! Map || raw.isEmpty) return null;
    final out = <OddsSlice>[];
    for (final entry in raw.entries) {
      final key = entry.key;
      final value = entry.value;
      if (key is! String || key.isEmpty) return null;
      if (value is! num || !value.isFinite || value < 0) return null;
      out.add(OddsSlice(key, label(key), value.toDouble()));
    }
    return out.isEmpty ? null : out;
  }

  /// `[{ "<idKey>": "...", "p": 0.31 }]`. Null when absent or unusable; these
  /// lists are conditional detail, so a bad one is dropped without
  /// invalidating the rarity row.
  static List<OddsSlice>? _parseEntryList(
    dynamic raw,
    String idKey,
    String Function(String key) label,
  ) {
    if (raw is! List || raw.isEmpty) return null;
    final out = <OddsSlice>[];
    for (final item in raw) {
      if (item is! Map) continue;
      final id = item[idKey];
      final p = item['p'];
      if (id is! String || id.isEmpty) continue;
      if (p is! num || !p.isFinite || p < 0) continue;
      out.add(OddsSlice(id, label(id), p.toDouble()));
    }
    if (out.isEmpty) return null;
    out.sort((a, b) => b.p.compareTo(a.p));
    return out;
  }
}

/// The odds entry point. Renders NOTHING when [odds] is null — spec
/// §6.3.B.10: absent or malformed means no affordance at all.
///
/// There is deliberately no loading variant: both host surfaces gate their
/// entire content behind a load state, so there is no moment where this chip
/// exists but its data doesn't. A skeleton here would be unreachable code
/// pretending to be a state.
class OddsAffordance extends StatelessWidget {
  const OddsAffordance({
    super.key,
    required this.odds,
    required this.title,
    this.subtitle,
  });

  final OddsBreakdown? odds;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final data = odds;
    if (data == null) return const SizedBox.shrink();

    return Semantics(
      button: true,
      label: 'Show exact odds',
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => showOddsSheet(
            context,
            odds: data,
            title: title,
            subtitle: subtitle,
          ),
          borderRadius: BorderRadius.circular(8),
          child: Ink(
            height: 36,
            padding: const EdgeInsets.symmetric(horizontal: 10),
            decoration: BoxDecoration(
              color: AppColors.parchmentDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: AppColors.coinDark, width: 2),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.percent_rounded,
                  size: 15,
                  color: AppColors.coinDark,
                ),
                const SizedBox(width: 5),
                Text(
                  'ODDS',
                  style: PixelText.pill(size: 11, color: AppColors.coinDark),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

void showOddsSheet(
  BuildContext context, {
  required OddsBreakdown odds,
  required String title,
  String? subtitle,
}) {
  showModalBottomSheet<void>(
    context: context,
    backgroundColor: Colors.transparent,
    isScrollControlled: true,
    builder: (sheetContext) => _OddsSheet(
      odds: odds,
      title: title,
      subtitle: subtitle,
    ),
  );
}

class _OddsSheet extends StatelessWidget {
  const _OddsSheet({required this.odds, required this.title, this.subtitle});

  final OddsBreakdown odds;
  final String title;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final context_ = context;
    return DraggableScrollableSheet(
      initialChildSize: 0.72,
      minChildSize: 0.4,
      maxChildSize: 0.92,
      expand: false,
      builder: (_, scrollController) => GameContainer(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
        frameColor: AppColors.coinDark,
        surfaceColor: AppColors.parchmentLight,
        glowColor: AppColors.coinMid,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Center(
              child: Container(
                width: 40,
                height: 4,
                decoration: BoxDecoration(
                  color: AppColors.woodMid,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
            ),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: HomeText.display(size: 22, color: HomeColors.ink),
            ),
            if (subtitle != null) ...[
              const SizedBox(height: 4),
              Text(
                subtitle!,
                textAlign: TextAlign.center,
                style: HomeText.body(
                  size: 12,
                  color: HomeColors.muted,
                  weight: FontWeight.w700,
                ),
              ),
            ],
            const SizedBox(height: 12),
            Expanded(
              child: ListView(
                controller: scrollController,
                padding: EdgeInsets.zero,
                children: [
                  _SectionLabel('BY RARITY'),
                  for (final slice in odds.rarity)
                    _OddsBar(
                      label: slice.label,
                      pct: slice.p,
                      color: caseRarityColor(slice.key),
                    ),
                  if (odds.rareMix != null) ...[
                    const SizedBox(height: 14),
                    _SectionLabel('IF IT ROLLS RARE'),
                    for (final slice in odds.rareMix!)
                      _OddsBar(
                        label: slice.label,
                        pct: slice.p,
                        color: AppColors.coinDark,
                      ),
                  ],
                  if (odds.byType != null) ...[
                    const SizedBox(height: 14),
                    _SectionLabel('BY POWERUP'),
                    for (final slice in _sorted(odds.byType!))
                      _OddsRowWithIcon(type: slice.key, label: slice.label, p: slice.p),
                  ],
                  if (odds.powerups != null) ...[
                    const SizedBox(height: 14),
                    _SectionLabel('POWERUP PRIZES'),
                    for (final slice in odds.powerups!)
                      _OddsRowWithIcon(type: slice.key, label: slice.label, p: slice.p),
                  ],
                  if (odds.accessories != null) ...[
                    const SizedBox(height: 14),
                    _SectionLabel('ACCESSORY PRIZES'),
                    for (final slice in odds.accessories!)
                      _OddsBar(
                        label: slice.label,
                        pct: slice.p,
                        color: AppColors.roofLight,
                      ),
                  ],
                  const SizedBox(height: 14),
                  Text(
                    _provenance(odds),
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 10, color: AppColors.textMid),
                  ),
                  const SizedBox(height: 12),
                  TextButton(
                    onPressed: () => Navigator.of(context_).maybePop(),
                    child: Text(
                      'CLOSE',
                      style: PixelText.pill(
                        size: 12,
                        color: AppColors.textDark,
                      ),
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

  static List<OddsSlice> _sorted(List<OddsSlice> slices) =>
      List.of(slices)..sort((a, b) => b.p.compareTo(a.p));

  static String _provenance(OddsBreakdown odds) {
    final parts = <String>[];
    if (odds.position != null && odds.totalParticipants != null) {
      parts.add('Position ${odds.position} of ${odds.totalParticipants}');
    }
    if (odds.configVersion != null) parts.add('Odds v${odds.configVersion}');
    if (parts.isEmpty) return 'Live odds from the server.';
    return parts.join(' · ');
  }
}

class _SectionLabel extends StatelessWidget {
  const _SectionLabel(this.text);
  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 8),
    child: Text(
      text,
      style: PixelText.pill(size: 11, color: AppColors.textMid),
    ),
  );
}

/// A rarity/mix row: label, a proportional fill that makes the distribution
/// readable at a glance, and the exact percentage.
class _OddsBar extends StatelessWidget {
  const _OddsBar({required this.label, required this.pct, required this.color});

  final String label;
  final double pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: AppColors.parchmentDark,
          border: Border.all(color: color, width: 2),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    label,
                    style: PixelText.title(size: 12, color: color),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
                const SizedBox(width: 8),
                Text(
                  formatOddsPercent(pct),
                  style: PixelText.number(size: 13, color: color),
                ),
              ],
            ),
            const SizedBox(height: 6),
            ClipRRect(
              borderRadius: BorderRadius.circular(3),
              child: LinearProgressIndicator(
                value: pct.clamp(0.0, 1.0),
                minHeight: 6,
                backgroundColor: AppColors.parchmentBorder,
                valueColor: AlwaysStoppedAnimation<Color>(color),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _OddsRowWithIcon extends StatelessWidget {
  const _OddsRowWithIcon({
    required this.type,
    required this.label,
    required this.p,
  });

  final String type;
  final String label;
  final double p;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 5),
      child: Row(
        children: [
          SizedBox(width: 26, child: PowerupIcon(type: type, size: 24)),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: PixelText.body(size: 12, color: AppColors.textDark),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(
            formatOddsPercent(p),
            style: PixelText.number(size: 12, color: AppColors.textMid),
          ),
        ],
      ),
    );
  }
}

/// Percentages are shown to whatever precision keeps them honest: a 3.1% drop
/// must not round to "3%" next to a 3.4% one, and a 0.4% drop must never round
/// to "0%" — that would read as impossible.
String formatOddsPercent(double p) {
  final pct = p * 100;
  if (pct > 0 && pct < 0.1) return '<0.1%';
  if (pct < 10 && (pct - pct.roundToDouble()).abs() > 0.049) {
    return '${pct.toStringAsFixed(1)}%';
  }
  return '${pct.round()}%';
}
