import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/race_participant_display.dart';

void main() {
  test('sortRaceParticipantsForDisplay puts finishers in finish order', () {
    final sorted = sortRaceParticipantsForDisplay([
      {
        'displayName': 'Shefali G',
        'totalSteps': 111267,
        'finishedAt': '2026-04-07T10:26:02.626Z',
      },
      {
        'displayName': 'Sugaroro',
        'totalSteps': 103127,
        'finishedAt': '2026-04-07T00:51:45.912Z',
      },
      {'displayName': 'emersonz', 'totalSteps': 73037, 'finishedAt': null},
    ]);

    expect(sorted.map((p) => p['displayName']), [
      'Sugaroro',
      'Shefali G',
      'emersonz',
    ]);
  });

  test(
    'sortRaceParticipantsForDisplay keeps stealthed runners pinned first',
    () {
      final sorted = sortRaceParticipantsForDisplay([
        {
          'displayName': 'Sugaroro',
          'totalSteps': 103127,
          'finishedAt': '2026-04-07T00:51:45.912Z',
        },
        {
          'displayName': '???',
          'totalSteps': null,
          'finishedAt': null,
          'stealthed': true,
        },
        {'displayName': 'Rohit', 'totalSteps': 54250, 'finishedAt': null},
      ]);

      expect(sorted.map((p) => p['displayName']), ['???', 'Sugaroro', 'Rohit']);
    },
  );

  test('sortRaceParticipantsForDisplay sorts unfinished runners by steps', () {
    final sorted = sortRaceParticipantsForDisplay([
      {'displayName': 'Rohit', 'totalSteps': 54250, 'finishedAt': null},
      {'displayName': 'Nattybo7', 'totalSteps': 22412, 'finishedAt': null},
      {'displayName': 'emersonz', 'totalSteps': 73037, 'finishedAt': null},
    ]);

    expect(sorted.map((p) => p['displayName']), [
      'emersonz',
      'Rohit',
      'Nattybo7',
    ]);
  });
}
