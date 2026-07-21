import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/balance_config.dart';
import 'package:step_tracker/screens/admin_balance_config_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Spec §6.3.A / test plan 27-29: the admin balance editor must show a
/// changed-paths-only diff before saving, refuse to silently overwrite a
/// concurrent edit (409), and block a soft-bound save until the admin
/// explicitly acknowledges the warnings (422).
Map<String, dynamic> _seedConfig() => {
  'schemaVersion': 1,
  'rarityByType': {
    'PROTEIN_SHAKE': 'COMMON',
    'SHORTCUT': 'RARE',
    'LEG_CRAMP': 'UNCOMMON',
  },
  'dropPool': {
    'COMMON': ['PROTEIN_SHAKE'],
    'UNCOMMON': ['LEG_CRAMP'],
    'RARE': ['SHORTCUT'],
  },
  'storeOnlyTypes': ['LEECH'],
  'typeWeights': {'RED_CARD': 0.5},
  'positionOdds': {
    'first': [0.48, 0.25, 0.27],
    'last': [0.20, 0.35, 0.45],
  },
  'upgradeCosts': {
    'byRarity': {
      'COMMON': [0, 5, 15, 45],
      'UNCOMMON': [0, 10, 30, 90],
      'RARE': [0, 15, 45, 135],
    },
    'byType': <String, dynamic>{},
  },
  'upgradeableTypes': ['PROTEIN_SHAKE', 'SHORTCUT'],
  'luckyHorseshoe': {
    'rareChanceByLevel': [0, 0.20, 0.45, 1.0],
  },
  'dailyBox': {
    'streakCap': 30,
    'odds': {
      'first': [0.70, 0.25, 0.05],
      'last': [0.20, 0.35, 0.45],
    },
    'coinRanges': {
      'COMMON': [10, 30],
      'UNCOMMON': [40, 80],
      'RARE_FALLBACK': [100, 200],
    },
    'rareCoinsShare': 0,
    'accessoryWeightMode': 'inverse',
  },
};

class _BalanceApi extends BackendApiService {
  _BalanceApi({
    this.supported = true,
    this.saveResults = const [],
    this.versions = const [],
  });

  final bool supported;

  /// Queued responses for successive PUTs, so a test can drive
  /// 409-then-retry / 422-then-acknowledge flows.
  final List<BalanceConfigSaveResult> saveResults;
  final List<BalanceConfigVersion> versions;

  final List<Map<String, dynamic>> savedBodies = [];
  int _saveIndex = 0;

  @override
  Future<AdminBalanceConfig?> fetchAdminBalanceConfig({
    required String identityToken,
  }) async {
    if (!supported) return null;
    return AdminBalanceConfig(
      version: 7,
      config: _seedConfig(),
      note: 'shortcut to rare',
      createdBy: 'admin-1',
      boundOverride: false,
      createdAt: '2026-07-20T12:00:00.000Z',
      bounds: const {
        'dailyBox.coinRanges.*': [5, 500],
        'positionOdds.*.RARE': [0, 0.6],
        'upgradeCosts.byRarity.*[3]': [10, 1000],
        'dailyBox.streakCap': [7, 90],
        'luckyHorseshoe.rareChanceByLevel[1]': [0, 0.5],
      },
    );
  }

  @override
  Future<List<BalanceConfigVersion>> fetchAdminBalanceConfigVersions({
    required String identityToken,
    int limit = 50,
  }) async => versions;

  @override
  Future<BalanceConfigSaveResult> saveAdminBalanceConfig({
    required String identityToken,
    required int expectedVersion,
    required Map<String, dynamic> config,
    String? note,
    bool acknowledgeBoundWarnings = false,
  }) async {
    savedBodies.add({
      'expectedVersion': expectedVersion,
      'config': config,
      'note': note,
      'acknowledgeBoundWarnings': acknowledgeBoundWarnings,
    });
    final result = _saveIndex < saveResults.length
        ? saveResults[_saveIndex]
        : BalanceConfigSaveResult.saved(version: expectedVersion + 1);
    _saveIndex += 1;
    return result;
  }
}

Future<AuthService> _authService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Admin',
  });
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpEditor(WidgetTester tester, BackendApiService api) async {
  tester.view.physicalSize = const Size(1400, 4200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: AdminBalanceConfigScreen(
        authService: await _authService(),
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 300));
}

Future<void> _setField(
  WidgetTester tester,
  String path,
  String value,
) async {
  final field = find.byKey(Key('bc-$path'), skipOffstage: false);
  expect(field, findsOneWidget, reason: 'no editor field for $path');
  await tester.ensureVisible(field);
  await tester.pump();
  await tester.enterText(field, value);
  await tester.pumpAndSettle();
}

Future<void> _tapText(WidgetTester tester, String label) async {
  final finder = find.text(label);
  expect(finder, findsWidgets, reason: 'missing control: $label');
  await tester.ensureVisible(finder.first);
  await tester.pump();
  await tester.tap(finder.first);
  await tester.pumpAndSettle();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('old backend (GET 404) -> unsupported notice, not an empty form', (
    WidgetTester tester,
  ) async {
    await _pumpEditor(tester, _BalanceApi(supported: false));

    expect(find.textContaining('not supported by this backend'), findsOneWidget);
    expect(find.text('REVIEW CHANGES'), findsNothing);
  });

  testWidgets('editing a field lists exactly that path in the diff preview and '
      'PUTs with the fetched expectedVersion', (WidgetTester tester) async {
    final api = _BalanceApi();
    await _pumpEditor(tester, api);

    expect(find.text('VERSION 7'), findsOneWidget);

    await _setField(tester, 'dailyBox.streakCap', '21');
    await _tapText(tester, 'REVIEW CHANGES');

    expect(find.text('CONFIRM CHANGES'), findsOneWidget);
    // Changed paths ONLY.
    expect(find.text('dailyBox.streakCap'), findsOneWidget);
    expect(find.text('30 → 21'), findsOneWidget);
    expect(find.text('positionOdds.first[0]'), findsNothing);

    await _tapText(tester, 'SAVE');

    expect(api.savedBodies, hasLength(1));
    expect(api.savedBodies.first['expectedVersion'], 7);
    expect(api.savedBodies.first['acknowledgeBoundWarnings'], false);
    final sent = api.savedBodies.first['config'] as Map<String, dynamic>;
    expect((sent['dailyBox'] as Map)['streakCap'], 21);
    // Untouched sections round-trip verbatim — including keys this editor
    // does not surface, so an admin save never drops server-side config.
    expect(sent['storeOnlyTypes'], ['LEECH']);
    expect(sent['typeWeights'], {'RED_CARD': 0.5});
    expect(sent['schemaVersion'], 1);
  });

  testWidgets('a value outside the served soft bounds warns inline, before '
      'submit', (WidgetTester tester) async {
    await _pumpEditor(tester, _BalanceApi());

    expect(find.textContaining('Outside sane range'), findsNothing);

    await _setField(tester, 'dailyBox.streakCap', '200');

    expect(find.textContaining('Outside sane range'), findsWidgets);
    expect(find.textContaining('7'), findsWidgets);
  });

  testWidgets('bound keys written against a rarity name or a coin-range pair '
      'still warn on the indexed inputs the form edits', (
    WidgetTester tester,
  ) async {
    await _pumpEditor(tester, _BalanceApi());

    // `positionOdds.*.RARE` governs index 2 of the triplet.
    await _setField(tester, 'positionOdds.first.2', '0.9');
    expect(find.textContaining('Outside sane range 0–0.6'), findsOneWidget);

    // `dailyBox.coinRanges.*` governs both endpoints of the pair.
    await _setField(tester, 'dailyBox.coinRanges.COMMON.0', '0');
    expect(find.textContaining('Outside sane range 5–500'), findsOneWidget);

    // `upgradeCosts.byRarity.*[3]` — bracketed index notation from the server.
    await _setField(tester, 'upgradeCosts.byRarity.RARE.3', '5000');
    expect(find.textContaining('Outside sane range 10–1000'), findsOneWidget);
  });

  testWidgets('409 shows a conflict notice, re-diffs against the returned '
      'config, and never silently overwrites', (WidgetTester tester) async {
    final conflicting = _seedConfig();
    (conflicting['dailyBox'] as Map)['streakCap'] = 45;

    final api = _BalanceApi(
      saveResults: [
        BalanceConfigSaveResult.conflict(
          currentVersion: 9,
          config: conflicting,
        ),
      ],
    );
    await _pumpEditor(tester, api);

    await _setField(tester, 'dailyBox.streakCap', '21');
    await _tapText(tester, 'REVIEW CHANGES');
    await _tapText(tester, 'SAVE');

    expect(find.text('VERSION CONFLICT'), findsOneWidget);
    expect(find.textContaining('Someone else changed this'), findsOneWidget);
    // Exactly one PUT: the stale save was rejected and nothing was retried
    // automatically.
    expect(api.savedBodies, hasLength(1));

    await _tapText(tester, 'REVIEW AGAIN');

    // Re-diffed against the config returned in the 409 body (45, not 30).
    expect(find.text('CONFIRM CHANGES'), findsOneWidget);
    expect(find.text('45 → 21'), findsOneWidget);
    expect(find.text('30 → 21'), findsNothing);

    await _tapText(tester, 'SAVE');
    expect(api.savedBodies, hasLength(2));
    expect(api.savedBodies.last['expectedVersion'], 9);
  });

  testWidgets('422 renders the bound warnings and blocks the save until the '
      '"I understand" toggle is set', (WidgetTester tester) async {
    final api = _BalanceApi(
      saveResults: [
        BalanceConfigSaveResult.boundWarnings(const [
          BalanceBoundWarning(
            path: 'dailyBox.streakCap',
            value: 200,
            bound: [7, 90],
            message: 'streakCap 200 is outside the sane range 7-90',
          ),
        ]),
      ],
    );
    await _pumpEditor(tester, api);

    await _setField(tester, 'dailyBox.streakCap', '200');
    await _tapText(tester, 'REVIEW CHANGES');
    await _tapText(tester, 'SAVE');

    expect(find.text('BOUND WARNINGS'), findsOneWidget);
    expect(
      find.textContaining('outside the sane range 7-90'),
      findsOneWidget,
    );
    expect(api.savedBodies, hasLength(1));

    // Save is blocked until acknowledged.
    final saveAnyway = find.widgetWithText(TextButton, 'SAVE ANYWAY');
    expect(saveAnyway, findsOneWidget);
    expect(tester.widget<TextButton>(saveAnyway).onPressed, isNull);

    await tester.tap(find.byKey(const Key('bc-ack-toggle')));
    await tester.pump();

    expect(tester.widget<TextButton>(saveAnyway).onPressed, isNotNull);
    await _tapText(tester, 'SAVE ANYWAY');

    expect(api.savedBodies, hasLength(2));
    expect(api.savedBodies.last['acknowledgeBoundWarnings'], true);
    expect(api.savedBodies.last['expectedVersion'], 7);
  });

  testWidgets('version history lists past versions and rollback goes through '
      'the same confirm step', (WidgetTester tester) async {
    final api = _BalanceApi(
      versions: const [
        BalanceConfigVersion(
          version: 7,
          note: 'shortcut to rare',
          createdBy: 'admin-1',
          boundOverride: false,
          createdAt: '2026-07-20T12:00:00.000Z',
          active: true,
        ),
        BalanceConfigVersion(
          version: 6,
          note: 'daily box tuning',
          createdBy: 'admin-1',
          boundOverride: true,
          createdAt: '2026-07-19T12:00:00.000Z',
          active: false,
        ),
      ],
    );
    await _pumpEditor(tester, api);

    expect(find.text('VERSION HISTORY'), findsOneWidget);
    expect(find.text('v6'), findsOneWidget);
    expect(find.text('daily box tuning'), findsOneWidget);

    await _tapText(tester, 'ROLL BACK');
    expect(find.text('ROLL BACK TO V6'), findsOneWidget);
  });
}
