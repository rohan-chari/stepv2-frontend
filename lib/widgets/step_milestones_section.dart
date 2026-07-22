import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/spinning_coin.dart';

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

/// Step-milestone daily rewards. Renders four tiers (5k/10k/15k/20k) with
/// locked/claimable/claimed state and a tap-to-claim button on each row.
/// Fed by the home race-card batch via [initialData] (so it appears with the
/// rest of the page); self-fetches `/users/me/step-milestones/today` only as
/// a fallback for old backends. Refreshes via [refresh] (parent
/// pull-to-refresh).
class StepMilestonesSection extends StatefulWidget {
  const StepMilestonesSection({
    super.key,
    required this.authService,
    required this.backendApiService,
    this.currentSteps,
    this.initialData,
    this.awaitingBatch = false,
  });

  final AuthService authService;
  final BackendApiService backendApiService;

  /// Optional hint from the parent's already-fetched step total; used as a
  /// best-guess until the server response arrives.
  final int? currentSteps;

  /// Milestones payload from the home race-card batch (`stepMilestones`, same
  /// shape as the standalone endpoint). When present, no extra request is
  /// made — the card renders in the same frame as the rest of the home page.
  final Map<String, dynamic>? initialData;

  /// True while the home batch is still in flight. Holds off the fallback
  /// self-fetch so we don't fire the extra request the batch was meant to
  /// replace; the fallback runs only if the batch lands without the field
  /// (old backend) or fails.
  final bool awaitingBatch;

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
    _consumeBatchOrFetch();
  }

  @override
  void didUpdateWidget(covariant StepMilestonesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Batch landed (or its payload changed): consume it, or fall back to the
    // standalone fetch when the batch came back without the field.
    if (!identical(oldWidget.initialData, widget.initialData) ||
        (oldWidget.awaitingBatch && !widget.awaitingBatch)) {
      _consumeBatchOrFetch();
      return;
    }
    // If today changed underneath us, re-fetch so the UI resets at midnight.
    if (_lastFetchedDate.isNotEmpty && _lastFetchedDate != _todayLocalDate()) {
      _refresh();
    }
  }

  void _consumeBatchOrFetch() {
    final data = widget.initialData;
    if (data != null) {
      _applyData(data);
    } else if (!widget.awaitingBatch) {
      // Old backend (no embedded stepMilestones) or batch failure: standalone
      // fetch, same as before the batching change.
      _refresh();
    }
    // else: batch still in flight — didUpdateWidget consumes it when it lands.
  }

  void _applyData(Map<String, dynamic> res) {
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
      _lastFetchedDate = res['localDate'] as String? ?? _todayLocalDate();
    });
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
      _applyData(res);
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
        children: [_buildHeader(), const SizedBox(height: 12), _buildCard()],
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
          // Light on the home tab's dark felt backdrop.
          style: PixelText.title(
            size: 22,
            color: AppColors.of(context).textLight,
          ),
        ),
        const Spacer(),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
          decoration: BoxDecoration(
            color: AppColors.of(context).parchment,
            borderRadius: BorderRadius.circular(999),
            border: Border.all(
              color: AppColors.of(
                context,
              ).parchmentBorder.withValues(alpha: 0.9),
            ),
          ),
          child: Text.rich(
            TextSpan(
              children: [
                TextSpan(
                  text: '$_totalCoinsClaimed',
                  style: PixelText.title(
                    size: 14,
                    color: AppColors.of(context).coinDark,
                  ),
                ),
                TextSpan(
                  text: ' / ${cap == 0 ? 110 : cap}',
                  style: PixelText.title(
                    size: 14,
                    color: AppColors.of(context).textMid,
                  ),
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
      body = SizedBox(
        height: 96,
        child: Center(
          child: SizedBox(
            width: 22,
            height: 22,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.of(context).accent,
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
            style: PixelText.body(
              size: 13,
              color: AppColors.of(context).textMid,
            ),
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
            color: AppColors.of(context).parchmentBorder.withValues(alpha: 0.6),
          ),
          const SizedBox(height: 12),
          _buildFooter(),
        ],
      );
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: AppColors.of(context).parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
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
            ? AppColors.of(context).success
            : AppColors.of(context).parchmentBorder.withValues(alpha: 0.6),
      ),
    );
  }

  Widget _node(_MilestoneTile tile) {
    final isClaimed = tile.claimed;
    final isClaimable = tile.claimable;
    final isBusy = _claimingThreshold == '${tile.threshold}';
    final color = isClaimed
        ? AppColors.of(context).success
        : isClaimable
        ? AppColors.of(context).gold
        : AppColors.of(context).muted;

    final circle = Container(
      width: 56,
      height: 56,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: isClaimed
            ? color.withValues(alpha: 0.16)
            : isClaimable
            ? color.withValues(alpha: 0.22)
            : AppColors.of(context).parchmentDark.withValues(alpha: 0.5),
        shape: BoxShape.circle,
        border: Border.all(
          color: isClaimable
              ? color
              : color.withValues(alpha: isClaimed ? 1 : 0.45),
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
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      color: color,
                    ),
                  )
                : const SpinningCoin(size: 34))
          : Icon(
              Icons.lock_rounded,
              size: 20,
              color: AppColors.of(context).textMid,
            ),
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
                ? AppColors.of(context).textDark
                : AppColors.of(context).textMid,
          ),
        ),
        const SizedBox(height: 1),
        if (isClaimable)
          Text(
            'TAP!',
            style: PixelText.title(size: 11, color: AppColors.of(context).gold),
          )
        else
          Text(
            '+${tile.coins}',
            style: PixelText.body(
              size: 12,
              color: isClaimed
                  ? AppColors.of(context).success
                  : AppColors.of(context).textMid,
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
                  style: PixelText.title(
                    size: 14,
                    color: AppColors.of(context).textDark,
                  ),
                ),
                TextSpan(
                  text: ' steps today',
                  style: PixelText.body(
                    size: 13,
                    color: AppColors.of(context).textMid,
                  ),
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
                    style: PixelText.title(
                      size: 14,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                  TextSpan(
                    text: ' to ${_formatCompact(next.threshold)}',
                    style: PixelText.body(
                      size: 13,
                      color: AppColors.of(context).textMid,
                    ),
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
            style: PixelText.body(
              size: 13,
              color: AppColors.of(context).success,
            ),
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
