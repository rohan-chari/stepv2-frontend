import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/edit_race_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// Issue 4: the owner can edit the buy-in on a PENDING race even after runners
// have paid in. The field is no longer hard-locked; a consequence line warns
// that changing it refunds/re-charges everyone, and a BUYIN_UNAFFORDABLE error
// surfaces the server's named-player message verbatim.

class _RecordingApi extends BackendApiService {
  Map<String, dynamic>? lastUpdate;

  @override
  Future<Map<String, dynamic>> updateRace({
    required String identityToken,
    required String raceId,
    String? name,
    int? maxDurationDays,
    bool? isPublic,
    bool? powerupsEnabled,
    int? powerupStepInterval,
    int? buyInAmount,
    String? payoutPreset,
    int? maxParticipants,
    bool setMaxParticipantsUnlimited = false,
    String? teamAName,
    String? teamBName,
    int? teamSize,
  }) async {
    lastUpdate = {'buyInAmount': buyInAmount};
    return {
      'race': {'id': raceId},
    };
  }
}

class _ThrowingApi extends BackendApiService {
  @override
  Future<Map<String, dynamic>> updateRace({
    required String identityToken,
    required String raceId,
    String? name,
    int? maxDurationDays,
    bool? isPublic,
    bool? powerupsEnabled,
    int? powerupStepInterval,
    int? buyInAmount,
    String? payoutPreset,
    int? maxParticipants,
    bool setMaxParticipantsUnlimited = false,
    String? teamAName,
    String? teamBName,
    int? teamSize,
  }) async {
    throw const ApiException(
      "Trail Walker doesn't have enough coins for the new buy-in.",
      statusCode: 400,
      code: 'BUYIN_UNAFFORDABLE',
    );
  }
}

Map<String, dynamic> _paidRace() => {
      'id': 'race-1',
      'name': 'Coin Clash',
      'status': 'PENDING',
      'maxDurationDays': 7,
      'buyInAmount': 100,
      'payoutPreset': 'WINNER_TAKES_ALL',
      'isPublic': false,
      'maxParticipants': 10,
      'participants': const [
        // Someone has already paid in -> buyInStatus HELD.
        {'userId': 'u1', 'status': 'ACCEPTED', 'buyInStatus': 'HELD'},
        {'userId': 'u2', 'status': 'ACCEPTED', 'buyInStatus': 'HELD'},
      ],
    };

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Trail Walker',
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Future<void> _pump(
  WidgetTester tester,
  BackendApiService api, {
  Map<String, dynamic>? race,
}) async {
  final authService = await _authService();
  await tester.pumpWidget(
    MaterialApp(
      home: EditRaceScreen(
        authService: authService,
        backendApiService: api,
        raceId: 'race-1',
        race: race ?? _paidRace(),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _editBuyIn(WidgetTester tester, String value) async {
  final field = find.descendant(
    of: find.byKey(const Key('edit-buyin-input')),
    matching: find.byType(TextField),
  );
  await tester.ensureVisible(field);
  await tester.enterText(field, value);
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('buy-in input is editable with paid participants (not locked)',
      (tester) async {
    await _pump(tester, _RecordingApi());

    // The old hard lock copy must be gone.
    expect(find.text('LOCKED — RUNNERS PAID'), findsNothing);
    expect(
      find.text('Buy-in is locked — a runner has already paid in.'),
      findsNothing,
    );

    // The input is enabled (enabled == null means "use default: enabled").
    final field = tester.widget<TextField>(
      find.descendant(
        of: find.byKey(const Key('edit-buyin-input')),
        matching: find.byType(TextField),
      ),
    );
    expect(field.enabled ?? true, isTrue);
  });

  testWidgets('shows the refund/re-charge consequence line', (tester) async {
    await _pump(tester, _RecordingApi());
    expect(
      find.textContaining('refunds or re-charges'),
      findsOneWidget,
    );
  });

  testWidgets('editing the amount PATCHes the new buy-in', (tester) async {
    final api = _RecordingApi();
    await _pump(tester, api);

    await _editBuyIn(tester, '150');
    await tester.ensureVisible(find.text('SAVE CHANGES'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pump();
    await tester.pump();

    expect(api.lastUpdate, isNotNull);
    expect(api.lastUpdate!['buyInAmount'], 150);
  });

  testWidgets('BUYIN_UNAFFORDABLE surfaces the server named-player message',
      (tester) async {
    await _pump(tester, _ThrowingApi());

    await _editBuyIn(tester, '175');
    await tester.ensureVisible(find.text('SAVE CHANGES'));
    await tester.tap(find.text('SAVE CHANGES'));
    await tester.pump();
    await tester.pump();

    expect(
      find.text("Trail Walker doesn't have enough coins for the new buy-in."),
      findsOneWidget,
    );
    await tester.pump(const Duration(seconds: 4));
  });
}
