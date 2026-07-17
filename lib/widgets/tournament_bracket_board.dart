import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/tournament.dart';
import '../utils/tournament_bracket.dart';
import 'app_avatar.dart';
import 'tournament_sponsor_card.dart';

/// A pannable / zoomable March-Madness bracket rendered on the app's checkered
/// green arcade grid — the grid IS the draggable board. Rounds progress
/// left-to-right (leaves → champion crown), joined by carved elbow connectors.
///
/// Pure presentation: it takes a normalized [BracketModel] and calls back on a
/// tap of the viewer's own live matchup. Everything degrades safely when the
/// model is empty.
class TournamentBracketBoard extends StatefulWidget {
  const TournamentBracketBoard({
    super.key,
    required this.model,
    this.onTapMyMatchup,
    this.onTapMatchup,
    this.stepFormatter,
  });

  final BracketModel model;

  /// Called with the raceId when the viewer taps their own live matchup box
  /// (opens the race to play).
  final void Function(String raceId)? onTapMyMatchup;

  /// Called with the raceId when the viewer taps ANY other matchup box that has
  /// a race (opens that race read-only to spectate).
  final void Function(String raceId)? onTapMatchup;

  /// Formats a step count for a live slot (e.g. 12,340 → "12.3k").
  final String Function(int steps)? stepFormatter;

  // -- Layout constants (logical px, pre-zoom) ------------------------------
  static const double cardW = 158;
  static const double slotH = 34;
  static const double boxPad = 7;
  static const double boxH = slotH * 2 + boxPad * 2 + 3; // two slots + divider
  static const double leafGap = 30;
  static const double leafPitch = boxH + leafGap;
  static const double colGap = 52;
  static const double colW = cardW + colGap;
  static const double topPad = 58;
  static const double sidePad = 26;
  static const double champW = 148;

  @override
  State<TournamentBracketBoard> createState() => _TournamentBracketBoardState();
}

class _TournamentBracketBoardState extends State<TournamentBracketBoard> {
  final TransformationController _controller = TransformationController();
  bool _centered = false;
  bool _showHint = true;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  // -- Geometry -------------------------------------------------------------

  /// Center offset of each matchup keyed by (round, matchIndex).
  final Map<(int, int), Offset> _centers = {};
  Offset _championCenter = Offset.zero;
  Size _canvasSize = Size.zero;

  void _computeGeometry() {
    _centers.clear();
    final model = widget.model;
    final size = model.bracketSize;
    final rounds = model.totalRounds;
    if (model.isEmpty) {
      _canvasSize = Size.zero;
      return;
    }
    final leafCount = BracketModel.matchupsInRound(size, 1);

    for (var r = 1; r <= rounds; r++) {
      final count = BracketModel.matchupsInRound(size, r);
      final x = TournamentBracketBoard.sidePad +
          (r - 1) * TournamentBracketBoard.colW +
          TournamentBracketBoard.cardW / 2;
      for (var i = 0; i < count; i++) {
        double cy;
        if (r == 1) {
          cy = TournamentBracketBoard.topPad +
              TournamentBracketBoard.boxH / 2 +
              i * TournamentBracketBoard.leafPitch;
        } else {
          final a = _centers[(r - 1, 2 * i)]!;
          final b = _centers[(r - 1, 2 * i + 1)]!;
          cy = (a.dy + b.dy) / 2;
        }
        _centers[(r, i)] = Offset(x, cy);
      }
    }

    final finalCenter = _centers[(rounds, 0)]!;
    _championCenter = Offset(
      TournamentBracketBoard.sidePad +
          rounds * TournamentBracketBoard.colW +
          TournamentBracketBoard.champW / 2,
      finalCenter.dy,
    );

    _canvasSize = Size(
      TournamentBracketBoard.sidePad * 2 +
          rounds * TournamentBracketBoard.colW +
          TournamentBracketBoard.champW,
      TournamentBracketBoard.topPad * 2 +
          leafCount * TournamentBracketBoard.leafPitch,
    );
  }

  /// The matchup to center the initial view on: my live/own matchup if any,
  /// else the first leaf.
  Offset _initialFocus() {
    for (final round in widget.model.rounds) {
      for (final m in round) {
        if (m.isMine) return _centers[(m.round, m.matchIndex)] ?? Offset.zero;
      }
    }
    return _centers[(1, 0)] ?? Offset.zero;
  }

  void _centerOn(Offset target, Size viewport) {
    // Slightly zoomed out so the surrounding bracket gives context.
    const scale = 0.92;
    final tx = viewport.width / 2 - target.dx * scale;
    final ty = viewport.height / 2 - target.dy * scale;
    // Compose screen = scale * point + translation directly (avoids the
    // deprecated Matrix4.translate/scale helpers).
    _controller.value = Matrix4.identity()
      ..setEntry(0, 0, scale)
      ..setEntry(1, 1, scale)
      ..setEntry(2, 2, scale)
      ..setEntry(0, 3, tx)
      ..setEntry(1, 3, ty);
  }

  @override
  Widget build(BuildContext context) {
    _computeGeometry();
    final model = widget.model;
    if (model.isEmpty) {
      return const SizedBox.shrink();
    }

    return LayoutBuilder(
      builder: (context, constraints) {
        final viewport = Size(constraints.maxWidth, constraints.maxHeight);
        if (!_centered && viewport.width > 0 && viewport.height > 0) {
          _centered = true;
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) _centerOn(_initialFocus(), viewport);
          });
        }

        return ClipRect(
          child: Stack(
            children: [
              // The checkered green arcade grid fills the whole viewport as a
              // base so edges never show bare while dragging.
              const Positioned.fill(
                child: ColoredBox(
                  color: AppColors.roofLight,
                  child: CustomPaint(
                    painter: ArcadeCheckerPainter(drawBottomStripe: false),
                  ),
                ),
              ),
              InteractiveViewer(
                transformationController: _controller,
                panEnabled: true,
                scaleEnabled: true,
                constrained: false,
                minScale: 0.6,
                maxScale: 1.5,
                boundaryMargin: const EdgeInsets.all(160),
                onInteractionStart: (_) {
                  if (_showHint) setState(() => _showHint = false);
                },
                child: SizedBox(
                  width: _canvasSize.width,
                  height: _canvasSize.height,
                  child: _buildCanvas(),
                ),
              ),
              if (_showHint)
                Positioned(
                  left: 0,
                  right: 0,
                  bottom: 12,
                  child: Center(child: _dragHint()),
                ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildCanvas() {
    final model = widget.model;
    final children = <Widget>[
      // The checkered grid ALSO tiles the full canvas so it pans/zooms with the
      // bracket — dragging moves the board, not just the cards.
      Positioned.fill(
        child: CustomPaint(
          painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        ),
      ),
      // Connector elbows behind the cards.
      Positioned.fill(
        child: CustomPaint(
          painter: _ConnectorPainter(
            centers: _centers,
            championCenter: _championCenter,
            model: model,
          ),
        ),
      ),
    ];

    // Round labels.
    for (var r = 1; r <= model.totalRounds; r++) {
      final x = TournamentBracketBoard.sidePad +
          (r - 1) * TournamentBracketBoard.colW;
      children.add(
        Positioned(
          left: x,
          top: 18,
          width: TournamentBracketBoard.cardW,
          child: _roundLabel(Tournament.roundLabelFor(model.bracketSize, r)),
        ),
      );
    }
    children.add(
      Positioned(
        left: TournamentBracketBoard.sidePad +
            model.totalRounds * TournamentBracketBoard.colW,
        top: 18,
        width: TournamentBracketBoard.champW,
        child: _roundLabel('CHAMPION'),
      ),
    );

    // Matchup boxes.
    for (final round in model.rounds) {
      for (final m in round) {
        final c = _centers[(m.round, m.matchIndex)];
        if (c == null) continue;
        children.add(
          Positioned(
            left: c.dx - TournamentBracketBoard.cardW / 2,
            top: c.dy - TournamentBracketBoard.boxH / 2,
            width: TournamentBracketBoard.cardW,
            child: _matchupBox(m),
          ),
        );
      }
    }

    // Champion cap.
    children.add(
      Positioned(
        left: _championCenter.dx - TournamentBracketBoard.champW / 2,
        top: _championCenter.dy - 44,
        width: TournamentBracketBoard.champW,
        child: _championNode(model.champion),
      ),
    );

    // "Presented by" sponsor card tucked under the champion cap — a labeled,
    // policy-compliant native ad (gated by the remote kill switch; renders
    // nothing when off, a house ad when there's no fill). Pans/zooms with the
    // board so it reads as part of the finals frame.
    const sponsorW = 220.0;
    children.add(
      Positioned(
        left: _championCenter.dx - sponsorW / 2,
        top: _championCenter.dy + 44 + 14,
        width: sponsorW,
        child: const TournamentSponsorCard(width: sponsorW),
      ),
    );

    return Stack(clipBehavior: Clip.none, children: children);
  }

  // -- Round label ----------------------------------------------------------

  Widget _roundLabel(String text) {
    return Center(
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
        decoration: BoxDecoration(
          color: AppColors.roofDark.withValues(alpha: 0.62),
          borderRadius: BorderRadius.circular(999),
          border: Border.all(color: AppColors.roofEdge, width: 1.5),
        ),
        child: Text(
          text,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: PixelText.title(size: 11, color: AppColors.parchment),
        ),
      ),
    );
  }

  // -- Matchup box ----------------------------------------------------------

  Widget _matchupBox(BracketMatchup m) {
    final mine = m.isMine;
    final live = m.liveForMe;
    final borderColor = mine ? AppColors.pillGoldDark : AppColors.parchmentBorder;

    final box = Container(
      decoration: BoxDecoration(
        color: AppColors.parchment,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: borderColor, width: mine ? 2.5 : 1.5),
        boxShadow: [
          BoxShadow(
            color: mine
                ? AppColors.pillGoldShadow.withValues(alpha: 0.55)
                : const Color(0x55000000),
            offset: const Offset(0, 3),
            blurRadius: mine ? 6 : 0,
          ),
        ],
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          _slotRow(m.top, top: true),
          Container(height: 1.5, color: AppColors.parchmentBorder),
          _slotRow(m.bottom, top: false),
        ],
      ),
    );

    final raceId = m.raceId;
    final hasRace = raceId != null && raceId.isNotEmpty;

    // My live matchup: play it — the loud gold "TAP TO RACE" ribbon.
    if (live && hasRace) {
      return GestureDetector(
        onTap: () => widget.onTapMyMatchup?.call(raceId),
        child: _ribboned(box, _tapRibbon()),
      );
    }

    // Any other matchup with a race: spectate it read-only. Live ones get a
    // subtle "WATCH" ribbon; a completed matchup stays tappable (to review the
    // result) without the ribbon — its winner check already reads.
    if (hasRace) {
      final child = m.completed
          ? box
          : _ribboned(box, _watchRibbon());
      return GestureDetector(
        onTap: () => widget.onTapMatchup?.call(raceId),
        child: child,
      );
    }

    return box;
  }

  Widget _ribboned(Widget box, Widget ribbon) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        box,
        Transform.translate(offset: const Offset(0, -2), child: ribbon),
      ],
    );
  }

  Widget _tapRibbon() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
      decoration: BoxDecoration(
        gradient: const LinearGradient(
          colors: [AppColors.pillGold, AppColors.pillGoldDark],
        ),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.pillGoldShadow, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.sports_esports_rounded,
              size: 12, color: AppColors.textDark),
          const SizedBox(width: 4),
          Text('TAP TO RACE',
              style: PixelText.title(size: 10, color: AppColors.textDark)),
        ],
      ),
    );
  }

  Widget _watchRibbon() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2.5),
      decoration: BoxDecoration(
        color: AppColors.roofDark.withValues(alpha: 0.9),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.roofEdge, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.visibility_rounded,
              size: 11, color: Colors.white.withValues(alpha: 0.85)),
          const SizedBox(width: 4),
          Text('WATCH',
              style: PixelText.title(
                  size: 9, color: Colors.white.withValues(alpha: 0.9))),
        ],
      ),
    );
  }

  Widget _slotRow(BracketSlot slot, {required bool top}) {
    switch (slot.state) {
      case BracketSlotState.open:
        return _emptySlot('OPEN', faded: false);
      case BracketSlotState.tbd:
        return _emptySlot('TBD', faded: true);
      case BracketSlotState.filled:
      case BracketSlotState.winner:
      case BracketSlotState.eliminated:
      case BracketSlotState.champion:
        return _filledSlot(slot);
    }
  }

  Widget _emptySlot(String label, {required bool faded}) {
    return SizedBox(
      height: TournamentBracketBoard.slotH,
      child: Center(
        child: Text(
          label,
          style: PixelText.title(
            size: 11,
            color: faded
                ? AppColors.textMid.withValues(alpha: 0.5)
                : AppColors.textMid,
          ),
        ),
      ),
    );
  }

  Widget _filledSlot(BracketSlot slot) {
    final won = slot.state == BracketSlotState.winner;
    final out = slot.state == BracketSlotState.eliminated;
    final name = slot.displayName ?? '???';
    final p = slot.participant;
    final avatarUrl = p?['avatar'] as String?;

    final nameStyle = PixelText.body(
      size: 12.5,
      color: out ? AppColors.textMid : AppColors.textDark,
    ).copyWith(
      decoration: out ? TextDecoration.lineThrough : null,
      fontWeight: (won || slot.isMe) ? FontWeight.w800 : FontWeight.w600,
    );

    return Opacity(
      opacity: out ? 0.62 : 1,
      child: Container(
        height: TournamentBracketBoard.slotH,
        padding: const EdgeInsets.symmetric(horizontal: 6),
        decoration: won
            ? BoxDecoration(color: AppColors.pillGold.withValues(alpha: 0.22))
            : null,
        child: Row(
          children: [
            SizedBox(
              width: 24,
              height: 24,
              child: AppAvatar(
                name: name,
                imageUrl: avatarUrl,
                size: 24,
                isUser: slot.isMe,
              ),
            ),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                atName(name),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: nameStyle,
              ),
            ),
            if (slot.forfeited)
              const Padding(
                padding: EdgeInsets.only(left: 3),
                child: Icon(Icons.flag_rounded, size: 12, color: AppColors.error),
              )
            else if (won)
              const Icon(Icons.check_circle_rounded,
                  size: 14, color: AppColors.roofLight)
            else if (slot.stealthed)
              Text(
                '???',
                style: PixelText.body(size: 10.5, color: AppColors.textMid),
              )
            else if (slot.steps > 0)
              Text(
                _fmt(slot.steps),
                style: PixelText.body(size: 10.5, color: AppColors.textMid),
              ),
          ],
        ),
      ),
    );
  }

  // -- Champion node --------------------------------------------------------

  Widget _championNode(BracketSlot champ) {
    final crowned = champ.state == BracketSlotState.champion;
    final name = champ.displayName;
    return Container(
      height: 88,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: crowned
            ? const LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [AppColors.pillGold, AppColors.pillGoldDark],
              )
            : null,
        color: crowned ? null : AppColors.parchmentDark.withValues(alpha: 0.55),
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: crowned ? AppColors.pillGoldShadow : AppColors.parchmentBorder,
          width: crowned ? 2.5 : 1.5,
        ),
        boxShadow: crowned
            ? const [
                BoxShadow(color: AppColors.pillGoldShadow, offset: Offset(0, 4)),
              ]
            : null,
      ),
      // Champion is conveyed by the gold gradient + a "CHAMPION" eyebrow over
      // the name — no crown glyph.
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Text(
            'CHAMPION',
            style: PixelText.title(
              size: crowned ? 10 : 13,
              color: crowned
                  ? AppColors.textDark.withValues(alpha: 0.75)
                  : AppColors.textMid,
            ),
          ),
          if (crowned && name != null) ...[
            const SizedBox(height: 3),
            Text(
              atName(name),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: PixelText.title(size: 15, color: AppColors.textDark),
            ),
          ],
        ],
      ),
    );
  }

  Widget _dragHint() {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      decoration: BoxDecoration(
        color: AppColors.roofDark.withValues(alpha: 0.82),
        borderRadius: BorderRadius.circular(999),
        border: Border.all(color: AppColors.roofEdge, width: 1.5),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Icon(Icons.pan_tool_rounded, size: 13, color: AppColors.parchment),
          const SizedBox(width: 6),
          Text('Drag to explore the bracket',
              style: PixelText.body(size: 12, color: AppColors.parchment)),
        ],
      ),
    );
  }

  String _fmt(int n) {
    if (widget.stepFormatter != null) return widget.stepFormatter!(n);
    if (n >= 1000) {
      final k = n / 1000;
      return '${k.toStringAsFixed(k >= 10 ? 0 : 1)}k';
    }
    return '$n';
  }
}

/// Draws the carved elbow connectors joining each matchup to the next round's
/// slot, and the final matchup to the champion cap.
class _ConnectorPainter extends CustomPainter {
  _ConnectorPainter({
    required this.centers,
    required this.championCenter,
    required this.model,
  });

  final Map<(int, int), Offset> centers;
  final Offset championCenter;
  final BracketModel model;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = AppColors.roofEdge.withValues(alpha: 0.85)
      ..strokeWidth = 3
      ..style = PaintingStyle.stroke
      ..strokeCap = StrokeCap.round;
    final halfCard = TournamentBracketBoard.cardW / 2;

    for (var r = 1; r < model.totalRounds; r++) {
      final count = BracketModel.matchupsInRound(model.bracketSize, r);
      for (var i = 0; i < count; i++) {
        final from = centers[(r, i)];
        final to = centers[(r + 1, i ~/ 2)];
        if (from == null || to == null) continue;
        _elbow(canvas, paint, from, to, halfCard);
      }
    }

    // Final matchup → champion cap.
    final finalCenter = centers[(model.totalRounds, 0)];
    if (finalCenter != null) {
      _elbow(
        canvas,
        paint,
        finalCenter,
        championCenter,
        halfCard,
        toHalf: TournamentBracketBoard.champW / 2,
      );
    }
  }

  void _elbow(
    Canvas canvas,
    Paint paint,
    Offset from,
    Offset to,
    double fromHalf, {
    double? toHalf,
  }) {
    final startX = from.dx + fromHalf;
    final endX = to.dx - (toHalf ?? fromHalf);
    final midX = (startX + endX) / 2;
    final path = Path()
      ..moveTo(startX, from.dy)
      ..lineTo(midX, from.dy)
      ..lineTo(midX, to.dy)
      ..lineTo(endX, to.dy);
    canvas.drawPath(path, paint);
  }

  @override
  bool shouldRepaint(covariant _ConnectorPainter old) =>
      old.centers != centers || old.championCenter != championCenter;
}
