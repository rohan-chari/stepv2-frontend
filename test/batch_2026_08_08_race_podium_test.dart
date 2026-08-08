// Feature batch 2026-08-08 — Item 4: RacePodium.
//
// The podium consumes `orderRaceParticipantsForDisplay` (Item 18), so these
// tests double as a guard that a race which ran WITH STEALTH ACTIVE still
// produces a correct top three once it completes and unmasks.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:step_tracker/models/race_payouts.dart';
import 'package:step_tracker/utils/race_participant_display.dart';
import 'package:step_tracker/widgets/race_podium.dart';

Map<String, dynamic> _p(
  String name, {
  int? placement,
  int? steps,
  String? userId,
  bool stealthed = false,
}) {
  return <String, dynamic>{
    'userId': userId ?? name,
    'displayName': name,
    if (steps != null) 'totalSteps': steps,
    'stealthed': stealthed,
    'finishedAt': null,
    if (placement != null) 'placement': placement,
  };
}

Widget _wrap(Widget child) => MaterialApp(
  home: Scaffold(
    body: SizedBox(width: 400, child: child),
  ),
);

void main() {
  setUp(() {
    // Known widget-test hang trap: anything that reaches PackageInfo without
    // a mock never completes.
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.steps',
      version: '2.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('finishersFromParticipants', () {
    test('takes the top three in display order', () {
      final participants = [
        _p('Ada', placement: 1, steps: 30000),
        _p('Bo', placement: 2, steps: 20000),
        _p('Cy', placement: 3, steps: 10000),
        _p('Dee', placement: 4, steps: 5000),
      ];

      final finishers = RacePodium.finishersFromParticipants(participants);

      expect(finishers, hasLength(3));
      expect(finishers.map((f) => f.displayName), ['Ada', 'Bo', 'Cy']);
      expect(finishers.map((f) => f.placement), [1, 2, 3]);
    });

    test('attaches payout coins by placement', () {
      final finishers = RacePodium.finishersFromParticipants(
        [_p('Ada', placement: 1), _p('Bo', placement: 2)],
        payoutTiers: const <PayoutTier>[
          (placement: 1, amount: 100),
          (placement: 2, amount: 40),
        ],
      );

      expect(finishers[0].payoutCoins, 100);
      expect(finishers[1].payoutCoins, 40);
    });

    test('missing fields degrade instead of crashing', () {
      final finishers = RacePodium.finishersFromParticipants([
        <String, dynamic>{},
        <String, dynamic>{'displayName': 'Bo', 'totalSteps': 'not-a-number'},
      ]);

      expect(finishers, hasLength(2));
      expect(finishers[0].displayName, '???');
      expect(finishers[0].totalSteps, isNull);
      expect(finishers[0].placement, 1);
      expect(finishers[1].totalSteps, isNull);
      expect(finishers[1].payoutCoins, isNull);
      expect(finishers[1].accessories, isEmpty);
    });

    test('marks the viewer', () {
      final finishers = RacePodium.finishersFromParticipants(
        [_p('Ada', placement: 1, userId: 'u1'), _p('Bo', placement: 2)],
        viewerUserId: 'u1',
      );
      expect(finishers[0].isViewer, isTrue);
      expect(finishers[1].isViewer, isFalse);
    });

    test('a race that ran with stealth still yields the right top three', () {
      // Completed races unmask, so every row carries a placement again — but
      // the ordering helper is the same one Item 18 changed, so pin it.
      final participants = orderRaceParticipantsForDisplay([
        _p('Cy', placement: 3, steps: 10000),
        _p('Ada', placement: 1, steps: 30000),
        _p('Bo', placement: 2, steps: 20000),
      ]);

      final finishers = RacePodium.finishersFromParticipants(participants);
      expect(finishers.map((f) => f.displayName), ['Ada', 'Bo', 'Cy']);
    });
  });

  group('canRender', () {
    test('needs at least two finishers', () {
      expect(RacePodium.canRender(0), isFalse);
      expect(RacePodium.canRender(1), isFalse);
      expect(RacePodium.canRender(2), isTrue);
      expect(RacePodium.canRender(3), isTrue);
    });
  });

  group('rendering', () {
    testWidgets('three finishers render three plinths', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RacePodium(
            finishers: RacePodium.finishersFromParticipants(
              [
                _p('Ada', placement: 1, steps: 30000),
                _p('Bo', placement: 2, steps: 20000),
                _p('Cy', placement: 3, steps: 10000),
              ],
              payoutTiers: const <PayoutTier>[(placement: 1, amount: 120)],
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('1ST'), findsOneWidget);
      expect(find.text('2ND'), findsOneWidget);
      expect(find.text('3RD'), findsOneWidget);
      expect(find.text('@Ada'), findsOneWidget);
      expect(find.text('@Bo'), findsOneWidget);
      expect(find.text('@Cy'), findsOneWidget);
      expect(find.text('30,000'), findsOneWidget);
      expect(find.text('+120'), findsOneWidget);
    });

    testWidgets('two finishers render only two plinths', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RacePodium(
            finishers: RacePodium.finishersFromParticipants([
              _p('Ada', placement: 1, steps: 30000),
              _p('Bo', placement: 2, steps: 20000),
            ]),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('1ST'), findsOneWidget);
      expect(find.text('2ND'), findsOneWidget);
      expect(find.text('3RD'), findsNothing);
    });

    testWidgets('a payout-free race shows no coin line', (tester) async {
      await tester.pumpWidget(
        _wrap(
          RacePodium(
            finishers: RacePodium.finishersFromParticipants([
              _p('Ada', placement: 1, steps: 300),
              _p('Bo', placement: 2, steps: 200),
            ]),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.textContaining('+'), findsNothing);
    });

    testWidgets('renders from the DEMO race fixture shape', (tester) async {
      // ui-test-planner risk 1: demo_race_engine serves status COMPLETED
      // through the REAL race detail screen, so the podium must render from a
      // fixture that has no placement, no animal and no payouts.
      final demoShaped = <Map<String, dynamic>>[
        {
          'userId': 'me',
          'displayName': 'Rohan',
          'totalSteps': 12000,
          'profilePhotoUrl': null,
          'accessories': const <Map<String, dynamic>>[],
          'status': 'ACCEPTED',
          'finishedAt': null,
          'stealthed': false,
        },
        {
          'userId': 'rival',
          'displayName': 'Pip',
          'totalSteps': 9000,
          'profilePhotoUrl': null,
          'accessories': const <Map<String, dynamic>>[],
          'status': 'ACCEPTED',
          'finishedAt': null,
          'stealthed': false,
        },
      ];

      await tester.pumpWidget(
        _wrap(
          RacePodium(
            finishers: RacePodium.finishersFromParticipants(
              orderRaceParticipantsForDisplay(demoShaped),
              viewerUserId: 'me',
            ),
          ),
        ),
      );
      await tester.pump(const Duration(seconds: 1));

      expect(find.text('@Rohan (you)'), findsOneWidget);
      expect(find.text('@Pip'), findsOneWidget);
      expect(find.text('1ST'), findsOneWidget);
      expect(find.text('2ND'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
