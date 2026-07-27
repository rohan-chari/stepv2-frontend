import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/balance_config.dart';
import 'package:step_tracker/screens/admin_balance_config_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Team-only drop pool spec §7 / test plan item 14.
///
/// The admin balance editor must surface the new `teamOnlyTypes` key as a
/// read-only chip row, and must render NOTHING AT ALL when the key is absent,
/// null, or not a list — the backend may be older than this build (CLAUDE.md's
/// #1 rule), and an older backend simply does not send the key.
Map<String, dynamic> _seedConfig({Object? teamOnlyTypes = _absent}) => {
  'schemaVersion': 1,
  'rarityByType': {
    'PROTEIN_SHAKE': 'COMMON',
    'RALLY_FLAG': 'UNCOMMON',
    'LEG_CRAMP': 'UNCOMMON',
  },
  'dropPool': {
    'COMMON': ['PROTEIN_SHAKE'],
    'UNCOMMON': ['LEG_CRAMP', 'RALLY_FLAG'],
    'RARE': <String>[],
  },
  'storeOnlyTypes': ['LEECH'],
  if (!identical(teamOnlyTypes, _absent)) 'teamOnlyTypes': teamOnlyTypes,
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

const Object _absent = Object();

class _BalanceApi extends BackendApiService {
  _BalanceApi(this.config);

  final Map<String, dynamic> config;
  final List<Map<String, dynamic>> savedBodies = [];

  @override
  Future<AdminBalanceConfig?> fetchAdminBalanceConfig({
    required String identityToken,
  }) async => AdminBalanceConfig(
    version: 11,
    config: config,
    note: 'team-only pool',
    createdBy: 'admin-1',
    boundOverride: false,
    createdAt: '2026-07-26T12:00:00.000Z',
    bounds: const {},
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
    savedBodies.add({'expectedVersion': expectedVersion, 'config': config});
    return BalanceConfigSaveResult.saved(version: expectedVersion + 1);
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

Future<_BalanceApi> _pumpEditor(
  WidgetTester tester,
  Map<String, dynamic> config,
) async {
  tester.view.physicalSize = const Size(1400, 4200);
  tester.view.devicePixelRatio = 2.0;
  addTearDown(tester.view.reset);

  final api = _BalanceApi(config);
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
  return api;
}

Finder _label() =>
    find.text('TEAM RACES ONLY', skipOffstage: false);

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('teamOnlyTypes renders as a read-only chip row in DROP POOL', (
    WidgetTester tester,
  ) async {
    await _pumpEditor(
      tester,
      _seedConfig(teamOnlyTypes: const ['RALLY_FLAG', 'UPRISING']),
    );

    expect(find.text('VERSION 11'), findsOneWidget);
    expect(_label(), findsOneWidget);
    expect(
      find.byKey(const Key('bc-teamOnly-RALLY_FLAG'), skipOffstage: false),
      findsOneWidget,
    );
    expect(
      find.byKey(const Key('bc-teamOnly-UPRISING'), skipOffstage: false),
      findsOneWidget,
    );
    // Read-only: the chips carry no tap affordance of any kind.
    expect(
      find.descendant(
        of: find.byKey(const Key('bc-teamOnly-RALLY_FLAG'), skipOffstage: false),
        matching: find.byType(GestureDetector),
        skipOffstage: false,
      ),
      findsNothing,
    );
  });

  testWidgets('an older backend that omits teamOnlyTypes renders nothing and '
      'does not throw', (WidgetTester tester) async {
    await _pumpEditor(tester, _seedConfig());

    expect(tester.takeException(), isNull);
    // The screen still loaded normally.
    expect(find.text('DROP POOL'), findsOneWidget);
    expect(_label(), findsNothing);
    expect(
      find.byKey(const Key('bc-teamOnly-RALLY_FLAG'), skipOffstage: false),
      findsNothing,
    );
  });

  testWidgets('a null / non-list / empty teamOnlyTypes renders nothing and '
      'does not throw', (WidgetTester tester) async {
    for (final value in <Object?>[
      null,
      'RALLY_FLAG',
      const {'RALLY_FLAG': true},
      const <String>[],
    ]) {
      await _pumpEditor(tester, _seedConfig(teamOnlyTypes: value));

      expect(tester.takeException(), isNull, reason: 'threw on $value');
      expect(find.text('DROP POOL'), findsOneWidget, reason: 'on $value');
      expect(_label(), findsNothing, reason: 'rendered a row for $value');
    }
  });

  testWidgets('teamOnlyTypes round-trips verbatim through an unrelated save', (
    WidgetTester tester,
  ) async {
    final api = await _pumpEditor(
      tester,
      _seedConfig(teamOnlyTypes: const ['RALLY_FLAG']),
    );

    final field = find.byKey(
      const Key('bc-dailyBox.streakCap'),
      skipOffstage: false,
    );
    await tester.ensureVisible(field);
    await tester.pump();
    await tester.enterText(field, '21');
    await tester.pumpAndSettle();

    for (final label in const ['REVIEW CHANGES', 'SAVE']) {
      final finder = find.text(label);
      await tester.ensureVisible(finder.first);
      await tester.pump();
      await tester.tap(finder.first);
      await tester.pumpAndSettle();
    }

    expect(api.savedBodies, hasLength(1));
    expect(
      (api.savedBodies.first['config'] as Map)['teamOnlyTypes'],
      ['RALLY_FLAG'],
    );
  });
}
