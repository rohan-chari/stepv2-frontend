import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/home_invite_preflight.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/home_invite_overlay.dart';

void main() {
  test(
    'parser requires resolved contract, skips malformed rows, and sorts',
    () {
      final parsed = HomeInvitePreflight.tryParse({
        'resolved': true,
        'invites': [
          {'kind': 'RACE', 'id': '', 'name': 'bad'},
          {
            'kind': 'RACE',
            'id': 'race',
            'name': 'Late race',
            'myInviteExpiresAt': '2026-08-13T12:00:00.000Z',
          },
          {
            'kind': 'TOURNAMENT',
            'id': 'bracket',
            'name': 'First bracket',
            'createdAt': '2026-08-12T12:00:00.000Z',
          },
        ],
      });
      expect(parsed.supported, isTrue);
      expect(parsed.invites.map((invite) => invite.id), ['bracket', 'race']);
      expect(
        HomeInvitePreflight.tryParse(const {'invites': []}).supported,
        isFalse,
      );
    },
  );

  testWidgets('X dismisses without invoking an invitation mutation', (
    tester,
  ) async {
    var responseCalls = 0;
    const invite = HomeInvite(
      kind: HomeInviteKind.race,
      id: 'race-1',
      name: 'Lunch Loop',
      status: 'PENDING',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeInviteOverlay(
          invite: invite,
          onRespond: (_) async => responseCalls++,
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('home-invite-dismiss')));
    await tester.pump();
    expect(responseCalls, 0);
  });

  testWidgets('funded exposure failure stays inline and keeps overlay open', (
    tester,
  ) async {
    const invite = HomeInvite(
      kind: HomeInviteKind.race,
      id: 'race-1',
      name: 'Lunch Loop',
      status: 'PENDING',
    );
    await tester.pumpWidget(
      MaterialApp(
        home: HomeInviteOverlay(
          invite: invite,
          onRespond: (_) async => throw const ApiException(
            'Conflict',
            statusCode: 409,
            code: 'FUNDED_EXPOSURE_LIMIT',
          ),
        ),
      ),
    );

    await tester.tap(find.byKey(const Key('home-invite-accept')));
    await tester.pump();

    expect(find.byKey(const Key('home-invite-overlay')), findsOneWidget);
    expect(
      find.text(
        'You’ve reached the active competition limit. Finish or leave an active competition, then try again.',
      ),
      findsOneWidget,
    );
    expect(find.text('Conflict'), findsNothing);
  });
}
