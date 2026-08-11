import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../styles.dart';
import '../services/ad_service.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/case_opening_strip.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_container.dart';
import '../widgets/home_chrome.dart';
import '../widgets/info_toast.dart';
import '../widgets/odds_sheet.dart';
import '../widgets/pill_button.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/spinning_crate.dart';
import '../constants/powerup_copy.dart';

/// A tiny [ChangeNotifier] whose only job is to fan a single "spin now" pulse
/// out to every reel listening on it, so one tap spins the whole reel bank.
class _SpinTrigger extends ChangeNotifier {
  void fire() => notifyListeners();
}

/// Full-screen "Open All" experience (item #1): opens every openable mystery
/// box (slot boxes + queued overflow) in one action and spins them together in
/// a vertical bank of full-width reels, then shows an aggregate summary.
///
/// [openAll] performs the actual open (batch endpoint, or a feature-detected
/// fallback to N single opens) and resolves the per-box results. It fires
/// exactly once, when the user taps OPEN ALL — nothing is consumed on screen
/// open. Each result mirrors the single-open shape:
/// `{type, rarity, autoActivated, queued}`.
class MultiCaseOpeningScreen extends StatefulWidget {
  final int boxCount;
  final bool includesQueued;
  final Future<List<Map<String, dynamic>>> Function() openAll;

  /// Invoked once with the resolved results, so the host can optimistically
  /// reconcile its inventory projection before the follow-up refresh.
  final void Function(List<Map<String, dynamic>> results)? onResults;

  /// Server-authoritative `rarityByType` for the decoy tiles; the reel's
  /// bundled table is the fallback. Null on an older backend.
  final Map<String, String>? rarityByType;

  /// Raw `powerupData.dropOdds`; hidden entirely when absent or malformed.
  final Map<String, dynamic>? dropOdds;

  /// Batch 2026-08-10b item 1 — one rewarded ad rerolls EVERY eligible box in
  /// this batch. **Null by default**, so nothing that builds this screen picks
  /// the button up implicitly: the host passes it only when the backend
  /// advertised `powerupData.boxRerollBatch == true` AND a reroll ad unit is
  /// baked into this build. Resolves the new rows (keyed `powerupId`), or null
  /// when the user backed out of the ad / it failed (already toasted by the
  /// host), in which case the summary is left exactly as it was.
  final Future<List<Map<String, dynamic>>?> Function(List<String> powerupIds)?
  onRerollAll;

  const MultiCaseOpeningScreen({
    super.key,
    required this.boxCount,
    required this.openAll,
    this.includesQueued = false,
    this.onResults,
    this.rarityByType,
    this.dropOdds,
    this.onRerollAll,
  });

  @override
  State<MultiCaseOpeningScreen> createState() => _MultiCaseOpeningScreenState();
}

enum _Phase { idle, loading, revealing, done }

class _MultiCaseOpeningScreenState extends State<MultiCaseOpeningScreen> {
  /// Mirrors the backend's `REROLL_BATCH_MAX_COUNT`. Used ONLY to word the
  /// disclaimer honestly — the server is what actually truncates, and any id
  /// past the cap comes back `skipped: "OVER_CAP"` with its unchanged roll.
  static const int rerollBatchMaxCount = 8;

  _Phase _phase = _Phase.idle;
  List<Map<String, dynamic>> _results = const [];
  final _SpinTrigger _trigger = _SpinTrigger();
  int _completed = 0;

  /// One reroll per batch, mirroring the single-box flow's one-per-box rule.
  bool _rerollUsed = false;
  bool _rerollingAll = false;

  /// Bumped on every reroll so each reel's key changes and Flutter genuinely
  /// REMOUNTS the strip (architect S1). Reusing the existing reel `State` would
  /// mean `onComplete` never fires again, leaving `_phase` stuck on
  /// `revealing` and `_canDismiss` false — a permanently undismissable overlay.
  int _rollGen = 0;

  @override
  void dispose() {
    _trigger.dispose();
    super.dispose();
  }

  Future<void> _openAll() async {
    if (_phase != _Phase.idle) return;
    setState(() => _phase = _Phase.loading);
    try {
      final results = await widget.openAll();
      if (!mounted) return;
      if (results.isEmpty) {
        // Nothing came back (e.g. everything was already opened). Close out
        // gracefully rather than showing an empty reel grid.
        showInfoToast(context, 'No boxes to open');
        Navigator.of(context).pop();
        return;
      }
      // Defer the parent inventory commit until every reel lands (spec §6) —
      // firing it here would spoil the results behind the still-spinning grid.
      setState(() {
        _results = results;
        _phase = _Phase.revealing;
      });
      // Build the reels this frame, then pulse them all next frame so every
      // reel is listening before the trigger fires.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _trigger.fire();
      });
    } catch (e) {
      if (!mounted) return;
      showErrorToast(context, 'Failed to open boxes');
      setState(() => _phase = _Phase.idle);
    }
  }

  void _onReelComplete() {
    if (!mounted) return;
    _completed++;
    if (_completed >= _results.length && _phase == _Phase.revealing) {
      HapticFeedback.mediumImpact();
      // Every reel has landed: commit all results together in one shot. This
      // covers the batch endpoint and the 404-compat _fallbackSingleOpens path,
      // since both resolve through widget.openAll before reaching here.
      widget.onResults?.call(_results);
      setState(() => _phase = _Phase.done);
    }
  }

  /// Ids this batch could plausibly reroll, from the CLIENT's point of view.
  /// A display filter only — the server re-checks everything, and an
  /// auto-activated Fanny Pack is already USED so it comes back `skipped`.
  List<String> get _rerollableIds => [
    for (final r in _results)
      if (r['powerupId'] is String &&
          r['autoActivated'] != true &&
          r['alreadyOpened'] != true)
        r['powerupId'] as String,
  ];

  /// Wording for the disclaimer. The server truncates to
  /// [rerollBatchMaxCount], so promising "ALL" past that would be a lie.
  String get _rerollDisclaimer {
    final n = _rerollableIds.length;
    final subject = n > rerollBatchMaxCount
        ? '$rerollBatchMaxCount of these boxes'
        : 'ALL of these boxes';
    return 'Watch an ad to reroll $subject. Every roll is replaced — '
        'the new rolls are final.';
  }

  Future<void> _rerollAll() async {
    final reroll = widget.onRerollAll;
    if (reroll == null || _rerollingAll || _rerollUsed) return;
    final ids = _rerollableIds;
    if (ids.isEmpty) return;

    setState(() => _rerollingAll = true);
    List<Map<String, dynamic>>? rows;
    try {
      rows = await reroll(ids);
    } catch (_) {
      // The host owns the error copy; never leave the button spinning.
      rows = null;
    }
    if (!mounted) return;
    if (rows == null) {
      // Backed out of the ad / already toasted: the summary is untouched and
      // the button stays available — no credit was spent.
      setState(() => _rerollingAll = false);
      return;
    }

    // Join on `powerupId` — the key `open-batch` and `reroll-batch` share.
    // Anything not echoed back (skipped, omitted foreign id, an older/newer
    // backend shape) keeps its original roll rather than blanking.
    final byId = <String, Map<String, dynamic>>{};
    for (final row in rows) {
      final id = row['powerupId'];
      if (id is String) byId[id] = row;
    }
    final merged = <Map<String, dynamic>>[];
    for (final existing in _results) {
      final id = existing['powerupId'];
      final match = id is String ? byId[id] : null;
      if (match == null) {
        merged.add(existing);
        continue;
      }
      merged.add({
        ...existing,
        if (match['type'] is String) 'type': match['type'],
        if (match['rarity'] is String) 'rarity': match['rarity'],
      });
    }

    setState(() {
      _results = merged;
      _rerollUsed = true;
      _rerollingAll = false;
      _rollGen++;
      _completed = 0;
      _phase = _Phase.revealing;
    });
    // Same two-step as the first open: build the (remounted) reels this frame,
    // pulse them next frame once every one of them is listening.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) _trigger.fire();
    });
  }

  // Dismissal is allowed only before the boxes are opened or after the whole
  // reel bank has landed — never while the reels are loading/spinning (spec §6)
  // and never while a reroll ad is up, so a backgrounded ad can't leave a
  // half-applied batch behind a popped route.
  bool get _canDismiss =>
      !_rerollingAll && (_phase == _Phase.idle || _phase == _Phase.done);

  void _close() {
    if (!_canDismiss) return;
    Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      // Block Android back + iOS swipe-back while the reels load/spin.
      canPop: _canDismiss,
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                child: ColoredBox(
                  color: AppColors.of(context).roofDark.withValues(alpha: 0.78),
                  child: const CustomPaint(
                    painter: ArcadeCheckerPainter(
                      tileColor: Color(0x0AFFFFFF),
                      stripeColor: Color(0x14000000),
                      drawBottomStripe: false,
                    ),
                  ),
                ),
              ),
            ),
            SafeArea(
              child: Column(
                children: [
                  if (AdService.remoteDualBoxBannersEnabled) ...[
                    const AdBannerSlot(
                      placement: AdBannerPlacement.boxTop,
                      reserveSpaceWhileLoading: true,
                    ),
                    if (AdService.boxTopBannerEnabled)
                      const SizedBox(height: 12),
                  ],
                  Expanded(
                    child: Center(
                      child: SingleChildScrollView(
                        padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                        child: ConstrainedBox(
                          // Match the single-box cabinet exactly. Open All adds
                          // reels vertically; it never makes them narrower.
                          constraints: const BoxConstraints(maxWidth: 460),
                          child: _phase == _Phase.done
                              ? _buildSummary()
                              : _buildOpening(),
                        ),
                      ),
                    ),
                  ),
                  if (AdService.bannersEnabled) const SizedBox(height: 12),
                  const AdBannerSlot(reserveSpaceWhileLoading: true),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildOpening() {
    return GameContainer(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
      frameColor: AppColors.of(context).accent,
      surfaceColor: AppColors.of(context).parchmentLight,
      glowColor: AppColors.of(context).coinMid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'OPEN ALL',
                  style: HomeText.display(
                    size: 28,
                    color: AppColors.of(context).ink,
                  ),
                ),
              ),
              OddsAffordance(
                odds: OddsBreakdown.parseDropOdds(widget.dropOdds),
                title: 'DROP ODDS',
                subtitle: 'Exactly what these boxes can roll for you.',
              ),
              const SizedBox(width: 8),
              _CloseButton(onTap: _close),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _phase == _Phase.idle
                ? 'Crack open all ${widget.boxCount} '
                      '${widget.boxCount == 1 ? 'box' : 'boxes'} at once'
                : 'Opening ${_results.length} '
                      '${_results.length == 1 ? 'box' : 'boxes'}...',
            style: HomeText.body(
              size: 14,
              color: AppColors.of(context).muted,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 16),
          if (_phase == _Phase.idle) ...[
            _buildIdlePreview(),
            const SizedBox(height: 18),
            PillButton(
              label: 'OPEN ALL',
              icon: Icons.auto_awesome_rounded,
              fullWidth: true,
              onPressed: _openAll,
            ),
          ] else if (_phase == _Phase.loading) ...[
            const SizedBox(height: 40),
            const Center(child: CircularProgressIndicator()),
            const SizedBox(height: 40),
          ] else
            _buildReelStack(),
        ],
      ),
    );
  }

  Widget _buildIdlePreview() {
    return Wrap(
      alignment: WrapAlignment.center,
      spacing: 10,
      runSpacing: 10,
      children: List.generate(
        widget.boxCount.clamp(0, 12),
        (_) => Container(
          width: 54,
          height: 54,
          decoration: BoxDecoration(
            color: AppColors.of(context).parchmentDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: AppColors.of(context).pillGoldShadow,
              width: 2,
            ),
          ),
          child: const Center(child: SpinningCrate(size: 34)),
        ),
      ),
    );
  }

  Widget _buildReelStack() {
    return Column(
      key: const Key('open-all-reel-stack'),
      mainAxisSize: MainAxisSize.min,
      children: [
        for (int i = 0; i < _results.length; i++) ...[
          SizedBox(
            width: double.infinity,
            child: CaseOpeningStrip(
              // Stable identity so each reel keeps its state across rebuilds —
              // but the roll GENERATION is part of it, so a reroll forces a
              // genuine remount and the new bank actually re-spins and lands.
              key: ValueKey('${_results[i]['powerupId'] ?? 'reel_$i'}:$_rollGen'),
              resultType: _results[i]['type'] as String? ?? '',
              resultRarity: _results[i]['rarity'] as String? ?? 'COMMON',
              // Same reel height as the single-box opening screen.
              height: 116,
              hideSwipeHint: true,
              spinTrigger: _trigger,
              rarityByType: widget.rarityByType,
              onComplete: _onReelComplete,
            ),
          ),
          if (i != _results.length - 1) const SizedBox(height: 10),
        ],
      ],
    );
  }

  Widget _buildSummary() {
    var autoActivated = 0;
    var queued = 0;
    for (final r in _results) {
      if (r['autoActivated'] == true) autoActivated++;
      if (r['queued'] == true) queued++;
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 450),
      curve: Curves.easeOutBack,
      builder: (context, value, child) => Transform.scale(
        scale: value,
        child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
      ),
      child: GameContainer(
        padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
        frameColor: AppColors.of(context).pillGold,
        surfaceColor: AppColors.of(context).parchmentLight,
        glowColor: AppColors.of(context).pillGold,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'YOU OPENED ${_results.length}',
              textAlign: TextAlign.center,
              style: HomeText.display(
                size: 30,
                color: AppColors.of(context).ink,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              _results.length == 1 ? 'box' : 'boxes',
              textAlign: TextAlign.center,
              style: PixelText.body(
                size: 13,
                color: AppColors.of(context).textMid,
              ),
            ),
            const SizedBox(height: 16),
            Wrap(
              alignment: WrapAlignment.center,
              spacing: 10,
              runSpacing: 10,
              children: [for (final r in _results) _summaryTile(r)],
            ),
            if (autoActivated > 0) ...[
              const SizedBox(height: 12),
              Text(
                '$autoActivated auto-activated',
                textAlign: TextAlign.center,
                style: PixelText.body(
                  size: 13,
                  color: AppColors.of(context).pillGreen,
                ),
              ),
            ],
            if (queued > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Included $queued queued ${queued == 1 ? 'box' : 'boxes'}',
                textAlign: TextAlign.center,
                style: PixelText.body(
                  size: 12,
                  color: AppColors.of(context).textMid,
                ),
              ),
            ],
            const SizedBox(height: 20),
            // Item 1 — REROLL ALL. Absent unless the host wired it (backend
            // advertised `boxRerollBatch`, a reroll ad unit is baked in, not
            // demo), already spent, or nothing in the bank is rerollable. On
            // Android the ad unit doesn't exist, so this whole block is
            // simply never built and the card renders as it does today.
            if (widget.onRerollAll != null &&
                !_rerollUsed &&
                _rerollableIds.isNotEmpty) ...[
              PillButton(
                key: const Key('open-all-reroll-button'),
                label: 'REROLL ALL',
                icon: Icons.ondemand_video_rounded,
                variant: PillButtonVariant.secondary,
                fontSize: 13,
                fullWidth: true,
                loading: _rerollingAll,
                onPressed: _rerollingAll ? null : _rerollAll,
              ),
              const SizedBox(height: 6),
              Text(
                _rerollDisclaimer,
                key: const Key('open-all-reroll-disclaimer'),
                textAlign: TextAlign.center,
                style: PixelText.body(
                  size: 11,
                  color: AppColors.of(context).textMid,
                ),
              ),
              const SizedBox(height: 14),
            ],
            PillButton(
              label: 'Continue',
              icon: Icons.check_rounded,
              fullWidth: true,
              // Disabled while the ad is up: a half-applied batch behind a
              // popped route is the one state this screen cannot recover from.
              onPressed: _rerollingAll
                  ? null
                  : () => Navigator.of(context).pop(),
            ),
          ],
        ),
      ),
    );
  }

  Widget _summaryTile(Map<String, dynamic> r) {
    final type = r['type'] as String? ?? '';
    final rarity = (r['rarity'] as String? ?? 'COMMON');
    final color = caseRarityColor(rarity);
    final name = PowerupCopy.nameFor(type);
    return SizedBox(
      width: 76,
      child: Column(
        children: [
          Container(
            width: 60,
            height: 60,
            decoration: BoxDecoration(
              color: AppColors.of(context).parchmentDark,
              borderRadius: BorderRadius.circular(8),
              border: Border.all(color: color, width: 2),
            ),
            alignment: Alignment.center,
            child: PowerupIcon(type: type, size: 42),
          ),
          const SizedBox(height: 4),
          Text(
            name,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: PixelText.body(
              size: 10,
              color: AppColors.of(context).textDark,
            ),
          ),
        ],
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});

  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          width: 38,
          height: 38,
          decoration: BoxDecoration(
            color: AppColors.of(context).errorLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.of(context).error, width: 2),
            boxShadow: [
              BoxShadow(
                color: AppColors.of(context).error,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Center(
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.of(context).textDark,
            ),
          ),
        ),
      ),
    );
  }
}
