import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/balance_config.dart';
import 'package:step_tracker/screens/admin_balance_config_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Position-aware drops spec §5 ("Admin UI risk — must be verified, not
/// assumed").
///
/// The backend is adding a `positionRules` block to the balance config. This
/// build's admin editor renders from KNOWN blocks only and prints "This config
/// carries no X block" for anything it doesn't recognise, so the live question
/// is what an admin save does with a top-level key the editor has no field
/// for: round-trip it, or reconstruct the object and silently drop it.
///
/// Dropping it would revert the whole feature with no error surface — the same
/// failure class as this repo's documented `renderMetadata` sanitizer wipes.
/// These tests pin the answer through the real screen and the real save path,
/// across EVERY route that can produce a PUT body: a plain save, a 409
/// re-diff-and-retry, and a 422 acknowledge-and-retry.
///
/// The assertions deliberately use `positionRules` itself (nested objects,
/// string arrays and a `{TYPE: number}` map) rather than a toy key, so a
/// shallow-copy or a JSON-shape assumption in the write path would show up.
Map<String, dynamic> _positionRules() => {
  'leaderExcluded': ['RED_CARD', 'SECOND_WIND'],
  'lastPlaceExcluded': ['TRAIL_MINE'],
  'leadingDownweight': {'RUNNERS_HIGH': 0.5},
  'trailingDownweight': {'CLEANSE': 0.5, 'MIRROR': 0.5, 'STEALTH_MODE': 0.5},
  'leadingDownweightFrom': 0.4,
  'trailingDownweightFrom': 0.6,
};

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
  // The block this build has no editor for.
  'positionRules': _positionRules(),
};

class _BalanceApi extends BackendApiService {
  _BalanceApi({this.saveResults = const []});

  final List<BalanceConfigSaveResult> saveResults;
  final List<Map<String, dynamic>> savedConfigs = [];
  int _saveIndex = 0;

  @override
  Future<AdminBalanceConfig?> fetchAdminBalanceConfig({
    required String identityToken,
  }) async => AdminBalanceConfig(
    version: 12,
    config: _seedConfig(),
    createdBy: 'admin-1',
    bounds: const {
      'dailyBox.streakCap': [7, 90],
    },
  );

  @override
  Future<List<BalanceConfigVersion>> fetchAdminBalanceConfigVersions({
    required String identityToken,
    int limit = 50,
  }) async => const [];

  @override
  Future<BalanceConfigSaveResult> saveAdminBalanceConfig({
    required String identityToken,
    required int expectedVersion,
    required Map<String, dynamic> config,
    String? note,
    bool acknowledgeBoundWarnings = false,
  }) async {
    savedConfigs.add(config);
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

/// Asserts a PUT body carries `positionRules` byte-for-byte as served.
void _expectPositionRulesIntact(Map<String, dynamic> sent) {
  final rules = sent['positionRules'];
  expect(
    rules,
    isNotNull,
    reason:
        'admin save DROPPED positionRules — a config-block wipe with no error',
  );
  expect(rules, isA<Map>());
  final map = rules as Map;
  expect(map['leaderExcluded'], ['RED_CARD', 'SECOND_WIND']);
  expect(map['lastPlaceExcluded'], ['TRAIL_MINE']);
  expect(map['leadingDownweight'], {'RUNNERS_HIGH': 0.5});
  expect(map['trailingDownweight'], {
    'CLEANSE': 0.5,
    'MIRROR': 0.5,
    'STEALTH_MODE': 0.5,
  });
  expect(map['leadingDownweightFrom'], 0.4);
  expect(map['trailingDownweightFrom'], 0.6);
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('an unrecognised positionRules block loads without breaking the '
      'editor and is not surfaced as an editable field', (
    WidgetTester tester,
  ) async {
    await _pumpEditor(tester, _BalanceApi());

    expect(find.text('VERSION 12'), findsOneWidget);
    expect(tester.takeException(), isNull);
    // No field is invented for a block this build doesn't know.
    expect(
      find.byKey(
        const Key('bc-positionRules.leadingDownweightFrom'),
        skipOffstage: false,
      ),
      findsNothing,
    );
  });

  testWidgets('a normal save round-trips positionRules untouched while '
      'applying only the edited path', (WidgetTester tester) async {
    final api = _BalanceApi();
    await _pumpEditor(tester, api);

    await _setField(tester, 'dailyBox.streakCap', '21');
    await _tapText(tester, 'REVIEW CHANGES');
    await _tapText(tester, 'SAVE');

    expect(api.savedConfigs, hasLength(1));
    final sent = api.savedConfigs.single;
    expect((sent['dailyBox'] as Map)['streakCap'], 21);
    _expectPositionRulesIntact(sent);
  });

  testWidgets('editing a NESTED path (an odds triplet) still round-trips '
      'positionRules — the deep copy must not lose sibling keys', (
    WidgetTester tester,
  ) async {
    final api = _BalanceApi();
    await _pumpEditor(tester, api);

    await _setField(tester, 'positionOdds.last.2', '0.5');
    await _tapText(tester, 'REVIEW CHANGES');
    await _tapText(tester, 'SAVE');

    final sent = api.savedConfigs.single;
    expect(((sent['positionOdds'] as Map)['last'] as List)[2], 0.5);
    _expectPositionRulesIntact(sent);
  });

  testWidgets('a 409 re-diff-and-retry sends the SERVER config forward, '
      'including its positionRules block', (WidgetTester tester) async {
    final serverConfig = _seedConfig();
    (serverConfig['dailyBox'] as Map)['streakCap'] = 45;
    // The concurrent admin also tuned positionRules — the retry must carry the
    // server's version of it, never the stale one we first fetched.
    (serverConfig['positionRules'] as Map)['lastPlaceExcluded'] = [
      'TRAIL_MINE',
      'DECOY',
    ];

    final api = _BalanceApi(
      saveResults: [
        BalanceConfigSaveResult.conflict(
          currentVersion: 13,
          config: serverConfig,
        ),
      ],
    );
    await _pumpEditor(tester, api);

    await _setField(tester, 'dailyBox.streakCap', '21');
    await _tapText(tester, 'REVIEW CHANGES');
    await _tapText(tester, 'SAVE');

    expect(find.text('VERSION CONFLICT'), findsOneWidget);
    await _tapText(tester, 'REVIEW AGAIN');
    await _tapText(tester, 'SAVE');

    expect(api.savedConfigs, hasLength(2));
    final retried = api.savedConfigs.last;
    expect((retried['dailyBox'] as Map)['streakCap'], 21);
    expect((retried['positionRules'] as Map)['lastPlaceExcluded'], [
      'TRAIL_MINE',
      'DECOY',
    ]);
  });

  testWidgets('a 422 acknowledge-and-retry also round-trips positionRules', (
    WidgetTester tester,
  ) async {
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

    await tester.tap(find.byKey(const Key('bc-ack-toggle')));
    await tester.pump();
    await _tapText(tester, 'SAVE ANYWAY');

    expect(api.savedConfigs, hasLength(2));
    _expectPositionRulesIntact(api.savedConfigs.last);
  });
}
