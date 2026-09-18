import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

String read(String path) => File(path).readAsStringSync();

void main() {
  test('frontend release documentation has one live source of truth', () {
    final readme = read('README.md');
    final release = read('RELEASE.md');
    final deployment = read('DEPLOYMENT.md');
    final agents = read('AGENTS.md');
    final claude = read('CLAUDE.md');

    expect(readme, contains('flutter build ipa --release'));
    expect(readme, contains('flutter build appbundle --release'));
    expect(release, contains('README.md'));
    expect(deployment, contains('RELEASE.md'));
    expect(agents, contains('README.md'));
    expect(agents, contains('RELEASE.md'));
    expect(claude, contains('AGENTS.md'));
    expect(claude, contains('RELEASE.md'));

    expect(
      release,
      isNot(contains('pm2 restart')),
      reason: 'frontend release docs must not own backend PM2 procedure',
    );
  });

  test('frontend archive is explicitly non-authoritative', () {
    final archive = read('docs/archive/README.md');
    expect(archive.toLowerCase(), contains('historical'));
    expect(archive, contains('Do **not** use archived files as current'));
  });
}
