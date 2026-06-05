import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/active_race_card.dart';

Widget _host(Widget child) {
  return MaterialApp(
    home: Scaffold(
      body: SizedBox(height: 248, child: child),
    ),
  );
}

void main() {
  testWidgets('renders race name, countdown, placement, and top-3 names', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ActiveRaceCard(
          raceId: 'race-1',
          raceName: 'Morning Walk',
          endsAt: DateTime.now().add(const Duration(hours: 2, minutes: 30)),
          userPlacement: 2,
          top3: const [
            {
              'rank': 1,
              'displayName': 'Alice',
              'equippedAccessories': <Map<String, dynamic>>[],
              'totalSteps': 12000,
              'isStealthed': false,
            },
            {
              'rank': 2,
              'displayName': 'Bob',
              'equippedAccessories': <Map<String, dynamic>>[],
              'totalSteps': 9000,
              'isStealthed': false,
            },
            {
              'rank': 3,
              'displayName': 'Cara',
              'equippedAccessories': <Map<String, dynamic>>[],
              'totalSteps': 7000,
              'isStealthed': false,
            },
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('MORNING WALK'), findsOneWidget);
    expect(find.text('ENDS IN '), findsOneWidget);
    expect(find.text('YOU: 2nd'), findsOneWidget);
    expect(find.text('@Alice'), findsOneWidget);
    expect(find.text('@Bob'), findsOneWidget);
    expect(find.text('@Cara'), findsOneWidget);
    expect(find.text('12,000 steps'), findsOneWidget);
  });

  testWidgets('stealthed top-3 racer shows ??? and no step count', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        ActiveRaceCard(
          raceId: 'race-2',
          raceName: 'Stealth Race',
          endsAt: DateTime.now().add(const Duration(hours: 1)),
          userPlacement: 1,
          top3: const [
            {
              'rank': 1,
              'displayName': '???',
              'equippedAccessories': <Map<String, dynamic>>[],
              'totalSteps': null,
              'isStealthed': true,
            },
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('???'), findsOneWidget);
    expect(find.textContaining('steps'), findsNothing);
    expect(find.text('YOU: 1st'), findsOneWidget);
  });

  testWidgets('handles fewer than 3 participants', (tester) async {
    await tester.pumpWidget(
      _host(
        ActiveRaceCard(
          raceId: 'race-3',
          raceName: 'Duo',
          endsAt: DateTime.now().add(const Duration(minutes: 45)),
          userPlacement: 2,
          top3: const [
            {
              'rank': 1,
              'displayName': 'Alice',
              'equippedAccessories': <Map<String, dynamic>>[],
              'totalSteps': 4000,
              'isStealthed': false,
            },
            {
              'rank': 2,
              'displayName': 'You',
              'equippedAccessories': <Map<String, dynamic>>[],
              'totalSteps': 3000,
              'isStealthed': false,
            },
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('@Alice'), findsOneWidget);
    expect(find.text('You'), findsOneWidget);
    expect(find.text('@Cara'), findsNothing);
  });

  testWidgets('tap invokes onTap', (tester) async {
    var tapped = false;
    await tester.pumpWidget(
      _host(
        ActiveRaceCard(
          raceId: 'race-4',
          raceName: 'Tappable',
          endsAt: DateTime.now().add(const Duration(hours: 3)),
          userPlacement: 1,
          onTap: () => tapped = true,
          top3: const [
            {
              'rank': 1,
              'displayName': 'Alice',
              'equippedAccessories': <Map<String, dynamic>>[],
              'totalSteps': 100,
              'isStealthed': false,
            },
          ],
        ),
      ),
    );
    await tester.pump();

    await tester.tap(find.text('TAPPABLE'));
    await tester.pump();
    expect(tapped, isTrue);
  });

  testWidgets('missing userPlacement renders YOU: —', (tester) async {
    await tester.pumpWidget(
      _host(
        ActiveRaceCard(
          raceId: 'race-5',
          raceName: 'No Placement',
          endsAt: DateTime.now().add(const Duration(hours: 1)),
          userPlacement: null,
          top3: const [
            {
              'rank': 1,
              'displayName': 'Alice',
              'equippedAccessories': <Map<String, dynamic>>[],
              'totalSteps': 100,
              'isStealthed': false,
            },
          ],
        ),
      ),
    );
    await tester.pump();

    expect(find.text('YOU: —'), findsOneWidget);
  });
}
