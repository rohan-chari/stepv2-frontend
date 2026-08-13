import 'dart:async';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/config/animals.dart';
import 'package:step_tracker/services/remote_asset_cache.dart';
import 'package:step_tracker/widgets/accessory_thumbnail.dart';
import 'package:step_tracker/widgets/home_course_track.dart';
import 'package:step_tracker/widgets/powerup_icon.dart';

// ---------------------------------------------------------------------------
// CDN-served art renders through the SAME widgets as bundled art.
//
// The contract these tests pin:
//   * a bundled assetKey still resolves synchronously to Image.asset/AssetImage
//     (the four existing AssetImage-casting suites depend on this);
//   * a remote assetKey whose versioned file is already on disk renders from
//     that file (FileImage) with the identical crop/geometry math;
//   * a remote assetKey with nothing on disk and a failing download falls
//     through to the existing CustomPaint / bolt-tile placeholders.
// ---------------------------------------------------------------------------

/// Real PNG bytes, so Image.file has something decodable to work with.
final _pngBytes = File(
  'assets/images/accessories/sunglasses.png',
).readAsBytesSync();

late Directory _tmp;

/// Writes `<kind>-<key>@<version>.png` into the cache dir and re-scans.
Future<void> _seedCachedFile(
  RemoteAssetKind kind,
  String key,
  String version,
) async {
  File(
    '${_tmp.path}/${kind.name}-$key@$version.png',
  ).writeAsBytesSync(_pngBytes);
  await RemoteAssetCache.instance.debugRescan();
}

Iterable<Image> _images(WidgetTester tester) =>
    tester.widgetList<Image>(find.byType(Image));

Iterable<Image> _fileImages(WidgetTester tester, String needle) =>
    _images(tester).where(
      (image) =>
          image.image is FileImage &&
          (image.image as FileImage).file.path.contains(needle),
    );

void main() {
  setUp(() async {
    _tmp = await Directory.systemTemp.createTemp('remote_asset_render_test');
    await RemoteAssetCache.instance.debugConfigure(
      cacheDir: _tmp,
      // A non-empty set is what makes unknown keys "remote"; the real init()
      // fills this from AssetManifest.
      bundledAssets: {
        'assets/images/accessories/baseball_cap.png',
        'assets/images/accessories/sunglasses.png',
        'assets/images/accessories/shoes.png',
        'assets/images/capybara_walk_right.png',
        'assets/images/powerups/mirror.png',
      },
      fetcher: (uri, headers) async => throw const SocketException('offline'),
    );
  });

  tearDown(() async {
    RemoteAssetCache.instance.debugReset();
    if (_tmp.existsSync()) await _tmp.delete(recursive: true);
  });

  Future<void> pumpSprite(
    WidgetTester tester, {
    required List<Map<String, dynamic>> accessories,
    String? animal,
    double size = 64,
  }) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Align(
            alignment: Alignment.topLeft,
            child: CapybaraSpriteWithAccessories(
              accessories: accessories,
              capybaraSize: size,
              frameIndex: 0,
              animal: animal,
            ),
          ),
        ),
      ),
    );
    await tester.pump();
  }

  testWidgets('a bundled accessory still renders as an AssetImage', (
    tester,
  ) async {
    await pumpSprite(
      tester,
      accessories: const [
        {'slot': 'HEAD', 'assetKey': 'baseball_cap', 'renderMetadata': {}},
      ],
    );

    expect(
      _images(tester).where(
        (image) =>
            image.image is AssetImage &&
            (image.image as AssetImage).assetName.contains('baseball_cap.png'),
      ),
      hasLength(1),
    );
  });

  testWidgets(
    'a current cached manifest entry overrides a same-key bundled accessory',
    (tester) async {
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'sunglasses': {
            'url': 'https://cdn/accessories/sunglasses@aabbcc.png',
          },
        },
      });
      await _seedCachedFile(
        RemoteAssetKind.accessories,
        'sunglasses',
        'aabbcc',
      );

      await pumpSprite(
        tester,
        accessories: const [
          {'slot': 'FACE', 'assetKey': 'sunglasses', 'renderMetadata': {}},
        ],
      );

      expect(_fileImages(tester, 'sunglasses@aabbcc'), hasLength(1));
      expect(
        _images(tester).where(
          (image) =>
              image.image is AssetImage &&
              (image.image as AssetImage).assetName.contains('sunglasses'),
        ),
        isEmpty,
      );
    },
  );

  testWidgets(
    'a stale cached version falls back to a same-key bundled accessory',
    (tester) async {
      await _seedCachedFile(
        RemoteAssetKind.accessories,
        'sunglasses',
        'oldversion',
      );
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'sunglasses': {
            'url': 'https://cdn/accessories/sunglasses@newversion.png',
          },
        },
      });

      await pumpSprite(
        tester,
        accessories: const [
          {'slot': 'FACE', 'assetKey': 'sunglasses', 'renderMetadata': {}},
        ],
      );
      await tester.pump();
      await tester.pump();

      expect(_fileImages(tester, 'sunglasses'), isEmpty);
      expect(
        _images(tester).where(
          (image) =>
              image.image is AssetImage &&
              (image.image as AssetImage).assetName.contains('sunglasses'),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets(
    'a failed remote download falls back to a same-key bundled accessory',
    (tester) async {
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'sunglasses': {
            'url': 'https://cdn/accessories/sunglasses@aabbcc.png',
          },
        },
      });

      await pumpSprite(
        tester,
        accessories: const [
          {'slot': 'FACE', 'assetKey': 'sunglasses', 'renderMetadata': {}},
        ],
      );
      await tester.pump();
      await tester.pump();

      expect(
        _images(tester).where(
          (image) =>
              image.image is AssetImage &&
              (image.image as AssetImage).assetName.contains('sunglasses'),
        ),
        hasLength(1),
      );
    },
  );

  testWidgets('a malformed manifest entry keeps the bundled accessory', (
    tester,
  ) async {
    RemoteAssetCache.instance.debugApplyManifest({
      'accessories': {
        'sunglasses': {'url': false},
      },
    });

    await pumpSprite(
      tester,
      accessories: const [
        {'slot': 'FACE', 'assetKey': 'sunglasses', 'renderMetadata': {}},
      ],
    );

    expect(
      _images(tester).where(
        (image) =>
            image.image is AssetImage &&
            (image.image as AssetImage).assetName.contains('sunglasses'),
      ),
      hasLength(1),
    );
  });

  testWidgets('legacy bundled-first behavior ignores a cached manifest entry', (
    tester,
  ) async {
    await RemoteAssetCache.instance.debugConfigure(
      cacheDir: _tmp,
      bundledAssets: {
        'assets/images/accessories/baseball_cap.png',
        'assets/images/accessories/sunglasses.png',
      },
      remoteAssetPreferred: false,
    );
    RemoteAssetCache.instance.debugApplyManifest({
      'accessories': {
        'sunglasses': {'url': 'https://cdn/accessories/sunglasses@aabbcc.png'},
      },
    });
    await _seedCachedFile(RemoteAssetKind.accessories, 'sunglasses', 'aabbcc');

    await pumpSprite(
      tester,
      accessories: const [
        {'slot': 'FACE', 'assetKey': 'sunglasses', 'renderMetadata': {}},
      ],
    );

    expect(_fileImages(tester, 'sunglasses@aabbcc'), isEmpty);
    expect(
      _images(tester).where(
        (image) =>
            image.image is AssetImage &&
            (image.image as AssetImage).assetName.contains('sunglasses'),
      ),
      hasLength(1),
    );
  });

  testWidgets('a cached remote accessory renders from its cached file', (
    tester,
  ) async {
    RemoteAssetCache.instance.debugApplyManifest({
      'accessories': {
        'pirate_hat': {'url': 'https://cdn/accessories/pirate_hat@aabbcc.png'},
      },
    });
    await _seedCachedFile(RemoteAssetKind.accessories, 'pirate_hat', 'aabbcc');

    await pumpSprite(
      tester,
      accessories: const [
        {'slot': 'HEAD', 'assetKey': 'pirate_hat', 'renderMetadata': {}},
      ],
    );

    expect(_fileImages(tester, 'pirate_hat@aabbcc'), hasLength(1));
    expect(
      _images(tester).where(
        (image) =>
            image.image is AssetImage &&
            (image.image as AssetImage).assetName.contains('pirate_hat'),
      ),
      isEmpty,
      reason: 'a remote key must never be requested from the asset bundle',
    );
  });

  testWidgets('a remote animation sheet keeps the frame-crop geometry', (
    tester,
  ) async {
    RemoteAssetCache.instance.debugApplyManifest({
      'accessories': {
        'pirate_flag': {
          'url': 'https://cdn/accessories/pirate_flag@abc123.png',
        },
      },
    });
    await _seedCachedFile(RemoteAssetKind.accessories, 'pirate_flag', 'abc123');

    await pumpSprite(
      tester,
      accessories: const [
        {
          'slot': 'HEAD',
          'assetKey': 'pirate_flag',
          'renderMetadata': {'animationFrames': 6},
        },
      ],
    );

    final sheet = _fileImages(tester, 'pirate_flag@abc123').single;
    expect(sheet.width, isNotNull);
    expect(sheet.height, isNotNull);
    // The sheet is laid out six frames wide against a one-frame-tall box, the
    // same math the bundled path uses.
    final overlayBox = tester.getSize(
      find
          .ancestor(of: find.byWidget(sheet), matching: find.byType(ClipRect))
          .first,
    );
    expect(sheet.width, closeTo(overlayBox.width * 6, 0.01));
    expect(sheet.height, closeTo(overlayBox.height, 0.01));
  });

  testWidgets('an uncached remote accessory falls back to the painter', (
    tester,
  ) async {
    RemoteAssetCache.instance.debugApplyManifest({
      'accessories': {
        'pirate_hat': {'url': 'https://cdn/accessories/pirate_hat@aabbcc.png'},
      },
    });

    await pumpSprite(
      tester,
      accessories: const [
        {'slot': 'HEAD', 'assetKey': 'pirate_hat', 'renderMetadata': {}},
      ],
    );
    // Let the failing download resolve.
    await tester.pump();
    await tester.pump();

    expect(_fileImages(tester, 'pirate_hat'), isEmpty);
    expect(find.byType(CustomPaint), findsWidgets);
    expect(tester.takeException(), isNull);
  });

  testWidgets('a remote FEET accessory renders all four shoes from cache', (
    tester,
  ) async {
    RemoteAssetCache.instance.debugApplyManifest({
      'accessories': {
        'boots': {'url': 'https://cdn/accessories/boots@aabbcc.png'},
      },
    });
    await _seedCachedFile(RemoteAssetKind.accessories, 'boots', 'aabbcc');

    await pumpSprite(
      tester,
      accessories: const [
        {'slot': 'FEET', 'assetKey': 'boots', 'renderMetadata': {}},
      ],
    );

    expect(_fileImages(tester, 'boots@aabbcc'), hasLength(4));
  });

  testWidgets(
    'a delayed cold-cache FEET download renders every shoe once it completes',
    (tester) async {
      final response = Completer<List<int>?>();
      var requests = 0;
      await RemoteAssetCache.instance.debugConfigure(
        cacheDir: _tmp,
        bundledAssets: {'assets/images/capybara_walk_right.png'},
        fetcher: (uri, headers) {
          requests++;
          return response.future;
        },
      );
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'boots': {'url': 'https://cdn/accessories/boots@aabbcc.png'},
        },
      });
      late Future<File?> sharedFetch;
      await tester.runAsync(() async {
        sharedFetch = RemoteAssetCache.instance.fetch(
          RemoteAssetKind.accessories,
          'boots',
        );
      });

      await pumpSprite(
        tester,
        accessories: const [
          {'slot': 'FEET', 'assetKey': 'boots', 'renderMetadata': {}},
        ],
      );
      expect(requests, 1);
      expect(_fileImages(tester, 'boots@aabbcc'), isEmpty);

      await tester.runAsync(() async {
        response.complete(_pngBytes);
        expect(await sharedFetch, isNotNull);
      });
      await tester.pump();
      expect(_fileImages(tester, 'boots@aabbcc'), hasLength(4));
      expect(tester.takeException(), isNull);
    },
  );

  group('AccessoryThumbnail', () {
    Future<void> pumpThumb(WidgetTester tester, Widget thumb) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: SizedBox.square(dimension: 48, child: thumb)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('bundled keys keep the thumb-first Image.asset path', (
      tester,
    ) async {
      await pumpThumb(tester, const AccessoryThumbnail(assetKey: 'sunglasses'));

      expect(
        _images(tester).where(
          (image) =>
              image.image is AssetImage &&
              (image.image as AssetImage).assetName.contains('sunglasses'),
        ),
        isNotEmpty,
      );
    });

    testWidgets(
      'a current cached manifest entry overrides a bundled thumbnail',
      (tester) async {
        RemoteAssetCache.instance.debugApplyManifest({
          'accessories': {
            'sunglasses': {
              'url': 'https://cdn/accessories/sunglasses@aabbcc.png',
            },
          },
        });
        await _seedCachedFile(
          RemoteAssetKind.accessories,
          'sunglasses',
          'aabbcc',
        );

        await pumpThumb(
          tester,
          const AccessoryThumbnail(assetKey: 'sunglasses'),
        );

        expect(_fileImages(tester, 'sunglasses@aabbcc'), hasLength(1));
        expect(
          _images(tester).where((image) => image.image is AssetImage),
          isEmpty,
          reason: 'the bundled _thumb must not outrank a manifest entry',
        );
      },
    );

    testWidgets('remote keys skip the _thumb attempt and use the cache', (
      tester,
    ) async {
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'pirate_hat': {
            'url': 'https://cdn/accessories/pirate_hat@aabbcc.png',
          },
        },
      });
      await _seedCachedFile(
        RemoteAssetKind.accessories,
        'pirate_hat',
        'aabbcc',
      );

      await pumpThumb(tester, const AccessoryThumbnail(assetKey: 'pirate_hat'));

      expect(_fileImages(tester, 'pirate_hat@aabbcc'), hasLength(1));
      expect(
        _images(tester).where((image) => image.image is AssetImage),
        isEmpty,
        reason: 'remote items ship no bundled _thumb.png to try',
      );
    });
  });

  group('remote characters', () {
    testWidgets('an uncached remote animal still renders the capybara', (
      tester,
    ) async {
      RemoteAssetCache.instance.debugApplyManifest({
        'characters': {
          'red_panda': {
            'url': 'https://cdn/characters/red_panda@abc123.png',
            'animationFrames': 8,
            'baselineOffset': -0.25,
          },
        },
      });

      await pumpSprite(tester, accessories: const [], animal: 'red_panda');

      expect(
        _images(tester).where(
          (image) =>
              image.image is AssetImage &&
              (image.image as AssetImage).assetName ==
                  'assets/images/capybara_walk_right.png',
        ),
        hasLength(1),
      );
    });

    testWidgets('a cached remote animal uses its frames and baseline', (
      tester,
    ) async {
      RemoteAssetCache.instance.debugApplyManifest({
        'characters': {
          'red_panda': {
            'url': 'https://cdn/characters/red_panda@abc123.png',
            'animationFrames': 8,
            'baselineOffset': -0.25,
          },
        },
      });
      await _seedCachedFile(RemoteAssetKind.characters, 'red_panda', 'abc123');

      final sprite = animalSpriteFor('red_panda');
      expect(sprite.frameCount, 8);
      expect(sprite.baselineOffset, closeTo(-0.25, 1e-9));
      expect(sprite.file, isNotNull);

      await pumpSprite(
        tester,
        accessories: const [],
        animal: 'red_panda',
        size: 64,
      );

      final sheet = _fileImages(tester, 'red_panda@abc123').single;
      expect(sheet.width, 64 * 8);
      expect(sheet.height, 64);
      // baselineOffset (-0.25 * 64 = -16) lifts the whole sprite.
      final capyTop = tester.getTopLeft(find.byWidget(sheet)).dy;
      await pumpSprite(tester, accessories: const [], animal: null, size: 64);
      final defaultTop = tester
          .getTopLeft(
            find.byWidgetPredicate(
              (w) =>
                  w is Image &&
                  w.image is AssetImage &&
                  (w.image as AssetImage).assetName ==
                      'assets/images/capybara_walk_right.png',
            ),
          )
          .dy;
      expect(capyTop - defaultTop, closeTo(-16, 0.01));
    });
  });

  group('powerup icons', () {
    Future<void> pumpIcon(WidgetTester tester, String type) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: Center(child: PowerupIcon(type: type, size: 32)),
          ),
        ),
      );
      await tester.pump();
    }

    testWidgets('a bundled powerup keeps its Image.asset', (tester) async {
      await pumpIcon(tester, 'MIRROR');
      expect(
        _images(tester).where(
          (image) =>
              image.image is AssetImage &&
              (image.image as AssetImage).assetName.contains('mirror.png'),
        ),
        hasLength(1),
      );
    });

    testWidgets('an unknown type with a cached remote icon renders it', (
      tester,
    ) async {
      RemoteAssetCache.instance.debugApplyManifest({
        'powerups': {
          'TIME_WARP': {'url': 'https://cdn/powerups/time_warp@abc123.png'},
        },
      });
      await _seedCachedFile(RemoteAssetKind.powerups, 'TIME_WARP', 'abc123');

      await pumpIcon(tester, 'TIME_WARP');

      expect(_fileImages(tester, 'TIME_WARP@abc123'), hasLength(1));
    });

    testWidgets('an unknown type with no art keeps the bolt fallback', (
      tester,
    ) async {
      await pumpIcon(tester, 'TIME_WARP');

      expect(find.byIcon(Icons.bolt_rounded), findsOneWidget);
    });
  });
}
