class StepSampleData {
  final DateTime periodStart;
  final DateTime periodEnd;
  final int steps;

  const StepSampleData({
    required this.periodStart,
    required this.periodEnd,
    required this.steps,
  });

  Map<String, dynamic> toJson() => {
        'periodStart': periodStart.toIso8601String(),
        'periodEnd': periodEnd.toIso8601String(),
        'steps': steps,
      };
}
