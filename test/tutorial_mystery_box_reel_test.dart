import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/demo/demo_reel_preview.dart';
import 'package:step_tracker/widgets/case_opening_strip.dart';

void main() {
  test('tutorial reel preview uses real powerups', () {
    expect(demoReelDropOdds['reelPreviewAvailable'], isTrue);
    final byType = demoReelDropOdds['byType'] as Map<String, dynamic>;
    expect(byType.keys.toSet(), {
      'PROTEIN_SHAKE',
      'COMPRESSION_SOCKS',
      'SHORTCUT',
    });
    expect(
      byType.values.fold<double>(
        0,
        (sum, value) => sum + (value as num).toDouble(),
      ),
      closeTo(1.0, 0.000001),
    );
    expect(demoReelRarityByType.keys.toSet(), byType.keys.toSet());
  });

  testWidgets('idle case reel centers a preview tile under the pointer', (
    tester,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Center(
            child: SizedBox(
              width: 350,
              child: CaseOpeningReel(
                itemCount: 5,
                resultIndex: 4,
                onComplete: () {},
                itemBuilder: (context, index, isResult) => SizedBox(
                  key: Key('tile-$index'),
                  width: 86,
                  height: 100,
                ),
              ),
            ),
          ),
        ),
      ),
    );

    final viewport = find.byKey(const Key('case-opening-reel-viewport'));
    final firstTile = find.byKey(const Key('tile-0'));
    final leadingPreview = find.byKey(
      const Key('case-opening-leading-preview-0'),
    );

    expect(viewport, findsOneWidget);
    expect(firstTile, findsOneWidget);
    expect(leadingPreview, findsOneWidget);
    expect(
      tester.getCenter(firstTile).dx,
      closeTo(tester.getCenter(viewport).dx, 0.5),
    );
    expect(
      tester.getCenter(leadingPreview).dx,
      lessThan(tester.getCenter(viewport).dx),
      reason: 'idle reel must have a tile visible to the left of the pointer',
    );
    expect(
      tester.getCenter(leadingPreview).dx,
      greaterThan(tester.getTopLeft(viewport).dx),
      reason: 'leading preview should be inside the visible reel window',
    );
  });
}
