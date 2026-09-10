/// Selects from server probability mass without filling gaps or normalizing.
/// A null result is a neutral decorative tile, never an invented prize.
String? sampleServerProbability(
  Object? raw,
  double roll, {
  bool requireComplete = true,
}) {
  if (raw is! Map || raw.isEmpty || !roll.isFinite || roll < 0 || roll >= 1) {
    return null;
  }
  var total = 0.0;
  for (final entry in raw.entries) {
    final value = entry.value;
    if (entry.key is! String ||
        (entry.key as String).isEmpty ||
        value is! num ||
        !value.isFinite ||
        value < 0 ||
        value > 1) {
      return null;
    }
    total += value.toDouble();
  }
  if (total > 1 + 1e-6 || (requireComplete && (total - 1).abs() > 1e-6)) {
    return null;
  }
  var cumulative = 0.0;
  for (final entry in raw.entries) {
    cumulative += (entry.value as num).toDouble();
    if (roll < cumulative) return entry.key as String;
  }
  return null;
}

/// Builds conditional item probabilities without losing omitted list mass.
Map<String, double>? serverItemProbabilities(Object? raw, String idKey) {
  if (raw is! List) return null;
  final result = <String, double>{};
  var total = 0.0;
  for (final row in raw) {
    if (row is! Map) return null;
    final id = row[idKey], probability = row['p'];
    if (id is! String ||
        id.isEmpty ||
        result.containsKey(id) ||
        probability is! num ||
        !probability.isFinite ||
        probability < 0 ||
        probability > 1) {
      return null;
    }
    result[id] = probability.toDouble();
    total += probability.toDouble();
  }
  return total <= 1 + 1e-6 ? result : null;
}
