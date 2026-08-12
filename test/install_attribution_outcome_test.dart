import 'dart:convert';

import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:step_tracker/services/activation_analytics_service.dart';
import 'package:step_tracker/services/auth_service.dart';
import 'package:step_tracker/services/backend_api_service.dart';
import 'package:step_tracker/services/install_attribution_service.dart';

/// Part C (spec test-plan item 8b): the install-attribution funnel.
///
/// The iOS clipboard handoff fails silently and we have never known at which
/// stage. Each stage now stashes ONE outcome per install, flushed after
/// sign-in as a name-encoded activation event (a context key unknown to an
/// older backend 400s the whole retained batch — names soft-drop per event).

class _OfflineApi extends BackendApiService {
  @override
  Future<void> sendActivationEvents({
    required String identityToken,
    required List<Map<String, dynamic>> events,
  }) async => throw const ApiException('offline');
}

const _channelName = 'com.steptracker/referral';

/// Installs a fake platform channel; [handler] answers per method name.
void _mockRaw(Object? Function(String method) handler) {
  TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
      .setMockMethodCallHandler(
        const MethodChannel(_channelName),
        (call) async => handler(call.method),
      );
}

Future<List<String>> _queuedNames() async {
  final prefs = await SharedPreferences.getInstance();
  final raw = prefs.getString('activation_events_v1');
  if (raw == null) return [];
  return (jsonDecode(raw) as List)
      .cast<Map>()
      .map((e) => e['name'].toString())
      .toList();
}

Future<InstallAttributionService> _service(
  InstallPlatform platform, {
  Map<String, Object> prefs = const {},
}) async {
  SharedPreferences.setMockInitialValues(prefs);
  final auth = AuthService();
  await auth.restoreSession();
  return InstallAttributionService(
    authService: auth,
    channel: const MethodChannel(_channelName),
    platform: platform,
  );
}

Future<String?> _stashedOutcome() async =>
    (await SharedPreferences.getInstance()).getString(
      InstallAttributionService.keyPendingOutcomeEvent,
    );

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    PackageInfo.setMockInitialValues(
      appName: 'Bara',
      packageName: 'com.rohanchari.steptracker',
      version: '2.1.0',
      buildNumber: '1',
      buildSignature: '',
    );
    SharedPreferences.setMockInitialValues({});
  });

  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel(_channelName), null);
  });

  group('event names', () {
    test('all seven install_attr_* names are allowlisted client-side', () {
      expect(
        ActivationAnalyticsService.allowedEventNames,
        containsAll(<String>[
          'install_attr_deep_link',
          'install_attr_detect_miss',
          'install_attr_read_denied',
          'install_attr_read_no_code',
          'install_attr_code_captured',
          'install_attr_install_referrer',
          'install_attr_error',
        ]),
      );
    });

    test('every outcome maps to a distinct allowlisted name', () {
      final names = InstallAttributionOutcome.values
          .map(InstallAttributionService.eventNameFor)
          .toList();
      expect(names.toSet().length, names.length);
      for (final name in names) {
        expect(ActivationAnalyticsService.allowedEventNames, contains(name));
      }
    });
  });

  group('iOS clipboard funnel', () {
    test('detect miss stashes detect_miss and reads nothing', () async {
      var readCalls = 0;
      _mockRaw((method) {
        if (method == 'clipboardHasProbableUrl') return false;
        readCalls += 1;
        return null;
      });
      final service = await _service(InstallPlatform.ios);

      await service.resolveOnFirstLaunch();

      expect(await _stashedOutcome(), 'install_attr_detect_miss');
      expect(readCalls, 0, reason: 'no read when nothing was detected');
    });

    test('detect hit + nil read is a DENIAL, not a miss', () async {
      _mockRaw((method) {
        if (method == 'clipboardHasProbableUrl') return true;
        return <String, Object?>{'status': 'denied'};
      });
      final service = await _service(InstallPlatform.ios);

      await service.resolveOnFirstLaunch();

      expect(await _stashedOutcome(), 'install_attr_read_denied');
      expect(
        await service.hasUnreadDetectedInvite(),
        isTrue,
        reason: 'the invite step offers the consented paste in this state only',
      );
    });

    test(
      'a legacy bare-string nil answer still classifies as denied',
      () async {
        _mockRaw((method) {
          if (method == 'clipboardHasProbableUrl') return true;
          return null;
        });
        final service = await _service(InstallPlatform.ios);

        await service.resolveOnFirstLaunch();

        expect(await _stashedOutcome(), 'install_attr_read_denied');
      },
    );

    test('a read with no BARA- code is read_no_code, not denied', () async {
      _mockRaw((method) {
        if (method == 'clipboardHasProbableUrl') return true;
        return <String, Object?>{
          'status': 'ok',
          'value': 'https://example.com/hello',
        };
      });
      final service = await _service(InstallPlatform.ios);

      await service.resolveOnFirstLaunch();

      expect(await _stashedOutcome(), 'install_attr_read_no_code');
      expect(await service.hasUnreadDetectedInvite(), isFalse);
    });

    test(
      'a captured code stashes code_captured and sets the pending code',
      () async {
        _mockRaw((method) {
          if (method == 'clipboardHasProbableUrl') return true;
          return <String, Object?>{
            'status': 'ok',
            'value': 'https://steptracker-api.org/r/BARA-7F3K',
          };
        });
        final service = await _service(InstallPlatform.ios);

        await service.resolveOnFirstLaunch();

        expect(await _stashedOutcome(), 'install_attr_code_captured');
        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('auth_pending_referral_code'), 'BARA-7F3K');
      },
    );

    test(
      'combined iOS URL preserves referral and race independently',
      () async {
        _mockRaw((method) {
          if (method == 'clipboardHasProbableUrl') return true;
          return <String, Object?>{
            'status': 'ok',
            'value': 'https://steptracker-api.org/r/raceToken123?ref=BARA-7F3K',
          };
        });
        final service = await _service(InstallPlatform.ios);

        await service.resolveOnFirstLaunch();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('auth_pending_referral_code'), 'BARA-7F3K');
        expect(prefs.getString('auth_pending_share_token'), 'raceToken123');
      },
    );

    test('a channel failure stashes error and never throws', () async {
      _mockRaw((method) => throw PlatformException(code: 'boom'));
      final service = await _service(InstallPlatform.ios);

      await service.resolveOnFirstLaunch();

      expect(await _stashedOutcome(), 'install_attr_error');
    });

    test(
      'the deferred paste read returns a code and clears the state',
      () async {
        _mockRaw((method) {
          if (method == 'clipboardHasProbableUrl') return true;
          return <String, Object?>{'status': 'denied'};
        });
        final service = await _service(InstallPlatform.ios);
        await service.resolveOnFirstLaunch();
        expect(await service.hasUnreadDetectedInvite(), isTrue);

        _mockRaw(
          (method) => <String, Object?>{'status': 'ok', 'value': 'BARA-7F3K'},
        );
        expect(await service.readInviteCodeFromPasteboard(), 'BARA-7F3K');
        expect(await service.hasUnreadDetectedInvite(), isFalse);
      },
    );

    test('a second denial on the deferred read returns null', () async {
      _mockRaw((method) => <String, Object?>{'status': 'denied'});
      final service = await _service(InstallPlatform.ios);
      expect(await service.readInviteCodeFromPasteboard(), isNull);
    });
  });

  group('Android + deep link', () {
    test(
      'an install referrer carrying a code stashes install_referrer',
      () async {
        _mockRaw((method) => 'referrer=BARA-7F3K&utm_source=share');
        final service = await _service(InstallPlatform.android);

        await service.resolveOnFirstLaunch();

        expect(await _stashedOutcome(), 'install_attr_install_referrer');
      },
    );

    test(
      'decoded Play payload preserves referral and race independently',
      () async {
        _mockRaw((method) => 'raceToken=raceToken123&ref=BARA-7F3K');
        final service = await _service(InstallPlatform.android);

        await service.resolveOnFirstLaunch();

        final prefs = await SharedPreferences.getInstance();
        expect(prefs.getString('auth_pending_referral_code'), 'BARA-7F3K');
        expect(prefs.getString('auth_pending_share_token'), 'raceToken123');
      },
    );

    test('an organic referrer stashes read_no_code', () async {
      _mockRaw((method) => 'utm_source=google-play&utm_medium=organic');
      final service = await _service(InstallPlatform.android);

      await service.resolveOnFirstLaunch();

      expect(await _stashedOutcome(), 'install_attr_read_no_code');
    });

    test('no referrer at all stashes detect_miss', () async {
      _mockRaw((method) => null);
      final service = await _service(InstallPlatform.android);

      await service.resolveOnFirstLaunch();

      expect(await _stashedOutcome(), 'install_attr_detect_miss');
    });

    test('a code already captured by a deep link stashes deep_link', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      await auth.restoreSession();
      await auth.setPendingReferralCode('BARA-7F3K');
      var platformCalls = 0;
      _mockRaw((method) {
        platformCalls += 1;
        return null;
      });
      final service = InstallAttributionService(
        authService: auth,
        channel: const MethodChannel(_channelName),
        platform: InstallPlatform.ios,
      );

      await service.resolveOnFirstLaunch();

      expect(await _stashedOutcome(), 'install_attr_deep_link');
      expect(
        platformCalls,
        0,
        reason: 'never touch the clipboard in this case',
      );
    });
  });

  group('stash then flush', () {
    test('the outcome flushes exactly once per install', () async {
      _mockRaw((method) => false);
      final service = await _service(InstallPlatform.ios);
      await service.resolveOnFirstLaunch();

      final analytics = ActivationAnalyticsService(
        backendApiService: _OfflineApi(),
      );
      await service.flushStashedOutcome(analytics);
      expect(await _queuedNames(), ['install_attr_detect_miss']);

      // A second flush (next cold start) must not re-emit.
      await service.flushStashedOutcome(analytics);
      expect(await _queuedNames(), ['install_attr_detect_miss']);
    });

    test('resolveOnFirstLaunch stays at-most-once per install', () async {
      var detectCalls = 0;
      _mockRaw((method) {
        if (method == 'clipboardHasProbableUrl') detectCalls += 1;
        return false;
      });
      final service = await _service(InstallPlatform.ios);

      await service.resolveOnFirstLaunch();
      await service.resolveOnFirstLaunch();

      expect(detectCalls, 1);
    });

    test('flushing with nothing stashed is a no-op', () async {
      SharedPreferences.setMockInitialValues({});
      final auth = AuthService();
      final service = InstallAttributionService(authService: auth);
      await service.flushStashedOutcome(
        ActivationAnalyticsService(backendApiService: _OfflineApi()),
      );
      expect(await _queuedNames(), isEmpty);
    });
  });
}
