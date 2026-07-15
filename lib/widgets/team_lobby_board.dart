import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/team_race.dart';
import 'home_course_track.dart' show AnimatedCapybaraWithAccessories;

/// TR-802 — the LoL-custom-lobby team picker, rendered as content for one
/// parchment board (the caller wraps it in the race-detail section card).
///
/// Two team columns face each other across a carved VS medallion. Each column
/// shows exactly `teamSize` slots: filled slots carry the member's capy (with
/// their real equipped cosmetics) and name; empty slots are dashed "pegs" and
/// ARE the join/switch affordance — tap the side you want (no abstract switch
/// button). A side at cap simply has no pegs left (TR-202 made physical).
///
/// When the local user's slot moves across the divider the board plays the
/// hop: their capy arcs over the VS medallion, lands with a dust puff, and
/// the receiving slot wobbles.
class TeamLobbyBoard extends StatefulWidget {
  const TeamLobbyBoard({
    super.key,
    required this.race,
    required this.participants,
    required this.myUserId,
    this.onTapEmptySlot,
  });

  final Map<String, dynamic> race;
  final List<Map<String, dynamic>> participants;
  final String? myUserId;

  /// Called with the side whose empty peg was tapped. Null disables taps
  /// (viewer can't join/switch right now).
  final void Function(RaceTeam team)? onTapEmptySlot;

  @override
  State<TeamLobbyBoard> createState() => _TeamLobbyBoardState();
}

class _TeamLobbyBoardState extends State<TeamLobbyBoard>
    with SingleTickerProviderStateMixin {
  static const double _slotHeight = 56;
  static const double _slotGap = 8;
  static const double _columnGap = 12;

  late final AnimationController _hopController;
  ({RaceTeam team, int index})? _mySlot;
  ({RaceTeam team, int index})? _hopFrom;
  ({RaceTeam team, int index})? _hopTo;
  List<Map<String, dynamic>> _hopAccessories = const [];
  String? _hopAnimal;

  @override
  void initState() {
    super.initState();
    _hopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 700),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          setState(() {
            _hopFrom = null;
            _hopTo = null;
          });
        }
      });
    _mySlot = _locateMySlot();
  }

  @override
  void didUpdateWidget(TeamLobbyBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    final next = _locateMySlot();
    final prev = _mySlot;
    if (prev != null && next != null && prev.team != next.team) {
      // My capy hopped the divider — fly it across.
      _hopFrom = prev;
      _hopTo = next;
      final me = _findMe();
      _hopAccessories =
          (me?['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
      _hopAnimal = me?['animal'] as String?;
      _hopController.forward(from: 0);
    }
    _mySlot = next;
  }

  @override
  void dispose() {
    _hopController.dispose();
    super.dispose();
  }

  Map<String, dynamic>? _findMe() {
    for (final p in widget.participants) {
      if (p['userId'] == widget.myUserId) return p;
    }
    return null;
  }

  List<Map<String, dynamic>> _sideMembers(RaceTeam team) {
    return widget.participants
        .where(
          (p) =>
              p['status'] == 'ACCEPTED' &&
              TeamRace.participantTeam(p) == team,
        )
        .toList(growable: false);
  }

  ({RaceTeam team, int index})? _locateMySlot() {
    for (final team in RaceTeam.values) {
      final members = _sideMembers(team);
      for (var i = 0; i < members.length; i++) {
        if (members[i]['userId'] == widget.myUserId) {
          return (team: team, index: i);
        }
      }
    }
    return null;
  }

  int get _teamSize {
    final size = TeamRace.teamSize(widget.race) ?? 0;
    // Defensive: a team race without a size still shows both rosters.
    if (size <= 0) {
      return math.max(
        math.max(_sideMembers(RaceTeam.teamA).length,
            _sideMembers(RaceTeam.teamB).length),
        1,
      );
    }
    return size.clamp(1, 5);
  }

  @override
  Widget build(BuildContext context) {
    final teamSize = _teamSize;
    final columnsHeight =
        teamSize * _slotHeight + (teamSize - 1) * _slotGap;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Face-off header: plaque VS plaque.
        Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(child: _teamPlaque(RaceTeam.teamA)),
            _vsMedallion(),
            Expanded(child: _teamPlaque(RaceTeam.teamB)),
          ],
        ),
        const SizedBox(height: 12),
        LayoutBuilder(
          builder: (context, constraints) {
            final columnWidth =
                (constraints.maxWidth - _columnGap) / 2;
            return SizedBox(
              height: columnsHeight,
              child: Stack(
                clipBehavior: Clip.none,
                children: [
                  Positioned(
                    left: 0,
                    top: 0,
                    width: columnWidth,
                    child: _teamColumn(RaceTeam.teamA, teamSize),
                  ),
                  Positioned(
                    right: 0,
                    top: 0,
                    width: columnWidth,
                    child: _teamColumn(RaceTeam.teamB, teamSize),
                  ),
                  if (_hopFrom != null && _hopTo != null)
                    _hopOverlay(columnWidth),
                ],
              ),
            );
          },
        ),
      ],
    );
  }

  // --- header chrome --------------------------------------------------------

  Widget _teamPlaque(RaceTeam team) {
    final color = TeamRace.color(team);
    final colorLight = TeamRace.colorLight(team);
    final colorDark = TeamRace.colorDark(team);
    final name = TeamRace.teamName(widget.race, team).toUpperCase();
    final filled = _sideMembers(team).length;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colorLight, color],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorDark, width: 2.5),
        boxShadow: [
          BoxShadow(color: colorDark, offset: const Offset(0, 3), blurRadius: 0),
        ],
      ),
      child: Column(
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: PixelText.title(size: 12, color: Colors.white).copyWith(
              shadows: const [
                Shadow(
                  color: Color(0x66000000),
                  offset: Offset(0, 1),
                  blurRadius: 0,
                ),
              ],
            ),
          ),
          const SizedBox(height: 3),
          Text(
            '$filled/$_teamSize',
            style: PixelText.number(
              size: 11,
              color: Colors.white.withValues(alpha: 0.9),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vsMedallion() {
    return Container(
      width: 46,
      height: 46,
      margin: const EdgeInsets.symmetric(horizontal: 6),
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        gradient: const RadialGradient(
          center: Alignment(-0.3, -0.4),
          colors: [AppColors.dirtLight, AppColors.dirtMid, AppColors.dirtDark],
          stops: [0.0, 0.55, 1.0],
        ),
        border: Border.all(color: AppColors.dirtDark, width: 3),
        boxShadow: const [
          BoxShadow(
            color: Color(0x59000000),
            offset: Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Center(
        child: Text(
          'VS',
          style: PixelText.title(size: 15, color: Colors.white).copyWith(
            shadows: const [
              Shadow(
                color: Color(0x80000000),
                offset: Offset(0, 2),
                blurRadius: 0,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // --- slot columns ----------------------------------------------------------

  Widget _teamColumn(RaceTeam team, int teamSize) {
    final members = _sideMembers(team);
    final sideLetter = team == RaceTeam.teamA ? 'A' : 'B';
    final hopActive = _hopTo != null;

    return Column(
      children: [
        for (var i = 0; i < teamSize; i++) ...[
          if (i > 0) const SizedBox(height: _slotGap),
          if (i < members.length)
            _wobbleWrapper(
              wobbles: hopActive &&
                  _hopTo!.team == team &&
                  _hopTo!.index == i,
              child: _filledSlot(
                key: Key('lobby-slot-$sideLetter-$i'),
                team: team,
                member: members[i],
                // While the hop is in flight the traveling capy lives in the
                // overlay, not the destination slot.
                hideCapy: hopActive &&
                    members[i]['userId'] == widget.myUserId,
              ),
            )
          else
            _emptySlot(
              key: Key('lobby-empty-$sideLetter-$i'),
              team: team,
            ),
        ],
      ],
    );
  }

  Widget _wobbleWrapper({required bool wobbles, required Widget child}) {
    if (!wobbles) return child;
    return AnimatedBuilder(
      animation: _hopController,
      builder: (context, inner) {
        final t = _hopController.value;
        // The plank only shakes once the capy lands (last 30% of the flight).
        final localT = t < 0.7 ? 0.0 : (t - 0.7) / 0.3;
        final angle =
            math.sin(localT * math.pi * 3) * (1 - localT) * 0.05;
        return Transform.rotate(angle: angle, child: inner);
      },
      child: child,
    );
  }

  Widget _filledSlot({
    required Key key,
    required RaceTeam team,
    required Map<String, dynamic> member,
    bool hideCapy = false,
  }) {
    final color = TeamRace.color(team);
    final colorDark = TeamRace.colorDark(team);
    final isMe = member['userId'] == widget.myUserId;
    final name = member['displayName'] as String? ?? '???';
    final accessories =
        (member['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];

    return Container(
      key: key,
      height: _slotHeight,
      padding: const EdgeInsets.symmetric(horizontal: 8),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: isMe ? color : color.withValues(alpha: 0.45),
          width: isMe ? 2.5 : 1.5,
        ),
        boxShadow: isMe
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 7,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          Opacity(
            opacity: hideCapy ? 0 : 1,
            child: SizedBox(
              width: 34,
              height: 34,
              child: AnimatedCapybaraWithAccessories(
                accessories: accessories,
                size: 34,
                animal: member['animal'] as String?,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  atName(name),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: PixelText.body(
                    size: 11,
                    color: AppColors.textDark,
                  ),
                ),
                if (isMe)
                  Container(
                    margin: const EdgeInsets.only(top: 2),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 5,
                      vertical: 1,
                    ),
                    decoration: BoxDecoration(
                      color: colorDark,
                      borderRadius: BorderRadius.circular(5),
                    ),
                    child: Text(
                      'YOU',
                      style: PixelText.title(size: 7.5, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _emptySlot({required Key key, required RaceTeam team}) {
    final color = TeamRace.color(team);
    final tappable = widget.onTapEmptySlot != null;

    return GestureDetector(
      key: key,
      behavior: HitTestBehavior.opaque,
      onTap: tappable ? () => widget.onTapEmptySlot!(team) : null,
      child: Opacity(
        opacity: tappable ? 1 : 0.55,
        child: SizedBox(
          height: _slotHeight,
          child: CustomPaint(
            painter: _DashedPegPainter(color: color.withValues(alpha: 0.55)),
            child: Center(
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.add_circle_outline_rounded,
                    size: 15,
                    color: color.withValues(alpha: 0.8),
                  ),
                  const SizedBox(width: 5),
                  Flexible(
                    child: Text(
                      'TAP TO JOIN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.title(
                        size: 9.5,
                        color: color.withValues(alpha: 0.8),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }

  // --- the hop ---------------------------------------------------------------

  Offset _slotCenter(({RaceTeam team, int index}) slot, double columnWidth) {
    final dy = slot.index * (_slotHeight + _slotGap) + _slotHeight / 2;
    final dx = slot.team == RaceTeam.teamA
        ? columnWidth / 2
        : columnWidth + _columnGap + columnWidth / 2;
    return Offset(dx, dy);
  }

  Widget _hopOverlay(double columnWidth) {
    final from = _slotCenter(_hopFrom!, columnWidth);
    final to = _slotCenter(_hopTo!, columnWidth);
    const capySize = 38.0;

    return AnimatedBuilder(
      key: const Key('lobby-hop-overlay'),
      animation: _hopController,
      builder: (context, child) {
        final t = Curves.easeInOut.transform(_hopController.value);
        // Quadratic bezier arcing well above both slots — the capy clears the
        // VS divider in one showy jump.
        final peak = Offset(
          (from.dx + to.dx) / 2,
          math.min(from.dy, to.dy) - 52,
        );
        final u = 1 - t;
        final pos = from * (u * u) + peak * (2 * u * t) + to * (t * t);
        // A touch of squash-and-stretch: stretch mid-air, squash on landing.
        final scale = 1 + 0.18 * math.sin(t * math.pi);
        final landing = t > 0.78;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (landing) ..._dustPuffs(to, (t - 0.78) / 0.22),
            Positioned(
              left: pos.dx - capySize / 2,
              top: pos.dy - capySize / 2,
              child: Transform.scale(
                scale: scale,
                child: Transform.rotate(
                  angle: math.sin(t * math.pi) *
                      (_hopTo!.team == RaceTeam.teamB ? 0.16 : -0.16),
                  child: child,
                ),
              ),
            ),
          ],
        );
      },
      child: SizedBox(
        width: capySize,
        height: capySize,
        child: AnimatedCapybaraWithAccessories(
          accessories: _hopAccessories,
          size: capySize,
          animal: _hopAnimal,
        ),
      ),
    );
  }

  List<Widget> _dustPuffs(Offset at, double t) {
    final fade = (1 - t).clamp(0.0, 1.0);
    return [
      for (var i = 0; i < 4; i++)
        Positioned(
          left: at.dx - 4 + (i - 1.5) * 12 * t,
          top: at.dy + _slotHeight / 2 - 12 - 8 * t * (i.isEven ? 1.2 : 0.7),
          child: Container(
            width: 7 + 3 * t,
            height: 7 + 3 * t,
            decoration: BoxDecoration(
              shape: BoxShape.circle,
              color: AppColors.dirtLight.withValues(alpha: 0.55 * fade),
            ),
          ),
        ),
    ];
  }
}

/// Dashed rounded-rect "empty peg" outline. UI chrome (a border), not artwork.
class _DashedPegPainter extends CustomPainter {
  _DashedPegPainter({required this.color});

  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = color
      ..style = PaintingStyle.stroke
      ..strokeWidth = 2;
    final rrect = RRect.fromRectAndRadius(
      Offset.zero & size,
      const Radius.circular(10),
    );
    final path = Path()..addRRect(rrect);
    const dash = 7.0;
    const gap = 5.0;
    for (final metric in path.computeMetrics()) {
      var distance = 0.0;
      while (distance < metric.length) {
        canvas.drawPath(
          metric.extractPath(distance, distance + dash),
          paint,
        );
        distance += dash + gap;
      }
    }
  }

  @override
  bool shouldRepaint(covariant _DashedPegPainter oldDelegate) =>
      oldDelegate.color != color;
}
