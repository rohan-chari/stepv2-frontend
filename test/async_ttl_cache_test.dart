import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/async_ttl_cache.dart';

void main() {
  group('AsyncTtlCache', () {
    test('serves a fresh value without calling fetch again', () async {
      var now = DateTime(2026, 7, 17, 12, 0, 0);
      var calls = 0;
      final cache = AsyncTtlCache<int>(
        ttl: const Duration(minutes: 15),
        clock: () => now,
      );

      final a = await cache.get(() async {
        calls += 1;
        return 1;
      });
      expect(a, 1);
      expect(calls, 1);
      expect(cache.isFresh, isTrue);

      // 5 minutes later, still fresh -> no new fetch.
      now = now.add(const Duration(minutes: 5));
      final b = await cache.get(() async {
        calls += 1;
        return 2;
      });
      expect(b, 1);
      expect(calls, 1);
    });

    test('refetches after the TTL expires', () async {
      var now = DateTime(2026, 7, 17, 12, 0, 0);
      var calls = 0;
      final cache = AsyncTtlCache<int>(
        ttl: const Duration(minutes: 15),
        clock: () => now,
      );

      await cache.get(() async {
        calls += 1;
        return calls;
      });
      now = now.add(const Duration(minutes: 16));
      final b = await cache.get(() async {
        calls += 1;
        return calls;
      });
      expect(b, 2);
      expect(calls, 2);
    });

    test('de-duplicates concurrent in-flight fetches', () async {
      final cache = AsyncTtlCache<int>(ttl: const Duration(minutes: 15));
      final completer = Completer<int>();
      var calls = 0;

      Future<int> fetch() {
        calls += 1;
        return completer.future;
      }

      final f1 = cache.get(fetch);
      final f2 = cache.get(fetch);
      expect(calls, 1); // only one fetch launched

      completer.complete(42);
      expect(await f1, 42);
      expect(await f2, 42);
    });

    test('invalidate forces a refetch but keeps the stale value readable',
        () async {
      final cache = AsyncTtlCache<int>(ttl: const Duration(minutes: 15));
      await cache.get(() async => 7);
      expect(cache.isFresh, isTrue);

      cache.invalidate();
      expect(cache.isFresh, isFalse);
      expect(cache.value, 7); // stale but still available for rendering

      var refetched = false;
      final v = await cache.get(() async {
        refetched = true;
        return 8;
      });
      expect(refetched, isTrue);
      expect(v, 8);
    });

    test('set records an externally-supplied fresh value', () async {
      final cache = AsyncTtlCache<int>(ttl: const Duration(minutes: 15));
      cache.set(99);
      expect(cache.isFresh, isTrue);
      var called = false;
      final v = await cache.get(() async {
        called = true;
        return 0;
      });
      expect(v, 99);
      expect(called, isFalse);
    });

    test('clear drops the value entirely (sign-out)', () async {
      final cache = AsyncTtlCache<int>(ttl: const Duration(minutes: 15));
      await cache.get(() async => 5);
      cache.clear();
      expect(cache.value, isNull);
      expect(cache.isFresh, isFalse);
      expect(cache.hasValue, isFalse);
    });

    test('a failed fetch caches nothing and propagates', () async {
      final cache = AsyncTtlCache<int>(ttl: const Duration(minutes: 15));
      await expectLater(
        cache.get(() async => throw StateError('boom')),
        throwsStateError,
      );
      expect(cache.hasValue, isFalse);
      // A later fetch still works.
      final v = await cache.get(() async => 3);
      expect(v, 3);
    });
  });
}
