import 'dart:io';

import 'package:flutter_test/flutter_test.dart';

void main() {
  test('all shipped identity surfaces use the shared dossier launcher', () {
    const files = <String>[
      'lib/screens/tabs/friends_tab.dart',
      'lib/screens/tabs/leaderboard_tab.dart',
      'lib/screens/tabs/ranked_tab.dart',
      'lib/screens/race_detail_screen.dart',
    ];
    final sources = {
      for (final path in files) path: File(path).readAsStringSync(),
    };
    for (final source in sources.values) {
      expect(source, contains('showPublicProfileSheet'));
      expect(source, isNot(contains('PublicProfileScreen(')));
      expect(source, isNot(contains('showFriendRequestSheet(')));
    }
    expect(
      sources.values
          .map((source) => 'showPublicProfileSheet'.allMatches(source).length)
          .fold<int>(0, (sum, count) => sum + count),
      greaterThanOrEqualTo(4),
    );
    expect(
      File('lib/widgets/goal_track.dart').readAsStringSync(),
      allOf(contains('onRunnerProfileTap'), contains('userId')),
    );
    expect(
      File('lib/widgets/race_podium.dart').readAsStringSync(),
      allOf(contains('onProfileTap'), contains('profilePhotoUrl')),
    );
    expect(
      File('lib/widgets/team_lobby_board.dart').readAsStringSync(),
      contains('onMemberProfileTap'),
    );
    expect(
      File('lib/widgets/home_course_track.dart').readAsStringSync(),
      contains('onRunnerProfileTap'),
    );
    expect(
      sources['lib/screens/race_detail_screen.dart'],
      contains('onRunnerProfileTap'),
    );
  });
}
