import 'package:flutter/material.dart';

import '../models/race_payouts.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/race_participant_display.dart';
import 'celebration_confetti.dart';
import 'race_ui.dart';
import 'spinning_coin.dart';

/// One occupied step of the podium.
@immutable
class PodiumFinisher {
  const PodiumFinisher({
    required this.placement,
    required this.displayName,
    this.totalSteps,
    this.accessories = const <Map<String, dynamic>>[],
    this.animal,
    this.payoutCoins,
    this.isViewer = false,
  });

  /// 1, 2 or 3.
  final int placement;
  final String displayName;

  /// Null when the payload didn't carry a step total — the line is then
  /// omitted rather than showing a fake 0.
  final int? totalSteps;
  final List<Map<String, dynamic>> accessories;
  final String? animal;

  /// Null or 0 → no coin line (an unfunded race pays nobody).
  final int? payoutCoins;
  final bool isViewer;
}

/// Fun-Run-style 1st/2nd/3rd podium for a finished SOLO (classic) race
/// (batch 2026-08-08, Item 4). Team races keep their winning-team board and
/// tournaments keep their own flow — neither routes through here.
///
/// Everything is read defensively by [finishersFromParticipants]: a race that
/// finished with two runners renders two platforms, and a payload missing
/// steps, accessories, animal or payouts still renders a sensible podium.
/// The DEMO race's completed fixture (`demo_race_engine.dart`) carries only
/// userId/displayName/totalSteps/accessories, which is exactly enough.
class RacePodium extends StatefulWidget {
  const RacePodium({
    super.key,
    required this.finishers,
    this.showConfetti = false,
  });

  /// Ordered 1st, 2nd, 3rd. Length 2 or 3 — see [canRender].
  final List<PodiumFinisher> finishers;

  /// Fires the shared happy-moment confetti behind the podium on entrance.
  /// The results popup already fires it at screen level, so only the race
  /// detail screen turns this on — two overlapping bursts read as a glitch.
  final bool showConfetti;

  /// A podium needs at least a 1st and a 2nd to read as a podium. A single
  /// finisher keeps the existing winner card — one lonely plinth looks broken.
  static bool canRender(int finisherCount) => finisherCount >= 2;

  /// Builds the top-3 finishers from a race's participant rows.
  ///
  /// [participants] must already be ordered for display (i.e. through
  /// [orderRaceParticipantsForDisplay]) — a completed race has no stealth
  /// masking left, so that ordering is the true finishing order. Item 18's
  /// ordering fix is what makes this safe; before it, a race that ran with
  /// stealth active could hand us a mis-ranked top three.
  static List<PodiumFinisher> finishersFromParticipants(
    List<Map<String, dynamic>> participants, {
    List<PayoutTier> payoutTiers = const [],
    String? viewerUserId,
  }) {
    final finishers = <PodiumFinisher>[];
    for (var i = 0; i < participants.length && i < 3; i++) {
      final p = participants[i];
      final placement = serverPlacementOf(p) ?? (i + 1);
      final name = p['displayName'];
      final steps = p['totalSteps'];
      final rawAccessories = p['accessories'];
      final userId = p['userId'];

      int? payout;
      for (final tier in payoutTiers) {
        if (tier.placement == placement) {
          payout = tier.amount;
          break;
        }
      }

      finishers.add(
        PodiumFinisher(
          // Clamp: a server placement of 4+ on a top-3 row would index off the
          // end of the platform geometry.
          placement: (placement >= 1 && placement <= 3) ? placement : i + 1,
          displayName: name is String && name.isNotEmpty ? name : '???',
          totalSteps: steps is num ? steps.toInt() : null,
          accessories:
              (rawAccessories is List)
                  ? rawAccessories.whereType<Map>().map((e) {
                      return e.cast<String, dynamic>();
                    }).toList()
                  : const <Map<String, dynamic>>[],
          animal: p['animal'] is String ? p['animal'] as String : null,
          payoutCoins: payout,
          isViewer: viewerUserId != null && userId == viewerUserId,
        ),
      );
    }
    return finishers;
  }

  @override
  State<RacePodium> createState() => _RacePodiumState();
}

class _RacePodiumState extends State<RacePodium>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 720),
  );

  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    // Respect the platform's reduce-motion setting: the podium is information,
    // the rise is decoration.
    if (MediaQuery.disableAnimationsOf(context)) {
      _controller.value = 1;
    } else {
      _controller.forward();
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // Platform heights: the winner stands a clear head above the other two, and
  // 2nd outranks 3rd by a smaller step.
  static const Map<int, double> _blockHeight = {1: 74, 2: 54, 3: 42};

  Color _blockColor(BuildContext context, int placement) {
    final colors = AppColors.of(context);
    return switch (placement) {
      1 => colors.medalGold,
      2 => colors.medalSilver,
      _ => colors.medalBronze,
    };
  }

  @override
  Widget build(BuildContext context) {
    final byPlacement = <int, PodiumFinisher>{};
    for (final f in widget.finishers) {
      byPlacement.putIfAbsent(f.placement, () => f);
    }

    // Visual order: 2nd left, 1st centre, 3rd right. A missing placement
    // simply leaves that side out (2 finishers → 1st + 2nd, no empty plinth).
    final columns = <Widget>[];
    for (final placement in const [2, 1, 3]) {
      final finisher = byPlacement[placement];
      if (finisher == null) continue;
      if (columns.isNotEmpty) columns.add(const SizedBox(width: 8));
      columns.add(Expanded(child: _buildColumn(context, finisher)));
    }

    final podium = Row(
      crossAxisAlignment: CrossAxisAlignment.end,
      children: columns,
    );

    if (!widget.showConfetti) return podium;
    return Stack(
      clipBehavior: Clip.none,
      alignment: Alignment.topCenter,
      children: [
        podium,
        const Positioned.fill(child: IgnorePointer(child: CelebrationConfetti())),
      ],
    );
  }

  Widget _buildColumn(BuildContext context, PodiumFinisher finisher) {
    final colors = AppColors.of(context);
    final placement = finisher.placement;
    final isWinner = placement == 1;
    final blockColor = _blockColor(context, placement);

    // Staggered rise: the winner lands first, the flanks follow.
    final start = switch (placement) {
      1 => 0.0,
      2 => 0.14,
      _ => 0.28,
    };
    final animation = CurvedAnimation(
      parent: _controller,
      curve: Interval(start, (start + 0.6).clamp(0.0, 1.0), curve: Curves.easeOutBack),
    );

    final payout = finisher.payoutCoins ?? 0;

    return AnimatedBuilder(
      animation: animation,
      builder: (context, child) {
        final t = animation.value.clamp(0.0, 1.0);
        return Opacity(
          opacity: t,
          child: Transform.translate(offset: Offset(0, (1 - t) * 22), child: child),
        );
      },
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          RacerAvatar(
            rank: placement,
            accessories: finisher.accessories,
            animal: finisher.animal,
            size: isWinner ? 62 : 48,
          ),
          const SizedBox(height: 6),
          Text(
            finisher.isViewer
                ? '${atName(finisher.displayName)} (you)'
                : atName(finisher.displayName),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: PixelText.title(
              size: isWinner ? 14 : 12.5,
              color: finisher.isViewer ? colors.textAccent : colors.textDark,
            ),
          ),
          if (finisher.totalSteps != null) ...[
            const SizedBox(height: 1),
            Text(
              _formatSteps(finisher.totalSteps!),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: PixelText.number(size: isWinner ? 14 : 12, color: colors.textMid),
            ),
          ],
          if (payout > 0) ...[
            const SizedBox(height: 3),
            Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const SpinningCoin(size: 13),
                const SizedBox(width: 3),
                Flexible(
                  child: Text(
                    '+$payout',
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.number(size: 13, color: colors.coinDark),
                  ),
                ),
              ],
            ),
          ],
          const SizedBox(height: 6),
          // The plinth. Hard offset shadow + carved numeral, matching the
          // app's pill/plaque chrome rather than a Material elevation.
          Container(
            height: _blockHeight[placement] ?? 42,
            width: double.infinity,
            alignment: Alignment.topCenter,
            padding: const EdgeInsets.only(top: 7),
            decoration: BoxDecoration(
              color: blockColor.withValues(alpha: 0.30),
              borderRadius: const BorderRadius.vertical(top: Radius.circular(7)),
              border: Border.all(color: blockColor.withValues(alpha: 0.95), width: 2),
              boxShadow: [
                BoxShadow(
                  color: colors.woodShadow.withValues(alpha: 0.35),
                  offset: const Offset(0, 3),
                  blurRadius: 0,
                ),
              ],
            ),
            child: Text(
              formatOrdinal(placement),
              style: PixelText.title(
                size: isWinner ? 15 : 13,
                color: colors.textDark,
              ),
            ),
          ),
        ],
      ),
    );
  }

  static String _formatSteps(int steps) {
    final s = steps.toString();
    final buffer = StringBuffer();
    for (var i = 0; i < s.length; i++) {
      if (i > 0 && (s.length - i) % 3 == 0) buffer.write(',');
      buffer.write(s[i]);
    }
    return buffer.toString();
  }
}
