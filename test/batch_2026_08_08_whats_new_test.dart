// Feature batch 2026-08-08 — Item 8: the What's New sheet.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/content/whats_new.dart';
import 'package:step_tracker/services/onboarding_state_service.dart';
import 'package:step_tracker/widgets/whats_new_sheet.dart';

const _entries = <WhatsNewEntry>[
  WhatsNewEntry(
    version: '2.2.0',
    title: 'PODIUMS & PAYOUTS',
    bullets: ['Races end on a podium.', 'Discard powerups for coins.'],
  ),
  WhatsNewEntry(
    version: '2.1.2',
    title: 'OLDER',
    bullets: ['Something older.'],
  ),
];

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.bara.steps',
      version: '2.2.0',
      buildNumber: '1',
      buildSignature: '',
    );
  });

  group('changelog lookup', () {
    test('matches the running version exactly', () {
      expect(whatsNewEntryFor('2.2.0', entries: _entries)?.title, 'PODIUMS & PAYOUTS');
      expect(whatsNewEntryFor('2.1.2', entries: _entries)?.title, 'OLDER');
    });

    test('a build with no entry shows nothing', () {
      expect(whatsNewEntryFor('9.9.9', entries: _entries), isNull);
      expect(whatsNewEntryFor(null, entries: _entries), isNull);
      expect(whatsNewEntryFor('', entries: _entries), isNull);
    });

    test('there is no prefix or "closest older" matching', () {
      // 2.2 must NOT resolve to 2.2.0 — a partial match would show the wrong
      // changelog on a hotfix build.
      expect(whatsNewEntryFor('2.2', entries: _entries), isNull);
      expect(whatsNewEntryFor('2.2.1', entries: _entries), isNull);
    });

    // Review fix 7: the sheet matches PackageInfo.version EXACTLY, so a
    // release whose pubspec version has no entry shows nothing — silently.
    // This ties the two together so the drift is caught at test time rather
    // than by nobody noticing the sheet never appeared.
    test('STRUCTURAL: pubspec version has a matching changelog entry', () {
      final pubspec = File('pubspec.yaml').readAsStringSync();
      final match = RegExp(
        r'^version:\s*([0-9]+\.[0-9]+\.[0-9]+)',
        multiLine: true,
      ).firstMatch(pubspec);
      expect(match, isNotNull, reason: 'could not parse version from pubspec');
      final version = match!.group(1)!;

      expect(
        whatsNewEntryFor(version),
        isNotNull,
        reason:
            'pubspec version $version has no WhatsNewEntry in '
            'lib/content/whats_new.dart, so this build would show no '
            "What's New sheet at all. Add an entry (see DEPLOYMENT.md step 2).",
      );
    });

    test('the shipped changelog is well-formed', () {
      expect(kWhatsNewEntries, isNotEmpty);
      for (final entry in kWhatsNewEntries) {
        expect(entry.version, isNotEmpty);
        expect(entry.bullets, isNotEmpty);
      }
      // Versions must be unique, or the lookup silently picks the first.
      final versions = kWhatsNewEntries.map((e) => e.version).toList();
      expect(versions.toSet().length, versions.length);
    });
  });

  group('shouldShowWhatsNew', () {
    test('a fresh install (null lastSeen) qualifies', () {
      expect(
        OnboardingStateService.shouldShowWhatsNew(
          currentVersion: '2.2.0',
          lastSeenVersion: null,
          hasEntryForVersion: true,
        ),
        isTrue,
      );
    });

    test('an updater from an older version qualifies', () {
      expect(
        OnboardingStateService.shouldShowWhatsNew(
          currentVersion: '2.2.0',
          lastSeenVersion: '2.1.2',
          hasEntryForVersion: true,
        ),
        isTrue,
      );
    });

    test('having already seen THIS version does not', () {
      expect(
        OnboardingStateService.shouldShowWhatsNew(
          currentVersion: '2.2.0',
          lastSeenVersion: '2.2.0',
          hasEntryForVersion: true,
        ),
        isFalse,
      );
    });

    test('no bundled entry for this build does not', () {
      expect(
        OnboardingStateService.shouldShowWhatsNew(
          currentVersion: '2.2.0',
          lastSeenVersion: null,
          hasEntryForVersion: false,
        ),
        isFalse,
      );
    });
  });

  group('persistence', () {
    test('round-trips the last seen version', () async {
      final service = OnboardingStateService();
      expect(await service.lastSeenWhatsNewVersion(), isNull);
      await service.setLastSeenWhatsNewVersion('2.2.0');
      expect(await service.lastSeenWhatsNewVersion(), '2.2.0');
    });

    // ui-test-planner risk 7 — the whole point of this test.
    test(
      'STRUCTURAL: the key is NOT in allKeys, so sign-out cannot wipe it',
      () {
        expect(
          OnboardingStateService.allKeys,
          isNot(contains(OnboardingStateService.keyLastSeenWhatsNewVersion)),
          reason:
              'lastSeenWhatsNewVersion must stay out of the sign-out wipe set '
              'or the What\'s New sheet re-shows after every sign-out. If you '
              'added a key to allKeys and this failed, remove that key — do '
              'not change this assertion.',
        );
      },
    );

    test('the sheet survives a sign-out wipe', () async {
      final service = OnboardingStateService();
      await service.setLastSeenWhatsNewVersion('2.2.0');
      // Put something that IS in the wipe set alongside it.
      await service.setEscapedHealthGate(true);

      await OnboardingStateService.clearPersistedState();

      expect(await service.escapedHealthGate(), isFalse);
      expect(await service.lastSeenWhatsNewVersion(), '2.2.0');
    });
  });

  group('the sheet renders', () {
    testWidgets('shows the title and every bullet', (tester) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(body: WhatsNewSheet(entry: _entries.first)),
        ),
      );
      await tester.pump(const Duration(milliseconds: 100));

      expect(find.text("WHAT'S NEW"), findsOneWidget);
      expect(find.text('PODIUMS & PAYOUTS'), findsOneWidget);
      expect(find.text('v2.2.0'), findsOneWidget);
      expect(find.text('Races end on a podium.'), findsOneWidget);
      expect(find.text('Discard powerups for coins.'), findsOneWidget);
      expect(find.byKey(const Key('whats-new-dismiss')), findsOneWidget);
    });
  });
}
