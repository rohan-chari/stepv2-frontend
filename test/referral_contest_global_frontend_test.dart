import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/admin_giveaway.dart';
import 'package:step_tracker/models/giveaway.dart';
import 'package:step_tracker/screens/admin_giveaway_screen.dart';
import 'package:step_tracker/screens/display_name_screen.dart';
import 'package:step_tracker/screens/giveaway_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';

const _globalContest = <String, dynamic>{
  'slug': 'september-trail',
  'title': 'September Referral Trail',
  'status': 'ACTIVE',
  'startsAt': '2026-08-20T04:00:00.000Z',
  'endsAt': '2026-10-01T04:00:00.000Z',
  'governingTimeZone': 'UTC',
  'prize': {'coins': 5000},
  'eligibility': {
    'mode': 'BARA_ACCOUNT',
    'summary': 'Open to signed-in Bara users.',
  },
  'sponsor': {'name': 'Bara'},
  'rules': {
    'version': 'bara-account-v1-0123456789abcdef01234567',
    'sha256':
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'sections': [
      {
        'heading': 'Who can join',
        'body':
            'Any signed-in Bara user may join. One entry per Bara account. No purchase necessary.',
      },
      {
        'heading': 'Contest window',
        'body':
            'Referrals count only after you join and before the contest ends.',
      },
      {
        'heading': 'How to win',
        'body':
            'The highest verified completed-referral count wins. Ties go to whoever reached the final count first.',
      },
      {
        'heading': 'Prize and platforms',
        'body':
            'The winner gets 5,000 non-transferable Bara coins with no cash value. Apple and Google are not involved.',
      },
    ],
  },
  'socialLinks': <Map<String, dynamic>>[],
};

Map<String, dynamic> _globalCurrent({
  String entryStatus = 'ACTION_REQUIRED',
  String displayName = 'TrailBara',
  bool emptyLeaderboard = false,
}) => {
  'contest': _globalContest,
  'leaderboard': emptyLeaderboard
      ? <Map<String, dynamic>>[]
      : const [
          {'rank': 1, 'displayName': 'Scout', 'completedCount': 8},
          {'rank': 2, 'displayName': 'Moss', 'completedCount': 6},
        ],
  'winner': null,
  'entry': {
    'status': entryStatus,
    'acceptedAt': entryStatus == 'ACTION_REQUIRED'
        ? null
        : '2026-08-25T15:00:00.000Z',
    'region': null,
    'displayName': displayName,
  },
  'standing': {
    'verifiedCount': entryStatus == 'ACTION_REQUIRED' ? 0 : 3,
    'reviewableCount': entryStatus == 'ACTION_REQUIRED' ? 0 : 1,
    'provisionalRank': entryStatus == 'ACTION_REQUIRED' ? null : 8,
    'reachedCountAt': entryStatus == 'ACTION_REQUIRED'
        ? null
        : '2026-08-26T12:00:00.000Z',
  },
  'share': {'code': 'BARA-7F3K', 'url': 'https://barastep.com/r/BARA-7F3K'},
};

class _GlobalGiveawayApi extends BackendApiService {
  _GlobalGiveawayApi({
    Map<String, dynamic>? payload,
    this.entryError,
    this.loadError,
  }) : payload = payload ?? _globalCurrent();

  Map<String, dynamic> payload;
  Object? entryError;
  Object? loadError;
  final List<Map<String, Object>> entries = [];

  @override
  Future<Map<String, dynamic>> fetchCurrentGiveaway({
    required String identityToken,
  }) async {
    if (loadError case final error?) throw error;
    return payload;
  }

  @override
  Future<Map<String, dynamic>> enterGlobalGiveaway({
    required String identityToken,
    required String slug,
    required String rulesVersion,
    required bool rulesAccepted,
  }) async {
    entries.add({
      'slug': slug,
      'rulesVersion': rulesVersion,
      'rulesAccepted': rulesAccepted,
    });
    if (entryError case final error?) throw error;
    payload = _globalCurrent(entryStatus: 'ELIGIBLE');
    return {
      'entry': {
        'status': 'ELIGIBLE',
        'acceptedAt': '2026-08-25T15:00:00.000Z',
        'displayName': 'TrailBara',
        'rulesVersion': rulesVersion,
      },
    };
  }
}

Map<String, dynamic> _globalAdminContest({int revision = 3}) => {
  'id': 'contest-global-1',
  'revision': revision,
  'slug': 'september-trail',
  'title': 'September Referral Trail',
  'status': 'DRAFT',
  'lifecycleStatus': 'DRAFT',
  'governingTimeZone': 'UTC',
  'startsAt': '2026-09-01T04:00:00.000Z',
  'endsAt': '2026-10-01T04:00:00.000Z',
  'cashCurrency': 'USD',
  'cashMinor': 0,
  'coinPrize': 5000,
  'eligibilityMode': 'BARA_ACCOUNT',
  'minimumAge': null,
  'eligibleCountries': null,
  'eligibleRegions': null,
  'sponsor': {'name': 'Bara'},
  'rules': _globalContest['rules'],
  'socialLinks': <Map<String, dynamic>>[],
  'bannerMessage': 'Bring your crew. The referral trail is open.',
  'publicReason': null,
  'amendedRulesVersion': null,
  'counts': {'entrants': 0, 'reviewableFacts': 0, 'rankedResults': 0},
  'publishedAt': null,
  'frozenAt': null,
  'finalizedAt': null,
  'cancelledAt': null,
  'archivedAt': null,
  'createdAt': '2026-08-25T12:00:00.000Z',
  'updatedAt': '2026-08-25T12:00:00.000Z',
};

class _GlobalAdminApi extends BackendApiService {
  Map<String, dynamic>? contest = _globalAdminContest();
  final List<Map<String, dynamic>> createdBodies = [];
  final List<Map<String, dynamic>> patchedBodies = [];
  final List<Map<String, Object>> deleteRequests = [];
  Object? deleteError;

  @override
  Future<Map<String, dynamic>> fetchAdminGiveaways({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async => {
    'records': contest == null ? [] : [contest],
    'nextCursor': null,
  };

  @override
  Future<Map<String, dynamic>> fetchAdminGiveawayDetail({
    required String identityToken,
    required String contestId,
  }) async => {
    'contest': contest,
    'result': {
      'rankedCount': 0,
      'noWinner': false,
      'potentialWinner': null,
      'verifiedWinner': null,
    },
    'fulfillment': null,
  };

  @override
  Future<Map<String, dynamic>> createAdminGiveaway({
    required String identityToken,
    required String idempotencyKey,
    required Map<String, dynamic> body,
  }) async {
    createdBodies.add(body);
    contest = _globalAdminContest(revision: 1);
    return {'contest': contest};
  }

  @override
  Future<Map<String, dynamic>> updateAdminGiveaway({
    required String identityToken,
    required String contestId,
    required int revision,
    required Map<String, dynamic> patch,
  }) async {
    patchedBodies.add(patch);
    contest = {...?contest, ...patch, 'revision': revision + 1};
    return {'contest': contest};
  }

  @override
  Future<Map<String, dynamic>> fetchAdminGiveawayCandidates({
    required String identityToken,
    required String contestId,
    String? cursor,
    int limit = 25,
  }) async => {'records': <Map<String, dynamic>>[], 'nextCursor': null};

  @override
  Future<Map<String, dynamic>> deleteAdminGiveawayDraft({
    required String identityToken,
    required String contestId,
    required String idempotencyKey,
    required int revision,
  }) async {
    deleteRequests.add({
      'contestId': contestId,
      'idempotencyKey': idempotencyKey,
      'revision': revision,
    });
    if (deleteError case final error?) throw error;
    final deleted = contest;
    contest = null;
    return {
      'deleted': {
        'id': deleted?['id'],
        'slug': deleted?['slug'],
        'lifecycleStatus': 'DRAFT',
      },
    };
  }

  @override
  Future<Map<String, dynamic>> mutateAdminGiveaway({
    required String identityToken,
    required String contestId,
    required String action,
    required String idempotencyKey,
    required Map<String, dynamic> body,
  }) async => {'contest': contest};
}

Future<AuthService> _auth({String? displayName = 'TrailBara'}) async {
  final initialValues = <String, Object>{
    'auth_identity_token': 'identity',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'user-1',
  };
  if (displayName case final name?) initialValues['auth_display_name'] = name;
  SharedPreferences.setMockInitialValues(initialValues);
  final auth = AuthService();
  await auth.restoreSession();
  return auth;
}

Future<void> _pumpContest(
  WidgetTester tester,
  _GlobalGiveawayApi api, {
  String? displayName = 'TrailBara',
  Size size = const Size(390, 844),
  double textScale = 1,
}) async {
  tester.view.physicalSize = size;
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
          disableAnimations: true,
        ),
        child: child ?? const SizedBox.shrink(),
      ),
      home: GiveawayScreen(
        slug: 'september-trail',
        authService: await _auth(displayName: displayName),
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
}

Future<void> _readToEnd(WidgetTester tester) async {
  final scroll = find.byKey(const Key('giveaway-global-rules-scroll'));
  expect(scroll, findsOneWidget);
  await tester.fling(scroll, const Offset(0, -4000), 1200);
  await tester.pump();
  await tester.pump(const Duration(milliseconds: 100));
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  test('global and legacy contest DTOs are mode-discriminated', () {
    final global = GiveawayContest.tryParse(_globalContest);
    expect(global?.eligibilityMode, GiveawayEligibilityMode.baraAccount);
    expect(global?.minimumAge, isNull);
    expect(global?.sponsorName, 'Bara');

    final malformed = Map<String, dynamic>.from(_globalContest)
      ..remove('eligibility');
    expect(GiveawayContest.tryParse(malformed), isNull);

    final admin = AdminGiveawayContest.tryParse(_globalAdminContest());
    expect(admin?.eligibilityMode, GiveawayEligibilityMode.baraAccount);
    expect(admin?.minimumAge, isNull);
  });

  test('both client feature-header branches advertise global contests', () {
    for (final ads in [true, false]) {
      final tokens = BackendApiService.clientFeaturesHeaderForPlatform(
        isIos: true,
        adsSupported: ads,
        racePayoutDoubleSupported: false,
      ).split(',');
      expect(
        tokens,
        containsAll(['referral_contest_v1', 'referral_contest_global_v1']),
      );
    }
    expect(
      BackendApiService.clientFeaturesHeader.split(','),
      contains('referral_contest_global_v1'),
    );
  });

  testWidgets(
    'global pre-entry embeds the route and rules and gates exact join request',
    (tester) async {
      final api = _GlobalGiveawayApi();
      await _pumpContest(tester, api);

      expect(find.text('ROUTE TO THE PRIZE'), findsOneWidget);
      for (final text in [
        'Join the contest',
        'Share your invite',
        'Your friend signs up',
        'They finish a qualifying race',
        'Most verified referrals wins',
      ]) {
        expect(find.text(text), findsOneWidget);
      }
      expect(find.text('OFFICIAL RULES'), findsOneWidget);
      expect(find.text('WHO CAN JOIN'), findsOneWidget);
      expect(find.textContaining('18 or older'), findsNothing);
      expect(find.textContaining('legal resident'), findsNothing);
      expect(find.byKey(const Key('giveaway-region-field')), findsNothing);
      expect(find.textContaining('ID'), findsNothing);

      final join = find.widgetWithText(PillButton, 'JOIN CONTEST');
      expect(tester.widget<PillButton>(join).onPressed, isNull);
      await tester.tap(find.byKey(const Key('giveaway-global-rules-accepted')));
      await tester.pump();
      expect(tester.widget<PillButton>(join).onPressed, isNull);

      await _readToEnd(tester);
      expect(tester.widget<PillButton>(join).onPressed, isNotNull);
      await tester.tap(join);
      await tester.pump();

      expect(api.entries, [
        {
          'slug': 'september-trail',
          'rulesVersion': 'bara-account-v1-0123456789abcdef01234567',
          'rulesAccepted': true,
        },
      ]);
      expect(find.text('YOUR RUN'), findsOneWidget);
      expect(find.text('SHARE YOUR INVITE'), findsOneWidget);
      expect(find.text('3'), findsWidgets);
      expect(find.text('#8'), findsWidgets);
    },
  );

  testWidgets('global join preserves scroll and acceptance after errors', (
    tester,
  ) async {
    final api = _GlobalGiveawayApi(
      entryError: const ApiException(
        'The rules changed.',
        statusCode: 409,
        code: 'RULES_CHANGED',
      ),
    );
    await _pumpContest(tester, api);
    await _readToEnd(tester);
    await tester.tap(find.byKey(const Key('giveaway-global-rules-accepted')));
    await tester.pump();
    await tester.tap(find.widgetWithText(PillButton, 'JOIN CONTEST'));
    await tester.pump();
    expect(find.textContaining('rules changed'), findsOneWidget);
    expect(
      tester
          .widget<Checkbox>(
            find.descendant(
              of: find.byKey(const Key('giveaway-global-rules-accepted')),
              matching: find.byType(Checkbox),
            ),
          )
          .value,
      isTrue,
    );
  });

  testWidgets('joined hub has pinned standing, expansion, and empty guidance', (
    tester,
  ) async {
    await _pumpContest(
      tester,
      _GlobalGiveawayApi(
        payload: _globalCurrent(
          entryStatus: 'ELIGIBLE',
          emptyLeaderboard: true,
        ),
      ),
    );
    expect(find.text('YOUR RUN'), findsOneWidget);
    expect(find.text('#8'), findsWidgets);
    expect(
      find.textContaining('Share your invite to lead the trail'),
      findsOneWidget,
    );
    expect(find.text('WHAT COUNTS?'), findsOneWidget);
    await tester.ensureVisible(find.text('WHAT COUNTS?'));
    await tester.tap(find.text('WHAT COUNTS?'));
    await tester.pump();
    expect(
      find.textContaining('qualifying race with another real player'),
      findsOneWidget,
    );
    expect(find.text('OFFICIAL RULES'), findsOneWidget);
  });

  testWidgets('missing display name routes to the existing recovery screen', (
    tester,
  ) async {
    await _pumpContest(
      tester,
      _GlobalGiveawayApi(payload: _globalCurrent(displayName: '')),
      displayName: null,
    );
    await _readToEnd(tester);
    expect(find.text('SET DISPLAY NAME TO JOIN'), findsOneWidget);
    tester
        .widget<PillButton>(
          find.widgetWithText(PillButton, 'SET DISPLAY NAME TO JOIN'),
        )
        .onPressed!();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(find.byType(DisplayNameScreen), findsOneWidget);
  });

  testWidgets('narrow large-text global entry keeps the sticky footer usable', (
    tester,
  ) async {
    await _pumpContest(
      tester,
      _GlobalGiveawayApi(),
      size: const Size(320, 700),
      textScale: 1.7,
    );
    expect(tester.takeException(), isNull);
    expect(find.byKey(const Key('giveaway-entry-footer')), findsOneWidget);
    await _readToEnd(tester);
    expect(tester.takeException(), isNull);
  });

  testWidgets('rules fallback belongs only to the current successful screen', (
    tester,
  ) async {
    final api = _GlobalGiveawayApi();
    await _pumpContest(tester, api);
    api.loadError = const ApiException('offline');
    await tester.tap(find.byKey(const Key('giveaway-retry')));
    await tester.pump();
    expect(find.text('Contest unavailable'), findsOneWidget);
    expect(find.text('OFFICIAL RULES'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await _pumpContest(
      tester,
      _GlobalGiveawayApi(loadError: const ApiException('offline')),
    );
    expect(find.text('Contest unavailable'), findsOneWidget);
    expect(find.text('OFFICIAL RULES'), findsNothing);
  });

  testWidgets(
    'global admin create is compact and draft delete reuses retry key',
    (tester) async {
      tester.view.physicalSize = const Size(390, 900);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      final api = _GlobalAdminApi();
      await tester.pumpWidget(
        MaterialApp(
          home: AdminGiveawayScreen(
            authService: await _auth(),
            backendApiService: api,
          ),
        ),
      );
      await tester.pump();

      await tester.tap(find.text('CREATE CONTEST'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('Home-card message'), findsOneWidget);
      expect(find.text('Shown as the headline on Home'), findsOneWidget);
      expect(find.textContaining('18+'), findsNothing);
      expect(find.text('Sponsor legal name'), findsNothing);
      final messageField = find.byKey(const Key('giveaway-banner-message'));
      await tester.enterText(messageField, 'Win cash with your crew today.');
      await tester.pump();
      expect(find.textContaining('without cash'), findsOneWidget);
      expect(
        tester
            .widget<PillButton>(find.widgetWithText(PillButton, 'SAVE DRAFT'))
            .onPressed,
        isNull,
      );
      await tester.enterText(
        messageField,
        'Bring your crew. The trail starts here.',
      );
      final createDraft = find.widgetWithText(PillButton, 'SAVE DRAFT');
      await tester.ensureVisible(createDraft);
      await tester.pump();
      final createButton = tester.widget<PillButton>(createDraft);
      expect(createButton.onPressed, isNotNull);
      createButton.onPressed!();
      await tester.pump();
      expect(api.createdBodies.single.keys.toSet(), {
        'slug',
        'title',
        'startsAt',
        'endsAt',
        'coinPrize',
        'bannerMessage',
        'eligibilityMode',
      });
      expect(api.createdBodies.single['eligibilityMode'], 'BARA_ACCOUNT');

      await tester.pumpAndSettle();
      await tester.tap(find.text('September Referral Trail').first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('DELETE DRAFT'), findsOneWidget);
      await tester.enterText(
        find.byKey(const Key('giveaway-banner-message')),
        'Every friend moves you up the trail.',
      );
      final saveDraft = find.widgetWithText(PillButton, 'SAVE DRAFT');
      await tester.ensureVisible(saveDraft);
      await tester.pump();
      final saveButton = tester.widget<PillButton>(saveDraft);
      expect(saveButton.onPressed, isNotNull);
      saveButton.onPressed!();
      await tester.pump();
      expect(api.patchedBodies.single.keys.toSet(), {
        'slug',
        'title',
        'startsAt',
        'endsAt',
        'coinPrize',
        'bannerMessage',
      });
      expect(
        api.patchedBodies.single['bannerMessage'],
        'Every friend moves you up the trail.',
      );
      await tester.ensureVisible(find.text('DELETE DRAFT'));
      await tester.tap(find.text('DELETE DRAFT'));
      await tester.pump();
      expect(find.textContaining('September Referral Trail'), findsWidgets);
      await tester.tap(find.widgetWithText(TextButton, 'KEEP DRAFT'));
      await tester.pump();
      expect(api.deleteRequests, isEmpty);

      api.deleteError = const ApiException('Connection lost.');
      await tester.tap(find.text('DELETE DRAFT'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'DELETE DRAFT'));
      await tester.pump();
      expect(api.deleteRequests, hasLength(1));
      final retryKey = api.deleteRequests.single['idempotencyKey'];
      expect(retryKey, isA<String>());
      expect(
        RegExp(
          r'^[0-9a-f]{8}-[0-9a-f]{4}-4[0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$',
        ).hasMatch(retryKey! as String),
        isTrue,
      );

      api.deleteError = null;
      await tester.ensureVisible(find.text('RETRY DELETE'));
      await tester.tap(find.text('RETRY DELETE'));
      await tester.pump();
      expect(api.deleteRequests, hasLength(2));
      expect(api.deleteRequests.last['idempotencyKey'], retryKey);
      expect(api.deleteRequests.last['revision'], 2);
      await tester.pumpAndSettle();
      expect(find.text('No contests yet.'), findsOneWidget);
    },
  );

  testWidgets('published global contest never exposes hard delete', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(390, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final api = _GlobalAdminApi()
      ..contest = {
        ..._globalAdminContest(),
        'status': 'ACTIVE',
        'lifecycleStatus': 'PUBLISHED',
        'publishedAt': '2026-08-25T12:00:00.000Z',
        'frozenAt': '2026-08-25T12:00:00.000Z',
      };
    await tester.pumpWidget(
      MaterialApp(
        home: AdminGiveawayScreen(
          authService: await _auth(),
          backendApiService: api,
        ),
      ),
    );
    await tester.pump();
    await tester.tap(find.text('September Referral Trail'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.text('DELETE DRAFT'), findsNothing);
  });
}
