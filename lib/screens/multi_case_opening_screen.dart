import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../styles.dart';
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

  const MultiCaseOpeningScreen({
    super.key,
    required this.boxCount,
    required this.openAll,
    this.includesQueued = false,
    this.onResults,
    this.rarityByType,
    this.dropOdds,
  });

  @override
  State<MultiCaseOpeningScreen> createState() => _MultiCaseOpeningScreenState();
}

enum _Phase { idle, loading, revealing, done }

class _MultiCaseOpeningScreenState extends State<MultiCaseOpeningScreen> {
  _Phase _phase = _Phase.idle;
  List<Map<String, dynamic>> _results = const [];
  final _SpinTrigger _trigger = _SpinTrigger();
  int _completed = 0;

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

  // Dismissal is allowed only before the boxes are opened or after the whole
  // reel bank has landed — never while the reels are loading/spinning (spec §6).
  bool get _canDismiss => _phase == _Phase.idle || _phase == _Phase.done;

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
                  color: AppColors.roofDark.withValues(alpha: 0.78),
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
                  const AdBannerSlot(),
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
      frameColor: AppColors.accent,
      surfaceColor: AppColors.parchmentLight,
      glowColor: AppColors.coinMid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'OPEN ALL',
                  style: HomeText.display(size: 28, color: HomeColors.ink),
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
              color: HomeColors.muted,
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
            color: AppColors.parchmentDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.pillGoldShadow, width: 2),
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
              // Stable identity so each reel keeps its state across rebuilds.
              key: ValueKey('reel_$i'),
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
    final rarityCounts = <String, int>{};
    var autoActivated = 0;
    var queued = 0;
    for (final r in _results) {
      final rarity = (r['rarity'] as String? ?? 'COMMON').toUpperCase();
      rarityCounts[rarity] = (rarityCounts[rarity] ?? 0) + 1;
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
        frameColor: AppColors.pillGold,
        surfaceColor: AppColors.parchmentLight,
        glowColor: AppColors.pillGold,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'YOU OPENED ${_results.length}',
              textAlign: TextAlign.center,
              style: HomeText.display(size: 30, color: HomeColors.ink),
            ),
            const SizedBox(height: 4),
            Text(
              [
                for (final e in rarityCounts.entries)
                  '${e.value} ${e.key.toLowerCase()}',
              ].join(' · '),
              textAlign: TextAlign.center,
              style: PixelText.body(size: 13, color: AppColors.textMid),
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
                style: PixelText.body(size: 13, color: AppColors.pillGreen),
              ),
            ],
            if (queued > 0) ...[
              const SizedBox(height: 6),
              Text(
                'Included $queued queued ${queued == 1 ? 'box' : 'boxes'}',
                textAlign: TextAlign.center,
                style: PixelText.body(size: 12, color: AppColors.textMid),
              ),
            ],
            const SizedBox(height: 20),
            PillButton(
              label: 'Continue',
              icon: Icons.check_rounded,
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(),
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
              color: AppColors.parchmentDark,
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
            style: PixelText.body(size: 10, color: AppColors.textDark),
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
            color: AppColors.errorLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.error, width: 2),
            boxShadow: const [
              BoxShadow(
                color: AppColors.error,
                offset: Offset(3, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: const Center(
            child: Icon(
              Icons.close_rounded,
              size: 20,
              color: AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }
}
