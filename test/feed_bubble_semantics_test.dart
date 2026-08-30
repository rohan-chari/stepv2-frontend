import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/constants/powerup_copy.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/utils/powerup_feed_presentation.dart';
import 'package:step_tracker/widgets/feed_bubble.dart';

const _harmfulTypes = <String>{
  'WRONG_TURN',
  'LEG_CRAMP',
  'RED_CARD',
  'BANANA_PEEL',
  'DETOUR_SIGN',
  'TRAIL_MINE',
  'PINECONE_TOSS',
  'SNEAKY_SWAP',
  'IMPOSTER',
  'RAINSTORM',
  'SIGNAL_JAMMER',
  'LEECH',
  'QUICKSAND',
  'POWER_OUTAGE',
  'DRILL_SERGEANT',
  'BOUNTY',
  'SHORTCUT',
};

const _beneficialTypes = <String>{
  'PROTEIN_SHAKE',
  'RUNNERS_HIGH',
  'SECOND_WIND',
  'TRAIL_MIX',
  'FANNY_PACK',
  'LUCKY_HORSESHOE',
  'CAMPFIRE_REST',
  'TRAIL_MAGNET',
  'POCKET_WATCH',
  'STEALTH_MODE',
  'MIRROR',
  'COMPRESSION_SOCKS',
  'CLEANSE',
  'DEFENSE_SCAN',
  'HITCHHIKE',
  'QUICK_RINSE',
  'UPRISING',
  'GHOST_PEPPER',
  'COIN_FLIP',
  'DECOY',
  'UMBRELLA',
  'RALLY_FLAG',
  'PIGGY_BANK',
  'SHELL',
};

Iterable<TextSpan> _leafSpans(InlineSpan span) sync* {
  if (span is! TextSpan) return;
  if (span.text != null) yield span;
  for (final child in span.children ?? const <InlineSpan>[]) {
    yield* _leafSpans(child);
  }
}

Map<String, Color?> _descriptionColors(WidgetTester tester) {
  final richTexts = tester.widgetList<RichText>(find.byType(RichText));
  final result = <String, Color?>{};
  for (final rich in richTexts) {
    for (final span in _leafSpans(rich.text)) {
      final value = span.text;
      if (value != null) result[value] = span.style?.color;
    }
  }
  return result;
}

double _relativeLuminance(Color color) {
  double channel(double value) {
    final normalized = value;
    return normalized <= 0.04045
        ? normalized / 12.92
        : math.pow((normalized + 0.055) / 1.055, 2.4).toDouble();
  }

  return 0.2126 * channel(color.r) +
      0.7152 * channel(color.g) +
      0.0722 * channel(color.b);
}

double _contrast(Color foreground, Color background) {
  final values = <double>[
    _relativeLuminance(foreground),
    _relativeLuminance(background),
  ]..sort();
  return (values.last + 0.05) / (values.first + 0.05);
}

void main() {
  setUp(() {
    SharedPreferences.setMockInitialValues({});
    PowerupCopy.resetForTest();
  });

  test('every bundled and legacy type has an explicit semantic valence', () {
    final expectedTypes = {...PowerupCopy.bundledTypes, 'BANANA_PEEL', 'SHELL'};
    expect({
      ..._harmfulTypes,
      ..._beneficialTypes,
      'MYSTERY_POTION',
    }, expectedTypes);
    for (final type in _harmfulTypes) {
      expect(
        PowerupFeedPresentation.valenceForType(type),
        PowerupFeedValence.harmful,
        reason: type,
      );
    }
    for (final type in _beneficialTypes) {
      expect(
        PowerupFeedPresentation.valenceForType(type),
        PowerupFeedValence.beneficial,
        reason: type,
      );
    }
    for (final type in [null, '', 'FUTURE_POWERUP', 'MYSTERY_POTION']) {
      expect(
        PowerupFeedPresentation.valenceForType(type),
        PowerupFeedValence.neutral,
        reason: '$type',
      );
    }
  });

  test('matches every named powerup independently at Unicode boundaries', () {
    const description =
        "Nathan's Decoy redirected Anjali's Hitchhike to Shefali. "
        'Compression Socks blocked Wrong Turn; Wrong Turntable is prose. '
        'éWrong Turné is also prose.';
    final mentions = PowerupFeedPresentation.mentionsIn(
      description,
      hintedType: 'HITCHHIKE',
    );
    expect(mentions.map((mention) => mention.text), [
      'Decoy',
      'Hitchhike',
      'Compression Socks',
      'Wrong Turn',
    ]);
    expect(mentions.map((mention) => mention.valence), [
      PowerupFeedValence.beneficial,
      PowerupFeedValence.beneficial,
      PowerupFeedValence.beneficial,
      PowerupFeedValence.harmful,
    ]);
  });

  test('matches the current catalog name for a known semantic type', () async {
    final installed = await PowerupCopy.refresh(
      fetch: () async => const {
        'version': 'feed-name-test',
        'powerups': [
          {
            'type': 'WRONG_TURN',
            'name': 'Wrong-Way Whistle',
            'description': 'A harmful reversal.',
          },
        ],
      },
    );
    expect(installed, isTrue);
    final mentions = PowerupFeedPresentation.mentionsIn(
      'Maya reflected the Wrong-Way Whistle.',
      hintedType: 'WRONG_TURN',
    );
    expect(mentions, hasLength(1));
    expect(mentions.single.text, 'Wrong-Way Whistle');
    expect(mentions.single.valence, PowerupFeedValence.harmful);
  });

  testWidgets('reflected Wrong Turn stays red while defenses stay green', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        theme: AppThemeData.light(),
        home: const Scaffold(
          body: Column(
            children: [
              FeedBubble(
                eventType: 'POWERUP_REFLECTED',
                powerupType: 'WRONG_TURN',
                description: "Maya's Mirror reflected Jordan's Wrong Turn.",
                actorName: 'Maya',
                relativeTime: 'now',
              ),
              FeedBubble(
                eventType: 'POWERUP_BLOCKED',
                powerupType: 'HITCHHIKE',
                description:
                    "Shefali's Compression Socks blocked the redirected Hitchhike.",
                actorName: 'Shefali',
                relativeTime: 'now',
              ),
            ],
          ),
        ),
      ),
    );

    final colors = _descriptionColors(tester);
    expect(colors['Wrong Turn'], AppPalette.light.feedAttack);
    expect(colors['Mirror'], AppPalette.light.feedPositive);
    expect(colors['Compression Socks'], AppPalette.light.feedPositive);
    expect(colors['Hitchhike'], AppPalette.light.feedPositive);
  });

  for (final dark in [false, true]) {
    testWidgets(
      'two-message redirect chain wraps and colors every name in ${dark ? 'dark' : 'light'} theme',
      (tester) async {
        tester.view.physicalSize = const Size(320, 760);
        tester.view.devicePixelRatio = 1;
        tester.platformDispatcher.textScaleFactorTestValue = 2;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);

        final theme = dark ? AppThemeData.night() : AppThemeData.light();
        await tester.pumpWidget(
          MaterialApp(
            theme: theme,
            home: const Scaffold(
              body: Padding(
                padding: EdgeInsets.all(8),
                child: Column(
                  children: [
                    FeedBubble(
                      eventType: 'POWERUP_REDIRECTED',
                      powerupType: 'HITCHHIKE',
                      description:
                          "Nathan's Decoy redirected Anjali's Hitchhike to Shefali.",
                      actorName: 'Nathan',
                      relativeTime: 'now',
                    ),
                    FeedBubble(
                      eventType: 'POWERUP_BLOCKED',
                      powerupType: 'HITCHHIKE',
                      description:
                          "Shefali's Compression Socks blocked the redirected Hitchhike.",
                      actorName: 'Shefali',
                      relativeTime: 'now',
                    ),
                  ],
                ),
              ),
            ),
          ),
        );

        expect(
          find.text(
            "Nathan's Decoy redirected Anjali's Hitchhike to Shefali.",
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(
          find.text(
            "Shefali's Compression Socks blocked the redirected Hitchhike.",
            findRichText: true,
          ),
          findsOneWidget,
        );
        expect(tester.takeException(), isNull);

        final palette = dark ? AppPalette.night : AppPalette.light;
        final colors = _descriptionColors(tester);
        for (final name in ['Decoy', 'Hitchhike', 'Compression Socks']) {
          expect(colors[name], palette.feedPositive, reason: name);
        }
        expect(
          _contrast(palette.feedPositive, palette.parchment),
          greaterThanOrEqualTo(4.5),
        );
        expect(
          _contrast(palette.feedAttack, palette.parchment),
          greaterThanOrEqualTo(4.5),
        );
      },
    );
  }
}
