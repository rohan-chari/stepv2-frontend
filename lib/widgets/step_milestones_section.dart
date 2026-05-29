import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/home_chrome.dart';
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
            .map(
              (m) => _MilestoneTile(
                threshold: (m['threshold'] as num?)?.toInt() ?? 0,
                coins: (m['coins'] as num?)?.toInt() ?? 0,
                claimed: m['claimed'] == true,
                claimable: m['claimable'] == true,
              ),
            )
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
      padding: const EdgeInsets.fromLTRB(16, 6, 16, 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _buildHeader(),
          const SizedBox(height: 12),
          _buildCard(),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    final cap = _tiles.fold<int>(0, (sum, t) => sum + t.coins);
    return Row(
      children: [
        const SpinningCoin(size: 22),
        const SizedBox(width: 8),
        Text(
          "Today's coins",
          style: PixelText.title(size: 22, color: AppColors.textDark),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.parchment,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.parchmentBorder.withValues(alpha: 0.9),
            ),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$_totalCoinsClaimed',
                  style: PixelText.title(size: 14, color: AppColors.coinDark),
                ),
                TextSpan(
                  text: ' / ${cap == 0 ? 110 : cap}',
                  style: PixelText.title(size: 14, color: AppColors.textMid),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildCard() {
    Widget body;
    if (_loading && _tiles.isEmpty) {
      body = const SizedBox(
        height: 96,
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
      );
    } else if (_error.isNotEmpty && _tiles.isEmpty) {
      body = Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Center(
          child: Text(
            "Couldn't load milestones.",
            style: PixelText.body(size: 13, color: AppColors.textMid),
          ),
        ),
      );
    } else {
      body = Column(
        children: [
          _buildTrack(),
          const SizedBox(height: 16),
          Container(
            height: 1,
            color: AppColors.parchmentBorder.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          _buildFooter(),
        ],
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.roofDark.withValues(alpha: 0.55),
          width: 2,
        ),
      ),
      padding: const EdgeInsets.fromLTRB(16, 18, 16, 14),
      child: body,
    );
  }

  Widget _buildTrack() {
    final nodes = <Widget>[];
    for (var i = 0; i < _tiles.length; i++) {
      if (i > 0) {
        nodes.add(Expanded(child: _connector(filled: _tiles[i - 1].claimed)));
      }
      nodes.add(_node(_tiles[i]));
    }
    return Row(crossAxisAlignment: CrossAxisAlignment.start, children: nodes);
  }

  Widget _connector({required bool filled}) {
    return Padding(
      // Align with the vertical center of the 56px node circle.
      padding: const EdgeInsets.only(top: 26.5),
      child: Container(
        height: 3,
        color: filled
            ? HomeColors.success
            : AppColors.parchmentBorder.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _node(_MilestoneTile tile) {
    final isClaimed = tile.claimed;
    final isClaimable = tile.claimable;
    final isBusy = _claimingThreshold == '${tile.threshold}';
    final color = isClaimed
        ? HomeColors.success
        : isClaimable
        ? HomeColors.gold
        : HomeColors.muted;

    final circle = Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isClaimed
            ? color.withValues(alpha: 0.16)
            : isClaimable
            ? color.withValues(alpha: 0.22)
            : AppColors.parchmentDark.withValues(alpha: 0.5),
        shape: BoxShape.circle,
        border: Border.all(
          color: isClaimable ? color : color.withValues(alpha: isClaimed ? 1 : 0.45),
          width: isClaimable ? 3 : 2,
        ),
        boxShadow: isClaimable
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: isClaimed
          ? Icon(Icons.check_rounded, size: 26, color: color)
          : isClaimable
          ? (isBusy
                ? SizedBox(
                    width: 22,
                    height: 22,
                    child: CircularProgressIndicator(strokeWidth: 2, color: color),
                  )
                : const SpinningCoin(size: 34))
          : const Icon(Icons.lock_rounded, size: 20, color: HomeColors.muted),
    );

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        GestureDetector(
          onTap: isClaimable && !isBusy ? () => _claim(tile.threshold) : null,
          behavior: HitTestBehavior.opaque,
          child: circle,
        ),
        const SizedBox(height: 7),
        Text(
          _formatCompact(tile.threshold),
          style: PixelText.title(
            size: 15,
            color: isClaimed || isClaimable
                ? AppColors.textDark
                : AppColors.textMid,
          ),
        ),
        const SizedBox(height: 1),
        if (isClaimable)
          Text('TAP!', style: PixelText.title(size: 11, color: HomeColors.gold))
        else
          Text(
            '+${tile.coins}',
            style: PixelText.body(
              size: 12,
              color: isClaimed ? HomeColors.success : AppColors.textMid,
            ),
          ),
      ],
    );
  }

  Widget _buildFooter() {
    _MilestoneTile? next;
    for (final t in _tiles) {
      if (!t.claimed) {
        next = t;
        break;
      }
    }
    final stepsToNext = next == null ? 0 : (next.threshold - _currentSteps);

    return Row(
      mainAxisAlignment: MainAxisAlignment.spaceBetween,
      children: [
        Flexible(
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: _formatWithCommas(_currentSteps),
                  style: PixelText.title(size: 14, color: AppColors.textDark),
                ),
                TextSpan(
                  text: ' steps today',
                  style: PixelText.body(size: 13, color: AppColors.textMid),
                ),
              ],
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        const SizedBox(width: 10),
        if (next != null && stepsToNext > 0)
          Flexible(
            child: Text.rich(
              TextSpan(
                children: [
                  TextSpan(
                    text: _formatWithCommas(stepsToNext),
                    style: PixelText.title(size: 14, color: AppColors.textDark),
                  ),
                  TextSpan(
                    text: ' to ${_formatCompact(next.threshold)}',
                    style: PixelText.body(size: 13, color: AppColors.textMid),
                  ),
                ],
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.right,
            ),
          )
        else
          Text(
            'All milestones hit!',
            style: PixelText.body(size: 13, color: HomeColors.success),
          ),
      ],
    );
  }

  static String _formatWithCommas(int n) {
    final s = n.toString();
    final buf = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buf.write(',');
      buf.write(s[i]);
    }
    return buf.toString();
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
