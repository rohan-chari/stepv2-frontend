import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/admin_screen.dart';
import 'package:step_tracker/screens/admin_sections.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';

/// Batch 2026-08-09 item 10 — the sectioned admin hub.
///
/// GROWTH / ENGAGEMENT / REVENUE / CONFIG / INBOX / DEBUG, every pre-existing
/// card findable exactly once, and — the part that matters against a prod
/// backend that hasn't deployed the new aggregates yet — every absent field
/// renders "—" instead of throwing.
class _AdminApi extends BackendApiService {
  _AdminApi({
    this.base = const {},
    this.sectioned,
    this.suggestions,
    this.suggestionsThrow = false,
  });

  final Map<String, dynamic> base;

  /// Returned when a non-empty `sections` list is requested. Null means the
  /// backend ignores the param and answers with the legacy payload.
  final Map<String, dynamic>? sectioned;
  final Map<String, dynamic>? suggestions;
  final bool suggestionsThrow;

  final List<List<String>> statsCalls = [];
  int suggestionCalls = 0;

  @override
  Future<Map<String, dynamic>> fetchAdminStats({
    required String identityToken,
    List<String> sections = const [],
  }) async {
    statsCalls.add(sections);
    if (sections.isEmpty) return base;
    return {...base, ...?sectioned};
  }

  @override
  Future<Map<String, dynamic>> fetchAdminSuggestions({
    required String identityToken,
    int limit = 50,
  }) async {
    suggestionCalls += 1;
    if (suggestionsThrow) throw Exception('boom');
    return suggestions ?? const {'suggestions': <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> fetchAdminSettings({
    required String identityToken,
  }) async => {'bannerAdsEnabled': true};
}

Future<AuthService> _auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'admin-1',
    'auth_display_name': 'Admin',
  });
  final service = AuthService();
  await service.restoreSession();
  return service;
}

Future<void> _pumpHub(WidgetTester tester, _AdminApi api) async {
  tester.view.physicalSize = const Size(1170, 3400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  final auth = await _auth();
  await tester.pumpWidget(
    MaterialApp(
      home: AdminScreen(authService: auth, backendApiService: api),
    ),
  );
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _expand(WidgetTester tester, String title) async {
  final header = find.byKey(Key('admin-section-header-$title'));
  // Expanding the sections above pushes the later headers off-screen; without
  // this the tap silently misses and the assertion below reads as a missing
  // widget rather than a missed tap.
  await tester.ensureVisible(header);
  await tester.pump();
  await tester.tap(header, warnIfMissed: false);
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

Future<void> _pumpBody(WidgetTester tester, Widget body) async {
  tester.view.physicalSize = const Size(1170, 3400);
  tester.view.devicePixelRatio = 3;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(body: SingleChildScrollView(child: body)),
    ),
  );
  await tester.pump();
}

const _sectionOrder = [
  'GROWTH',
  'ENGAGEMENT',
  'REVENUE',
  'CONFIG',
  'INBOX',
  'DEBUG',
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  // ------------------------------------------------------------------
  // The hub
  // ------------------------------------------------------------------
  group('hub layout', () {
    testWidgets('renders the six sections in order', (tester) async {
      await _pumpHub(tester, _AdminApi());

      for (final title in _sectionOrder) {
        expect(
          find.byKey(Key('admin-section-$title')),
          findsOneWidget,
          reason: '$title section missing',
        );
      }

      double top(String t) =>
          tester.getTopLeft(find.byKey(Key('admin-section-$t'))).dy;
      for (var i = 1; i < _sectionOrder.length; i++) {
        expect(
          top(_sectionOrder[i - 1]) < top(_sectionOrder[i]),
          isTrue,
          reason: '${_sectionOrder[i - 1]} must precede ${_sectionOrder[i]}',
        );
      }
    });

    testWidgets('DEBUG starts collapsed and its toys live inside it', (
      tester,
    ) async {
      await _pumpHub(tester, _AdminApi());

      // Collapsed: nothing from the debug drawer is on screen.
      expect(find.text('TEST INFO TOAST'), findsNothing);
      expect(find.text('POWERUP ICONS'), findsNothing);
      expect(find.text('POWERUP CRATE'), findsNothing);

      await _expand(tester, 'DEBUG');

      expect(find.text('TEST INFO TOAST'), findsOneWidget);
      expect(find.text('TEST ERROR TOAST'), findsOneWidget);
      expect(find.text('POWERUP ICONS'), findsOneWidget);
      expect(find.text('POWERUP CRATE'), findsOneWidget);
    });

    testWidgets('CONFIG holds the flags card and every sub-screen link', (
      tester,
    ) async {
      await _pumpHub(tester, _AdminApi());
      await _expand(tester, 'CONFIG');

      expect(find.text('Banner ads'), findsOneWidget);
      expect(find.text('ACCESSORY RENDER TUNER'), findsOneWidget);
      expect(find.text('BALANCE CONFIG'), findsOneWidget);
      expect(find.text('POWERUP SHOP'), findsOneWidget);
    });

    testWidgets('no card appears twice across the hub', (tester) async {
      await _pumpHub(tester, _AdminApi());
      for (final title in _sectionOrder) {
        await _expand(tester, title);
      }

      for (final label in [
        'TEST INFO TOAST',
        'POWERUP ICONS',
        'POWERUP CRATE',
        'ACCESSORY RENDER TUNER',
        'BALANCE CONFIG',
        'POWERUP SHOP',
      ]) {
        expect(find.text(label), findsOneWidget, reason: '$label duplicated');
      }
    });
  });

  // ------------------------------------------------------------------
  // Lazy per-section fetching
  // ------------------------------------------------------------------
  group('lazy section fetching', () {
    testWidgets('the base payload is fetched once, with no sections', (
      tester,
    ) async {
      final api = _AdminApi(
        base: const {
          'users': {'total': 12},
        },
      );
      await _pumpHub(tester, api);

      expect(api.statsCalls, [const <String>[]]);
    });

    testWidgets('REVENUE fetches economy+ads only when first expanded', (
      tester,
    ) async {
      final api = _AdminApi(
        base: const {
          'users': {'total': 12},
        },
        sectioned: const {
          'coinEconomy': {
            'days': [
              {'date': '2026-08-08', 'minted': 900, 'sunk': 400},
            ],
          },
        },
      );
      await _pumpHub(tester, api);
      expect(api.statsCalls.length, 1);

      await _expand(tester, 'REVENUE');
      expect(api.statsCalls.length, 2);
      expect(api.statsCalls.last, ['economy', 'ads']);

      // Collapsing and re-expanding must not re-run the aggregates.
      await _expand(tester, 'REVENUE');
      await _expand(tester, 'REVENUE');
      expect(api.statsCalls.length, 2);
    });

    testWidgets('INBOX fetches suggestions only when first expanded', (
      tester,
    ) async {
      final api = _AdminApi();
      await _pumpHub(tester, api);
      expect(api.suggestionCalls, 0);

      await _expand(tester, 'INBOX');
      expect(api.suggestionCalls, 1);
    });
  });

  // ------------------------------------------------------------------
  // GROWTH / ENGAGEMENT bodies
  // ------------------------------------------------------------------
  group('growth body', () {
    testWidgets('renders users, versions, retention and the invite funnel', (
      tester,
    ) async {
      await _pumpBody(
        tester,
        const AdminGrowthStatsBody(
          stats: {
            'users': {'total': 10, 'newLast7Days': 4, 'newLast30Days': 9},
            'activity': {'dauToday': 7},
            'versionsSince': '2026-07-09',
            'versions': [
              {'version': '2.2.0', 'platform': 'ios', 'users': 7},
              {'version': 'unknown', 'users': 3},
            ],
            'retention': {
              'withFriend': {'d1Cohort': 10, 'd1Retained': 5},
            },
            'referralFunnel': {
              'linkOpensLast7Days': 3,
              'linkOpensTotal': 30,
              'rewarded': 2,
            },
          },
        ),
      );

      expect(find.text('USERS'), findsOneWidget);
      expect(find.text('4 / 9'), findsOneWidget);
      expect(find.text('VERSIONS'), findsOneWidget);
      expect(find.text('2.2.0 (ios)'), findsOneWidget);
      expect(find.text('2026-07-09'), findsOneWidget);
      expect(find.text('RETENTION (LAST 32D COHORT)'), findsOneWidget);
      expect(find.text('5/10 (50%)'), findsOneWidget);
      expect(find.text('INVITE FUNNEL'), findsOneWidget);
      expect(find.text('3 / 30'), findsOneWidget);
    });

    testWidgets('an empty payload degrades to em-dashes, never a crash', (
      tester,
    ) async {
      await _pumpBody(tester, const AdminGrowthStatsBody(stats: {}));

      expect(find.text('USERS'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(find.text('VERSIONS'), findsNothing); // additive, hides entirely
      expect(tester.takeException(), isNull);
    });

    testWidgets('a null payload renders the load failure, not an exception', (
      tester,
    ) async {
      await _pumpBody(tester, const AdminGrowthStatsBody(stats: null));
      expect(tester.takeException(), isNull);
    });
  });

  group('engagement body', () {
    testWidgets('renders races, the team block and friends', (tester) async {
      await _pumpBody(
        tester,
        const AdminEngagementStatsBody(
          stats: {
            'activity': {
              'dauInActiveRace': 5,
              'pctDauInActiveRace': 42,
              'avgUniqueBoxOpenersPerDay': 11,
            },
            'races': {
              'privateTotal': 40,
              'privateActive': 5,
              'publicTotal': 12,
              'publicActive': 2,
            },
            'teamRaces': {
              'createdTotal': 8,
              'createdLast7Days': 3,
              'completedTotal': 6,
              'completedLast7Days': 2,
              'activeNow': 1,
            },
            'friends': {
              'distribution': {'0': 1, '1': 2, '2': 3, '3-5': 4, '6+': 5},
            },
          },
        ),
      );

      expect(find.text('RACES'), findsOneWidget);
      expect(find.text('40 / 5'), findsOneWidget);
      expect(find.text('12 / 2'), findsOneWidget);
      // The already-computed team block finally has a home.
      expect(find.text('TEAM RACES'), findsOneWidget);
      expect(find.text('8 / 3'), findsOneWidget);
      expect(find.text('1'), findsWidgets);
      expect(find.text('11'), findsOneWidget);
      expect(find.text('1 / 2 / 3 / 4 / 5'), findsOneWidget);
    });

    testWidgets('an older backend without teamRaces hides that block', (
      tester,
    ) async {
      await _pumpBody(
        tester,
        const AdminEngagementStatsBody(
          stats: {
            'races': {'privateTotal': 40, 'privateActive': 5},
          },
        ),
      );

      expect(find.text('TEAM RACES'), findsNothing);
      expect(find.text('RACES'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });

  // ------------------------------------------------------------------
  // REVENUE body — the new aggregates
  // ------------------------------------------------------------------
  group('revenue body', () {
    testWidgets('renders coinEconomy and adRevenue', (tester) async {
      await _pumpBody(
        tester,
        const AdminRevenueBody(
          stats: {
            'activity': {
              'rewardedAds': {
                'coinReward': {'uniqueDauWatchers': 18, 'pctOfDau': 15},
                'extraSpin': {'uniqueDauWatchers': 9, 'pctOfDau': 8},
              },
            },
            'coinEconomy': {
              'days': [
                {'date': '2026-08-08', 'minted': 1200, 'sunk': 900},
                {'date': '2026-08-07', 'minted': 1000, 'sunk': 1100},
              ],
              'purchasesBySku': [
                {'sku': 'PW_LEECH', 'count': 4, 'coins': 1200},
              ],
              'boxOpens': [
                {'date': '2026-08-08', 'count': 55},
              ],
            },
            'adRevenue': {
              'days': [
                {
                  'date': '2026-08-08',
                  'coinRewardWatches': 30,
                  'extraSpinWatches': 12,
                },
              ],
              'capUtilization': {'avgWatchesPerUser': 2, 'usersAtCap': 6},
            },
          },
        ),
      );

      expect(find.text('REWARDED ADS (TODAY)'), findsOneWidget);
      expect(find.text('18 (15%)'), findsOneWidget);
      expect(find.text('9 (8%)'), findsOneWidget);

      expect(find.text('COINS MINTED VS SUNK'), findsOneWidget);
      expect(find.text('1,200 / 900'), findsOneWidget);
      // A day that sinks more than it mints is the thing you open this for.
      expect(find.text('1,000 / 1,100'), findsOneWidget);

      expect(find.text('SHOP PURCHASES BY SKU'), findsOneWidget);
      expect(find.text('PW_LEECH'), findsOneWidget);
      expect(find.text('4 · 1,200'), findsOneWidget);

      expect(find.text('BOX OPENS'), findsOneWidget);
      expect(find.text('55'), findsOneWidget);

      expect(find.text('AD WATCHES'), findsOneWidget);
      expect(find.text('30 / 12'), findsOneWidget);
      expect(find.text('CAP UTILIZATION'), findsOneWidget);
      expect(find.text('2'), findsWidgets);
      expect(find.text('6'), findsWidgets);
    });

    testWidgets('a prod backend without the new blocks degrades to "—"', (
      tester,
    ) async {
      // This is the real deploy-order case: the app ships before the backend
      // aggregates do. It must render the section, not blow up or vanish.
      await _pumpBody(tester, const AdminRevenueBody(stats: {}));

      expect(find.text('COINS MINTED VS SUNK'), findsOneWidget);
      expect(find.text('AD WATCHES'), findsOneWidget);
      expect(find.text('—'), findsWidgets);
      expect(tester.takeException(), isNull);
    });

    testWidgets('malformed rows are skipped, not rendered as garbage', (
      tester,
    ) async {
      await _pumpBody(
        tester,
        const AdminRevenueBody(
          stats: {
            'coinEconomy': {
              'days': 'not-a-list',
              'purchasesBySku': [
                {'sku': null, 'count': 'x'},
              ],
            },
            'adRevenue': {'capUtilization': 'nope'},
          },
        ),
      );

      expect(tester.takeException(), isNull);
      expect(find.text('COINS MINTED VS SUNK'), findsOneWidget);
    });

    testWidgets('the loading state shows a spinner, the error state a note', (
      tester,
    ) async {
      await _pumpBody(
        tester,
        const AdminRevenueBody(stats: null, loading: true),
      );
      expect(find.byType(CircularProgressIndicator), findsOneWidget);

      await _pumpBody(
        tester,
        const AdminRevenueBody(stats: null, failed: true),
      );
      expect(find.textContaining('Couldn’t load'), findsOneWidget);
    });
  });

  // ------------------------------------------------------------------
  // INBOX
  // ------------------------------------------------------------------
  group('suggestions inbox', () {
    Future<void> pumpInbox(WidgetTester tester, _AdminApi api) async {
      final auth = await _auth();
      await _pumpBody(
        tester,
        AdminInboxBody(authService: auth, backendApiService: api),
      );
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
    }

    testWidgets('renders the newest-first list', (tester) async {
      await pumpInbox(
        tester,
        _AdminApi(
          suggestions: const {
            'suggestions': [
              {
                'id': 's1',
                'displayName': 'Walker',
                'text': 'please add a dark mode',
                'category': 'feature',
                'platform': 'ios',
                'appVersion': '2.2.0',
                'createdAt': '2026-08-08T10:00:00.000Z',
              },
            ],
          },
        ),
      );

      expect(find.text('please add a dark mode'), findsOneWidget);
      expect(find.textContaining('Walker'), findsOneWidget);
    });

    testWidgets('an empty inbox says so instead of rendering nothing', (
      tester,
    ) async {
      await pumpInbox(tester, _AdminApi());
      expect(find.textContaining('No suggestions'), findsOneWidget);
    });

    testWidgets('a failing fetch shows an error with a retry', (tester) async {
      final api = _AdminApi(suggestionsThrow: true);
      await pumpInbox(tester, api);

      expect(find.textContaining('Couldn’t load'), findsOneWidget);
      expect(api.suggestionCalls, 1);

      await tester.tap(find.byKey(const Key('admin-inbox-retry')));
      for (var i = 0; i < 6; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(api.suggestionCalls, 2);
    });

    testWidgets('a row missing every optional field still renders', (
      tester,
    ) async {
      await pumpInbox(
        tester,
        _AdminApi(
          suggestions: const {
            'suggestions': [
              {'id': 's1', 'text': 'bare row'},
              'not-a-map',
            ],
          },
        ),
      );

      expect(find.text('bare row'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });

    testWidgets('an older backend serving no list is an empty inbox', (
      tester,
    ) async {
      await pumpInbox(
        tester,
        _AdminApi(suggestions: const {'nextBefore': null}),
      );
      expect(find.textContaining('No suggestions'), findsOneWidget);
      expect(tester.takeException(), isNull);
    });
  });
}
