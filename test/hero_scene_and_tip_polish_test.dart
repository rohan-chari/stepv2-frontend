import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/coach_tip.dart';
import 'package:step_tracker/widgets/hero_pace_sign.dart';
import 'package:step_tracker/widgets/home_hero_scene.dart';

/// Polish pass on the home hero and the coach tips (2026-07-27, follow-up).
///
/// Three separate defects, all of them things a unit test over a helper would
/// have missed because they are properties of what actually renders:
///
///  1. the pace line on the trail sign shrank to ~7pt and was unreadable;
///  2. the coach tip carried its own gutters, so on a host that already had
///     padding the card sat visibly inset from the control it explained;
///  3. the clouds drifted *against* the ground, which inverts the depth cue.

/// Effective on-screen font size of [key]'s text, after any [FittedBox] above
/// it has scaled the subtree.
///
/// `getSize` reports the pre-transform box and `getRect` the painted one, so
/// their ratio is the scale actually applied — which is the whole question
/// here. Reading `style.fontSize` alone would have happily passed on the
/// broken version.
double _renderedFontSize(WidgetTester tester, Key key) {
  final finder = find.byKey(key);
  final local = tester.getSize(finder);
  final painted = tester.getRect(finder);
  final scale = local.height == 0 ? 1.0 : painted.height / local.height;
  return tester.widget<Text>(finder).style!.fontSize! * scale;
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  group('hero pace sign legibility', () {
    // The longest line the hero can produce (home_tab's _heroSummary).
    const longest =
        'Huge day. You cleared every milestone — go claim those coins.';

    Future<void> pumpAtHomeSize(
      WidgetTester tester, {
      required bool compact,
      String text = longest,
      Brightness brightness = Brightness.light,
    }) async {
      final height = HeroPaceSign.heightFor(compact: compact);
      await tester.binding.setSurfaceSize(const Size(390, 400));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: ThemeData(brightness: brightness),
          home: Scaffold(
            body: Center(
              child: SizedBox(
                height: height,
                width: height * HeroPaceSign.plankAspect,
                child: HeroPaceSign(text: text),
              ),
            ),
          ),
        ),
      );
      await tester.pump();
    }

    // The text window must seat three whole lines at the base size, because
    // that is how many the longest copy takes on a phone — at the shipped 40pt
    // board the window held 1.7 lines, so the FittedBox scaled the whole block
    // to ~7pt to make it fit.
    //
    // Asserted as geometry rather than as a measured font size on purpose:
    // widget tests substitute a monospaced test font whose glyphs are a full em
    // wide, so any assertion that depends on advance widths measures the test
    // font, not DM Sans. Line *height* is exact in both.
    testWidgets('the text window seats three full lines at the base size', (
      tester,
    ) async {
      await pumpAtHomeSize(tester, compact: false, text: 'x');

      const lineHeight = HeroPaceSign.textSize * 1.35; // PixelText.body height
      final window = tester.getSize(
        find.byKey(const Key('hero-pace-sign-window')),
      );
      expect(window.height, greaterThanOrEqualTo(lineHeight * 3));
      expect(window.width, greaterThanOrEqualTo(200));
    });

    testWidgets('short phones still seat more than two lines', (tester) async {
      await pumpAtHomeSize(tester, compact: true, text: 'x');

      const lineHeight = HeroPaceSign.textSize * 1.35;
      final window = tester.getSize(
        find.byKey(const Key('hero-pace-sign-window')),
      );
      expect(window.height, greaterThan(lineHeight * 2.5));
    });

    testWidgets('a line that fits is painted at full size, never shrunk', (
      tester,
    ) async {
      await pumpAtHomeSize(tester, compact: false, text: 'Nice pace.');

      expect(
        _renderedFontSize(tester, const Key('hero-pace-sign-text')),
        closeTo(HeroPaceSign.textSize, 0.01),
      );
    });

    testWidgets('the board is meaningfully larger than the 40pt original', (
      tester,
    ) async {
      expect(HeroPaceSign.heightFor(compact: false), greaterThan(40));
      expect(HeroPaceSign.heightFor(compact: true), greaterThan(40));
    });

    testWidgets('the ink and its highlight are identical in both palettes', (
      tester,
    ) async {
      TextStyle inkStyle() => tester
          .widget<Text>(find.byKey(const Key('hero-pace-sign-text')))
          .style!;

      await pumpAtHomeSize(tester, compact: false);
      final light = inkStyle();
      await pumpAtHomeSize(
        tester,
        compact: false,
        brightness: Brightness.dark,
      );
      final dark = inkStyle();

      // The plank PNG is one fixed-colour asset, so nothing painted on it may
      // flip with the palette — the night-flip trap that made roofMid-as-text
      // invisible. This covers the added carve highlight, not just the ink.
      expect(light.color, dark.color);
      expect(light.shadows?.map((s) => s.color).toList(),
          dark.shadows?.map((s) => s.color).toList());
    });
  });

  group('coach tip', () {
    // The store reads its seen-set out of SharedPreferences before the tip is
    // allowed to show; without a mock backing store that read never resolves
    // and nothing renders.
    setUp(() => SharedPreferences.setMockInitialValues({}));

    Future<void> pumpTip(
      WidgetTester tester, {
      EdgeInsets? margin,
    }) async {
      await tester.binding.setSurfaceSize(const Size(390, 600));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        MaterialApp(
          theme: AppThemeData.light(),
          home: Scaffold(
            body: Column(
              children: [
                CoachTipHost(
                  tip: CoachTipId.friendsAdd,
                  store: CoachTipStore(),
                  margin: margin ?? const EdgeInsets.fromLTRB(16, 8, 16, 4),
                  child: const SizedBox.shrink(),
                ),
                Container(key: const Key('sibling'), height: 40),
              ],
            ),
          ),
        ),
      );
      // Let the seen-set read resolve, then run the entrance.
      await tester.pump();
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
    }

    testWidgets('a zero-gutter margin aligns the card with its siblings', (
      tester,
    ) async {
      await pumpTip(tester, margin: const EdgeInsets.only(bottom: 12));

      final card = tester.getRect(find.byKey(const Key('coach-tip-card')));
      final sibling = tester.getRect(find.byKey(const Key('sibling')));

      // The Friends tab bug: the tip's own 16pt gutters stacked on top of the
      // tab's, leaving the card visibly inset from the search field it points
      // at. With a zero horizontal margin the card's edges line up with its
      // siblings' exactly.
      expect(card.left, closeTo(sibling.left, 0.5));
      expect(card.right, closeTo(sibling.right, 0.5));
    });

    testWidgets('the card leaves a gap above the control below it', (
      tester,
    ) async {
      await pumpTip(tester, margin: const EdgeInsets.only(bottom: 12));

      final cardBottom = tester
          .getRect(find.byType(CoachTipHost))
          .bottom;
      final siblingTop = tester.getRect(find.byKey(const Key('sibling'))).top;
      expect(siblingTop - cardBottom, greaterThanOrEqualTo(0));
    });

    testWidgets('the card uses the app-wide parchment card language', (
      tester,
    ) async {
      await pumpTip(tester);

      final decorated = tester
          .widgetList<DecoratedBox>(find.byType(DecoratedBox))
          .map((d) => d.decoration)
          .whereType<BoxDecoration>()
          .where((d) => d.borderRadius == BorderRadius.circular(14))
          .toList();

      expect(decorated, isNotEmpty,
          reason: 'the tip should use the 14pt card radius, not its own 12pt');
      final card = decorated.first;
      expect(card.color, AppPalette.light.parchment);
      // The hard, un-blurred drop is the house shadow.
      expect(card.boxShadow!.single.blurRadius, 0);
      expect(card.boxShadow!.single.offset, const Offset(0, 4));
    });

    testWidgets('GOT IT still dismisses the tip', (tester) async {
      await pumpTip(tester);
      expect(find.text(coachTipCopy(CoachTipId.friendsAdd)), findsOneWidget);

      await tester.tap(find.text('GOT IT'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));
      await tester.pump();

      expect(find.text(coachTipCopy(CoachTipId.friendsAdd)), findsNothing);
    });
  });

  group('cloud parallax', () {
    testWidgets('clouds drift the same way as the ground, only slower', (
      tester,
    ) async {
      await tester.binding.setSurfaceSize(const Size(390, 500));
      addTearDown(() => tester.binding.setSurfaceSize(null));
      await tester.pumpWidget(
        const MaterialApp(
          home: Scaffold(
            body: HomeHeroScene(
              groundScrollSpeed: 26,
              child: SizedBox.expand(),
            ),
          ),
        ),
      );
      await tester.pump();

      final cloud = find.byKey(const ValueKey('home-cloud-0'));
      final start = tester.getTopLeft(cloud).dx;
      // Far enough into the 60s ambient period to move, nowhere near the wrap.
      await tester.pump(const Duration(seconds: 5));
      final later = tester.getTopLeft(cloud).dx;

      // Ground slides LEFT (negative x). A background layer must travel the
      // same direction — opposing motion reads as the clouds racing forward in
      // front of the mascot, not as depth behind it.
      expect(later, lessThan(start));

      // ...and slower than the ground, which is the actual depth cue.
      final cloudSpeed = (start - later) / 5;
      expect(cloudSpeed, lessThan(26));
      expect(cloudSpeed, greaterThan(0));
    });
  });
}
