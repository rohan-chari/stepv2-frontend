import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/services/backend_api_service.dart';

// ---------------------------------------------------------------------------
// CDN-served art: the `remote_assets` capability token and the render-site
// structural guard.
//
// The backend gates remote-only catalog rows behind this token, so a build
// that can't resolve CDN art never sees (or buys) an item it would draw as a
// grey placeholder. The token MUST appear in BOTH branches of the
// clientFeaturesHeader ternary — editing only the ads branch silently disables
// the whole feature on ad-less builds (precedent: team_races, powerups3).
// ---------------------------------------------------------------------------

void main() {
  test('clientFeaturesHeader advertises the remote_assets token', () {
    final tokens = BackendApiService.clientFeaturesHeader.split(',');
    expect(tokens, contains('remote_assets'));
  });

  test('existing feature tokens survive alongside remote_assets', () {
    final tokens = BackendApiService.clientFeaturesHeader.split(',');
    for (final token in const [
      'characters',
      'jammer',
      'spinpowerups',
      'team_races',
      'tournaments',
      'powerups5',
    ]) {
      expect(tokens, contains(token));
    }
  });

  test('remote_assets is in BOTH branches of the header ternary', () {
    final source = File(
      'lib/services/backend_api_service.dart',
    ).readAsStringSync();
    final match = RegExp(
      r"clientFeaturesHeader\s*=\s*_adsSupported\s*\?\s*'([^']*)'\s*:\s*'([^']*)'",
    ).firstMatch(source);

    expect(
      match,
      isNotNull,
      reason: 'the header ternary shape changed — re-check this guard',
    );
    expect(match!.group(1)!.split(','), contains('remote_assets'));
    expect(match.group(2)!.split(','), contains('remote_assets'));
  });

  // CLAUDE.md's "structural guard over source" carve-out (precedent:
  // test/demo_race_network_guard_test.dart). A raw Image.asset on an accessory
  // path bypasses the resolver, so a CDN-only item silently renders the grey
  // CustomPaint placeholder instead of its art — invisible until an item ships.
  test('accessory render sites go through the resolver, not Image.asset', () {
    for (final path in const [
      'lib/widgets/home_course_track.dart',
      'lib/widgets/accessory_thumbnail.dart',
    ]) {
      final source = File(path).readAsStringSync();
      expect(
        RegExp(
          r"""Image\.asset\(\s*'assets/images/(accessories|powerups)/""",
        ).hasMatch(source),
        isFalse,
        reason:
            '$path builds an accessory/powerup Image.asset directly; use '
            'RemoteOrBundledAccessoryImage so CDN-served art resolves',
      );
      expect(
        source.contains('remote_or_bundled_accessory_image.dart'),
        isTrue,
        reason: '$path must import the resolver',
      );
    }
  });
}
