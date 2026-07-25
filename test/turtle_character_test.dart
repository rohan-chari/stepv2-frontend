import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/screens/tabs/shop_tab.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/styles.dart';
import 'package:step_tracker/widgets/accessory_thumbnail.dart';
import 'package:step_tracker/widgets/attack_outcome_modal.dart';
import 'package:step_tracker/widgets/feed_bubble.dart';
import 'package:step_tracker/widgets/goal_track.dart';
import 'package:step_tracker/widgets/home_course_track.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

// ---------------------------------------------------------------------------
// Turtle base character (docs/turtle-character-requirements.md §10 "Frontend").
//
// The turtle sheet is 704x88 = EIGHT 88x88 frames, not the capybara's six. The
// frame count is per-animal config (`AnimalSprite.frameCount`), so the proof
// this works is that the REAL widgets render the turtle sheet laid out at 8
// frames wide.
//
// Back-compat (CLAUDE.md rule #1): the backend may be newer or older than this
// binary. An `animal` value this build doesn't bundle, or no `animal` at all,
// must silently render the capybara; a missing `blockedBy` must keep the
// existing Compression Socks default.
// ---------------------------------------------------------------------------

const _turtleAsset = 'assets/images/turtle_walk_right.png';
const _capybaraAsset = 'assets/images/capybara_walk_right.png';

/// Every walk-cycle sheet rendered in the tree, as
/// `assetName -> frames wide`. `CapybaraSpriteWithAccessories` lays the sheet
/// out at `width = capybaraSize * frameCount` and `height = capybaraSize`, so
/// the width/height ratio IS the frame count the widget used.
Map<String, int> _renderedSheets(WidgetTester tester) {
  final result = <String, int>{};
  for (final image in tester.widgetList<Image>(find.byType(Image))) {
    final provider = image.image;
    if (provider is! AssetImage) continue;
    final name = provider.assetName;
    if (!name.endsWith('_walk_right.png')) continue;
    final w = image.width;
    final h = image.height;
    if (w == null || h == null || h == 0) continue;
    result[name] = (w / h).round();
  }
  return result;
}

Future<void> _pumpTrack(WidgetTester tester, {String? animal}) async {
  await tester.binding.setSurfaceSize(const Size(800, 900));
  addTearDown(() => tester.binding.setSurfaceSize(null));
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: HomeCourseTrack(
          goalSteps: 8000,
          runners: [
            GoalTrackRunner(
              name: 'You',
              progress: 0.5,
              isUser: true,
              animal: animal,
            ),
          ],
        ),
      ),
    ),
  );
  await tester.pump();
}

Future<void> _pumpModal(WidgetTester tester, Map<String, dynamic> result) async {
  await tester.pumpWidget(
    MaterialApp(
      home: Scaffold(
        body: AttackOutcomeModal(result: result, onDismiss: () {}),
      ),
    ),
  );
  await tester.pump();
}

// -- Shop harness (mirrors the shape the real catalog endpoint returns) ------

class _FakeShopApi extends BackendApiService {
  _FakeShopApi(this.catalog);

  final Map<String, dynamic> catalog;

  @override
  Future<Map<String, dynamic>> fetchShopCatalog({
    required String identityToken,
  }) async {
    return catalog;
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupShopCatalog({
    required String identityToken,
  }) async {
    return {'coins': 5000, 'items': <Map<String, dynamic>>[]};
  }

  @override
  Future<Map<String, dynamic>> fetchPowerupInventory({
    required String identityToken,
  }) async {
    return {'items': <Map<String, dynamic>>[]};
  }
}

Future<AuthService> _createAuthService() async {
  SharedPreferences.setMockInitialValues({
    'auth_identity_token': 'apple-token',
    'auth_user_identifier': 'apple-user-123',
    'auth_session_token': 'session-token',
    'auth_backend_user_id': 'user-1',
    'auth_display_name': 'Walker',
    'auth_coins': 5000,
    'auth_held_coins': 0,
  });
  final authService = AuthService();
  await authService.restoreSession();
  return authService;
}

Map<String, dynamic> _turtleCatalog() => {
  'coins': 5000,
  'ownedItemIds': <String>[],
  'equipped': <String, dynamic>{},
  'items': [
    {
      'id': 'item-turtle',
      'sku': 'turtle',
      'name': 'Turtle',
      'description':
          'Slow and steady — and armored. Shell: 30% chance to bounce off '
          'any attack a rival throws your way.',
      'slot': 'CHARACTER',
      'priceCoins': 1000,
      'assetKey': 'turtle',
      'owned': false,
      'equipped': false,
      'renderMetadata': {'animationFrames': 8},
    },
  ],
};

void main() {
  // §10.1 --------------------------------------------------------------------
  testWidgets('home course track renders the turtle sheet at 8 frames', (
    tester,
  ) async {
    await _pumpTrack(tester, animal: 'turtle');

    final sheets = _renderedSheets(tester);
    expect(
      sheets.containsKey(_turtleAsset),
      isTrue,
      reason: 'expected the turtle walk sheet on the track, got: $sheets',
    );
    expect(sheets[_turtleAsset], 8);
    expect(sheets.containsKey(_capybaraAsset), isFalse);
  });

  // §10.2 — degradation, both directions of backend/app skew ------------------
  testWidgets('an unknown animal falls back to the capybara without throwing', (
    tester,
  ) async {
    await _pumpTrack(tester, animal: 'unknown_animal');

    expect(tester.takeException(), isNull);
    final sheets = _renderedSheets(tester);
    expect(sheets[_capybaraAsset], 6);
    expect(sheets.containsKey('assets/images/unknown_animal.png'), isFalse);
  });

  testWidgets('a missing animal falls back to the capybara without throwing', (
    tester,
  ) async {
    await _pumpTrack(tester, animal: null);

    expect(tester.takeException(), isNull);
    expect(_renderedSheets(tester)[_capybaraAsset], 6);
  });

  // §10.3 --------------------------------------------------------------------
  testWidgets('AttackOutcomeModal renders a SHELL block as "Shell"', (
    tester,
  ) async {
    await _pumpModal(tester, const {
      'blocked': true,
      'blockedBy': 'SHELL',
      'outcome': 'BLOCKED',
      'upgradeLevel': 0,
      'coinsSpent': 0,
    });

    expect(find.text('BLOCKED!'), findsOneWidget);
    expect(find.text('Shell'), findsOneWidget);
    expect(find.text('SHELL'), findsNothing);
    expect(
      tester.widget<PowerupIcon>(find.byType(PowerupIcon)).type,
      'SHELL',
    );
    expect(tester.takeException(), isNull);
  });

  // §10.4 — degradation: an older backend never sends blockedBy ---------------
  testWidgets('AttackOutcomeModal without blockedBy still renders the default', (
    tester,
  ) async {
    await _pumpModal(tester, const {'blocked': true, 'outcome': 'BLOCKED'});

    expect(find.text('BLOCKED!'), findsOneWidget);
    expect(find.text('Compression Socks'), findsOneWidget);
    expect(
      tester.widget<PowerupIcon>(find.byType(PowerupIcon)).type,
      'COMPRESSION_SOCKS',
    );
  });

  // §8.3 — the race feed treats a Shell block as a shield ---------------------
  testWidgets('FeedBubble gives a SHELL use the shield accent', (tester) async {
    late Color shieldColor;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) {
              shieldColor = AppColors.of(context).feedShield;
              return const FeedBubble(
                eventType: 'POWERUP_USED',
                powerupType: 'SHELL',
                description: "Walker's Shell bounced off Rival's Leg Cramp!",
                actorName: 'Walker',
                relativeTime: '1m',
              );
            },
          ),
        ),
      ),
    );
    await tester.pump();

    // The description is a RichText whose spans split the server sentence
    // around the powerup name; the avatar's initial is a plain Text (also a
    // RichText in the tree), so pick the one that actually has children.
    final spans = tester
        .widgetList<RichText>(find.byType(RichText))
        .map((r) => r.text)
        .whereType<TextSpan>()
        .expand((t) => t.children ?? const <InlineSpan>[])
        .whereType<TextSpan>()
        .toList();
    final shellSpan = spans.firstWhere((s) => s.text == 'Shell');
    expect(shellSpan.style?.color, shieldColor);
  });

  // §10.5 --------------------------------------------------------------------
  testWidgets('shop CHARACTER tile renders the turtle at 8 frames for 1000', (
    tester,
  ) async {
    await tester.binding.setSurfaceSize(const Size(800, 1400));
    addTearDown(() => tester.binding.setSurfaceSize(null));

    final auth = await _createAuthService();
    await tester.pumpWidget(
      MaterialApp(
        home: ShopTab(
          authService: auth,
          backendApiService: _FakeShopApi(_turtleCatalog()),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 200));

    // Characters live behind their own category pill in the STORE segment.
    final pill = find.text('CHARACTERS');
    if (pill.evaluate().isNotEmpty) {
      await tester.tap(pill.first);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 200));
    }

    expect(find.text('Turtle'), findsWidgets);
    expect(find.textContaining('1000'), findsWidgets);

    final thumbs = tester
        .widgetList<AccessoryThumbnail>(find.byType(AccessoryThumbnail))
        .where((t) => t.assetKey == 'turtle')
        .toList();
    expect(thumbs, isNotEmpty, reason: 'no turtle thumbnail in the store grid');
    expect(thumbs.first.assetPath, _turtleAsset);
    expect(thumbs.first.animationFrames, 8);
  });
}
