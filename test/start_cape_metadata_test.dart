import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/config/start_cape_metadata.dart';
import 'package:step_tracker/widgets/home_course_track.dart';

// The start screen's cape must render whatever the Accessory Tuner tuned:
// the shop-catalog funnel caches the cape's renderMetadata and the start
// screen reads it, falling back to the compiled prod snapshot only when no
// cache exists. These tests cover the resolution rules and prove the cached
// metadata actually drives the rendered widget geometry.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('StartCapeMetadata.load', () {
    test('returns compiled fallback when nothing cached', () async {
      SharedPreferences.setMockInitialValues({});
      final metadata = await StartCapeMetadata.load();
      expect(metadata, StartCapeMetadata.fallback);
    });

    test('returns cached tuner item (bobble + metadata) when present',
        () async {
      SharedPreferences.setMockInitialValues({
        StartCapeMetadata.prefsKey: jsonEncode({
          'bobble': true,
          'renderMetadata': {
            'scale': 3.0,
            'rotation': 0.5,
            'renderLayer': 'front',
            'animationFrames': 6,
          },
        }),
      });
      final item = await StartCapeMetadata.load();
      expect(item['bobble'], true);
      expect(item['renderMetadata']['scale'], 3.0);
      expect(item['renderMetadata']['rotation'], 0.5);
    });

    test('falls back on corrupt or empty cache', () async {
      SharedPreferences.setMockInitialValues({
        StartCapeMetadata.prefsKey: 'not json{',
      });
      expect(await StartCapeMetadata.load(), StartCapeMetadata.fallback);

      SharedPreferences.setMockInitialValues({
        StartCapeMetadata.prefsKey: '{}',
      });
      expect(await StartCapeMetadata.load(), StartCapeMetadata.fallback);

      SharedPreferences.setMockInitialValues({
        StartCapeMetadata.prefsKey:
            jsonEncode({'bobble': true, 'renderMetadata': {}}),
      });
      expect(await StartCapeMetadata.load(), StartCapeMetadata.fallback);
    });

    test('save round-trips through load, carrying bobble', () async {
      SharedPreferences.setMockInitialValues({});
      await StartCapeMetadata.save(
        bobble: true,
        renderMetadata: {'scale': 2.15, 'offsetY': -0.004},
      );
      final item = await StartCapeMetadata.load();
      expect(item['bobble'], true);
      expect(item['renderMetadata']['scale'], 2.15);
      expect(item['renderMetadata']['offsetY'], -0.004);
    });
  });

  group('rendered cape geometry', () {
    // Renders the same widget the start screen uses and asserts the cached
    // scale actually changes the laid-out accessory box, proving the metadata
    // is applied rather than merely stored.
    Future<Size> pumpAndMeasureCape(
      WidgetTester tester,
      Map<String, dynamic> renderMetadata,
    ) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: CapybaraCustomizationPreview(
              accessories: [
                {
                  'assetKey': 'cape',
                  'slot': 'BACK',
                  'bobble': false,
                  'renderMetadata': renderMetadata,
                },
              ],
              size: 100,
              showShadow: false,
            ),
          ),
        ),
      );
      await tester.pump();
      final positioned = tester
          .widgetList<Positioned>(find.byType(Positioned))
          .where((p) => p.width != null && p.height != null)
          .last;
      return Size(positioned.width!, positioned.height!);
    }

    testWidgets('scale in renderMetadata drives the accessory box',
        (tester) async {
      final small = await pumpAndMeasureCape(tester, {
        'scale': 1.0,
        'animationFrames': 6,
        'renderLayer': 'front',
      });
      final large = await pumpAndMeasureCape(tester, {
        'scale': 2.0,
        'animationFrames': 6,
        'renderLayer': 'front',
      });
      expect(large.width, closeTo(small.width * 2, 0.01));
      expect(large.height, closeTo(small.height * 2, 0.01));
    });
  });
}
