import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/home_chrome.dart';
import '../widgets/pill_button.dart';
import '../widgets/spinning_coin.dart';

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

/// Step-milestone daily rewards. Renders four tiers (5k/10k/15k/20k) with
/// locked/claimable/claimed state and a tap-to-claim button on each row.
/// Self-fetches from `/users/me/step-milestones/today`; refreshes via
/// [refresh] (called by parent pull-to-refresh).
class StepMilestonesSection extends StatefulWidget {
  const StepMilestonesSection({
    super.key,
    required this.authService,
    required this.backendApiService,
    this.currentSteps,
  });

  final AuthService authService;
  final BackendApiService backendApiService;

  /// Optional hint from the parent's already-fetched step total; used as a
  /// best-guess until the server response arrives.
  final int? currentSteps;

  @override
  State<StepMilestonesSection> createState() => StepMilestonesSectionState();
}

class StepMilestonesSectionState extends State<StepMilestonesSection> {
  bool _loading = true;
  String _error = '';
  int _currentSteps = 0;
  int _totalCoinsClaimed = 0;
  List<_MilestoneTile> _tiles = const [];
  String _claimingThreshold = '';
  String _lastFetchedDate = '';

  Future<void> refresh() => _refresh();

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  @override
  void didUpdateWidget(covariant StepMilestonesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // If today changed underneath us, re-fetch so the UI resets at midnight.
    if (_lastFetchedDate.isNotEmpty && _lastFetchedDate != _todayLocalDate()) {
      _refresh();
    }
  }

  Future<void> _refresh() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }

    final date = _todayLocalDate();
    try {
      final res = await widget.backendApiService.fetchStepMilestonesToday(
        identityToken: token,
        localDate: date,
      );
      if (!mounted) return;
      final milestones = (res['milestones'] as List? ?? [])
          .cast<Map<String, dynamic>>();
      setState(() {
        _loading = false;
        _error = '';
        _currentSteps = (res['currentSteps'] as num?)?.toInt() ?? 0;
        _totalCoinsClaimed = (res['totalCoinsClaimed'] as num?)?.toInt() ?? 0;
        _tiles = milestones
            .map((m) => _MilestoneTile(
                  threshold: (m['threshold'] as num?)?.toInt() ?? 0,
                  coins: (m['coins'] as num?)?.toInt() ?? 0,
                  claimed: m['claimed'] == true,
                  claimable: m['claimable'] == true,
                ))
            .toList(growable: false);
        _lastFetchedDate = date;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _error = e.toString();
      });
    }
  }

  Future<void> _claim(int threshold) async {
    if (_claimingThreshold.isNotEmpty) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    setState(() => _claimingThreshold = '$threshold');
    try {
      final res = await widget.backendApiService.claimStepMilestone(
        identityToken: token,
        localDate: _todayLocalDate(),
        threshold: threshold,
      );
      final coinsAfter = (res['coinsAfter'] as num?)?.toInt();
      if (coinsAfter != null) {
        await widget.authService.updateCoins(coinsAfter);
      }
      await _refresh();
    } catch (_) {
      // On error (e.g. 409 race), force a refresh so the UI matches truth.
      await _refresh();
    } finally {
      if (mounted) setState(() => _claimingThreshold = '');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.fromLTRB(14, 10, 14, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            "Today's coin checkpoints",
            style: PixelText.title(size: 20, color: AppColors.textDark),
          ),
          const SizedBox(height: 4),
          Text(
            'Hit each step threshold today, then tap to claim. Up to 110 coins/day.',
            style: PixelText.body(size: 13, color: AppColors.textMid),
          ),
          if (_totalCoinsClaimed > 0) ...[
            const SizedBox(height: 6),
            Text(
              'Claimed today: $_totalCoinsClaimed / 110 coins',
              style: PixelText.body(size: 13, color: AppColors.accent),
            ),
          ],
          const SizedBox(height: 14),
          if (_loading) ...[
            const SizedBox(
              height: 48,
              child: Center(
                child: SizedBox(
                  width: 22,
                  height: 22,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: AppColors.accent,
                  ),
                ),
              ),
            ),
          ] else if (_error.isNotEmpty && _tiles.isEmpty) ...[
            Text(
              "Couldn't load milestones.",
              style: PixelText.body(size: 13, color: AppColors.textMid),
            ),
          ] else
            ..._buildRows(),
        ],
      ),
    );
  }

  List<Widget> _buildRows() {
    final rows = <Widget>[];
    for (var i = 0; i < _tiles.length; i++) {
      final tile = _tiles[i];
      if (i > 0) {
        rows.add(const SizedBox(height: 12));
        rows.add(Divider(
          height: 1,
          color: HomeColors.line.withValues(alpha: 0.10),
        ));
        rows.add(const SizedBox(height: 12));
      }
      rows.add(_buildTile(tile));
    }
    return rows;
  }

  Widget _buildTile(_MilestoneTile tile) {
    final isClaimed = tile.claimed;
    final isClaimable = tile.claimable;
    final isBusy = _claimingThreshold == '${tile.threshold}';
    final progress = tile.threshold <= 0
        ? 0.0
        : (_currentSteps / tile.threshold).clamp(0.0, 1.0);

    return Row(
      children: [
        Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            color: isClaimed
                ? HomeColors.cream
                : (isClaimable ? HomeColors.cream : HomeColors.surfaceMuted),
            borderRadius: BorderRadius.circular(8),
            border: Border.all(
              color: isClaimed
                  ? HomeColors.success.withValues(alpha: 0.65)
                  : isClaimable
                      ? HomeColors.gold.withValues(alpha: 0.65)
                      : HomeColors.line.withValues(alpha: 0.10),
              width: 2,
            ),
          ),
          child: Center(
            child: isClaimed
                ? const Icon(
                    Icons.check_rounded,
                    size: 24,
                    color: HomeColors.success,
                  )
                : isClaimable
                    ? const SpinningCoin(size: 24)
                    : Icon(
                        Icons.lock_rounded,
                        size: 22,
                        color: HomeColors.muted.withValues(alpha: 0.65),
                      ),
          ),
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                '${_formatCompact(tile.threshold)} STEPS',
                style: HomeText.title(
                  size: 16,
                  color: isClaimed || isClaimable
                      ? HomeColors.ink
                      : HomeColors.muted,
                ),
              ),
              const SizedBox(height: 4),
              ClipRRect(
                borderRadius: BorderRadius.circular(999),
                child: LinearProgressIndicator(
                  value: progress,
                  minHeight: 4,
                  backgroundColor: HomeColors.surfaceMuted,
                  color: isClaimed
                      ? HomeColors.success
                      : (isClaimable ? HomeColors.gold : HomeColors.muted),
                ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 12),
        if (isClaimed)
          Text(
            'CLAIMED',
            style: HomeText.title(size: 13, color: HomeColors.success),
          )
        else if (isClaimable)
          SizedBox(
            width: 90,
            child: PillButton(
              label: isBusy ? '...' : '+${tile.coins}',
              variant: PillButtonVariant.primary,
              fontSize: 13,
              padding: const EdgeInsets.symmetric(
                horizontal: 10,
                vertical: 8,
              ),
              onPressed: isBusy ? null : () => _claim(tile.threshold),
            ),
          )
        else
          Text(
            '+${tile.coins}',
            style: HomeText.title(size: 16, color: HomeColors.muted),
          ),
      ],
    );
  }

  static String _formatCompact(int n) {
    if (n >= 1000) {
      return '${(n / 1000).toStringAsFixed(n % 1000 == 0 ? 0 : 1)}k';
    }
    return '$n';
  }
}

class _MilestoneTile {
  final int threshold;
  final int coins;
  final bool claimed;
  final bool claimable;

  const _MilestoneTile({
    required this.threshold,
    required this.coins,
    required this.claimed,
    required this.claimable,
  });
}
