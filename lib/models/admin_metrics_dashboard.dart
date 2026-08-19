/// Defensive client projection of the additive admin metrics v2 envelope.
///
/// The backend and app roll independently. This file deliberately accepts
/// `Object?` at every boundary and copies only string-keyed maps; a malformed,
/// missing, null, older, or newer leaf therefore becomes null/unavailable and
/// can never throw while an operator is opening the dashboard.
enum AdminDashboardStatus { available, disabled, unavailable }

enum AdminSourceStatus {
  available,
  collecting,
  disabled,
  notConfigured,
  stale,
  error,
  unavailable,
}

enum AdminCoverageStatus { collecting, mature, unavailable }

class AdminRatio {
  const AdminRatio({this.numerator, this.denominator, this.percent});

  final int? numerator;
  final int? denominator;
  final double? percent;
}

class AdminAverage {
  const AdminAverage({this.numerator, this.denominator, this.average});

  final int? numerator;
  final int? denominator;
  final double? average;
}

class AdminMetricMap {
  const AdminMetricMap._(this._value);

  final Map<String, Object?> _value;

  static AdminMetricMap? from(Object? raw) {
    if (raw is! Map) return null;
    final copy = <String, Object?>{};
    for (final entry in raw.entries) {
      final key = entry.key;
      if (key is String) copy[key] = entry.value;
    }
    return AdminMetricMap._(copy);
  }

  bool contains(String key) => _value.containsKey(key);

  Object? raw(String key) => _value[key];

  AdminMetricMap? map(String key) => from(_value[key]);

  String? text(String key) {
    final value = _value[key];
    return value is String && value.isNotEmpty ? value : null;
  }

  int? integer(String key) {
    final value = _value[key];
    if (value is int) return value;
    if (value is num && value.isFinite && value == value.truncateToDouble()) {
      return value.toInt();
    }
    return null;
  }

  double? decimal(String key) {
    final value = _value[key];
    return value is num && value.isFinite ? value.toDouble() : null;
  }

  bool? boolean(String key) {
    final value = _value[key];
    return value is bool ? value : null;
  }

  List<AdminMetricMap> rows(String key) {
    final value = _value[key];
    if (value is! List) return const [];
    final rows = <AdminMetricMap>[];
    for (final row in value) {
      final parsed = from(row);
      if (parsed != null) rows.add(parsed);
    }
    return rows;
  }

  AdminRatio ratio(String key) {
    final value = map(key);
    return AdminRatio(
      numerator: value?.integer('numerator'),
      denominator: value?.integer('denominator'),
      percent: value?.decimal('percent'),
    );
  }

  AdminAverage average(String key) {
    final value = map(key);
    return AdminAverage(
      numerator: value?.integer('numerator'),
      denominator: value?.integer('denominator'),
      average: value?.decimal('average'),
    );
  }
}

class AdminDashboardWindow {
  const AdminDashboardWindow({this.days, this.start, this.end, this.timeZone});

  factory AdminDashboardWindow.from(Object? raw) {
    final map = AdminMetricMap.from(raw);
    return AdminDashboardWindow(
      days: map?.integer('days'),
      start: map?.text('start'),
      end: map?.text('end'),
      timeZone: map?.text('timeZone'),
    );
  }

  final int? days;
  final String? start;
  final String? end;
  final String? timeZone;
}

class AdminSource {
  const AdminSource({required this.status, this.asOf});

  factory AdminSource.from(Object? raw) {
    final map = AdminMetricMap.from(raw);
    final status = switch (map?.text('status')) {
      'available' => AdminSourceStatus.available,
      'collecting' => AdminSourceStatus.collecting,
      'disabled' => AdminSourceStatus.disabled,
      'not_configured' => AdminSourceStatus.notConfigured,
      'stale' => AdminSourceStatus.stale,
      'error' => AdminSourceStatus.error,
      _ => AdminSourceStatus.unavailable,
    };
    return AdminSource(status: status, asOf: map?.text('asOf'));
  }

  final AdminSourceStatus status;
  final String? asOf;
}

class AdminSources {
  const AdminSources({
    required this.productDb,
    required this.foregroundActivity,
    required this.appStoreConnect,
    required this.admob,
  });

  factory AdminSources.from(Object? raw) {
    final map = AdminMetricMap.from(raw);
    return AdminSources(
      productDb: AdminSource.from(map?.raw('productDb')),
      foregroundActivity: AdminSource.from(map?.raw('foregroundActivity')),
      appStoreConnect: AdminSource.from(map?.raw('appStoreConnect')),
      admob: AdminSource.from(map?.raw('admob')),
    );
  }

  final AdminSource productDb;
  final AdminSource foregroundActivity;
  final AdminSource appStoreConnect;
  final AdminSource admob;
}

class AdminMetricCoverage {
  const AdminMetricCoverage({
    required this.status,
    this.collectingSince,
    this.eligible,
    this.totalPopulation,
    this.eligibilityPercent,
  });

  factory AdminMetricCoverage.from(Object? raw) {
    final map = AdminMetricMap.from(raw);
    final status = switch (map?.text('status')) {
      'collecting' => AdminCoverageStatus.collecting,
      'mature' => AdminCoverageStatus.mature,
      'unavailable' => AdminCoverageStatus.unavailable,
      _ => AdminCoverageStatus.unavailable,
    };
    return AdminMetricCoverage(
      status: status,
      collectingSince: map?.text('collectingSince'),
      eligible: map?.integer('eligible'),
      totalPopulation: map?.integer('totalPopulation'),
      eligibilityPercent: map?.decimal('eligibilityPercent'),
    );
  }

  final AdminCoverageStatus status;
  final String? collectingSince;
  final int? eligible;
  final int? totalPopulation;
  final double? eligibilityPercent;
}

class AdminCoverage {
  const AdminCoverage(this._metrics);

  factory AdminCoverage.from(Object? raw) {
    final coverage = AdminMetricMap.from(raw);
    final metrics = coverage?.map('metricCoverage');
    final parsed = <String, AdminMetricCoverage>{};
    if (metrics != null) {
      for (final key in const [
        'observedForegroundDau',
        'observedForegroundWau',
        'observedForegroundMau',
        'retentionD1',
        'retentionD7',
        'retentionD30',
        'healthWithin24h',
        'leaderboardViews',
        'notificationOpen',
        'boxOpen',
        'firstRacePowerUse',
      ]) {
        if (metrics.contains(key)) {
          parsed[key] = AdminMetricCoverage.from(metrics.raw(key));
        }
      }
    }
    return AdminCoverage(parsed);
  }

  final Map<String, AdminMetricCoverage> _metrics;

  AdminMetricCoverage? metric(String key) => _metrics[key];
}

class AdminMetricsEnvelope {
  const AdminMetricsEnvelope._({
    required this.present,
    required this.schemaVersion,
    required this.status,
    required this.window,
    required this.sources,
    required this.coverage,
    required this.summary,
    required this.userGrowth,
    required this.inviteFunnel,
    required this.onboardingFunnel,
    required this.activation,
    required this.retention,
    required this.raceEngagement,
    required this.virality,
    required this.revenue,
    required this.releaseAdoption,
  });

  factory AdminMetricsEnvelope.fromStats(Map<String, dynamic>? stats) {
    final dashboard = AdminMetricMap.from(stats?['metricsDashboard']);
    final present = dashboard != null;
    final rawStatus = dashboard?.text('status');
    final status = switch (rawStatus) {
      'available' => AdminDashboardStatus.available,
      'disabled' => AdminDashboardStatus.disabled,
      _ => AdminDashboardStatus.unavailable,
    };
    return AdminMetricsEnvelope._(
      present: present,
      schemaVersion: dashboard?.integer('schemaVersion'),
      status: status,
      window: AdminDashboardWindow.from(dashboard?.raw('window')),
      sources: AdminSources.from(dashboard?.raw('sources')),
      coverage: AdminCoverage.from(dashboard?.raw('coverage')),
      summary: dashboard?.map('summary'),
      userGrowth: dashboard?.map('userGrowth'),
      inviteFunnel: dashboard?.map('inviteFunnel'),
      onboardingFunnel: dashboard?.map('onboardingFunnel'),
      activation: dashboard?.map('activation'),
      retention: dashboard?.map('retention'),
      raceEngagement: dashboard?.map('raceEngagement'),
      virality: dashboard?.map('virality'),
      revenue: dashboard?.map('revenue'),
      releaseAdoption: dashboard?.map('releaseAdoption'),
    );
  }

  final bool present;
  final int? schemaVersion;
  final AdminDashboardStatus status;
  final AdminDashboardWindow window;
  final AdminSources sources;
  final AdminCoverage coverage;
  final AdminMetricMap? summary;
  final AdminMetricMap? userGrowth;
  final AdminMetricMap? inviteFunnel;
  final AdminMetricMap? onboardingFunnel;
  final AdminMetricMap? activation;
  final AdminMetricMap? retention;
  final AdminMetricMap? raceEngagement;
  final AdminMetricMap? virality;
  final AdminMetricMap? revenue;
  final AdminMetricMap? releaseAdoption;
}
