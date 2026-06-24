import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/app_version_gate.dart';

void main() {
  group('compareVersions', () {
    test('orders by numeric segments', () {
      expect(compareVersions('1.4.0', '1.4.1'), -1);
      expect(compareVersions('1.4.1', '1.4.0'), 1);
      expect(compareVersions('1.4.0', '1.4.0'), 0);
    });

    test('treats missing trailing segments as zero', () {
      expect(compareVersions('1.4', '1.4.0'), 0);
      expect(compareVersions('1.4.1', '1.4'), 1);
    });

    test('compares numerically, not lexically', () {
      expect(compareVersions('1.4.10', '1.4.9'), 1);
      expect(compareVersions('1.10.0', '1.9.0'), 1);
    });

    test('strips build/pre-release suffixes', () {
      expect(compareVersions('1.4.2+45', '1.4.2'), 0);
      expect(compareVersions('1.4.2-beta.1', '1.4.2'), 0);
    });

    test('returns null when either side is unparseable', () {
      expect(compareVersions('unknown', '1.4.0'), isNull);
      expect(compareVersions('1.4.0', ''), isNull);
    });
  });

  group('VersionPolicy.fromJson', () {
    test('reads all fields when present', () {
      final policy = VersionPolicy.fromJson({
        'minSupportedVersion': '1.4.0',
        'latestVersion': '1.4.2',
        'updateUrl': {'ios': 'https://ios', 'android': 'https://android'},
      });
      expect(policy.minSupportedVersion, '1.4.0');
      expect(policy.latestVersion, '1.4.2');
      expect(policy.iosUrl, 'https://ios');
      expect(policy.androidUrl, 'https://android');
    });

    test('defaults missing/garbled fields safely (old or partial backend)', () {
      final policy = VersionPolicy.fromJson({});
      expect(policy.minSupportedVersion, isNull);
      expect(policy.latestVersion, isNull);
      expect(policy.iosUrl, isNull);
      expect(policy.androidUrl, isNull);
    });

    test('ignores non-string field types without throwing', () {
      final policy = VersionPolicy.fromJson({
        'minSupportedVersion': 140,
        'updateUrl': 'not-a-map',
      });
      expect(policy.minSupportedVersion, isNull);
      expect(policy.iosUrl, isNull);
    });
  });

  group('evaluateVersionGate', () {
    VersionPolicy policy({String? min, String? latest}) => VersionPolicy(
      minSupportedVersion: min,
      latestVersion: latest,
    );

    test('requires an update below the floor', () {
      expect(
        evaluateVersionGate(
          currentVersion: '1.3.6',
          policy: policy(min: '1.4.0', latest: '1.4.2'),
        ),
        VersionGateStatus.updateRequired,
      );
    });

    test('offers an optional update between floor and latest', () {
      expect(
        evaluateVersionGate(
          currentVersion: '1.4.0',
          policy: policy(min: '1.4.0', latest: '1.4.2'),
        ),
        VersionGateStatus.updateAvailable,
      );
    });

    test('is ok on the latest version', () {
      expect(
        evaluateVersionGate(
          currentVersion: '1.4.2',
          policy: policy(min: '1.4.0', latest: '1.4.2'),
        ),
        VersionGateStatus.ok,
      );
    });

    test('treats the floor as inclusive (not blocked)', () {
      final status = evaluateVersionGate(
        currentVersion: '1.4.0',
        policy: policy(min: '1.4.0', latest: '1.4.0'),
      );
      expect(status, VersionGateStatus.ok);
    });

    test('fails open when the current version is unknown', () {
      expect(
        evaluateVersionGate(
          currentVersion: 'unknown',
          policy: policy(min: '1.4.0', latest: '1.4.2'),
        ),
        VersionGateStatus.ok,
      );
    });

    test('fails open when the policy floor is unset/garbled', () {
      expect(
        evaluateVersionGate(
          currentVersion: '1.0.0',
          policy: policy(min: null, latest: null),
        ),
        VersionGateStatus.ok,
      );
    });
  });
}
