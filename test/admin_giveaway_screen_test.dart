import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/models/admin_giveaway.dart';
import 'package:step_tracker/models/giveaway.dart';
import 'package:step_tracker/screens/admin_giveaway_screen.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/widgets/pill_button.dart';

Map<String, dynamic> adminContest({
  String status = 'VERIFYING',
  String lifecycle = 'PUBLISHED',
  int revision = 5,
}) => {
  'id': 'contest-1',
  'revision': revision,
  'slug': 'bara-referral-2026-09',
  'title': 'Bara Referral Contest',
  'status': status,
  'lifecycleStatus': lifecycle,
  'governingTimeZone': 'America/New_York',
  'startsAt': '2026-09-01T04:00:00.000Z',
  'endsAt': '2026-10-01T04:00:00.000Z',
  'cashCurrency': 'USD',
  'cashMinor': 5000,
  'coinPrize': 5000,
  'minimumAge': 18,
  'eligibleCountries': ['US'],
  'eligibleRegions': giveawayUsRegionsV1.toList()..sort(),
  'sponsor': {'legalName': 'Bara LLC', 'mailingAddress': '1 Trail Way'},
  'rules': {
    'version': '2026-09-v1',
    'sha256':
        '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
    'sections': [
      {'heading': 'How to enter', 'body': 'Complete verified referrals.'},
      {
        'heading': 'Notice',
        'body': 'No purchase. Apple and Google are not sponsors.',
      },
    ],
  },
  'socialLinks': const <Map<String, dynamic>>[],
  'bannerMessage': r'Win US$50 + 5,000 coins.',
  'publicReason': null,
  'amendedRulesVersion': null,
  'counts': {'entrants': 12, 'reviewableFacts': 1, 'rankedResults': 0},
  'publishedAt': lifecycle == 'DRAFT' ? null : '2026-08-20T12:00:00.000Z',
  'frozenAt': lifecycle == 'DRAFT' ? null : '2026-08-20T12:00:00.000Z',
  'finalizedAt': lifecycle == 'FINAL' ? '2026-10-02T12:00:00.000Z' : null,
  'cancelledAt': null,
  'archivedAt': null,
  'createdAt': '2026-08-10T12:00:00.000Z',
  'updatedAt': '2026-08-20T12:00:00.000Z',
};

Map<String, dynamic> result({bool verified = false}) => {
  'rankedCount': 12,
  'noWinner': false,
  'potentialWinner': verified
      ? null
      : {'entrantId': 'entrant-1', 'displayName': 'Rohan', 'originalRank': 1},
  'verifiedWinner': verified
      ? {'entrantId': 'entrant-1', 'displayName': 'Rohan', 'originalRank': 1}
      : null,
};

class _AdminGiveawayApi extends BackendApiService {
  _AdminGiveawayApi({
    this.listError,
    this.malformed = false,
    this.patchError,
    this.publishError,
    this.detailError,
    this.mutationError,
  });
  final Object? listError;
  final bool malformed;
  final Object? patchError;
  final Object? publishError;
  final Object? detailError;
  final Object? mutationError;
  Map<String, dynamic> contest = adminContest();
  Map<String, dynamic> currentResult = {
    'rankedCount': 0,
    'noWinner': false,
    'potentialWinner': null,
    'verifiedWinner': null,
  };
  Map<String, dynamic>? fulfillment;
  Map<String, dynamic>? candidateOverride;
  final List<String> actions = [];
  final List<Map<String, dynamic>> draftBodies = [];
  final List<Map<String, dynamic>> bannerCorrectionBodies = [];
  final List<String> idempotencyKeys = [];
  Completer<Map<String, dynamic>>? publishCompleter;
  Completer<Map<String, dynamic>>? patchCompleter;

  @override
  Future<Map<String, dynamic>> correctAdminGiveawayBanner({
    required String identityToken,
    required String contestId,
    required String idempotencyKey,
    required int revision,
    required String bannerMessage,
    required String reason,
  }) async {
    actions.add('banner-correction');
    idempotencyKeys.add(idempotencyKey);
    if (mutationError != null) throw mutationError!;
    bannerCorrectionBodies.add({
      'revision': revision,
      'bannerMessage': bannerMessage,
      'reason': reason,
    });
    contest = {
      ...contest,
      'revision': revision + 1,
      'bannerMessage': bannerMessage,
    };
    return {'contest': contest};
  }

  @override
  Future<Map<String, dynamic>> fetchAdminGiveaways({
    required String identityToken,
    String? cursor,
    int limit = 25,
  }) async {
    if (listError != null) throw listError!;
    if (malformed) {
      return {
        'records': [
          {'id': 7},
        ],
        'nextCursor': null,
      };
    }
    return {
      'records': [contest],
      'nextCursor': null,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchAdminGiveawayDetail({
    required String identityToken,
    required String contestId,
  }) async {
    if (detailError != null) throw detailError!;
    return {
      'contest': contest,
      'result': currentResult,
      'fulfillment': fulfillment,
    };
  }

  @override
  Future<Map<String, dynamic>> fetchAdminGiveawayCandidates({
    required String identityToken,
    required String contestId,
    String? cursor,
    int limit = 25,
  }) async => {
    'records': [
      candidateOverride ??
          {
            'entrantId': 'entrant-1',
            'displayName': 'Rohan',
            'status': 'ELIGIBLE',
            'verifiedCount': 7,
            'reviewableCount': 1,
            'reachedCountAt': '2026-09-12T12:00:00.000Z',
            'provisionalRank': 1,
            'auditSignals': {
              'sharedRaceCount': 1,
              'correlationFlags': ['DEVICE_CLUSTER'],
            },
            'reviewFacts': [
              {'referralFactId': 'fact-1', 'status': 'FLAGGED'},
            ],
          },
    ],
    'nextCursor': cursor == null ? 'page-2' : null,
  };

  @override
  Future<Map<String, dynamic>> createAdminGiveaway({
    required String identityToken,
    required String idempotencyKey,
    required Map<String, dynamic> body,
  }) async {
    actions.add('create');
    idempotencyKeys.add(idempotencyKey);
    draftBodies.add(body);
    contest = adminContest(status: 'DRAFT', lifecycle: 'DRAFT', revision: 1);
    return {'contest': contest};
  }

  @override
  Future<Map<String, dynamic>> updateAdminGiveaway({
    required String identityToken,
    required String contestId,
    required int revision,
    required Map<String, dynamic> patch,
  }) async {
    if (patchCompleter != null) return patchCompleter!.future;
    if (patchError != null) throw patchError!;
    actions.add('patch');
    draftBodies.add(patch);
    contest = {...contest, ...patch, 'revision': revision + 1};
    contest['rules'] = {
      ...(patch['rules'] as Map<String, dynamic>),
      'sha256':
          'abcdef0123456789abcdef0123456789abcdef0123456789abcdef0123456789',
    };
    return {'contest': contest};
  }

  @override
  Future<Map<String, dynamic>> mutateAdminGiveaway({
    required String identityToken,
    required String contestId,
    required String action,
    required String idempotencyKey,
    required Map<String, dynamic> body,
  }) async {
    actions.add(action);
    idempotencyKeys.add(idempotencyKey);
    if (mutationError != null) throw mutationError!;
    if (action == 'publish' && publishError != null) throw publishError!;
    if (action == 'publish' && publishCompleter != null) {
      return publishCompleter!.future;
    }
    final nextRevision = (contest['revision'] as int) + 1;
    if (action == 'review') throw StateError('wrong action');
    if (action == 'reviews') {
      contest = {...contest, 'revision': nextRevision};
      return {
        'contest': contest,
        'review': {
          'id': 'review-1',
          'referralFactId': 'fact-1',
          'decision': body['decision'],
          'reasonCode': body['reasonCode'],
          'decidedAt': '2026-10-02T11:00:00.000Z',
        },
      };
    }
    if (action == 'finalize') {
      contest = {
        ...contest,
        'revision': nextRevision,
        'finalizedAt': '2026-10-02T12:00:00.000Z',
      };
      currentResult = result();
      return {'contest': contest, 'result': currentResult};
    }
    if (action == 'winner') {
      if (body['decision'] == 'REJECT') {
        contest = {...contest, 'revision': nextRevision};
        currentResult = {
          'rankedCount': 12,
          'noWinner': false,
          'potentialWinner': null,
          'verifiedWinner': null,
        };
        return {'contest': contest, 'result': currentResult};
      }
      contest = {
        ...contest,
        'revision': nextRevision,
        'status': 'FINAL',
        'lifecycleStatus': 'FINAL',
        'finalizedAt': '2026-10-02T12:00:00.000Z',
      };
      currentResult = result(verified: true);
      return {'contest': contest, 'result': currentResult};
    }
    if (action == 'select-next') {
      contest = {...contest, 'revision': nextRevision};
      currentResult = {
        'rankedCount': 12,
        'noWinner': false,
        'potentialWinner': {
          'entrantId': 'entrant-2',
          'displayName': 'Scout',
          'originalRank': 2,
        },
        'verifiedWinner': null,
      };
      return {'contest': contest, 'result': currentResult};
    }
    if (action == 'fulfillment') {
      contest = {...contest, 'revision': nextRevision};
      final transition = body['transition'] as String;
      fulfillment = {
        'status': transition,
        'provider': body['provider'],
        'providerReference': body.containsKey('providerReference')
            ? '••••'
            : null,
        'cashSentMinor':
            transition == 'CASH_SENT' || transition == 'CASH_DELIVERED'
            ? 5000
            : null,
        'cashSentCurrency':
            transition == 'CASH_SENT' || transition == 'CASH_DELIVERED'
            ? 'USD'
            : null,
        'claimedAt': '2026-10-02T13:00:00.000Z',
        'cashSentAt':
            transition == 'CASH_SENT' || transition == 'CASH_DELIVERED'
            ? '2026-10-02T14:00:00.000Z'
            : null,
        'cashDeliveredAt': transition == 'CASH_DELIVERED'
            ? '2026-10-02T15:00:00.000Z'
            : null,
        'coinsAwardedAt': null,
        'coinTransactionId': null,
        'fulfilledAt': null,
      };
      return {'contest': contest, 'fulfillment': fulfillment};
    }
    if (action == 'award-coins') {
      contest = {...contest, 'revision': nextRevision};
      fulfillment = {
        ...fulfillment!,
        'status': 'COINS_AWARDED',
        'coinsAwardedAt': '2026-10-02T16:00:00.000Z',
        'coinTransactionId': 'coin-tx-1',
        'fulfilledAt': '2026-10-02T16:00:00.000Z',
      };
      return {'contest': contest, 'fulfillment': fulfillment};
    }
    if (action == 'archive') {
      contest = {
        ...contest,
        'revision': nextRevision,
        'status': 'ARCHIVED',
        'lifecycleStatus': 'ARCHIVED',
        'archivedAt': '2026-10-03T12:00:00.000Z',
      };
      return {'contest': contest};
    }
    contest = {...contest, 'revision': nextRevision};
    return {'contest': contest};
  }
}

Future<AuthService> auth() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'identity',
    'auth_session_token': 'session',
    'auth_backend_user_id': 'admin-1',
    'auth_display_name': 'Admin',
  });
  final service = AuthService();
  await service.restoreSession();
  return service;
}

Future<void> _pump(WidgetTester tester, _AdminGiveawayApi api) async {
  tester.view.physicalSize = const Size(390, 844);
  tester.view.devicePixelRatio = 1;
  addTearDown(tester.view.reset);
  await tester.pumpWidget(
    MaterialApp(
      home: AdminGiveawayScreen(
        authService: await auth(),
        backendApiService: api,
      ),
    ),
  );
  await tester.pump();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(
    () => PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    ),
  );

  test('candidate fixture matches the pinned defensive model', () async {
    final raw = await _AdminGiveawayApi().fetchAdminGiveawayCandidates(
      identityToken: 'identity',
      contestId: 'contest-1',
    );
    final records = raw['records']! as List;
    expect(AdminGiveawayCandidate.tryParse(records.single), isNotNull);
    expect(
      AdminGiveawayContest.tryParse({
        ...adminContest(),
        'eligibleRegions': ['US-ZZ'],
      }),
      isNull,
    );
  });

  test('candidate and fulfillment lifecycle values fail closed', () async {
    final raw = await _AdminGiveawayApi().fetchAdminGiveawayCandidates(
      identityToken: 'identity',
      contestId: 'contest-1',
    );
    final candidate = Map<String, dynamic>.from(
      (raw['records']! as List).single as Map,
    );
    for (final invalidCandidate in [
      {...candidate, 'status': 'UNKNOWN'},
      {...candidate, 'status': 'INELIGIBLE'},
      {...candidate, 'status': 'WITHDRAWN'},
      {
        ...candidate,
        'verifiedCount': 0,
        'provisionalRank': 1,
        'reachedCountAt': '2026-09-12T12:00:00.000Z',
      },
      {...candidate, 'provisionalRank': null},
      {...candidate, 'reachedCountAt': null},
      {...candidate, 'provisionalRank': 0},
      {
        ...candidate,
        'reviewableCount': 0,
        'reviewFacts': [
          {'referralFactId': 'fact-1', 'status': 'FLAGGED'},
        ],
      },
    ]) {
      expect(AdminGiveawayCandidate.tryParse(invalidCandidate), isNull);
    }

    const empty = <String, dynamic>{
      'provider': null,
      'providerReference': null,
      'cashSentMinor': null,
      'cashSentCurrency': null,
      'claimedAt': null,
      'cashSentAt': null,
      'cashDeliveredAt': null,
      'coinsAwardedAt': null,
      'coinTransactionId': null,
      'fulfilledAt': null,
    };
    expect(
      AdminGiveawayFulfillment.tryParse({...empty, 'status': 'UNKNOWN'}),
      isNull,
    );
    expect(
      AdminGiveawayFulfillment.tryParse({
        ...empty,
        'status': 'UNCLAIMED',
        'cashSentAt': '2026-10-03T12:00:00.000Z',
      }),
      isNull,
    );
    expect(
      AdminGiveawayFulfillment.tryParse({...empty, 'status': 'CLAIMED'}),
      isNull,
    );
    expect(
      AdminGiveawayFulfillment.tryParse({
        ...empty,
        'status': 'CASH_SENT',
        'claimedAt': '2026-10-03T11:00:00.000Z',
        'cashSentAt': '2026-10-03T12:00:00.000Z',
      }),
      isNull,
    );
    expect(
      AdminGiveawayFulfillment.tryParse({
        ...empty,
        'status': 'CASH_DELIVERED',
        'provider': 'Wise',
        'providerReference': '••••',
        'cashSentMinor': 5000,
        'cashSentCurrency': 'USD',
        'claimedAt': '2026-10-03T11:00:00.000Z',
        'cashSentAt': '2026-10-03T12:00:00.000Z',
      }),
      isNull,
    );
    expect(
      AdminGiveawayFulfillment.tryParse({
        ...empty,
        'status': 'COINS_AWARDED',
        'provider': 'Wise',
        'providerReference': '••••',
        'cashSentMinor': 5000,
        'cashSentCurrency': 'USD',
        'claimedAt': '2026-10-03T11:00:00.000Z',
        'cashSentAt': '2026-10-03T12:00:00.000Z',
        'cashDeliveredAt': '2026-10-04T12:00:00.000Z',
      }),
      isNull,
    );

    expect(
      AdminGiveawayFulfillment.tryParse({...empty, 'status': 'UNCLAIMED'}),
      isNotNull,
    );
    expect(
      AdminGiveawayFulfillment.tryParse({
        ...empty,
        'status': 'CLAIMED',
        'claimedAt': '2026-10-03T11:00:00.000Z',
      }),
      isNotNull,
    );
    expect(
      AdminGiveawayFulfillment.tryParse({
        ...empty,
        'status': 'COINS_AWARDED',
        'coinsAwardedAt': '2026-10-03T12:00:00.000Z',
        'coinTransactionId': 'coin-tx-only',
        'fulfilledAt': '2026-10-03T12:00:00.000Z',
      }),
      isNotNull,
    );
    expect(
      AdminGiveawayFulfillment.tryParse({
        ...empty,
        'status': 'CASH_DELIVERED',
        'provider': 'ACH',
        'providerReference': '••••',
        'cashSentMinor': 7500,
        'cashSentCurrency': 'USD',
        'claimedAt': '2026-10-03T10:00:00.000Z',
        'cashSentAt': '2026-10-03T11:00:00.000Z',
        'cashDeliveredAt': '2026-10-03T12:00:00.000Z',
        'fulfilledAt': '2026-10-03T12:00:00.000Z',
      }),
      isNotNull,
    );
  });

  test(
    'admin contest requires full territory rules and lifecycle coherence',
    () {
      final valid = adminContest();
      final duplicateRegions = giveawayUsRegionsV1.toList()
        ..remove('US-WY')
        ..add('US-AL');
      final invalid = <Map<String, dynamic>>[
        {
          ...valid,
          'eligibleRegions': ['US-NY', 'US-CA', 'US-DC'],
        },
        {...valid, 'eligibleRegions': duplicateRegions},
        {...valid}..remove('sponsor'),
        {...valid, 'sponsor': null},
        {
          ...valid,
          'rules': {...valid['rules'] as Map, 'sha256': 'abcdef123456'},
        },
        {
          ...valid,
          'rules': {...valid['rules'] as Map, 'sections': const []},
        },
        {...valid, 'status': 'ACTIVE', 'lifecycleStatus': 'DRAFT'},
        {...valid, 'status': 'FINAL', 'lifecycleStatus': 'PUBLISHED'},
        {
          ...valid,
          'status': 'FINAL',
          'lifecycleStatus': 'FINAL',
          'finalizedAt': null,
        },
        {
          ...valid,
          'status': 'CANCELLED',
          'lifecycleStatus': 'CANCELLED',
          'cancelledAt': null,
        },
        {
          ...valid,
          'status': 'ARCHIVED',
          'lifecycleStatus': 'ARCHIVED',
          'archivedAt': null,
        },
        {...valid, 'publishedAt': null},
        {...valid, 'frozenAt': null},
      ];
      for (final payload in invalid) {
        expect(AdminGiveawayContest.tryParse(payload), isNull);
      }

      expect(
        AdminGiveawayContest.tryParse(
          adminContest(status: 'DRAFT', lifecycle: 'DRAFT'),
        ),
        isNotNull,
      );
      expect(
        AdminGiveawayContest.tryParse({
          ...valid,
          'status': 'FINAL',
          'lifecycleStatus': 'FINAL',
          'finalizedAt': '2026-10-02T12:00:00.000Z',
        }),
        isNotNull,
      );
      expect(
        AdminGiveawayContest.tryParse({
          ...valid,
          'cashMinor': 0,
          'coinPrize': 7500,
        }),
        isNotNull,
      );
      expect(
        AdminGiveawayContest.tryParse({
          ...valid,
          'cashMinor': 12500,
          'coinPrize': 0,
        }),
        isNotNull,
      );
      expect(
        AdminGiveawayContest.tryParse({
          ...valid,
          'cashMinor': 0,
          'coinPrize': 1000000,
        }),
        isNotNull,
      );
      for (final prizes in [
        (cash: 0, coins: 0),
        (cash: -1, coins: 5000),
        (cash: 5000, coins: -1),
        (cash: 5000, coins: 1000001),
      ]) {
        expect(
          AdminGiveawayContest.tryParse({
            ...valid,
            'cashMinor': prizes.cash,
            'coinPrize': prizes.coins,
          }),
          isNull,
        );
      }
    },
  );

  test('admin result rejects impossible winner combinations', () {
    final winner = {
      'entrantId': 'entrant-1',
      'displayName': 'Rohan',
      'originalRank': 1,
    };
    for (final payload in [
      {
        'rankedCount': 0,
        'noWinner': true,
        'potentialWinner': winner,
        'verifiedWinner': null,
      },
      {
        'rankedCount': 2,
        'noWinner': false,
        'potentialWinner': winner,
        'verifiedWinner': winner,
      },
      {
        'rankedCount': 0,
        'noWinner': false,
        'potentialWinner': winner,
        'verifiedWinner': null,
      },
      {
        'rankedCount': 2,
        'noWinner': true,
        'potentialWinner': null,
        'verifiedWinner': winner,
      },
    ]) {
      expect(AdminGiveawayResult.tryParse(payload), isNull);
    }
  });

  test('admin mutation fingerprint never retains a payout reference', () {
    const reference = 'private-bank-reference-9237';
    final first = adminGiveawayRequestFingerprint('fulfillment', {
      'revision': 8,
      'transition': 'CASH_SENT',
      'provider': 'ACH',
      'providerReference': reference,
    });
    final replay = adminGiveawayRequestFingerprint('fulfillment', {
      'revision': 8,
      'transition': 'CASH_SENT',
      'provider': 'ACH',
      'providerReference': reference,
    });
    expect(first, replay);
    expect(first, isNot(contains(reference)));
  });

  testWidgets('invalid lifecycle cannot expose destructive contest controls', (
    tester,
  ) async {
    final api = _AdminGiveawayApi()
      ..contest = {
        ...adminContest(status: 'DRAFT', lifecycle: 'DRAFT'),
        'status': 'FINAL',
      };
    await _pump(tester, api);
    expect(
      find.text('Giveaway tools require the latest server'),
      findsOneWidget,
    );
    expect(find.text('ARCHIVE'), findsNothing);
    expect(find.text('CANCEL CONTEST'), findsNothing);
  });

  testWidgets(
    'impossible contest result and fulfillment snapshots fail closed',
    (tester) async {
      final emptyFulfillment = <String, dynamic>{
        'status': 'UNCLAIMED',
        'provider': null,
        'providerReference': null,
        'cashSentMinor': null,
        'cashSentCurrency': null,
        'claimedAt': null,
        'cashSentAt': null,
        'cashDeliveredAt': null,
        'coinsAwardedAt': null,
        'coinTransactionId': null,
        'fulfilledAt': null,
      };
      final cancelled = {
        ...adminContest(),
        'status': 'CANCELLED',
        'lifecycleStatus': 'CANCELLED',
        'finalizedAt': null,
        'cancelledAt': '2026-10-02T12:00:00.000Z',
        'publicReason': 'Contest cancelled.',
        'amendedRulesVersion': '2026-09-v2',
      };
      final archivedFinal = {
        ...adminContest(status: 'FINAL', lifecycle: 'FINAL'),
        'status': 'ARCHIVED',
        'lifecycleStatus': 'ARCHIVED',
        'archivedAt': '2026-10-03T12:00:00.000Z',
      };
      final cases =
          <
            ({
              Map<String, dynamic> contest,
              Map<String, dynamic> result,
              Map<String, dynamic>? fulfillment,
            })
          >[
            (contest: adminContest(), result: result(), fulfillment: null),
            (
              contest: adminContest(status: 'FINAL', lifecycle: 'FINAL'),
              result: {
                'rankedCount': 0,
                'noWinner': true,
                'potentialWinner': null,
                'verifiedWinner': null,
              },
              fulfillment: emptyFulfillment,
            ),
            (contest: cancelled, result: result(), fulfillment: null),
            (contest: archivedFinal, result: result(), fulfillment: null),
          ];

      for (final value in cases) {
        final api = _AdminGiveawayApi()
          ..contest = value.contest
          ..currentResult = value.result
          ..fulfillment = value.fulfillment;
        await _pump(tester, api);
        await tester.tap(find.text('Bara Referral Contest'));
        await tester.pump();
        await tester.pump(const Duration(milliseconds: 400));
        expect(
          find.text('Giveaway tools require the latest server'),
          findsOneWidget,
        );
        expect(find.text('VERIFY WINNER'), findsNothing);
        expect(find.text('MARK CLAIMED'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets('malformed candidate coherence fails the admin surface closed', (
    tester,
  ) async {
    final api = _AdminGiveawayApi()
      ..candidateOverride = {
        'entrantId': 'entrant-1',
        'displayName': 'Rohan',
        'status': 'INELIGIBLE',
        'verifiedCount': 7,
        'reviewableCount': 1,
        'reachedCountAt': '2026-09-12T12:00:00.000Z',
        'provisionalRank': 1,
        'auditSignals': {
          'sharedRaceCount': 1,
          'correlationFlags': ['DEVICE_CLUSTER'],
        },
        'reviewFacts': [
          {'referralFactId': 'fact-1', 'status': 'FLAGGED'},
        ],
      };
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Giveaway tools require the latest server'),
      findsOneWidget,
    );
    expect(find.text('APPROVE'), findsNothing);
  });

  testWidgets(
    'older backend and malformed list fail closed with latest-server message',
    (tester) async {
      for (final api in [
        _AdminGiveawayApi(
          listError: const ApiException('missing', statusCode: 404),
        ),
        _AdminGiveawayApi(malformed: true),
      ]) {
        await _pump(tester, api);
        expect(
          find.text('Giveaway tools require the latest server'),
          findsOneWidget,
        );
        expect(find.text('CREATE CONTEST'), findsNothing);
        await tester.pumpWidget(const SizedBox());
      }
    },
  );

  testWidgets(
    'reopens persistent verifying state, paginates candidates, and reviews fact',
    (tester) async {
      final api = _AdminGiveawayApi();
      await _pump(tester, api);
      expect(find.text('VERIFYING'), findsOneWidget);
      await tester.tap(find.text('Bara Referral Contest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      expect(find.text('CANDIDATE REVIEW'), findsOneWidget);
      expect(find.textContaining('Rohan'), findsWidgets);
      expect(find.textContaining('DEVICE_CLUSTER'), findsOneWidget);
      expect(find.text('LOAD MORE'), findsOneWidget);
      await tester.tap(find.text('APPROVE FACT'));
      await tester.pump();
      expect(find.textContaining('Approve this referral fact'), findsOneWidget);
      await tester.tap(find.text('APPROVE'));
      await tester.pump();
      expect(api.actions.where((value) => value == 'reviews'), hasLength(1));
    },
  );

  testWidgets('detail 404 asks for the latest server without losing Admin', (
    tester,
  ) async {
    final api = _AdminGiveawayApi(
      detailError: const ApiException('missing', statusCode: 404),
    );
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    expect(
      find.text('Giveaway tools require the latest server'),
      findsOneWidget,
    );
  });

  testWidgets(
    'full winner, cash, exactly-once coins, and archive controls progress in order',
    (tester) async {
      final api = _AdminGiveawayApi();
      await _pump(tester, api);
      await tester.tap(find.text('Bara Referral Contest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();
      await tester.tap(find.text('FINALIZE RESULTS'));
      await tester.pump();
      await tester.tap(find.text('FINALIZE'));
      await tester.pump();
      expect(find.text('POTENTIAL WINNER: ROHAN'), findsOneWidget);
      await tester.tap(find.text('VERIFY WINNER'));
      await tester.pump();
      await tester.tap(find.text('VERIFY'));
      await tester.pump();
      expect(find.text('VERIFIED WINNER: ROHAN'), findsOneWidget);

      for (final pair in [
        ('MARK CLAIMED', 'CLAIMED'),
        ('MARK CASH SENT', 'CASH_SENT'),
        ('MARK CASH DELIVERED', 'CASH_DELIVERED'),
      ]) {
        await tester.ensureVisible(find.text(pair.$1));
        await tester.tap(find.text(pair.$1));
        await tester.pump();
        if (pair.$2 == 'CASH_SENT' || pair.$2 == 'CASH_DELIVERED') {
          await tester.enterText(
            find.byKey(const Key('giveaway-provider')),
            'ACH',
          );
          await tester.enterText(
            find.byKey(const Key('giveaway-provider-reference')),
            'secret-ref',
          );
        }
        await tester.tap(find.text('CONFIRM'));
        await tester.pump();
        expect(find.text(pair.$2), findsWidgets);
      }
      await tester.ensureVisible(find.text('AWARD 5,000 COINS'));
      await tester.tap(find.text('AWARD 5,000 COINS'));
      await tester.pump();
      await tester.tap(find.text('AWARD COINS'));
      await tester.tap(find.text('AWARD COINS'), warnIfMissed: false);
      await tester.pump();
      expect(
        api.actions.where((value) => value == 'award-coins'),
        hasLength(1),
      );
      expect(find.text('COINS_AWARDED'), findsOneWidget);
      expect(find.textContaining('coin-tx-1'), findsOneWidget);
      await tester.tap(find.text('ARCHIVE'));
      await tester.pump();
      await tester.tap(find.text('ARCHIVE CONTEST'));
      await tester.pump();
      expect(find.text('ARCHIVED'), findsWidgets);
    },
  );

  testWidgets('coin-only verified winner can award coins immediately', (
    tester,
  ) async {
    final api = _AdminGiveawayApi()
      ..contest = {
        ...adminContest(status: 'FINAL', lifecycle: 'FINAL'),
        'cashMinor': 0,
        'coinPrize': 777,
      }
      ..currentResult = result(verified: true)
      ..fulfillment = {
        'status': 'UNCLAIMED',
        'provider': null,
        'providerReference': null,
        'cashSentMinor': null,
        'cashSentCurrency': null,
        'claimedAt': null,
        'cashSentAt': null,
        'cashDeliveredAt': null,
        'coinsAwardedAt': null,
        'coinTransactionId': null,
        'fulfilledAt': null,
      };
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('MARK CLAIMED'), findsNothing);
    expect(find.text('AWARD 777 COINS'), findsOneWidget);
    await tester.ensureVisible(find.text('AWARD 777 COINS'));
    await tester.pump(const Duration(milliseconds: 100));
    await tester.tap(find.text('AWARD 777 COINS'));
    await tester.pump();
    await tester.tap(find.text('AWARD COINS'));
    await tester.pump();

    expect(
      api.actions.where((action) => action == 'award-coins'),
      hasLength(1),
    );
    expect(find.text('COINS_AWARDED'), findsOneWidget);
    expect(find.textContaining('coin-tx-1'), findsOneWidget);
  });

  testWidgets('cash-only delivered fulfillment reopens as complete', (
    tester,
  ) async {
    final api = _AdminGiveawayApi()
      ..contest = {
        ...adminContest(status: 'FINAL', lifecycle: 'FINAL'),
        'cashMinor': 7500,
        'coinPrize': 0,
      }
      ..currentResult = result(verified: true)
      ..fulfillment = {
        'status': 'CASH_DELIVERED',
        'provider': 'ACH',
        'providerReference': '••••',
        'cashSentMinor': 7500,
        'cashSentCurrency': 'USD',
        'claimedAt': '2026-10-03T10:00:00.000Z',
        'cashSentAt': '2026-10-03T11:00:00.000Z',
        'cashDeliveredAt': '2026-10-03T12:00:00.000Z',
        'coinsAwardedAt': null,
        'coinTransactionId': null,
        'fulfilledAt': '2026-10-03T12:00:00.000Z',
      };
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));

    expect(find.text('CASH_DELIVERED'), findsOneWidget);
    expect(find.textContaining('latest server'), findsNothing);
    expect(find.textContaining('AWARD'), findsNothing);
  });

  testWidgets(
    'published banner correction requires a reason and explicit confirmation',
    (tester) async {
      final api = _AdminGiveawayApi();
      await _pump(tester, api);
      await tester.tap(find.text('Bara Referral Contest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text('BANNER CORRECTION'), findsOneWidget);
      expect(find.text(r'Win US$50 + 5,000 coins.'), findsOneWidget);
      expect(
        tester
            .widget<PillButton>(
              find.widgetWithText(PillButton, 'REVIEW CORRECTION'),
            )
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const Key('giveaway-banner-correction')),
      );
      await tester.pump();
      await tester.enterText(
        find.byKey(const Key('giveaway-banner-correction')),
        r'Corrected: win US$50 + 5,000 Bara coins.',
      );
      await tester.enterText(
        find.byKey(const Key('giveaway-banner-correction-reason')),
        'Corrected end-user wording without changing material terms.',
      );
      await tester.pump();
      await tester.ensureVisible(find.text('REVIEW CORRECTION'));
      await tester.pump();
      await tester.tap(find.text('REVIEW CORRECTION'));
      await tester.pump();
      expect(find.text('Apply audited banner correction?'), findsOneWidget);
      expect(
        find.textContaining('This correction and its reason are audited'),
        findsOneWidget,
      );
      await tester.tap(find.text('APPLY CORRECTION'));
      await tester.pump();

      expect(
        api.actions.where((value) => value == 'banner-correction'),
        hasLength(1),
      );
      expect(api.bannerCorrectionBodies.single, {
        'revision': 5,
        'bannerMessage': r'Corrected: win US$50 + 5,000 Bara coins.',
        'reason': 'Corrected end-user wording without changing material terms.',
      });
      expect(
        find.text(r'Corrected: win US$50 + 5,000 Bara coins.'),
        findsOneWidget,
      );
    },
  );

  testWidgets('invalid banner correction remains actionable', (tester) async {
    final api = _AdminGiveawayApi(
      mutationError: const ApiException(
        'Invalid banner correction',
        statusCode: 400,
        code: 'INVALID_BANNER_CORRECTION',
      ),
    );
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    await tester.ensureVisible(
      find.byKey(const Key('giveaway-banner-correction')),
    );
    await tester.enterText(
      find.byKey(const Key('giveaway-banner-correction')),
      r'Corrected: win US$50 + 5,000 Bara coins.',
    );
    await tester.enterText(
      find.byKey(const Key('giveaway-banner-correction-reason')),
      'Corrected end-user wording without changing material terms.',
    );
    await tester.pump();
    await tester.ensureVisible(find.text('REVIEW CORRECTION'));
    await tester.pump();
    await tester.tap(find.text('REVIEW CORRECTION'));
    await tester.pump();
    await tester.tap(find.text('APPLY CORRECTION'));
    await tester.pump();
    expect(
      find.text(
        'Banner correction was rejected. Check the new copy and audit reason.',
      ),
      findsOneWidget,
    );
    expect(
      find.text(r'Corrected: win US$50 + 5,000 Bara coins.'),
      findsOneWidget,
    );
  });

  testWidgets(
    'rejecting a potential winner unlocks select-next only afterward',
    (tester) async {
      final api = _AdminGiveawayApi()
        ..contest = {
          ...adminContest(),
          'finalizedAt': '2026-10-02T12:00:00.000Z',
        }
        ..currentResult = result();
      await _pump(tester, api);
      await tester.tap(find.text('Bara Referral Contest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      expect(find.text('SELECT NEXT'), findsNothing);
      await tester.ensureVisible(find.text('REJECT WINNER'));
      await tester.pump();
      await tester.tap(find.text('REJECT WINNER'));
      await tester.pump();
      await tester.tap(find.text('REJECT'));
      await tester.pump();
      expect(find.text('SELECT NEXT'), findsOneWidget);
      await tester.ensureVisible(find.text('SELECT NEXT'));
      await tester.pump();
      await tester.tap(find.widgetWithText(PillButton, 'SELECT NEXT'));
      await tester.pump();
      await tester.tap(find.widgetWithText(TextButton, 'SELECT NEXT'));
      await tester.pump();
      expect(find.text('POTENTIAL WINNER: SCOUT'), findsOneWidget);
    },
  );

  testWidgets('draft editor exposes the simplified coin-only setup', (
    tester,
  ) async {
    final api = _AdminGiveawayApi()
      ..contest = adminContest(
        status: 'DRAFT',
        lifecycle: 'DRAFT',
        revision: 2,
      );
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.pump();
    expect(find.byKey(const Key('giveaway-cash-prize-toggle')), findsNothing);
    expect(find.byKey(const Key('giveaway-coin-prize-toggle')), findsOneWidget);
    expect(find.textContaining('no cash prizes'), findsOneWidget);
    expect(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Coin prize',
      ),
      findsOneWidget,
    );
    expect(find.text('SAVE DRAFT'), findsOneWidget);
    expect(find.text('PUBLISH'), findsOneWidget);
    expect(find.text('BANNER CORRECTION'), findsNothing);
    expect(find.text('LEGAL DETAILS (ONE-TIME SETUP)'), findsOneWidget);
    final titleField = find.byWidgetPredicate(
      (widget) =>
          widget is TextField && widget.decoration?.labelText == 'Title',
    );
    await tester.enterText(titleField, 'Edited legal title');
    await tester.pump();
    expect(find.text('Save draft changes before publishing.'), findsOneWidget);
    expect(
      tester
          .widget<PillButton>(find.widgetWithText(PillButton, 'PUBLISH'))
          .onPressed,
      isNull,
    );
  });

  testWidgets(
    'editing a legacy draft title preserves every frozen legacy field',
    (tester) async {
      const originalRules = <String, dynamic>{
        'version': 'legacy-september-v7',
        'sha256':
            '0123456789abcdef0123456789abcdef0123456789abcdef0123456789abcdef',
        'sections': [
          {
            'heading': 'Original entry rule',
            'body': 'This historical rule must survive unrelated edits.',
          },
          {
            'heading': 'Original tie break',
            'body': 'The first entrant to reach the final score wins.',
          },
        ],
      };
      const originalSocial = <Map<String, dynamic>>[
        {
          'platform': 'instagram',
          'label': 'Follow the original account',
          'url': 'https://www.instagram.com/barastep/',
        },
      ];
      final originalRegions = giveawayUsRegionsV1.toList()..sort();
      final api = _AdminGiveawayApi()
        ..contest = {
          ...adminContest(status: 'DRAFT', lifecycle: 'DRAFT', revision: 2),
          'cashCurrency': 'USD',
          'cashMinor': 7300,
          'coinPrize': 4100,
          'minimumAge': 18,
          'eligibleCountries': const ['US'],
          'eligibleRegions': originalRegions,
          'sponsor': const {
            'legalName': 'Original Sponsor LLC',
            'mailingAddress': '77 Original Trail',
          },
          'rules': originalRules,
          'socialLinks': originalSocial,
          'bannerMessage': r'Original US$73 + 4,100 coin prize.',
        };

      await _pump(tester, api);
      await tester.tap(find.text('Bara Referral Contest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final title = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Title',
      );
      await tester.enterText(title, 'Edited title only');
      await tester.pump();
      final save = find.widgetWithText(PillButton, 'SAVE DRAFT');
      await tester.ensureVisible(save);
      tester.widget<PillButton>(save).onPressed!();
      await tester.pump();

      final body = api.draftBodies.single;
      expect(body['title'], 'Edited title only');
      expect(body['cashCurrency'], 'USD');
      expect(body['cashMinor'], 7300);
      expect(body['coinPrize'], 4100);
      expect(body['minimumAge'], 18);
      expect(body['eligibleRegions'], originalRegions);
      expect(body['sponsor'], const {
        'legalName': 'Original Sponsor LLC',
        'mailingAddress': '77 Original Trail',
      });
      expect(body['rules'], {
        'version': originalRules['version'],
        'sections': originalRules['sections'],
      });
      expect(body['socialLinks'], originalSocial);
      expect(body['bannerMessage'], r'Original US$73 + 4,100 coin prize.');
    },
  );

  testWidgets(
    'create draft uses compact global coin-only fields and banner copy',
    (tester) async {
      final api = _AdminGiveawayApi()..contest = adminContest();
      await _pump(tester, api);
      await tester.tap(find.text('CREATE CONTEST'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      Finder field(String label) => find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == label,
      );

      await tester.enterText(field('Slug'), 'fall-referrals');
      expect(field('Starts at (ISO-8601)'), findsNothing);
      expect(field('Ends at (ISO-8601)'), findsNothing);
      expect(find.byKey(const Key('giveaway-start-date')), findsOneWidget);
      expect(find.byKey(const Key('giveaway-start-time')), findsOneWidget);
      expect(find.byKey(const Key('giveaway-end-date')), findsOneWidget);
      expect(find.byKey(const Key('giveaway-end-time')), findsOneWidget);
      expect(
        find.text('Picker values use this device’s local timezone.'),
        findsNWidgets(2),
      );
      await tester.tap(find.byKey(const Key('giveaway-start-time')));
      await tester.pump();
      expect(find.byType(TimePickerDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(TimePickerDialog))).pop();
      await tester.pump();
      await tester.tap(find.byKey(const Key('giveaway-start-date')));
      await tester.pump();
      expect(find.byType(DatePickerDialog), findsOneWidget);
      Navigator.of(tester.element(find.byType(DatePickerDialog))).pop();
      await tester.pump();
      expect(find.byKey(const Key('giveaway-advanced-details')), findsNothing);
      expect(field('Sponsor legal name'), findsNothing);
      expect(field('Sponsor mailing address'), findsNothing);
      expect(field('Governing timezone'), findsNothing);
      expect(field('Home-card message'), findsOneWidget);
      await tester.enterText(
        field('Home-card message'),
        'Bring your crew. The referral trail is open.',
      );
      await tester.ensureVisible(find.text('SAVE DRAFT'));
      await tester.tap(find.text('SAVE DRAFT'));
      await tester.pump();

      expect(api.actions.where((value) => value == 'create'), hasLength(1));
      final body = api.draftBodies.single;
      expect(body.keys.toSet(), {
        'slug',
        'title',
        'startsAt',
        'endsAt',
        'coinPrize',
        'bannerMessage',
        'eligibilityMode',
      });
      expect(body['coinPrize'], 5000);
      expect(
        body['bannerMessage'],
        'Bring your crew. The referral trail is open.',
      );
      expect(body['eligibilityMode'], 'BARA_ACCOUNT');
      expect(DateTime.parse(body['startsAt'] as String).isUtc, isTrue);
      expect(DateTime.parse(body['endsAt'] as String).isUtc, isTrue);
    },
  );

  testWidgets('slug validation matches the backend and prevents save', (
    tester,
  ) async {
    final api = _AdminGiveawayApi()
      ..contest = adminContest(
        status: 'DRAFT',
        lifecycle: 'DRAFT',
        revision: 2,
      );
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    final slug = find.byWidgetPredicate(
      (widget) => widget is TextField && widget.decoration?.labelText == 'Slug',
    );
    for (final invalid in [
      '',
      'Uppercase',
      '-leading',
      'trailing-',
      'two--hyphens',
      List.filled(81, 'a').join(),
    ]) {
      await tester.enterText(slug, invalid);
      await tester.pump();
      expect(
        find.text(
          'Use 1–80 lowercase letters, numbers, and single hyphens only.',
        ),
        findsOneWidget,
      );
      expect(
        tester
            .widget<PillButton>(find.widgetWithText(PillButton, 'SAVE DRAFT'))
            .onPressed,
        isNull,
      );
    }
    await tester.enterText(slug, 'valid-referrals-2026');
    await tester.pump();
    expect(
      find.text(
        'Use 1–80 lowercase letters, numbers, and single hyphens only.',
      ),
      findsNothing,
    );
    expect(
      tester
          .widget<PillButton>(find.widgetWithText(PillButton, 'SAVE DRAFT'))
          .onPressed,
      isNotNull,
    );
  });

  testWidgets(
    'legacy coin prize edits preserve cash and require a positive prize',
    (tester) async {
      final api = _AdminGiveawayApi()
        ..contest = adminContest(
          status: 'DRAFT',
          lifecycle: 'DRAFT',
          revision: 2,
        );
      await _pump(tester, api);
      await tester.tap(find.text('Bara Referral Contest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      final coins = find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Coin prize',
      );
      await tester.enterText(coins, '7500');
      await tester.pump();
      await tester.ensureVisible(find.text('SAVE DRAFT'));
      await tester.tap(find.text('SAVE DRAFT'));
      await tester.pump();
      expect(api.draftBodies.single['cashCurrency'], 'USD');
      expect(api.draftBodies.single['cashMinor'], 5000);
      expect(api.draftBodies.single['coinPrize'], 7500);

      api.draftBodies.clear();
      await tester.ensureVisible(
        find.byKey(const Key('giveaway-coin-prize-toggle')),
      );
      await tester.tap(find.byKey(const Key('giveaway-coin-prize-toggle')));
      await tester.pump();
      expect(
        find.text('Enable a prize with a value greater than zero.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<PillButton>(find.widgetWithText(PillButton, 'SAVE DRAFT'))
            .onPressed,
        isNull,
      );
      await tester.ensureVisible(
        find.byKey(const Key('giveaway-coin-prize-toggle')),
      );
      await tester.tap(find.byKey(const Key('giveaway-coin-prize-toggle')));
      await tester.pump();
      await tester.enterText(coins, '-1');
      await tester.pump();
      expect(
        find.text('Coin prize must be a whole number from 0 to 1,000,000.'),
        findsOneWidget,
      );
      await tester.enterText(coins, '1000001');
      await tester.pump();
      expect(
        find.text('Coin prize must be a whole number from 0 to 1,000,000.'),
        findsOneWidget,
      );
      expect(
        tester
            .widget<PillButton>(find.widgetWithText(PillButton, 'SAVE DRAFT'))
            .onPressed,
        isNull,
      );
    },
  );

  testWidgets(
    'publish double tap is single-flight and validation failure stays actionable',
    (tester) async {
      final api =
          _AdminGiveawayApi(
              publishError: const ApiException(
                'bad rules',
                statusCode: 400,
                code: 'PUBLISH_VALIDATION_FAILED',
              ),
            )
            ..contest = adminContest(
              status: 'DRAFT',
              lifecycle: 'DRAFT',
              revision: 2,
            );
      await _pump(tester, api);
      await tester.tap(find.text('Bara Referral Contest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.ensureVisible(find.text('PUBLISH'));
      await tester.drag(
        find.byType(SingleChildScrollView),
        const Offset(0, -250),
      );
      await tester.pump();
      await tester.tap(find.text('PUBLISH'));
      await tester.tap(find.text('PUBLISH'), warnIfMissed: false);
      await tester.pump();
      expect(find.text('Publish immutable contest?'), findsOneWidget);
      await tester.tap(find.widgetWithText(TextButton, 'PUBLISH'));
      await tester.pump();

      expect(api.actions.where((value) => value == 'publish'), hasLength(1));
      expect(
        find.text(
          'Publishing validation failed. Review the contest fields and rules.',
        ),
        findsOneWidget,
      );
    },
  );

  testWidgets('revision conflict offers persistent detail reload', (
    tester,
  ) async {
    final api = _AdminGiveawayApi(
      patchError: const ApiException(
        'stale',
        statusCode: 409,
        code: 'REVISION_CONFLICT',
      ),
    )..contest = adminContest(status: 'DRAFT', lifecycle: 'DRAFT', revision: 2);
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('SAVE DRAFT'));
    await tester.tap(find.text('SAVE DRAFT'));
    await tester.pump();
    expect(find.text('RELOAD LATEST'), findsOneWidget);
  });

  testWidgets('draft controls lock while a save request is in flight', (
    tester,
  ) async {
    final completer = Completer<Map<String, dynamic>>();
    final api = _AdminGiveawayApi()
      ..contest = adminContest(status: 'DRAFT', lifecycle: 'DRAFT', revision: 2)
      ..patchCompleter = completer;
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('SAVE DRAFT'));
    await tester.tap(find.text('SAVE DRAFT'));
    await tester.pump();
    final title = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Title',
      ),
    );
    expect(title.enabled, isFalse);
    expect(find.text('ADD RULE SECTION'), findsNothing);
    expect(
      tester
          .widget<TextField>(
            find.byWidgetPredicate(
              (widget) =>
                  widget is TextField &&
                  widget.decoration?.labelText == 'Coin prize',
            ),
          )
          .enabled,
      isFalse,
    );
    completer.complete({'contest': api.contest});
    await tester.pump();
  });

  testWidgets('draft controls lock while publish is in flight', (tester) async {
    final completer = Completer<Map<String, dynamic>>();
    final api = _AdminGiveawayApi()
      ..contest = adminContest(status: 'DRAFT', lifecycle: 'DRAFT', revision: 2)
      ..publishCompleter = completer;
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    await tester.ensureVisible(find.text('PUBLISH'));
    await tester.tap(find.text('PUBLISH'));
    await tester.pump();
    await tester.tap(find.widgetWithText(TextButton, 'PUBLISH'));
    await tester.pump();

    final title = tester.widget<TextField>(
      find.byWidgetPredicate(
        (widget) =>
            widget is TextField && widget.decoration?.labelText == 'Title',
      ),
    );
    expect(title.enabled, isFalse);
    expect(find.text('ADD RULE SECTION'), findsNothing);
    expect(
      tester
          .widget<PillButton>(find.widgetWithText(PillButton, 'SAVE DRAFT'))
          .onPressed,
      isNull,
    );
    expect(find.byTooltip('Remove'), findsNothing);

    completer.complete({'contest': adminContest(revision: 3)});
    await tester.pump();
  });

  testWidgets('ambiguous mutation retries reuse the idempotency key', (
    tester,
  ) async {
    final api = _AdminGiveawayApi(
      mutationError: const ApiException('gateway', statusCode: 503),
    );
    await _pump(tester, api);
    await tester.tap(find.text('Bara Referral Contest'));
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
    for (var attempt = 0; attempt < 2; attempt++) {
      await tester.ensureVisible(find.text('FINALIZE RESULTS'));
      await tester.tap(find.text('FINALIZE RESULTS'));
      await tester.pump();
      await tester.tap(find.text('FINALIZE'));
      await tester.pump();
    }
    expect(api.idempotencyKeys, hasLength(2));
    expect(api.idempotencyKeys[0], api.idempotencyKeys[1]);
  });

  testWidgets(
    'failed fulfillment clears the reference and reuses its idempotency key',
    (tester) async {
      const secretReference = 'private-bank-reference-9237';
      final api =
          _AdminGiveawayApi(
              mutationError: const ApiException('gateway', statusCode: 503),
            )
            ..contest = adminContest(status: 'FINAL', lifecycle: 'FINAL')
            ..currentResult = result(verified: true)
            ..fulfillment = {
              'status': 'CASH_SENT',
              'provider': 'ACH',
              'providerReference': '••••',
              'cashSentMinor': 5000,
              'cashSentCurrency': 'USD',
              'claimedAt': '2026-10-02T13:00:00.000Z',
              'cashSentAt': '2026-10-02T14:00:00.000Z',
              'cashDeliveredAt': null,
              'coinsAwardedAt': null,
              'coinTransactionId': null,
              'fulfilledAt': null,
            };
      await _pump(tester, api);
      await tester.tap(find.text('Bara Referral Contest'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      for (var attempt = 0; attempt < 2; attempt++) {
        await tester.ensureVisible(find.text('MARK CASH DELIVERED'));
        await tester.tap(find.text('MARK CASH DELIVERED'));
        await tester.pump();
        final referenceField = find.byKey(
          const Key('giveaway-provider-reference'),
        );
        expect(
          tester.widget<TextField>(referenceField).controller?.text,
          isEmpty,
        );
        await tester.enterText(referenceField, secretReference);
        await tester.tap(find.text('CONFIRM'));
        await tester.pump();
      }

      expect(api.idempotencyKeys, hasLength(2));
      expect(api.idempotencyKeys[0], api.idempotencyKeys[1]);
      expect(
        api.idempotencyKeys,
        everyElement(isNot(contains(secretReference))),
      );
    },
  );
}
