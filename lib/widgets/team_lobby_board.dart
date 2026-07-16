import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/team_race.dart';
import 'home_course_track.dart' show AnimatedCapybaraWithAccessories;

// --- extracted hop kinematics (pure, unit-testable) -------------------------

/// Analytic center of slot [index] within its column.
///
/// Slots are uniform, so ANY center — including the departed "from" slot that
/// no longer exists in the widget tree after a team switch rebuild — is
/// computed from the measured [columnWidth] + the fixed slot metrics and the
/// known index. This is what lets the hop anchor its takeoff on a slot that's
/// already gone (Issue 2, revision-log pass 2 #6).
@visibleForTesting
Offset lobbySlotCenter({
  required RaceTeam team,
  required int index,
  required double columnWidth,
  required double slotHeight,
  required double slotGap,
  required double columnGap,
}) {
  final dy = index * (slotHeight + slotGap) + slotHeight / 2;
  final dx = team == RaceTeam.teamA
      ? columnWidth / 2
      : columnWidth + columnGap + columnWidth / 2;
  return Offset(dx, dy);
}

/// Distance-scaled arc peak height (px the capy rises above the higher slot).
/// A fixed peak made short and long jumps look wrong; this scales with the
/// takeoff→landing distance, clamped to a sane range.
@visibleForTesting
double lobbyHopPeak(Offset from, Offset to) {
  final dist = (to - from).distance;
  return (dist * 0.42).clamp(46.0, 140.0);
}

/// Pure hop position for a raw controller value [t] in [0,1].
///
/// ONE easing curve (easeInOut) applied ONCE — no bezier stacked on top of a
/// second curve. Horizontal travel is a straight lerp; the vertical arc is a
/// parabola that is 0 at both ends and peaks (upward) at the midpoint, its
/// height scaled by [lobbyHopPeak].
@visibleForTesting
Offset lobbyHopPosition({
  required Offset from,
  required Offset to,
  required double t,
}) {
  final e = Curves.easeInOut.transform(t.clamp(0.0, 1.0));
  final x = _lerpDouble(from.dx, to.dx, e);
  final baseY = _lerpDouble(from.dy, to.dy, e);
  final peak = lobbyHopPeak(from, to);
  // -4·peak·e·(1-e): 0 at e∈{0,1}, minimum (highest on screen) −peak at e=0.5.
  final arc = -4 * peak * e * (1 - e);
  return Offset(x, baseY + arc);
}

double _lerpDouble(double a, double b, double t) => a + (b - a) * t;

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
/// hop: their capy arcs over the VS medallion on a single easing curve, its
/// arc height scaled to the jump distance, and cross-fades into the receiving
/// slot (which also wobbles) instead of popping in on a single frame.
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
  // Issue 2: roomier slots so the (now larger) username + capy aren't cramped.
  static const double _slotHeight = 64;
  static const double _slotGap = 10;
  static const double _columnGap = 12;
  static const double _avatarSize = 42;
  static const double _hopCapySize = 46;

  // The last fraction of the flight where the traveling capy dissolves into
  // its landing slot (cross-fade handoff — no single-frame pop).
  static const double _landFadeStart = 0.80;

  late final AnimationController _hopController;
  ({RaceTeam team, int index})? _hopFrom;
  ({RaceTeam team, int index})? _hopTo;
  List<Map<String, dynamic>> _hopAccessories = const [];
  String? _hopAnimal;

  @override
  void initState() {
    super.initState();
    _hopController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 640),
    )..addStatusListener((status) {
        if (status == AnimationStatus.completed) {
          if (!mounted) return;
          setState(() {
            _hopFrom = null;
            _hopTo = null;
          });
        }
      });
  }

  @override
  void didUpdateWidget(TeamLobbyBoard oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Derive both anchors from the actual participant lists: the takeoff index
    // from oldWidget (the slot is gone from the new tree), the landing index
    // from the new list. Unrelated rebuilds (poll refreshes, step updates)
    // keep the same team on both sides → no hop is (re)started.
    final from = _locateSlot(oldWidget.participants);
    final to = _locateSlot(widget.participants);
    if (from != null && to != null && from.team != to.team) {
      _hopFrom = from;
      _hopTo = to;
      final me = _findMe();
      _hopAccessories =
          (me?['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
              const [];
      _hopAnimal = me?['animal'] as String?;
      // A genuine side change (even mid-flight) replaces the arc cleanly.
      _hopController.forward(from: 0);
    }
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

  List<Map<String, dynamic>> _sideMembersOf(
    List<Map<String, dynamic>> participants,
    RaceTeam team,
  ) {
    return participants
        .where(
          (p) =>
              p['status'] == 'ACCEPTED' &&
              TeamRace.participantTeam(p) == team,
        )
        .toList(growable: false);
  }

  List<Map<String, dynamic>> _sideMembers(RaceTeam team) =>
      _sideMembersOf(widget.participants, team);

  /// My (team, index-within-side) in an arbitrary participant list, or null.
  ({RaceTeam team, int index})? _locateSlot(
    List<Map<String, dynamic>> participants,
  ) {
    for (final team in RaceTeam.values) {
      final members = _sideMembersOf(participants, team);
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
    final columnsHeight = teamSize * _slotHeight + (teamSize - 1) * _slotGap;

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
        const SizedBox(height: 14),
        LayoutBuilder(
          builder: (context, constraints) {
            final columnWidth = (constraints.maxWidth - _columnGap) / 2;
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
    // Light plaques (the gold team) can't carry white text — flip the title to
    // the team's dark tone and drop the dark drop-shadow.
    final lightPlaque = color.computeLuminance() > 0.55;
    final onPlaque = lightPlaque ? colorDark : Colors.white;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colorLight, color],
        ),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorDark, width: 3),
        boxShadow: [
          BoxShadow(color: colorDark, offset: const Offset(0, 4), blurRadius: 0),
        ],
      ),
      child: Column(
        children: [
          Text(
            name,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            textAlign: TextAlign.center,
            style: PixelText.title(size: 15, color: onPlaque).copyWith(
              shadows: lightPlaque
                  ? null
                  : const [
                      Shadow(
                        color: Color(0x66000000),
                        offset: Offset(0, 1.5),
                        blurRadius: 0,
                      ),
                    ],
            ),
          ),
          const SizedBox(height: 4),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
            decoration: BoxDecoration(
              color: colorDark.withValues(alpha: 0.85),
              borderRadius: BorderRadius.circular(7),
            ),
            child: Text(
              '$filled/$_teamSize',
              style: PixelText.number(size: 14, color: Colors.white),
            ),
          ),
        ],
      ),
    );
  }

  Widget _vsMedallion() {
    return Container(
      width: 52,
      height: 52,
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
          style: PixelText.title(size: 17, color: Colors.white).copyWith(
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
                // The arriving capy cross-fades in over the last leg of the
                // flight; until then it lives in the overlay, not the slot.
                isArriving:
                    hopActive && members[i]['userId'] == widget.myUserId,
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
        // The plank only shakes once the capy lands (the cross-fade window).
        final localT = t < _landFadeStart
            ? 0.0
            : (t - _landFadeStart) / (1 - _landFadeStart);
        final angle = math.sin(localT * math.pi * 3) * (1 - localT) * 0.05;
        return Transform.rotate(angle: angle, child: inner);
      },
      child: child,
    );
  }

  Widget _filledSlot({
    required Key key,
    required RaceTeam team,
    required Map<String, dynamic> member,
    bool isArriving = false,
  }) {
    final color = TeamRace.color(team);
    final colorDark = TeamRace.colorDark(team);
    final isMe = member['userId'] == widget.myUserId;
    final name = member['displayName'] as String? ?? '???';
    final accessories =
        (member['accessories'] as List?)?.cast<Map<String, dynamic>>() ??
            const <Map<String, dynamic>>[];

    final capy = SizedBox(
      width: _avatarSize,
      height: _avatarSize,
      child: AnimatedCapybaraWithAccessories(
        accessories: accessories,
        size: _avatarSize,
        animal: member['animal'] as String?,
      ),
    );

    return Container(
      key: key,
      height: _slotHeight,
      padding: const EdgeInsets.symmetric(horizontal: 10),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.14),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isMe ? color : color.withValues(alpha: 0.45),
          width: isMe ? 3 : 1.5,
        ),
        boxShadow: isMe
            ? [
                BoxShadow(
                  color: color.withValues(alpha: 0.45),
                  blurRadius: 8,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      child: Row(
        children: [
          // Arriving capy dissolves in over the cross-fade window; everyone
          // else is fully opaque.
          if (isArriving)
            AnimatedBuilder(
              animation: _hopController,
              builder: (context, inner) =>
                  Opacity(opacity: _landFade(_hopController.value), child: inner),
              child: capy,
            )
          else
            capy,
          const SizedBox(width: 9),
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
                    size: 14.5,
                    color: AppColors.textDark,
                  ),
                ),
                if (isMe)
                  Container(
                    margin: const EdgeInsets.only(top: 3),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 2,
                    ),
                    decoration: BoxDecoration(
                      color: colorDark,
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'YOU',
                      style: PixelText.title(size: 9, color: Colors.white),
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// Opacity of the arriving capy as it dissolves into its slot: 0 for most of
  /// the flight, ramping 0→1 across the final [_landFadeStart..1] window.
  double _landFade(double t) {
    if (t <= _landFadeStart) return 0.0;
    return ((t - _landFadeStart) / (1 - _landFadeStart)).clamp(0.0, 1.0);
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
                    size: 19,
                    color: color.withValues(alpha: 0.85),
                  ),
                  const SizedBox(width: 7),
                  Flexible(
                    child: Text(
                      'TAP TO JOIN',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: PixelText.title(
                        size: 12,
                        color: color.withValues(alpha: 0.85),
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
    return lobbySlotCenter(
      team: slot.team,
      index: slot.index,
      columnWidth: columnWidth,
      slotHeight: _slotHeight,
      slotGap: _slotGap,
      columnGap: _columnGap,
    );
  }

  Widget _hopOverlay(double columnWidth) {
    final from = _slotCenter(_hopFrom!, columnWidth);
    final to = _slotCenter(_hopTo!, columnWidth);
    const capySize = _hopCapySize;

    return AnimatedBuilder(
      key: const Key('lobby-hop-overlay'),
      animation: _hopController,
      builder: (context, child) {
        final t = _hopController.value;
        final pos = lobbyHopPosition(from: from, to: to, t: t);
        final e = Curves.easeInOut.transform(t);
        // Squash-and-stretch tied to the same single curve: stretch mid-air.
        final scale = 1 + 0.16 * math.sin(e * math.pi);
        // Dissolve the traveler out as its slot capy dissolves in.
        final overlayOpacity = 1 - _landFade(t);
        final landing = t > _landFadeStart;

        return Stack(
          clipBehavior: Clip.none,
          children: [
            if (landing)
              ..._dustPuffs(to, (t - _landFadeStart) / (1 - _landFadeStart)),
            Positioned(
              left: pos.dx - capySize / 2,
              top: pos.dy - capySize / 2,
              child: Opacity(
                opacity: overlayOpacity,
                child: Transform.scale(
                  scale: scale,
                  child: Transform.rotate(
                    angle: math.sin(e * math.pi) *
                        (_hopTo!.team == RaceTeam.teamB ? 0.16 : -0.16),
                    child: child,
                  ),
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
      const Radius.circular(12),
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
