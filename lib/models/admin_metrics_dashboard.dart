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

/// Defensive projection of the additive DAU/engagement section. The section
/// is intentionally separate from the older summary maps: a backend can add
/// or omit this block without changing the legacy dashboard contract.
class AdminDauAction {
  const AdminDauAction({this.users, this.events});

  factory AdminDauAction.from(Object? raw) {
    final map = AdminMetricMap.from(raw);
    return AdminDauAction(
      users: map?.integer('users'),
      events: map?.integer('events'),
    );
  }

  final int? users;
  final int? events;
}

enum AdminDauComparisonStatus { available, gatheringData }

class AdminDauComparison {
  const AdminDauComparison({
    required this.status,
    this.current,
    this.prior,
    this.absoluteChange,
    this.percentChange,
    this.currentStart,
    this.currentEnd,
    this.priorStart,
    this.priorEnd,
    this.actionBasedDau,
    this.averageActionReach,
    this.usersWithAnyAction,
    required this.actions,
  });

  factory AdminDauComparison.from(Object? raw) {
    final map = AdminMetricMap.from(raw);
    final headline = map?.map('actionBasedDau');
    final average = map?.map('averageActionReach');
    final union = map?.map('usersWithAnyAction');
    final actionMap = <String, AdminDauComparison>{};
    final rawActions = map?.map('actions');
    if (rawActions != null) {
      for (final key in const [
        'raceParticipation', 'boxOpen', 'powerupUse', 'dailyRewardClaim',
        'notificationOpen', 'rewardedAd', 'leaderboardView', 'raceCreated',
        'raceCompleted',
      ]) {
        if (rawActions.contains(key)) {
          actionMap[key] = AdminDauComparison.from(rawActions.raw(key));
        }
      }
    }
    final source = headline ?? map;
    return AdminDauComparison(
      status: source?.text('status') == 'available'
          ? AdminDauComparisonStatus.available
          : AdminDauComparisonStatus.gatheringData,
      current: source?.decimal('current'),
      prior: source?.decimal('prior'),
      absoluteChange: source?.decimal('absoluteChange'),
      percentChange: source?.decimal('percentChange'),
      currentStart: source?.text('currentStart'),
      currentEnd: source?.text('currentEnd'),
      priorStart: source?.text('priorStart'),
      priorEnd: source?.text('priorEnd'),
      actionBasedDau: headline == null
          ? null
          : AdminDauComparison.from(map?.raw('actionBasedDau')),
      averageActionReach: average == null
          ? null
          : AdminDauComparison.from(map?.raw('averageActionReach')),
      usersWithAnyAction: union == null
          ? null
          : AdminDauComparison.from(map?.raw('usersWithAnyAction')),
      actions: actionMap,
    );
  }

  final AdminDauComparisonStatus status;
  final double? current;
  final double? prior;
  final double? absoluteChange;
  final double? percentChange;
  final String? currentStart;
  final String? currentEnd;
  final String? priorStart;
  final String? priorEnd;
  final AdminDauComparison? actionBasedDau;
  final AdminDauComparison? averageActionReach;
  final AdminDauComparison? usersWithAnyAction;
  final Map<String, AdminDauComparison> actions;

  bool get hasUsableChange =>
      status == AdminDauComparisonStatus.available &&
      current != null &&
      prior != null &&
      prior != 0 &&
      absoluteChange != null &&
      percentChange != null;
}

class AdminDauDailyRow {
  const AdminDauDailyRow({
    this.date,
    this.actionBasedDau,
    this.averageActionReach,
    this.usersWithAnyAction,
  });

  factory AdminDauDailyRow.from(Object? raw) {
    final map = AdminMetricMap.from(raw);
    return AdminDauDailyRow(
      date: map?.text('date'),
      actionBasedDau: map?.integer('actionBasedDau'),
      averageActionReach: map?.decimal('averageActionReach'),
      usersWithAnyAction: map?.integer('usersWithAnyAction'),
    );
  }

  final String? date;
  final int? actionBasedDau;
  final double? averageActionReach;
  final int? usersWithAnyAction;
}

class AdminDauEngagement {
  const AdminDauEngagement({
    this.asOf,
    this.timeZone,
    this.actionBasedDauUsers,
    this.actionBasedDauStatus,
    this.todayDate,
    required this.actions,
    this.averageActionReach,
    this.usersWithAnyAction,
    required this.comparisons,
    required this.daily,
  });

  factory AdminDauEngagement.from(Object? raw) {
    final map = AdminMetricMap.from(raw);
    final actionBasedDau = map?.map('actionBasedDau');
    final today = map?.map('today');
    final rawActions = today?.map('actions');
    final actions = <String, AdminDauAction>{};
    for (final key in const [
      'raceParticipation',
      'boxOpen',
      'powerupUse',
      'dailyRewardClaim',
      'notificationOpen',
      'rewardedAd',
      'leaderboardView',
      'raceCreated',
      'raceCompleted',
    ]) {
      if (rawActions?.contains(key) ?? false) {
        actions[key] = AdminDauAction.from(rawActions?.raw(key));
      }
    }

    final comparisons = <String, AdminDauComparison>{};
    for (final key in const [
      'dayOverDay',
      'weekOverWeek',
      'monthOverMonth',
      'sixMonthsOverSixMonths',
      'yearOverYear',
    ]) {
      if (map?.map('comparisons')?.contains(key) ?? false) {
        comparisons[key] = AdminDauComparison.from(
          map?.map('comparisons')?.raw(key),
        );
      }
    }

    return AdminDauEngagement(
      asOf: map?.text('asOf'),
      timeZone: map?.text('timeZone'),
      actionBasedDauUsers: actionBasedDau?.integer('users'),
      actionBasedDauStatus: actionBasedDau?.text('status'),
      todayDate: today?.text('date'),
      actions: actions,
      averageActionReach: today?.decimal('averageActionReach'),
      usersWithAnyAction: today?.integer('usersWithAnyAction'),
      comparisons: comparisons,
      daily:
          map
              ?.rows('daily')
              .map(
                (row) => AdminDauDailyRow(
                  date: row.text('date'),
                  actionBasedDau: row.integer('actionBasedDau'),
                  averageActionReach: row.decimal('averageActionReach'),
                  usersWithAnyAction: row.integer('usersWithAnyAction'),
                ),
              )
              .toList() ??
          const <AdminDauDailyRow>[],
    );
  }

  final String? asOf;
  final String? timeZone;
  final int? actionBasedDauUsers;
  final String? actionBasedDauStatus;
  final String? todayDate;
  final Map<String, AdminDauAction> actions;
  final double? averageActionReach;
  final int? usersWithAnyAction;
  final Map<String, AdminDauComparison> comparisons;
  final List<AdminDauDailyRow> daily;
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
    required this.dauEngagement,
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
      dauEngagement: dashboard?.raw('dauEngagement') == null
          ? null
          : AdminDauEngagement.from(dashboard?.raw('dauEngagement')),
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
  final AdminDauEngagement? dauEngagement;
  final AdminMetricMap? virality;
  final AdminMetricMap? revenue;
  final AdminMetricMap? releaseAdoption;
}
