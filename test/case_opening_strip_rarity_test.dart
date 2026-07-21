import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/widgets/case_opening_strip.dart';

/// Spec §6.3.B.8 / test plan 25-26: the reel's bundled `_rarityByType` table is
/// a FALLBACK only. When the backend sends a rarity table the server value wins
/// for every tile; when it is absent the bundled table still renders the reel.
Future<void> _pumpStrip(
  WidgetTester tester, {
  Map<String, String>? rarityByType,
}) async {
  tester.view.physicalSize = const Size(1170, 2532);
  tester.view.devicePixelRatio = 3.0;
  addTearDown(tester.view.reset);

  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: CaseOpeningStrip(
          resultType: '',
          resultRarity: 'COMMON',
          onComplete: () {},
          rarityByType: rarityByType,
        ),
      ),
    ),
  );
  await tester.pump();
}

List<String> _tileRarities(WidgetTester tester) => tester
    .widgetList<CaseReelTile>(find.byType(CaseReelTile, skipOffstage: false))
    .map((t) => t.rarity)
    .toList();

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  testWidgets('server rarityByType overrides the bundled map for every tile', (
    WidgetTester tester,
  ) async {
    // Deliberately a rarity the bundled table assigns to NO common type, so a
    // pass can only come from the server map.
    const allUncommon = {
      'PROTEIN_SHAKE': 'UNCOMMON',
      'SHORTCUT': 'UNCOMMON',
      'TRAIL_MIX': 'UNCOMMON',
      'DETOUR_SIGN': 'UNCOMMON',
      'TRAIL_MAGNET': 'UNCOMMON',
      'RUNNERS_HIGH': 'UNCOMMON',
      'LEG_CRAMP': 'UNCOMMON',
      'STEALTH_MODE': 'UNCOMMON',
      'WRONG_TURN': 'UNCOMMON',
      'PINECONE_TOSS': 'UNCOMMON',
      'RED_CARD': 'UNCOMMON',
      'SECOND_WIND': 'UNCOMMON',
      'COMPRESSION_SOCKS': 'UNCOMMON',
      'FANNY_PACK': 'UNCOMMON',
      'LUCKY_HORSESHOE': 'UNCOMMON',
      'POCKET_WATCH': 'UNCOMMON',
      'TRAIL_MINE': 'UNCOMMON',
      'SNEAKY_SWAP': 'UNCOMMON',
      'CLEANSE': 'UNCOMMON',
      'MIRROR': 'UNCOMMON',
    };

    await _pumpStrip(tester, rarityByType: allUncommon);

    final rarities = _tileRarities(tester);
    expect(rarities, isNotEmpty);
    expect(rarities.every((r) => r == 'UNCOMMON'), isTrue);
  });

  testWidgets('server map absent -> bundled fallback used, reel still renders', (
    WidgetTester tester,
  ) async {
    await _pumpStrip(tester);

    final rarities = _tileRarities(tester);
    expect(rarities, isNotEmpty);
    // The bundled table assigns COMMON to half the pool, so an all-UNCOMMON
    // reel here would mean the fallback was dropped.
    expect(rarities.any((r) => r == 'COMMON'), isTrue);
    expect(
      rarities.every(
        (r) => const {'COMMON', 'UNCOMMON', 'RARE'}.contains(r),
      ),
      isTrue,
    );
  });

  testWidgets('a partial server map only overrides the types it names', (
    WidgetTester tester,
  ) async {
    // SHORTCUT is RARE in config but COMMON in the bundled table. Types the
    // server omits must keep their bundled rarity rather than defaulting.
    await _pumpStrip(tester, rarityByType: const {'SHORTCUT': 'RARE'});

    final rarities = _tileRarities(tester);
    expect(rarities.any((r) => r == 'COMMON'), isTrue);
    expect(tester.takeException(), isNull);
  });
}
