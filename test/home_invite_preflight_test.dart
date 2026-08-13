import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/models/home_invite_preflight.dart';
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
}
