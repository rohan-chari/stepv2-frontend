import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/ad_service.dart';

class _FakeNativeRewardedAd implements RewardedAdNativeHandle {
  _FakeNativeRewardedAd([this.earned = true]);

  final bool earned;
  int disposeCalls = 0;
  int showCalls = 0;

  @override
  void dispose() => disposeCalls++;

  @override
  Future<bool> showAndAwaitReward({required Duration timeout}) async {
    showCalls++;
    return earned;
  }
}

class _LoadCall {
  _LoadCall({
    required this.adUnitId,
    required this.userId,
    required this.customData,
    required this.completer,
  });

  final String adUnitId;
  final String userId;
  final String customData;
  final Completer<RewardedAdNativeHandle?> completer;
}

class _FakeLoader {
  final List<_LoadCall> calls = [];
  bool completeImmediately = true;

  Future<RewardedAdNativeHandle?> call({
    required String adUnitId,
    required String userId,
    required String customData,
  }) {
    final completer = Completer<RewardedAdNativeHandle?>();
    calls.add(
      _LoadCall(
        adUnitId: adUnitId,
        userId: userId,
        customData: customData,
        completer: completer,
      ),
    );
    if (completeImmediately) completer.complete(_FakeNativeRewardedAd());
    return completer.future;
  }
}

void main() {
  group('context-bound rewarded-ad cache', () {
    late DateTime now;
    late int initializeCalls;
    late RewardedAdSdkInitializer initializer;
    late _FakeLoader loader;

    setUp(() {
      now = DateTime(2026, 8, 25, 12);
      initializeCalls = 0;
      initializer = RewardedAdSdkInitializer(() async {
        initializeCalls++;
      });
      loader = _FakeLoader();
    });

    AdService service() => AdService(
      adUnitId: 'real-unit',
      requireConfiguredAdUnit: true,
      supportedOverride: true,
      sdkInitializer: initializer,
      rewardedAdLoader: loader.call,
      now: () => now,
    );

    test('same context concurrent warms share one SDK load', () async {
      loader.completeImmediately = false;
      final ads = service();
      final context = RewardedAdContext.getCoins(
        userId: 'user-1',
        localDate: '2026-08-25',
      );

      final first = ads.warm(context);
      final second = ads.warm(context);

      await Future<void>.delayed(Duration.zero);
      expect(loader.calls, hasLength(1));
      expect(initializeCalls, 1);

      loader.calls.single.completer.complete(_FakeNativeRewardedAd());
      await Future.wait([first, second]);

      expect(ads.isReadyFor(context), isTrue);
      expect(loader.calls, hasLength(1));
    });

    test(
      'different controllers share one in-flight SDK initialization',
      () async {
        final initGate = Completer<void>();
        initializer = RewardedAdSdkInitializer(() async {
          initializeCalls++;
          await initGate.future;
        });
        final first = service();
        final second = service();

        final warms = [
          first.warm(
            RewardedAdContext.extraSpin(
              userId: 'user-1',
              localDate: '2026-08-25',
            ),
          ),
          second.warm(
            RewardedAdContext.getCoins(
              userId: 'user-1',
              localDate: '2026-08-25',
            ),
          ),
        ];
        await Future<void>.delayed(Duration.zero);

        expect(initializeCalls, 1);
        expect(loader.calls, isEmpty);

        initGate.complete();
        await Future.wait(warms);
        expect(loader.calls, hasLength(2));
      },
    );

    test('failed SDK initialization settles before a later retry', () async {
      var attempts = 0;
      initializer = RewardedAdSdkInitializer(() async {
        initializeCalls++;
        attempts++;
        if (attempts == 1) throw StateError('first initialization failed');
      });
      final ads = service();
      final context = RewardedAdContext.getCoins(
        userId: 'user-1',
        localDate: '2026-08-25',
      );

      await ads.warm(context);
      expect(initializeCalls, 1);
      expect(loader.calls, isEmpty);

      await ads.warm(context);
      expect(initializeCalls, 2);
      expect(loader.calls, hasLength(1));
      expect(ads.isReadyFor(context), isTrue);
    });

    test('loader receives every exact SSV user and customData form', () async {
      final contexts = <RewardedAdContext>[
        RewardedAdContext.extraSpin(userId: 'u1', localDate: '2026-08-25'),
        RewardedAdContext.getCoins(userId: 'u2', localDate: '2026-08-25'),
        RewardedAdContext.powerupUnlock(
          userId: 'u3',
          sku: 'POWER:SKU',
          localDate: '2026-08-25',
        ),
        RewardedAdContext.cosmeticUnlock(
          userId: 'u4',
          sku: 'HAT-SKU',
          localDate: '2026-08-25',
        ),
        RewardedAdContext.boxReroll(userId: 'u5', localDate: '2026-08-25'),
        RewardedAdContext.racePayoutDouble(userId: 'u6', offerId: 'offer-9'),
      ];
      const expected = <String>[
        '2026-08-25',
        'coins:2026-08-25',
        'powerup_unlock:u3:POWER:SKU',
        'shop_unlock:u4:HAT-SKU',
        'box_reroll:u5:2026-08-25',
        'race_payout_double:u6:offer-9',
      ];

      for (var index = 0; index < contexts.length; index++) {
        final ads = service();
        await ads.warm(contexts[index]);
        expect(loader.calls[index].userId, contexts[index].userId);
        expect(loader.calls[index].customData, expected[index]);
      }
    });

    test(
      '44-minute ad stays ready and 46-minute ad is evicted and reloaded',
      () async {
        final ads = service();
        final context = RewardedAdContext.getCoins(
          userId: 'user-1',
          localDate: '2026-08-25',
        );
        await ads.warm(context);
        final firstAd = await loader.calls.single.completer.future;

        now = now.add(const Duration(minutes: 44));
        expect(ads.isReadyFor(context), isTrue);
        await ads.warm(context);
        expect(loader.calls, hasLength(1));

        now = now.add(const Duration(minutes: 2));
        expect(ads.isReadyFor(context), isFalse);
        expect((firstAd! as _FakeNativeRewardedAd).disposeCalls, 1);
        await ads.warm(context);
        expect(loader.calls, hasLength(2));
        expect(ads.isReadyFor(context), isTrue);
      },
    );

    test('context churn keeps only the latest queued target', () async {
      loader.completeImmediately = false;
      final ads = service();
      final first = RewardedAdContext.getCoins(
        userId: 'user-1',
        localDate: '2026-08-25',
      );
      final skipped = RewardedAdContext.getCoins(
        userId: 'user-1',
        localDate: '2026-08-26',
      );
      final latest = RewardedAdContext.getCoins(
        userId: 'user-2',
        localDate: '2026-08-26',
      );

      final warm = ads.warm(first);
      await Future<void>.delayed(Duration.zero);
      unawaited(ads.warm(skipped));
      unawaited(ads.warm(latest));
      expect(loader.calls, hasLength(1));

      final obsolete = _FakeNativeRewardedAd();
      loader.calls.first.completer.complete(obsolete);
      await Future<void>.delayed(Duration.zero);
      expect(obsolete.disposeCalls, 1);
      expect(loader.calls, hasLength(2));
      expect(loader.calls.last.userId, 'user-2');
      expect(loader.calls.last.customData, 'coins:2026-08-26');

      loader.calls.last.completer.complete(_FakeNativeRewardedAd());
      await warm;
      expect(ads.isReadyFor(first), isFalse);
      expect(ads.isReadyFor(skipped), isFalse);
      expect(ads.isReadyFor(latest), isTrue);
    });

    test('late completion after owner disposal is discarded', () async {
      loader.completeImmediately = false;
      final ads = service();
      final context = RewardedAdContext.extraSpin(
        userId: 'user-1',
        localDate: '2026-08-25',
      );

      final warm = ads.warm(context);
      await Future<void>.delayed(Duration.zero);
      ads.dispose();
      final lateAd = _FakeNativeRewardedAd();
      loader.calls.single.completer.complete(lateAd);
      await warm;

      expect(lateAd.disposeCalls, 1);
      expect(ads.isReadyFor(context), isFalse);
    });

    test(
      'show requires an exact context and consumes readiness once',
      () async {
        final ads = service();
        final context = RewardedAdContext.boxReroll(
          userId: 'user-1',
          localDate: '2026-08-25',
        );
        final mismatch = RewardedAdContext.boxReroll(
          userId: 'user-2',
          localDate: '2026-08-25',
        );
        await ads.warm(context);

        expect(await ads.showAndAwaitRewardFor(mismatch), isFalse);
        expect(ads.isReadyFor(context), isTrue);
        expect(await ads.showAndAwaitRewardFor(context), isTrue);
        expect(await ads.showAndAwaitRewardFor(context), isFalse);
        expect(ads.isReadyFor(context), isFalse);
      },
    );

    test('dismissed native ad preserves the false reward result', () async {
      loader.completeImmediately = false;
      final ads = service();
      final context = RewardedAdContext.extraSpin(
        userId: 'user-1',
        localDate: '2026-08-25',
      );
      final warm = ads.warm(context);
      await Future<void>.delayed(Duration.zero);
      loader.calls.single.completer.complete(_FakeNativeRewardedAd(false));
      await warm;

      expect(await ads.showAndAwaitRewardFor(context), isFalse);
      expect(ads.isReadyFor(context), isFalse);
    });

    test(
      'empty user and missing configured unit never initialize the SDK',
      () async {
        final missingUnit = AdService(
          adUnitId: '',
          requireConfiguredAdUnit: true,
          supportedOverride: true,
          sdkInitializer: initializer,
          rewardedAdLoader: loader.call,
        );
        await missingUnit.warm(
          RewardedAdContext.getCoins(userId: 'user-1', localDate: '2026-08-25'),
        );
        await service().warm(
          const RewardedAdContext(
            placement: RewardedAdPlacement.getCoins,
            userId: '',
            customData: 'coins:2026-08-25',
            localDate: '2026-08-25',
          ),
        );

        expect(initializeCalls, 0);
        expect(loader.calls, isEmpty);
      },
    );
  });
}
