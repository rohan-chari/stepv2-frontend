import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/app_avatar.dart';
import 'package:step_tracker/widgets/fire_aura.dart';
import 'package:step_tracker/widgets/leaderboard_plank.dart';

// The multiplier fire aura used to be a ~5px rim tucked BEHIND the avatar: its
// size was capped at `avatarSize + 1.4 * verticalPadding` so it couldn't bleed
// into the next plank, and the avatar painted over everything inside that.
// These pin the corrected treatment — a ring drawn in front, materially bigger
// than the avatar, whose base is never sliced by the row below.

const double kAvatarSize = 32;
const double kVerticalPadding = 8;

Widget _wrap(double multiplier) => MaterialApp(
  home: Scaffold(
    body: Column(
      children: [
        LeaderboardPlank(
          rank: 3,
          name: 'Anjali',
          steps: 12000,
          formattedSteps: '12,000',
          currentMultiplier: multiplier,
          avatarSize: kAvatarSize,
          verticalPadding: kVerticalPadding,
        ),
        // A following plank: its opaque background is what used to paint over
        // any flame that bled downward.
        const LeaderboardPlank(
          rank: 4,
          name: 'Bhavin',
          steps: 9000,
          formattedSteps: '9,000',
          avatarSize: kAvatarSize,
          verticalPadding: kVerticalPadding,
        ),
      ],
    ),
  ),
);

void main() {
  testWidgets('the flame is much bigger than the avatar at every buff tier', (
    tester,
  ) async {
    for (final (multiplier, minScale) in [(2.0, 1.5), (11.0, 1.9)]) {
      await tester.pumpWidget(_wrap(multiplier));
      await tester.pump();

      final fire = tester.getSize(find.byType(FireAura));
      expect(
        fire.width / kAvatarSize,
        greaterThanOrEqualTo(minScale),
        reason: 'flame at ${multiplier}x should be >= ${minScale}x the avatar',
      );
      // Higher tiers burn bigger, not just brighter.
      expect(tester.widget<FireAura>(find.byType(FireAura)).tier, multiplier.floor());
    }
  });

  // The ring's hole is NOT the sprite frame's centre: it is an oval sitting low
  // in the frame (flames lick up above it), 0.417 wide by 0.458 tall. Aligning
  // the frame instead of the hole is what left the ring hanging off the avatar.
  testWidgets('the ring hole lands on the avatar centre at every tier', (
    tester,
  ) async {
    for (final multiplier in [2.0, 3.0, 4.0, 5.0, 7.0, 11.0]) {
      await tester.pumpWidget(_wrap(multiplier));
      await tester.pump();

      final fire = tester.getRect(find.byType(FireAura));
      final avatar = tester.getRect(find.byType(AppAvatar).first);
      final hole = FireAura.holeCenter(fire.width);

      expect(
        fire.left + hole.dx,
        moreOrLessEquals(avatar.center.dx, epsilon: 0.5),
        reason: 'ring hangs left/right of the avatar at ${multiplier}x',
      );
      expect(
        fire.top + hole.dy,
        moreOrLessEquals(avatar.center.dy, epsilon: 0.5),
        reason: 'ring sits high/low on the avatar at ${multiplier}x',
      );
    }
  });

  testWidgets('every tier renders at the same size — intensity carries the '
      'tier, not scale', (tester) async {
    for (final multiplier in [2.0, 5.0, 11.0]) {
      await tester.pumpWidget(_wrap(multiplier));
      await tester.pump();
      expect(
        tester.getSize(find.byType(FireAura)).width,
        moreOrLessEquals(kAvatarSize * 2.0, epsilon: 0.01),
      );
    }
  });

  testWidgets('an 11x burns harder than a 4x', (tester) async {
    // Intensity ramps monotonically and saturates at 8x.
    final low = FireAura.intensityFor(2);
    final mid = FireAura.intensityFor(4);
    final high = FireAura.intensityFor(11);
    expect(low, 0.0);
    expect(mid, greaterThan(low));
    expect(high, greaterThan(mid));
    expect(high, 1.0);
    expect(FireAura.intensityFor(20), 1.0, reason: 'saturates, never overflows');

    // The bloom layer only exists on the hot tiers: a 2x is a plain ring, an
    // 11x is a ring plus a blurred copy underneath.
    await tester.pumpWidget(_wrap(2));
    await tester.pump();
    expect(find.byType(ImageFiltered), findsNothing);

    await tester.pumpWidget(_wrap(11));
    await tester.pump();
    expect(find.byType(ImageFiltered), findsWidgets);
    expect(find.byType(ColorFiltered), findsWidgets);
  });

  testWidgets('the flame paints in front of the avatar', (tester) async {
    await tester.pumpWidget(_wrap(11));
    await tester.pump();

    final stack = tester.widget<Stack>(
      find
          .ancestor(of: find.byType(FireAura), matching: find.byType(Stack))
          .first,
    );
    final avatarIndex = stack.children.indexWhere((w) => w is AppAvatar);
    final fireIndex = stack.children.indexWhere(
      (w) => w is Positioned && w.child is SizedBox,
    );
    expect(avatarIndex, isNonNegative);
    expect(fireIndex, isNonNegative);
    expect(
      fireIndex,
      greaterThan(avatarIndex),
      reason: 'later Stack children paint on top — the flame must be after '
          'the avatar, or it is hidden behind it again',
    );
  });

  testWidgets('the base of the flame is not sliced by the plank below', (
    tester,
  ) async {
    await tester.pumpWidget(_wrap(11));
    await tester.pump();

    final fire = tester.getRect(find.byType(FireAura));
    final rowBottom = tester.getRect(find.byType(LeaderboardPlank).first).bottom;
    expect(
      fire.bottom,
      lessThanOrEqualTo(rowBottom + 0.01),
      reason: 'flame extends past its own row and the next plank paints over it',
    );
    // ...and all that extra size went upward instead.
    final avatar = tester.getRect(find.byType(AppAvatar).first);
    expect(fire.top, lessThan(avatar.top));
  });
}
