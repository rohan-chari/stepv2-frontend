import 'package:flutter_test/flutter_test.dart';
import 'package:step_tracker/utils/race_positions.dart';

void main() {
  test('both zero: both at 0.0, scale stays at 75k', () {
    final (my, their, scale) =
        computeRacePositions(mySteps: 0, theirSteps: 0);
    expect(my, 0.0);
    expect(their, 0.0);
    expect(scale, 75000);
  });

  test('50k vs 30k: positions relative to 75k scale', () {
    final (my, their, scale) =
        computeRacePositions(mySteps: 50000, theirSteps: 30000);
    expect(scale, 75000);
    expect(my, closeTo(50000 / 75000, 0.001));
    expect(their, closeTo(30000 / 75000, 0.001));
  });

  test('scale bumps when leader exceeds 75k', () {
    final (my, their, scale) =
        computeRacePositions(mySteps: 80000, theirSteps: 60000);
    expect(scale, 100000);
    expect(my, closeTo(80000 / 100000, 0.001));
    expect(their, closeTo(60000 / 100000, 0.001));
  });

  test('scale bumps multiple times for very high steps', () {
    final (my, their, scale) =
        computeRacePositions(mySteps: 200000, theirSteps: 150000);
    expect(scale, 200000);
    expect(my, closeTo(1.0, 0.001));
    expect(their, closeTo(0.75, 0.001));
  });

  test('tied steps: same position', () {
    final (my, their, scale) =
        computeRacePositions(mySteps: 40000, theirSteps: 40000);
    expect(my, their);
    expect(scale, 75000);
  });

  test('one zero, one non-zero', () {
    final (my, their, scale) =
        computeRacePositions(mySteps: 0, theirSteps: 60000);
    expect(my, 0.0);
    expect(their, closeTo(60000 / 75000, 0.001));
    expect(scale, 75000);
  });

  test('exactly at scale boundary', () {
    final (my, their, scale) =
        computeRacePositions(mySteps: 75000, theirSteps: 50000);
    expect(scale, 75000);
    expect(my, 1.0);
    expect(their, closeTo(50000 / 75000, 0.001));
  });

  test('just over scale boundary bumps up', () {
    final (my, their, scale) =
        computeRacePositions(mySteps: 75001, theirSteps: 50000);
    expect(scale, 100000);
    expect(my, closeTo(75001 / 100000, 0.001));
  });
}
