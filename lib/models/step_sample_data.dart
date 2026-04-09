class StepSampleData {
  final DateTime periodStart;
  final DateTime periodEnd;
  final int steps;
  final String? sourceName;
  final String? sourceId;
  final String? sourceDeviceId;
  final String? deviceModel;
  final String? recordingMethod;
  final Map<String, dynamic>? metadata;

  const StepSampleData({
    required this.periodStart,
    required this.periodEnd,
    required this.steps,
    this.sourceName,
    this.sourceId,
    this.sourceDeviceId,
    this.deviceModel,
    this.recordingMethod,
    this.metadata,
  });

  Map<String, dynamic> toJson() => {
    'periodStart': periodStart.toIso8601String(),
    'periodEnd': periodEnd.toIso8601String(),
    'steps': steps,
    if (sourceName != null) 'sourceName': sourceName,
    if (sourceId != null) 'sourceId': sourceId,
    if (sourceDeviceId != null) 'sourceDeviceId': sourceDeviceId,
    if (deviceModel != null) 'deviceModel': deviceModel,
    if (recordingMethod != null) 'recordingMethod': recordingMethod,
    if (metadata != null) 'metadata': _jsonSafeMap(metadata!),
  };

  static Map<String, dynamic> _jsonSafeMap(Map<String, dynamic> value) {
    return value.map(
      (key, nestedValue) => MapEntry(key, _jsonSafeValue(nestedValue)),
    );
  }

  static dynamic _jsonSafeValue(dynamic value) {
    if (value == null || value is num || value is bool || value is String) {
      return value;
    }

    if (value is DateTime) {
      return value.toIso8601String();
    }

    if (value is Enum) {
      return value.name;
    }

    if (value is Map) {
      return value.map(
        (key, nestedValue) =>
            MapEntry(key.toString(), _jsonSafeValue(nestedValue)),
      );
    }

    if (value is Iterable) {
      return value.map(_jsonSafeValue).toList();
    }

    return value.toString();
  }
}
