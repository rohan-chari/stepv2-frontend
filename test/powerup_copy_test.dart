import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';

/// §9.5.4 — backend-served powerup copy with a 4-level resolution order:
///   1. current in-memory backend snapshot
///   2. persisted last-known-good backend snapshot
///   3. bundled emergency copy
///   4. the raw enum string
///
/// Every test drives the store through its injected fetcher so no real HTTP is
/// involved, and each starts from a clean SharedPreferences + store.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Map<String, dynamic> entry(
    String type, {
    String? name,
    String? description,
    String? shortDescription,
    List<String>? upgradeTierLabels,
  }) {
    return {
      'type': type,
      'name': name ?? 'Server $type',
      'description': description ?? 'Server description for $type',
      if (shortDescription != null) 'shortDescription': shortDescription,
      'upgradeTierLabels': upgradeTierLabels ?? const <String>[],
    };
  }

  Map<String, dynamic> payload(
    List<Map<String, dynamic>> powerups, {
    String version = '2026-07-20T22:15:00.000Z',
  }) {
    return {'version': version, 'powerups': powerups};
  }

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    PowerupCopy.resetForTest();
  });

  group('resolution order', () {
    test('falls back to bundled emergency copy before any fetch', () {
      // Level 3: no snapshot at all yet (brand-new offline install).
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Leg Cramp');
      expect(PowerupCopy.descriptionFor('LEG_CRAMP'), isNotEmpty);
    });

    test('falls back to the raw enum string for an unknown type', () {
      // Level 4 — never an empty string.
      expect(PowerupCopy.nameFor('SOME_FUTURE_TYPE'), 'SOME_FUTURE_TYPE');
      expect(PowerupCopy.nameFor('SOME_FUTURE_TYPE'), isNotEmpty);
    });

    test('never renders an empty string for any known bundled type', () {
      for (final type in PowerupCopy.bundledTypes) {
        expect(PowerupCopy.nameFor(type), isNotEmpty, reason: type);
        expect(PowerupCopy.descriptionFor(type), isNotEmpty, reason: type);
      }
    });

    test('in-memory snapshot wins over bundled copy', () async {
      await PowerupCopy.refresh(
        fetch: () async => payload([entry('LEG_CRAMP', name: 'Cramp!')]),
      );
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Cramp!');
    });

    test('bundled copy still wins for a type the snapshot omits', () async {
      await PowerupCopy.refresh(
        fetch: () async => payload([entry('LEG_CRAMP', name: 'Cramp!')]),
      );
      // POCKET_WATCH is absent from the snapshot -> level 3, not empty.
      expect(PowerupCopy.nameFor('POCKET_WATCH'), 'Pocket Watch');
    });

    test('an empty server string does not win over bundled copy', () async {
      await PowerupCopy.refresh(
        fetch: () async => payload([
          entry('LEG_CRAMP', name: 'Cramp!'),
          // A blank name must be ignored per "present and non-empty".
          {
            'type': 'POCKET_WATCH',
            'name': '   ',
            'description': 'ok',
            'upgradeTierLabels': const <String>[],
          },
        ]),
      );
      expect(PowerupCopy.nameFor('POCKET_WATCH'), 'Pocket Watch');
    });

    test('persisted snapshot resolves before bundled copy on a cold start',
        () async {
      await PowerupCopy.refresh(
        fetch: () async => payload([entry('LEG_CRAMP', name: 'Persisted!')]),
      );
      // Simulate relaunch: fresh in-memory state, same SharedPreferences.
      PowerupCopy.resetForTest(keepPersisted: true);
      await PowerupCopy.loadPersisted();
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Persisted!');
    });
  });

  group('shortDescription nullability', () {
    test('shortDescriptionFor resolves null when no layer has one', () async {
      // SHORTCUT has no short description in ANY layer. The resolver reports
      // that honestly; the effect-rail chain below decides what to render.
      await PowerupCopy.refresh(
        fetch: () async => payload([entry('SHORTCUT')]),
      );
      expect(PowerupCopy.shortDescriptionFor('SHORTCUT'), isNull);
    });

    test('the effect rail falls back to the FULL description, never blank', () {
      // Regression guard for the shipped chain
      // (`short ?? description ?? ''`). 11 of 26 types have no short copy and
      // have always shown their description here — omitting the line would be
      // a visible regression for every one of them.
      expect(
        PowerupCopy.effectRailSubtitleFor('SHORTCUT'),
        PowerupCopy.descriptionFor('SHORTCUT'),
      );
      expect(PowerupCopy.effectRailSubtitleFor('SHORTCUT'), isNotEmpty);
    });

    test('the effect rail prefers short copy when it exists', () {
      expect(PowerupCopy.effectRailSubtitleFor('LEG_CRAMP'), 'Steps frozen');
    });

    test('the effect rail is an empty string for an unknown type', () {
      // Never null, never the raw enum — the subtitle just goes away.
      expect(PowerupCopy.effectRailSubtitleFor('SOME_FUTURE_TYPE'), '');
    });

    test('every bundled type yields a non-empty effect-rail subtitle', () {
      for (final type in PowerupCopy.bundledTypes) {
        expect(
          PowerupCopy.effectRailSubtitleFor(type),
          isNotEmpty,
          reason: type,
        );
      }
    });

    test('a server-omitted short description still resolves bundled copy',
        () async {
      // Level 3 of the resolution order still applies to shortDescription: a
      // snapshot that omits it must not blank out copy the app already had.
      await PowerupCopy.refresh(
        fetch: () async => payload([entry('LEG_CRAMP')]),
      );
      expect(PowerupCopy.shortDescriptionFor('LEG_CRAMP'), 'Steps frozen');
    });

    test('a present shortDescription is returned', () async {
      await PowerupCopy.refresh(
        fetch: () async => payload([
          entry('LEG_CRAMP', shortDescription: 'Steps frozen solid'),
        ]),
      );
      expect(PowerupCopy.shortDescriptionFor('LEG_CRAMP'), 'Steps frozen solid');
    });
  });

  group('upgrade tier labels', () {
    test('server labels win when four are supplied', () async {
      await PowerupCopy.refresh(
        fetch: () async => payload([
          entry(
            'POCKET_WATCH',
            upgradeTierLabels: ['A', 'B', 'C', 'D'],
          ),
        ]),
      );
      expect(PowerupCopy.upgradeTierLabelsFor('POCKET_WATCH'),
          ['A', 'B', 'C', 'D']);
    });

    test('an empty server list falls back to bundled tier labels', () async {
      await PowerupCopy.refresh(
        fetch: () async => payload([entry('POCKET_WATCH')]),
      );
      final labels = PowerupCopy.upgradeTierLabelsFor('POCKET_WATCH');
      expect(labels, isNotNull);
      expect(labels!.length, 4);
    });

    test('a non-upgradeable type has no tier labels', () {
      expect(PowerupCopy.upgradeTierLabelsFor('CLEANSE'), isNull);
    });

    test('a malformed tier list is ignored in favour of bundled labels',
        () async {
      await PowerupCopy.refresh(
        fetch: () async => payload([
          {
            'type': 'POCKET_WATCH',
            'name': 'Pocket Watch',
            'description': 'd',
            // Only two entries: not a usable ladder.
            'upgradeTierLabels': ['A', 'B'],
          },
        ]),
      );
      expect(PowerupCopy.upgradeTierLabelsFor('POCKET_WATCH')!.length, 4);
    });
  });

  group('bundled emergency copy contract', () {
    test('Leech fallback copy is DURATION-NEUTRAL (§7.5.1)', () {
      final desc = PowerupCopy.descriptionFor('LEECH');
      // A new binary may talk to an old backend (30 min) or a new one (60 min),
      // so the bundled string must commit to neither.
      expect(desc.contains('30'), isFalse, reason: desc);
      expect(desc.contains('60'), isFalse, reason: desc);
      expect(desc.toLowerCase().contains('min'), isFalse, reason: desc);
      expect(desc.toLowerCase().contains('hour'), isFalse, reason: desc);
    });

    test('bundled copy covers the new store types', () {
      expect(PowerupCopy.nameFor('HITCHHIKE'), 'Hitchhike');
      expect(PowerupCopy.nameFor('QUICK_RINSE'), 'Quick Rinse');
      expect(PowerupCopy.descriptionFor('HITCHHIKE'), isNotEmpty);
      expect(PowerupCopy.descriptionFor('QUICK_RINSE'), isNotEmpty);
    });

    test('MYSTERY_BOX is not a user-renderable copy type', () {
      expect(PowerupCopy.bundledTypes, isNot(contains('MYSTERY_BOX')));
    });
  });

  group('snapshot validation — never clobber a good snapshot', () {
    Future<void> seedGood() async {
      await PowerupCopy.refresh(
        fetch: () async => payload([entry('LEG_CRAMP', name: 'Good')]),
      );
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Good');
    }

    test('an empty powerups list is rejected', () async {
      await seedGood();
      final ok = await PowerupCopy.refresh(fetch: () async => payload([]));
      expect(ok, isFalse);
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Good');
    });

    test('a malformed (non-map) response is rejected', () async {
      await seedGood();
      final ok = await PowerupCopy.refresh(fetch: () async => {'nope': 1});
      expect(ok, isFalse);
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Good');
    });

    test('duplicate types are rejected wholesale', () async {
      await seedGood();
      final ok = await PowerupCopy.refresh(
        fetch: () async => payload([
          entry('LEG_CRAMP', name: 'Dup A'),
          entry('LEG_CRAMP', name: 'Dup B'),
        ]),
      );
      expect(ok, isFalse);
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Good');
    });

    test('an entry missing a name is rejected wholesale', () async {
      await seedGood();
      final ok = await PowerupCopy.refresh(
        fetch: () async => payload([
          {'type': 'LEG_CRAMP', 'description': 'd'},
        ]),
      );
      expect(ok, isFalse);
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Good');
    });

    test('an entry with a blank type is rejected wholesale', () async {
      await seedGood();
      final ok = await PowerupCopy.refresh(
        fetch: () async => payload([entry('   ')]),
      );
      expect(ok, isFalse);
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Good');
    });

    test('a rejected refresh does not overwrite the PERSISTED snapshot',
        () async {
      await seedGood();
      await PowerupCopy.refresh(fetch: () async => payload([]));
      PowerupCopy.resetForTest(keepPersisted: true);
      await PowerupCopy.loadPersisted();
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Good');
    });
  });

  group('transient failures are never a permanent lockout', () {
    test('a 404 falls back and still allows a later refresh to succeed',
        () async {
      final ok = await PowerupCopy.refresh(
        fetch: () async => throw PowerupCopyUnavailable(404),
      );
      expect(ok, isFalse);
      // Bundled copy still renders.
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Leg Cramp');
      // The endpoint is NOT marked permanently unsupported.
      expect(PowerupCopy.isPermanentlyUnsupported, isFalse);

      final second = await PowerupCopy.refresh(
        fetch: () async => payload([entry('LEG_CRAMP', name: 'Back!')]),
      );
      expect(second, isTrue);
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Back!');
    });

    test('a 500 and a timeout behave the same way', () async {
      expect(
        await PowerupCopy.refresh(
          fetch: () async => throw PowerupCopyUnavailable(500),
        ),
        isFalse,
      );
      expect(
        await PowerupCopy.refresh(fetch: () async => throw StateError('timeout')),
        isFalse,
      );
      expect(PowerupCopy.isPermanentlyUnsupported, isFalse);
      expect(
        await PowerupCopy.refresh(
          fetch: () async => payload([entry('LEG_CRAMP', name: 'Recovered')]),
        ),
        isTrue,
      );
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Recovered');
    });

    test('a failed refresh keeps serving the persisted snapshot', () async {
      await PowerupCopy.refresh(
        fetch: () async => payload([entry('LEG_CRAMP', name: 'Persisted')]),
      );
      PowerupCopy.resetForTest(keepPersisted: true);
      await PowerupCopy.loadPersisted();
      await PowerupCopy.refresh(
        fetch: () async => throw PowerupCopyUnavailable(404),
      );
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Persisted');
    });
  });

  group('refresh coalescing', () {
    test('concurrent refreshes issue exactly one request', () async {
      var calls = 0;
      Future<Map<String, dynamic>> fetch() async {
        calls++;
        await Future<void>.delayed(const Duration(milliseconds: 10));
        return payload([entry('LEG_CRAMP', name: 'Once')]);
      }

      final results = await Future.wait([
        PowerupCopy.refresh(fetch: fetch),
        PowerupCopy.refresh(fetch: fetch),
        PowerupCopy.refresh(fetch: fetch),
      ]);

      expect(calls, 1);
      expect(results, everyElement(isTrue));
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Once');
    });

    test('a later refresh after the in-flight one completes does fetch again',
        () async {
      var calls = 0;
      Future<Map<String, dynamic>> fetch() async {
        calls++;
        return payload([entry('LEG_CRAMP', name: 'Call $calls')]);
      }

      await PowerupCopy.refresh(fetch: fetch);
      await PowerupCopy.refresh(fetch: fetch);
      expect(calls, 2);
    });
  });

  group('persistence survives logout', () {
    test('clearing the session does NOT clear the copy snapshot', () async {
      await PowerupCopy.refresh(
        fetch: () async => payload([entry('LEG_CRAMP', name: 'Global copy')]),
      );
      // Copy is global, not user-scoped: a logout must leave it intact.
      await PowerupCopy.onLogout();
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Global copy');

      PowerupCopy.resetForTest(keepPersisted: true);
      await PowerupCopy.loadPersisted();
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Global copy');
    });
  });

  group('older/newer backend shapes never crash', () {
    test('unknown extra fields are ignored', () async {
      final ok = await PowerupCopy.refresh(
        fetch: () async => {
          'version': '1',
          'somethingNew': {'a': 1},
          'powerups': [
            {
              'type': 'LEG_CRAMP',
              'name': 'Cramp',
              'description': 'd',
              'shortDescription': null,
              'upgradeTierLabels': const <String>[],
              'futureField': 42,
            },
          ],
        },
      );
      expect(ok, isTrue);
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Cramp');
    });

    test('a missing version still validates (additive-only response)', () async {
      final ok = await PowerupCopy.refresh(
        fetch: () async => {
          'powerups': [
            {'type': 'LEG_CRAMP', 'name': 'Cramp', 'description': 'd'},
          ],
        },
      );
      expect(ok, isTrue);
      expect(PowerupCopy.nameFor('LEG_CRAMP'), 'Cramp');
    });

    test('null entries inside the list are rejected wholesale', () async {
      final ok = await PowerupCopy.refresh(
        fetch: () async => {
          'version': '1',
          'powerups': [null],
        },
      );
      expect(ok, isFalse);
    });
  });
}
