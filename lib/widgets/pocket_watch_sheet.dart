import 'package:flutter/material.dart';

import '../constants/powerup_copy.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import 'pill_button.dart';
import 'powerup_icon.dart';
import 'spinning_coin.dart';

/// §6.4 — Pocket Watch's explicit two-mode sheet.
///
/// Pocket Watch used to be a single generic "extend everything" action. It now
/// does one of two clearly different things, and the user must be able to see
/// WHICH before they spend coins:
///
/// * `MY BUFFS` — the legacy behavior: extend every eligible timed self-buff.
///   Sent with NO `targetEffectId`, so the request stays byte-identical to what
///   older builds send.
/// * `MY DEBUFFS` — extend exactly ONE harmful timed effect this user applied
///   to a rival.
///
/// Targeted mode is offered ONLY when the backend advertises
/// `pocketWatchTargetEffect`. Against an older backend that flag is absent, and
/// that backend would silently IGNORE `targetEffectId` and extend the user's own
/// buffs instead — charging them for something they didn't choose. Hence the
/// hard gate rather than optimistic sending.

/// The types Pocket Watch may extend on a rival (§6.1).
///
/// Notably excludes Hitchhike (§2 non-goal), self-buffs, and untimed effects.
const Set<String> kPocketWatchTargetableTypes = {
  'LEG_CRAMP',
  'WRONG_TURN',
  'DETOUR_SIGN',
  'SIGNAL_JAMMER',
  'LEECH',
  // AoE, but stored as one row per affected rival — each row is separately
  // selectable so the single-target scope is explicit before paying.
  'RAINSTORM',
};

/// One selectable rival debuff.
class PocketWatchEffect {
  const PocketWatchEffect({
    required this.id,
    required this.type,
    required this.targetUserId,
    required this.expiresAt,
  });

  final String id;
  final String type;
  final String? targetUserId;
  final DateTime expiresAt;
}

/// Whether targeted mode may be offered at all.
///
/// Missing, null, or malformed capability data means legacy self mode only —
/// never optimistically true.
bool pocketWatchTargetingEnabled(Map<String, dynamic>? powerupData) {
  final capabilities = powerupData?['capabilities'];
  if (capabilities is! Map) return false;
  // Strict identity check: only a real `true` opens targeted mode. A string
  // "true" or a 1 from a variant backend must not.
  return capabilities['pocketWatchTargetEffect'] == true;
}

List<Map<String, dynamic>> _effectMaps(Map<String, dynamic>? powerupData) {
  final raw = powerupData?['activeEffects'];
  if (raw is! List) return const [];
  return raw.whereType<Map>().map((e) => e.cast<String, dynamic>()).toList();
}

/// The rival debuffs this viewer may extend.
///
/// Returns empty (never throws) for absent/malformed data, an unknown viewer,
/// or a backend that hasn't shipped the capability yet.
List<PocketWatchEffect> pocketWatchTargetableEffects(
  Map<String, dynamic>? powerupData, {
  required String? viewerUserId,
  DateTime? now,
}) {
  if (!pocketWatchTargetingEnabled(powerupData)) return const [];
  // Without a known viewer we cannot prove the effect is ours to extend, and
  // the backend would reject it with EFFECT_NOT_OWNED anyway.
  if (viewerUserId == null || viewerUserId.isEmpty) return const [];

  final at = now ?? DateTime.now();
  final out = <PocketWatchEffect>[];

  for (final e in _effectMaps(powerupData)) {
    final id = e['id'];
    final type = e['type'];
    if (id is! String || id.isEmpty) continue;
    if (type is! String || !kPocketWatchTargetableTypes.contains(type)) {
      continue;
    }
    // Only effects I applied, and never one pointed back at me.
    if (e['sourceUserId'] != viewerUserId) continue;
    if (e['onSelf'] == true) continue;
    if (e['targetUserId'] == viewerUserId) continue;

    // Untimed or unparseable expiry: there is no duration to extend.
    final expiresAt = DateTime.tryParse(e['expiresAt'] as String? ?? '');
    if (expiresAt == null || !expiresAt.isAfter(at)) continue;

    out.add(
      PocketWatchEffect(
        id: id,
        type: type,
        targetUserId: e['targetUserId'] as String?,
        expiresAt: expiresAt,
      ),
    );
  }

  return out;
}

/// How many timed self-buffs the legacy mode would extend.
int pocketWatchSelfBuffCount(
  Map<String, dynamic>? powerupData, {
  required String? viewerUserId,
  DateTime? now,
}) {
  final at = now ?? DateTime.now();
  var count = 0;
  for (final e in _effectMaps(powerupData)) {
    final isMine =
        e['onSelf'] == true ||
        (viewerUserId != null && e['targetUserId'] == viewerUserId);
    if (!isMine) continue;
    final expiresAt = DateTime.tryParse(e['expiresAt'] as String? ?? '');
    if (expiresAt == null || !expiresAt.isAfter(at)) continue;
    count++;
  }
  return count;
}

/// Confirms a tier. [targetEffectId] is null in self mode, which keeps the
/// outgoing request identical to the legacy one.
typedef PocketWatchConfirm = void Function(int level, String? targetEffectId);

class PocketWatchSheet extends StatefulWidget {
  const PocketWatchSheet({
    super.key,
    required this.powerupData,
    required this.viewerUserId,
    required this.myCoins,
    required this.tierLabels,
    required this.costForLevel,
    required this.onConfirm,
    this.participants = const [],
    this.now,
  });

  final Map<String, dynamic>? powerupData;
  final String? viewerUserId;
  final int myCoins;
  final List<String> tierLabels;
  final int Function(int level) costForLevel;
  final PocketWatchConfirm onConfirm;

  /// Race participants, used to put a name and avatar on each rival. Purely
  /// cosmetic — a missing entry degrades to a neutral label.
  final List<Map<String, dynamic>> participants;

  final DateTime? now;

  @override
  State<PocketWatchSheet> createState() => _PocketWatchSheetState();
}

enum _Mode { buffs, debuffs }

class _PocketWatchSheetState extends State<PocketWatchSheet> {
  _Mode _mode = _Mode.buffs;
  String? _selectedEffectId;

  bool get _targetingEnabled =>
      pocketWatchTargetingEnabled(widget.powerupData);

  List<PocketWatchEffect> get _targets => pocketWatchTargetableEffects(
        widget.powerupData,
        viewerUserId: widget.viewerUserId,
        now: widget.now,
      );

  int get _selfBuffCount => pocketWatchSelfBuffCount(
        widget.powerupData,
        viewerUserId: widget.viewerUserId,
        now: widget.now,
      );

  String _rivalName(String? userId) {
    if (userId == null) return 'a rival';
    for (final p in widget.participants) {
      if (p['userId'] == userId) {
        final name = p['displayName'];
        if (name is String && name.trim().isNotEmpty) return atName(name.trim());
      }
    }
    return 'a rival';
  }

  String _remainingLabel(DateTime expiresAt) {
    final remaining = expiresAt.difference(widget.now ?? DateTime.now());
    if (remaining.isNegative) return 'expiring';
    if (remaining.inHours > 0) {
      return '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m left';
    }
    return '${remaining.inMinutes}m left';
  }

  void _confirm(int level) {
    if (_mode == _Mode.debuffs) {
      // Targeted mode requires an explicit selection — never guess a target.
      final selected = _selectedEffectId;
      if (selected == null) return;
      widget.onConfirm(level, selected);
      return;
    }
    // Self mode sends no targetEffectId at all: the legacy request shape.
    widget.onConfirm(level, null);
  }

  @override
  Widget build(BuildContext context) {
    final targets = _targets;
    final selfCount = _selfBuffCount;
    final activeCount = _mode == _Mode.buffs ? selfCount : targets.length;
    final canConfirm = activeCount > 0 &&
        (_mode == _Mode.buffs || _selectedEffectId != null);

    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const PowerupIcon(
                  type: 'POCKET_WATCH',
                  size: 22,
                  spinning: true,
                ),
                const SizedBox(width: 6),
                Text(
                  PowerupCopy.nameFor('POCKET_WATCH'),
                  style: PixelText.title(size: 18, color: AppColors.textDark),
                ),
              ],
            ),
            const SizedBox(height: 12),
            if (_targetingEnabled) _buildModeToggle(selfCount, targets.length),
            if (_targetingEnabled) const SizedBox(height: 12),
            if (_mode == _Mode.buffs)
              _buildBuffsPane(selfCount)
            else
              _buildDebuffsPane(targets),
            const SizedBox(height: 14),
            ..._buildTierButtons(canConfirm),
          ],
        ),
      ),
    );
  }

  Widget _buildModeToggle(int selfCount, int targetCount) {
    Widget seg(String label, _Mode mode, int count) {
      final selected = _mode == mode;
      return Expanded(
        child: GestureDetector(
          onTap: () => setState(() {
            _mode = mode;
            // Switching away from targeted mode drops the selection so a stale
            // pick can't be confirmed after coming back.
            if (mode == _Mode.buffs) _selectedEffectId = null;
          }),
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 160),
            curve: Curves.easeOut,
            padding: const EdgeInsets.symmetric(vertical: 9),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: selected ? AppColors.pillGold : Colors.transparent,
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: selected ? AppColors.pillGoldShadow : Colors.transparent,
                width: 2,
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  label,
                  style: PixelText.title(
                    size: 12,
                    color: selected ? AppColors.textDark : AppColors.textMid,
                  ),
                ),
                const SizedBox(width: 5),
                // The count is what tells the user which mode is even usable
                // before they commit, so it stays visible on both segments.
                Text(
                  '$count',
                  style: PixelText.title(
                    size: 12,
                    color: selected
                        ? AppColors.textDark
                        : AppColors.textMid.withValues(alpha: 0.75),
                  ),
                ),
              ],
            ),
          ),
        ),
      );
    }

    return Container(
      padding: const EdgeInsets.all(4),
      decoration: BoxDecoration(
        color: AppColors.parchmentDark,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        children: [
          Text('', style: PixelText.body(size: 1)),
          seg('MY BUFFS', _Mode.buffs, selfCount),
          const SizedBox(width: 4),
          seg('MY DEBUFFS', _Mode.debuffs, targetCount),
        ],
      ),
    );
  }

  Widget _buildBuffsPane(int count) {
    if (!_targetingEnabled) {
      // Without the toggle the mode still needs a heading so the sheet reads
      // the same on an older backend.
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            'MY BUFFS',
            textAlign: TextAlign.center,
            style: PixelText.title(size: 13, color: AppColors.textMid),
          ),
          const SizedBox(height: 6),
          _buffsBody(count),
        ],
      );
    }
    return _buffsBody(count);
  }

  Widget _buffsBody(int count) {
    if (count == 0) {
      return Text(
        key: const Key('pocket-watch-buffs-empty'),
        'No timed buffs to extend right now.',
        textAlign: TextAlign.center,
        style: PixelText.body(size: 13, color: AppColors.textMid),
      );
    }
    return Text(
      'Extends all $count active timed '
      '${count == 1 ? 'buff' : 'buffs'} on you.',
      textAlign: TextAlign.center,
      style: PixelText.body(size: 13, color: AppColors.textMid),
    );
  }

  Widget _buildDebuffsPane(List<PocketWatchEffect> targets) {
    if (targets.isEmpty) {
      return Text(
        key: const Key('pocket-watch-debuffs-empty'),
        "You haven't put any timed effects on a rival yet.",
        textAlign: TextAlign.center,
        style: PixelText.body(size: 13, color: AppColors.textMid),
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text(
          'Extends ONE effect you chose.',
          textAlign: TextAlign.center,
          style: PixelText.body(size: 13, color: AppColors.textMid),
        ),
        const SizedBox(height: 8),
        ConstrainedBox(
          constraints: const BoxConstraints(maxHeight: 220),
          child: ListView.builder(
            key: const Key('pocket-watch-effect-list'),
            shrinkWrap: true,
            itemCount: targets.length,
            itemBuilder: (_, i) => _buildEffectRow(targets[i]),
          ),
        ),
      ],
    );
  }

  Widget _buildEffectRow(PocketWatchEffect effect) {
    final selected = _selectedEffectId == effect.id;
    return Padding(
      padding: const EdgeInsets.only(bottom: 6),
      child: GestureDetector(
        key: Key('pocket-watch-effect-${effect.id}'),
        onTap: () => setState(() => _selectedEffectId = effect.id),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
          decoration: BoxDecoration(
            color: selected ? AppColors.pillGold : AppColors.parchmentDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: selected ? AppColors.pillGoldShadow : Colors.transparent,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              PowerupIcon(type: effect.type, size: 22),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      PowerupCopy.nameFor(effect.type),
                      style: PixelText.title(
                        size: 13,
                        color: AppColors.textDark,
                      ),
                    ),
                    Text(
                      'on ${_rivalName(effect.targetUserId)}',
                      style: PixelText.body(size: 11, color: AppColors.textMid),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Text(
                _remainingLabel(effect.expiresAt),
                style: PixelText.body(size: 11, color: AppColors.textMid),
              ),
            ],
          ),
        ),
      ),
    );
  }

  List<Widget> _buildTierButtons(bool canConfirm) {
    final buttons = <Widget>[];
    for (var level = 0; level < 4; level++) {
      final label = level < widget.tierLabels.length
          ? widget.tierLabels[level]
          : 'Tier $level';
      final cost = widget.costForLevel(level);
      final affordable = widget.myCoins >= cost;
      final enabled = canConfirm && affordable;

      buttons.add(
        Padding(
          padding: const EdgeInsets.only(bottom: 6),
          child: PillButton(
            key: Key('pocket-watch-tier-$level'),
            label: level == 0 ? 'USE BASE — $label' : 'LVL $level — $label',
            variant: level == 0
                ? PillButtonVariant.secondary
                : PillButtonVariant.primary,
            fontSize: 12,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            trailing: level == 0
                ? null
                : Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        '$cost',
                        style: PixelText.pill(size: 12, color: Colors.white),
                      ),
                      const SizedBox(width: 4),
                      const SpinningCoin(size: 14),
                    ],
                  ),
            onPressed: enabled ? () => _confirm(level) : null,
          ),
        ),
      );
    }
    return buttons;
  }
}
