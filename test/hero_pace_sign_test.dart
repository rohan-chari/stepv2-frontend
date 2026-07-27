import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/hero_pace_sign.dart';

/// Batch 2026-07-27 item 18 — the hero pace line used to sit directly on the
/// scrolling ground strip with only a drop shadow separating it from the brick
/// texture. It now sits on a wooden trail-sign plank.
///
/// The plank is a fixed-colour PNG, so its text colour must NOT be a theme
/// surface token: the wood is the same warm brown in both palettes, and a
/// night-flipping token would go invisible on it. These tests pin that.

Future<void> _pump(
  WidgetTester tester, {
  required Brightness brightness,
  String text = 'Fresh day. Get moving to hit your first milestone.',
}) async {
  await tester.binding.setSurfaceSize(const Size(390, 400));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      theme: ThemeData(brightness: brightness),
      home: Scaffold(
        body: Center(
          child: SizedBox(width: 300, child: HeroPaceSign(text: text)),
        ),
      ),
    ),
  );
  await tester.pump();
}

void main() {
  testWidgets('the sign renders the plank art and the pace line', (
    tester,
  ) async {
    await _pump(tester, brightness: Brightness.light);

    final image = tester.widget<Image>(
      find.byKey(const Key('hero-pace-sign-plank')),
    );
    expect((image.image as AssetImage).assetName,
        'assets/images/trail_sign_plank.png');
    expect(find.text('Fresh day. Get moving to hit your first milestone.'),
        findsOneWidget);
    expect(tester.takeException(), isNull);
  });

  testWidgets('the pace text keeps the same wood-safe colour in both palettes', (
    tester,
  ) async {
    Color renderedInk() => tester
        .widget<Text>(find.byKey(const Key('hero-pace-sign-text')))
        .style!
        .color!;

    await _pump(tester, brightness: Brightness.light);
    final light = renderedInk();
    await _pump(tester, brightness: Brightness.dark);
    final dark = renderedInk();

    // The plank does not change colour with the theme, so neither may the text.
    expect(light, dark);
    expect(light, HeroPaceSign.inkOnWood);
  });

  test('the ink clears 4.5:1 against the plank wood', () {
    double luminance(Color c) {
      double channel(double v) =>
          v <= 0.03928 ? v / 12.92 : math.pow((v + 0.055) / 1.055, 2.4) as double;
      return 0.2126 * channel(c.r) + 0.7152 * channel(c.g) + 0.0722 * channel(c.b);
    }

    final a = luminance(HeroPaceSign.plankWood) + 0.05;
    final b = luminance(HeroPaceSign.inkOnWood) + 0.05;
    final ratio = a > b ? a / b : b / a;
    expect(ratio, greaterThanOrEqualTo(4.5));
  });

  testWidgets('a long pace line shrinks to fit rather than truncating', (
    tester,
  ) async {
    await _pump(
      tester,
      brightness: Brightness.light,
      text: 'You are absolutely flying today and well past every milestone '
          'that this app has to offer you right now.',
    );

    // Same defect class as item 4: a silent ellipsis is worse than shrinking.
    // Three things together guarantee the line is never truncated — no line
    // cap, no ellipsis, and a laid-out paragraph that fits inside the plank.
    final text = tester.widget<Text>(
      find.byKey(const Key('hero-pace-sign-text')),
    );
    expect(text.maxLines, isNull);
    expect(text.overflow, isNot(TextOverflow.ellipsis));

    final paragraph = tester.renderObject<RenderParagraph>(
      find.byKey(const Key('hero-pace-sign-text')),
    );
    expect(paragraph.didExceedMaxLines, isFalse);
    expect(find.byType(FittedBox), findsWidgets);

    // And the whole sign still fits the 300pt slot it was given.
    expect(
      tester.getSize(find.byKey(const Key('hero-pace-sign-plank'))).width,
      lessThanOrEqualTo(300),
    );
  });
}
