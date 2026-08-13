import 'dart:convert';
import 'dart:async';
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/remote_asset_cache.dart';

// ---------------------------------------------------------------------------
// RemoteAssetCache — the registry + disk cache behind CDN-served art.
//
// CLAUDE.md rule #1 (never break older clients) shows up here as: an empty
// bundled-asset set means "treat everything as bundled", so a pre-init frame —
// or any widget test that never calls init() — stays on today's Image.asset
// path byte for byte. Manifest parsing is defensive because the backend may be
// older (no /assets/manifest at all) or newer (fields we don't know).
// ---------------------------------------------------------------------------

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    tmp = await Directory.systemTemp.createTemp('remote_asset_cache_test');
    await RemoteAssetCache.instance.debugConfigure(cacheDir: tmp);
  });

  tearDown(() async {
    RemoteAssetCache.instance.debugReset();
    if (tmp.existsSync()) await tmp.delete(recursive: true);
  });

  group('isBundled', () {
    test('an empty manifest set treats every asset as bundled', () {
      expect(
        RemoteAssetCache.instance.isBundled(
          'assets/images/accessories/anything.png',
        ),
        isTrue,
      );
    });

    test('a loaded manifest set answers by membership', () async {
      await RemoteAssetCache.instance.debugConfigure(
        cacheDir: tmp,
        bundledAssets: {'assets/images/accessories/sunglasses.png'},
      );
      expect(
        RemoteAssetCache.instance.isBundled(
          'assets/images/accessories/sunglasses.png',
        ),
        isTrue,
      );
      expect(
        RemoteAssetCache.instance.isBundled(
          'assets/images/accessories/pirate_hat.png',
        ),
        isFalse,
      );
    });
  });

  group('manifest parsing', () {
    test('reads accessories, characters and powerups', () {
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'pirate_hat': {
            'url': 'https://cdn/accessories/pirate_hat@aabbcc.png',
          },
        },
        'characters': {
          'red_panda': {
            'url': 'https://cdn/characters/red_panda@ddeeff.png',
            'animationFrames': 8,
            'baselineOffset': -0.09,
          },
        },
        'powerups': {
          'TIME_WARP': {'url': 'https://cdn/powerups/time_warp@123456.png'},
        },
      });

      final hat = RemoteAssetCache.instance.entry(
        RemoteAssetKind.accessories,
        'pirate_hat',
      );
      expect(hat, isNotNull);
      expect(hat!.url, 'https://cdn/accessories/pirate_hat@aabbcc.png');
      expect(hat.version, 'aabbcc');

      final panda = RemoteAssetCache.instance.entry(
        RemoteAssetKind.characters,
        'red_panda',
      );
      expect(panda!.animationFrames, 8);
      expect(panda.baselineOffset, closeTo(-0.09, 1e-9));

      expect(
        RemoteAssetCache.instance
            .entry(RemoteAssetKind.powerups, 'TIME_WARP')
            ?.url,
        'https://cdn/powerups/time_warp@123456.png',
      );
    });

    test('ignores malformed sections and entries without crashing', () {
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': 'not-a-map',
        'characters': {
          'broken': {'animationFrames': 6},
          'ok': {'url': 'https://cdn/characters/ok@abc123.png'},
          'alsoBroken': 42,
        },
      });

      expect(
        RemoteAssetCache.instance.entry(RemoteAssetKind.accessories, 'x'),
        isNull,
      );
      expect(
        RemoteAssetCache.instance.entry(RemoteAssetKind.characters, 'broken'),
        isNull,
      );
      expect(
        RemoteAssetCache.instance.entry(RemoteAssetKind.characters, 'ok'),
        isNotNull,
      );
      // Missing metadata reads as "unknown", never as a bogus default.
      expect(
        RemoteAssetCache.instance
            .entry(RemoteAssetKind.characters, 'ok')
            ?.animationFrames,
        isNull,
      );
    });

    test('a null / non-map manifest leaves the registry untouched', () {
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'hat': {'url': 'https://cdn/accessories/hat@aaa111.png'},
        },
      });
      RemoteAssetCache.instance.debugApplyManifest(null);
      expect(
        RemoteAssetCache.instance.entry(RemoteAssetKind.accessories, 'hat'),
        isNotNull,
      );
    });
  });

  group('disk cache', () {
    test('cachedFile finds the versioned file written for an entry', () async {
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'pirate_hat': {
            'url': 'https://cdn/accessories/pirate_hat@aabbcc.png',
          },
        },
      });
      expect(
        RemoteAssetCache.instance.cachedFile(
          RemoteAssetKind.accessories,
          'pirate_hat',
        ),
        isNull,
      );

      File(
        '${tmp.path}/accessories-pirate_hat@aabbcc.png',
      ).writeAsBytesSync(const [1, 2, 3]);
      await RemoteAssetCache.instance.debugRescan();

      final file = RemoteAssetCache.instance.cachedFile(
        RemoteAssetKind.accessories,
        'pirate_hat',
      );
      expect(file, isNotNull);
      expect(file!.existsSync(), isTrue);
    });

    test('a stale version on disk is not served for the new entry', () async {
      File(
        '${tmp.path}/accessories-pirate_hat@000000.png',
      ).writeAsBytesSync(const [1]);
      await RemoteAssetCache.instance.debugRescan();
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'pirate_hat': {
            'url': 'https://cdn/accessories/pirate_hat@aabbcc.png',
          },
        },
      });

      expect(
        RemoteAssetCache.instance.cachedFile(
          RemoteAssetKind.accessories,
          'pirate_hat',
        ),
        isNull,
      );
    });

    test(
      'fetch writes the versioned file and deletes stale siblings',
      () async {
        File(
          '${tmp.path}/accessories-pirate_hat@000000.png',
        ).writeAsBytesSync(const [1]);
        await RemoteAssetCache.instance.debugConfigure(
          cacheDir: tmp,
          fetcher: (uri, headers) async => const [7, 7, 7],
        );
        await RemoteAssetCache.instance.debugRescan();
        RemoteAssetCache.instance.debugApplyManifest({
          'accessories': {
            'pirate_hat': {
              'url': 'https://cdn/accessories/pirate_hat@aabbcc.png',
            },
          },
        });

        final file = await RemoteAssetCache.instance.fetch(
          RemoteAssetKind.accessories,
          'pirate_hat',
        );

        expect(file, isNotNull);
        expect(file!.path, endsWith('accessories-pirate_hat@aabbcc.png'));
        expect(file.readAsBytesSync(), const [7, 7, 7]);
        expect(
          File('${tmp.path}/accessories-pirate_hat@000000.png').existsSync(),
          isFalse,
          reason: 'the superseded version must be deleted, not accumulated',
        );
        // No temp files left behind by the atomic write.
        expect(tmp.listSync().map((e) => e.path.split('/').last).toList(), [
          'accessories-pirate_hat@aabbcc.png',
        ]);
      },
    );

    test('a failing download resolves to null instead of throwing', () async {
      await RemoteAssetCache.instance.debugConfigure(
        cacheDir: tmp,
        fetcher: (uri, headers) async => throw const SocketException('offline'),
      );
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'pirate_hat': {
            'url': 'https://cdn/accessories/pirate_hat@aabbcc.png',
          },
        },
      });

      expect(
        await RemoteAssetCache.instance.fetch(
          RemoteAssetKind.accessories,
          'pirate_hat',
        ),
        isNull,
      );
    });

    test(
      'concurrent cold-cache callers await the same completed download',
      () async {
        final response = Completer<List<int>?>();
        var requests = 0;
        await RemoteAssetCache.instance.debugConfigure(
          cacheDir: tmp,
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

        final first = RemoteAssetCache.instance.fetch(
          RemoteAssetKind.accessories,
          'boots',
        );
        final second = RemoteAssetCache.instance.fetch(
          RemoteAssetKind.accessories,
          'boots',
        );

        expect(identical(first, second), isTrue);
        expect(requests, 1);
        response.complete(const [7, 7, 7]);

        final files = await Future.wait([first, second]);
        expect(files, everyElement(isNotNull));
        expect(files[0]!.path, files[1]!.path);
      },
    );

    test(
      'a manifest refresh retries a shared request without publishing stale art',
      () async {
        final firstResponse = Completer<List<int>?>();
        final secondResponse = Completer<List<int>?>();
        final requested = <String>[];
        await RemoteAssetCache.instance.debugConfigure(
          cacheDir: tmp,
          fetcher: (uri, headers) {
            requested.add(uri.path);
            return requested.length == 1
                ? firstResponse.future
                : secondResponse.future;
          },
        );
        RemoteAssetCache.instance.debugApplyManifest({
          'accessories': {
            'boots': {'url': 'https://cdn/accessories/boots@old111.png'},
          },
        });

        final first = RemoteAssetCache.instance.fetch(
          RemoteAssetKind.accessories,
          'boots',
        );
        RemoteAssetCache.instance.debugApplyManifest({
          'accessories': {
            'boots': {'url': 'https://cdn/accessories/boots@new222.png'},
          },
        });
        final second = RemoteAssetCache.instance.fetch(
          RemoteAssetKind.accessories,
          'boots',
        );
        expect(identical(first, second), isTrue);

        firstResponse.complete(const [1, 1, 1]);
        await Future<void>.delayed(Duration.zero);
        expect(requested, hasLength(2));
        secondResponse.complete(const [2, 2, 2]);

        final file = await first;
        expect(file, isNotNull);
        expect(file!.path, endsWith('accessories-boots@new222.png'));
        expect(file.readAsBytesSync(), const [2, 2, 2]);
        expect(
          RemoteAssetCache.instance
              .cachedFile(RemoteAssetKind.accessories, 'boots')
              ?.path,
          endsWith('accessories-boots@new222.png'),
        );
        expect(
          File('${tmp.path}/accessories-boots@old111.png').existsSync(),
          isFalse,
        );
      },
    );

    test(
      'a stale failed download retries the replacement manifest version',
      () async {
        final firstResponse = Completer<List<int>?>();
        var requests = 0;
        await RemoteAssetCache.instance.debugConfigure(
          cacheDir: tmp,
          fetcher: (uri, headers) {
            requests++;
            return requests == 1 ? firstResponse.future : Future.value([2]);
          },
        );
        RemoteAssetCache.instance.debugApplyManifest({
          'accessories': {
            'boots': {'url': 'https://cdn/accessories/boots@old111.png'},
          },
        });

        final fetch = RemoteAssetCache.instance.fetch(
          RemoteAssetKind.accessories,
          'boots',
        );
        RemoteAssetCache.instance.debugApplyManifest({
          'accessories': {
            'boots': {'url': 'https://cdn/accessories/boots@new222.png'},
          },
        });
        firstResponse.complete(null);

        final file = await fetch;
        expect(file?.path, endsWith('accessories-boots@new222.png'));
        expect(requests, 2);
      },
    );

    test('fetch of an unknown key is a null no-op', () async {
      expect(
        await RemoteAssetCache.instance.fetch(
          RemoteAssetKind.accessories,
          'nope',
        ),
        isNull,
      );
    });
  });

  group('refreshManifest', () {
    test('fetches, registers and persists the manifest', () async {
      final requested = <Uri>[];
      final headersSeen = <Map<String, String>>[];
      await RemoteAssetCache.instance.debugConfigure(
        cacheDir: tmp,
        fetcher: (uri, headers) async {
          requested.add(uri);
          headersSeen.add(headers);
          if (uri.path.endsWith('/assets/manifest')) {
            return utf8.encode(
              jsonEncode({
                'accessories': {
                  'pirate_hat': {
                    'url': 'https://cdn/accessories/pirate_hat@aabbcc.png',
                  },
                },
              }),
            );
          }
          return const [9];
        },
      );

      await RemoteAssetCache.instance.refreshManifest(
        releaseChannel: 'testflight',
      );

      expect(requested.first.path, endsWith('/assets/manifest'));
      expect(headersSeen.first['X-Release-Channel'], 'testflight');
      expect(
        RemoteAssetCache.instance.entry(
          RemoteAssetKind.accessories,
          'pirate_hat',
        ),
        isNotNull,
      );

      final prefs = await SharedPreferences.getInstance();
      expect(prefs.getString(RemoteAssetCache.manifestPrefsKey), isNotNull);
    });

    test('a failed manifest fetch keeps the previous registry', () async {
      RemoteAssetCache.instance.debugApplyManifest({
        'accessories': {
          'hat': {'url': 'https://cdn/accessories/hat@aaa111.png'},
        },
      });
      await RemoteAssetCache.instance.debugConfigure(
        cacheDir: tmp,
        fetcher: (uri, headers) async => throw const SocketException('offline'),
        keepRegistry: true,
      );

      await RemoteAssetCache.instance.refreshManifest();

      expect(
        RemoteAssetCache.instance.entry(RemoteAssetKind.accessories, 'hat'),
        isNotNull,
      );
    });

    test(
      'an accepted manifest clears categories omitted by the new response',
      () async {
        RemoteAssetCache.instance.debugApplyManifest({
          'accessories': {
            'old_hat': {'url': 'https://cdn/accessories/old_hat@aaa111.png'},
          },
          'characters': {
            'old_cat': {'url': 'https://cdn/characters/old_cat@aaa111.png'},
          },
          'powerups': {
            'OLD_POWER': {'url': 'https://cdn/powerups/old_power@aaa111.png'},
          },
        });
        await RemoteAssetCache.instance.debugConfigure(
          cacheDir: tmp,
          fetcher: (uri, headers) async => utf8.encode(
            jsonEncode({
              'accessories': {
                'new_hat': {
                  'url': 'https://cdn/accessories/new_hat@bbb222.png',
                },
              },
            }),
          ),
          keepRegistry: true,
        );

        await RemoteAssetCache.instance.refreshManifest();

        expect(
          RemoteAssetCache.instance.entry(
            RemoteAssetKind.accessories,
            'old_hat',
          ),
          isNull,
        );
        expect(
          RemoteAssetCache.instance.entry(
            RemoteAssetKind.accessories,
            'new_hat',
          ),
          isNotNull,
        );
        expect(
          RemoteAssetCache.instance.entry(
            RemoteAssetKind.characters,
            'old_cat',
          ),
          isNull,
        );
        expect(
          RemoteAssetCache.instance.entry(
            RemoteAssetKind.powerups,
            'OLD_POWER',
          ),
          isNull,
        );
      },
    );

    test('restores the persisted manifest on init when offline', () async {
      SharedPreferences.setMockInitialValues({
        RemoteAssetCache.manifestPrefsKey: jsonEncode({
          'accessories': {
            'pirate_hat': {
              'url': 'https://cdn/accessories/pirate_hat@aabbcc.png',
            },
          },
        }),
      });
      await RemoteAssetCache.instance.debugConfigure(cacheDir: tmp);

      await RemoteAssetCache.instance.debugRestorePersistedManifest();

      expect(
        RemoteAssetCache.instance.entry(
          RemoteAssetKind.accessories,
          'pirate_hat',
        ),
        isNotNull,
      );
    });
  });
}
