/// Base scale for the race track in steps.
const int _baseScale = 75000;

/// Increment when the leader exceeds the current scale.
const int _scaleIncrement = 25000;

/// Computes track positions based on step totals against a dynamic scale.
///
/// Scale starts at 100k. If the leader exceeds it, bumps up in 25k increments.
/// Returns (myPosition, theirPosition, scale).
(double myPosition, double theirPosition, int scale) computeRacePositions({
  required int mySteps,
  required int theirSteps,
}) {
  final maxSteps = mySteps > theirSteps ? mySteps : theirSteps;

  // Compute scale: start at 100k, bump in 25k increments if exceeded
  int scale = _baseScale;
  while (maxSteps > scale) {
    scale += _scaleIncrement;
  }

  final myPos = (mySteps / scale).clamp(0.0, 1.0);
  final theirPos = (theirSteps / scale).clamp(0.0, 1.0);
  return (myPos, theirPos, scale);
}
