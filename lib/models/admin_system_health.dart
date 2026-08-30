/// Defensive projection of the additive Admin system-health endpoint.
///
/// The backend and app deploy independently. A response that does not satisfy
/// the locked v1 contract is rejected as a whole and rendered as a contained
/// malformed state; additive fields are ignored.
library;

const int _maxSafeInteger = 9007199254740991;
const int _maxPoolGauge = 1000000;
const double _maxDurationMs = 86400000;

enum AdminSystemHealthStatus { available, partial, unavailable }

enum AdminSystemHealthOverall { healthy, pressure, degraded, unknown }

enum AdminSystemHealthHistoryStatus { available, partial, unavailable }

enum AdminSystemHealthProcessStatus { healthy, pressure, degraded, unknown }

enum AdminSystemHealthCollectionStatus { complete, collecting }

enum AdminSystemHealthFetchStatus { available, routeUnavailable, malformed }

class AdminSystemHealthFetchResult {
  const AdminSystemHealthFetchResult._(this.status, this.health);

  factory AdminSystemHealthFetchResult.available(
    Object? value, {
    DateTime? now,
  }) {
    final health = value is AdminSystemHealthEnvelope
        ? value
        : AdminSystemHealthEnvelope.tryParse(value, now: now);
    return health == null
        ? const AdminSystemHealthFetchResult.malformed()
        : AdminSystemHealthFetchResult._(
            AdminSystemHealthFetchStatus.available,
            health,
          );
  }

  const AdminSystemHealthFetchResult.routeUnavailable()
    : this._(AdminSystemHealthFetchStatus.routeUnavailable, null);

  const AdminSystemHealthFetchResult.malformed()
    : this._(AdminSystemHealthFetchStatus.malformed, null);

  final AdminSystemHealthFetchStatus status;
  final AdminSystemHealthEnvelope? health;
}

class AdminSystemHealthEnvelope {
  const AdminSystemHealthEnvelope._({
    required this.status,
    required this.overall,
    required this.historyStatus,
    required this.generatedAt,
    required this.windowMinutes,
    required this.windowCoverageMinutes,
    required this.expectedProcesses,
    required this.freshProcesses,
    required this.missingProcesses,
    required this.processes,
    required this.stepIngestion,
    required this.failureWindows,
  });

  static AdminSystemHealthEnvelope? tryParse(Object? value, {DateTime? now}) {
    try {
      final map = _objectMap(value);
      if (map == null || map['schema'] != 'admin-system-health-v1') return null;
      final status = _status(map['status']);
      final overall = _overall(map['overall']);
      final historyStatus = _historyStatus(map['historyStatus']);
      final generatedAt = _date(map['generatedAt']);
      final windowMinutes = _integer(map['windowMinutes'], max: 10080);
      final coverage = _integer(map['windowCoverageMinutes'], max: 60);
      final expected = _integer(map['expectedProcesses'], max: 4);
      final fresh = _integer(map['freshProcesses'], max: 4);
      if (status == null ||
          overall == null ||
          historyStatus == null ||
          generatedAt == null ||
          windowMinutes != 60 ||
          coverage == null ||
          expected != 4 ||
          fresh == null) {
        return null;
      }
      if (now != null &&
          generatedAt.isAfter(now.toUtc().add(const Duration(minutes: 5)))) {
        return null;
      }

      final missingRaw = _objectList(map['missingProcesses']);
      final processRaw = _objectList(map['processes']);
      if (missingRaw == null || processRaw == null) return null;
      final missing = <AdminSystemHealthMissingProcess>[];
      final missingIdentities = <String>{};
      for (final row in missingRaw) {
        final parsed = AdminSystemHealthMissingProcess._parse(row);
        if (parsed == null || !missingIdentities.add(parsed.identity)) {
          return null;
        }
        missing.add(parsed);
      }
      final processes = <AdminSystemHealthProcess>[];
      final processIdentities = <String>{};
      for (final row in processRaw) {
        final parsed = AdminSystemHealthProcess._parse(row, now: now);
        if (parsed == null || !processIdentities.add(parsed.identity)) {
          return null;
        }
        processes.add(parsed);
      }
      if (processes.length != fresh ||
          missing.length != expected! - fresh ||
          processIdentities.any(missingIdentities.contains)) {
        return null;
      }
      final derivedCoverage = processes.isEmpty
          ? 0
          : processes
                .map((process) => process.coverageMinutes)
                .reduce((left, right) => left < right ? left : right);
      if (coverage != derivedCoverage) return null;
      if (status == AdminSystemHealthStatus.available &&
          (fresh != 4 || missing.isNotEmpty)) {
        return null;
      }
      if (status == AdminSystemHealthStatus.partial &&
          (fresh == 0 || fresh == 4)) {
        return null;
      }
      if (status == AdminSystemHealthStatus.unavailable && fresh != 0) {
        return null;
      }
      if (status == AdminSystemHealthStatus.partial &&
          overall != AdminSystemHealthOverall.degraded) {
        return null;
      }
      if (status == AdminSystemHealthStatus.unavailable &&
          overall != AdminSystemHealthOverall.unknown) {
        return null;
      }

      final stepRaw = map['stepIngestion'];
      final step = stepRaw == null
          ? null
          : AdminSystemHealthStepIngestion._parse(stepRaw);
      if (stepRaw != null && step == null) return null;
      final contributingHttpProcesses = processes
          .where((process) => process.role == 'http')
          .length;
      if ((contributingHttpProcesses == 0) != (step == null) ||
          (step != null &&
              step.contributingHttpProcesses != contributingHttpProcesses)) {
        return null;
      }

      final windowsRaw = map['failureWindows'];
      List<AdminSystemHealthFailureWindow>? windows;
      if (windowsRaw != null) {
        final rows = _objectList(windowsRaw);
        if (rows == null || rows.length != 3) return null;
        const names = ['60m', '24h', '7d'];
        const minutes = [60, 1440, 10080];
        windows = <AdminSystemHealthFailureWindow>[];
        for (var i = 0; i < rows.length; i++) {
          final parsed = AdminSystemHealthFailureWindow._parse(rows[i]);
          if (parsed == null ||
              parsed.window != names[i] ||
              parsed.windowMinutes != minutes[i]) {
            return null;
          }
          windows.add(parsed);
        }
      }
      if (historyStatus == AdminSystemHealthHistoryStatus.unavailable &&
          windows != null) {
        return null;
      }
      if (historyStatus != AdminSystemHealthHistoryStatus.unavailable &&
          windows == null) {
        return null;
      }

      return AdminSystemHealthEnvelope._(
        status: status,
        overall: overall,
        historyStatus: historyStatus,
        generatedAt: generatedAt,
        windowMinutes: windowMinutes!,
        windowCoverageMinutes: coverage,
        expectedProcesses: expected,
        freshProcesses: fresh,
        missingProcesses: List.unmodifiable(missing),
        processes: List.unmodifiable(processes),
        stepIngestion: step,
        failureWindows: List.unmodifiable(windows ?? const []),
      );
    } catch (_) {
      return null;
    }
  }

  final AdminSystemHealthStatus status;
  final AdminSystemHealthOverall overall;
  final AdminSystemHealthHistoryStatus historyStatus;
  final DateTime generatedAt;
  final int windowMinutes;
  final int windowCoverageMinutes;
  final int expectedProcesses;
  final int freshProcesses;
  final List<AdminSystemHealthMissingProcess> missingProcesses;
  final List<AdminSystemHealthProcess> processes;
  final AdminSystemHealthStepIngestion? stepIngestion;
  final List<AdminSystemHealthFailureWindow> failureWindows;

  AdminSystemHealthProcess? process(String role, String instance) {
    for (final process in processes) {
      if (process.role == role && process.instance == instance) return process;
    }
    return null;
  }
}

class AdminSystemHealthMissingProcess {
  const AdminSystemHealthMissingProcess._({
    required this.role,
    required this.instance,
    required this.reason,
  });

  static AdminSystemHealthMissingProcess? _parse(Object? value) {
    final map = _objectMap(value);
    if (map == null) return null;
    final role = _identityRole(map['role'], map['instance']);
    final instance = map['instance'];
    final reason = map['reason'];
    if (role == null ||
        instance is! String ||
        !const {
          'missing',
          'stale',
          'malformed',
          'unavailable',
        }.contains(reason)) {
      return null;
    }
    return AdminSystemHealthMissingProcess._(
      role: role,
      instance: instance,
      reason: reason as String,
    );
  }

  final String role;
  final String instance;
  final String reason;
  String get identity => '$role:$instance';
}

class AdminSystemHealthProcess {
  const AdminSystemHealthProcess._({
    required this.role,
    required this.instance,
    required this.status,
    required this.capturedAt,
    required this.coverageMinutes,
    required this.oldestBucketAt,
    required this.newestBucketAt,
    required this.pool,
    required this.last60m,
    required this.resources,
  });

  static AdminSystemHealthProcess? _parse(Object? value, {DateTime? now}) {
    final map = _objectMap(value);
    if (map == null) return null;
    final role = _identityRole(map['role'], map['instance']);
    final instance = map['instance'];
    final status = _processStatus(map['status']);
    final capturedAt = _date(map['capturedAt']);
    final coverage = _integer(map['coverageMinutes'], max: 60);
    final oldestRaw = map['oldestBucketAt'];
    final newestRaw = map['newestBucketAt'];
    final oldest = oldestRaw == null ? null : _date(oldestRaw);
    final newest = newestRaw == null ? null : _date(newestRaw);
    final pool = AdminSystemHealthPool._parse(map['pool']);
    final interval = AdminSystemHealthInterval._parse(map['last60m']);
    final resources = AdminSystemHealthResources._parse(map['process']);
    if (role == null ||
        instance is! String ||
        status == null ||
        capturedAt == null ||
        coverage == null ||
        pool == null ||
        interval == null ||
        resources == null) {
      return null;
    }
    if (coverage == 0) {
      if (oldestRaw != null || newestRaw != null) return null;
    } else if (oldest == null || newest == null || oldest.isAfter(newest)) {
      return null;
    }
    if (now != null &&
        capturedAt.isAfter(now.toUtc().add(const Duration(minutes: 5)))) {
      return null;
    }
    return AdminSystemHealthProcess._(
      role: role,
      instance: instance,
      status: status,
      capturedAt: capturedAt,
      coverageMinutes: coverage,
      oldestBucketAt: oldest,
      newestBucketAt: newest,
      pool: pool,
      last60m: interval,
      resources: resources,
    );
  }

  final String role;
  final String instance;
  final AdminSystemHealthProcessStatus status;
  final DateTime capturedAt;
  final int coverageMinutes;
  final DateTime? oldestBucketAt;
  final DateTime? newestBucketAt;
  final AdminSystemHealthPool pool;
  final AdminSystemHealthInterval last60m;
  final AdminSystemHealthResources resources;
  String get identity => '$role:$instance';
}

class AdminSystemHealthPool {
  const AdminSystemHealthPool._({
    required this.max,
    required this.total,
    required this.idle,
    required this.nonIdle,
    required this.checkedOut,
    required this.waiting,
  });

  static AdminSystemHealthPool? _parse(Object? value) {
    final map = _objectMap(value);
    if (map == null) return null;
    final max = _integer(map['max'], min: 1, max: _maxPoolGauge);
    final total = _integer(map['total'], max: _maxPoolGauge);
    final idle = _integer(map['idle'], max: _maxPoolGauge);
    final nonIdle = _integer(map['nonIdle'], max: _maxPoolGauge);
    final checkedOut = _integer(map['checkedOut'], max: _maxPoolGauge);
    final waiting = _integer(map['waiting'], max: _maxPoolGauge);
    if (max == null ||
        total == null ||
        idle == null ||
        nonIdle == null ||
        checkedOut == null ||
        waiting == null ||
        idle > total ||
        nonIdle != total - idle ||
        checkedOut > nonIdle ||
        total > max) {
      return null;
    }
    return AdminSystemHealthPool._(
      max: max,
      total: total,
      idle: idle,
      nonIdle: nonIdle,
      checkedOut: checkedOut,
      waiting: waiting,
    );
  }

  final int max;
  final int total;
  final int idle;
  final int nonIdle;
  final int checkedOut;
  final int waiting;
}

class AdminSystemHealthInterval {
  const AdminSystemHealthInterval._({
    required this.acquisitions,
    required this.releases,
    required this.queuedCheckouts,
    required this.queuedTimeouts,
    required this.queuedWaitP95Ms,
    required this.queuedWaitMaxMs,
    required this.physicalAttempts,
    required this.physicalTimeouts,
    required this.physicalErrors,
  });

  static AdminSystemHealthInterval? _parse(Object? value) {
    final map = _objectMap(value);
    if (map == null) return null;
    final acquisitions = _integer(map['acquisitions']);
    final releases = _integer(map['releases']);
    final queuedCheckouts = _integer(map['queuedCheckouts']);
    final queuedTimeouts = _integer(map['queuedTimeouts']);
    final physicalAttempts = _integer(map['physicalAttempts']);
    final physicalTimeouts = _integer(map['physicalTimeouts']);
    final physicalErrors = _integer(map['physicalErrors']);
    final waitP95 = _optionalDuration(map, 'queuedWaitP95Ms');
    final waitMax = _optionalDuration(map, 'queuedWaitMaxMs');
    if (acquisitions == null ||
        releases == null ||
        queuedCheckouts == null ||
        queuedTimeouts == null ||
        physicalAttempts == null ||
        physicalTimeouts == null ||
        physicalErrors == null ||
        waitP95.invalid ||
        waitMax.invalid) {
      return null;
    }
    return AdminSystemHealthInterval._(
      acquisitions: acquisitions,
      releases: releases,
      queuedCheckouts: queuedCheckouts,
      queuedTimeouts: queuedTimeouts,
      queuedWaitP95Ms: waitP95.value,
      queuedWaitMaxMs: waitMax.value,
      physicalAttempts: physicalAttempts,
      physicalTimeouts: physicalTimeouts,
      physicalErrors: physicalErrors,
    );
  }

  final int acquisitions;
  final int releases;
  final int queuedCheckouts;
  final int queuedTimeouts;
  final double? queuedWaitP95Ms;
  final double? queuedWaitMaxMs;
  final int physicalAttempts;
  final int physicalTimeouts;
  final int physicalErrors;
}

class AdminSystemHealthResources {
  const AdminSystemHealthResources._({
    required this.rssBytes,
    required this.cpuOneCorePercent,
    required this.eventLoopP99Ms,
  });

  static AdminSystemHealthResources? _parse(Object? value) {
    final map = _objectMap(value);
    if (map == null) return null;
    final rss = _integer(map['rssBytes']);
    final cpu = _finiteNumber(map['cpuOneCorePercent'], max: 100);
    final loop = _duration(map['eventLoopP99Ms']);
    if (rss == null || cpu == null || loop == null) return null;
    return AdminSystemHealthResources._(
      rssBytes: rss,
      cpuOneCorePercent: cpu,
      eventLoopP99Ms: loop,
    );
  }

  final int rssBytes;
  final double cpuOneCorePercent;
  final double eventLoopP99Ms;
}

class AdminSystemHealthStepIngestion {
  const AdminSystemHealthStepIngestion._({
    required this.contributingHttpProcesses,
    required this.requests,
    required this.successes,
    required this.failures,
    required this.queuedTimeouts,
    required this.latencyP95Ms,
    required this.transactionP95Ms,
    required this.phases,
    required this.endpoints,
  });

  static AdminSystemHealthStepIngestion? _parse(Object? value) {
    final map = _objectMap(value);
    if (map == null) return null;
    final contributing = _integer(
      map['contributingHttpProcesses'],
      min: 1,
      max: 2,
    );
    final requests = _integer(map['requests']);
    final successes = _integer(map['successes']);
    final failures = _integer(map['failures']);
    final queuedTimeouts = _integer(map['queuedTimeouts']);
    final latency = _optionalDuration(map, 'latencyP95Ms');
    final transaction = _optionalDuration(map, 'transactionP95Ms');
    final phaseRaw = _objectList(map['phases']);
    final endpointRaw = _objectList(map['endpoints']);
    if (contributing == null ||
        requests == null ||
        successes == null ||
        failures == null ||
        queuedTimeouts == null ||
        queuedTimeouts > failures ||
        successes + failures != requests ||
        latency.invalid ||
        transaction.invalid ||
        phaseRaw == null ||
        endpointRaw == null ||
        endpointRaw.length != 3) {
      return null;
    }
    final phases = <AdminSystemHealthPhase>[];
    final phaseNames = <String>{};
    for (final row in phaseRaw) {
      final parsed = AdminSystemHealthPhase._parse(row);
      if (parsed == null || !phaseNames.add(parsed.phase)) return null;
      phases.add(parsed);
    }
    const names = ['steps', 'samples', 'sync-v2'];
    final endpoints = <AdminSystemHealthStepEndpoint>[];
    for (var i = 0; i < endpointRaw.length; i++) {
      final parsed = AdminSystemHealthStepEndpoint._parse(endpointRaw[i]);
      if (parsed == null || parsed.endpoint != names[i]) return null;
      endpoints.add(parsed);
    }
    if (endpoints.fold<int>(0, (sum, row) => sum + row.requests) != requests ||
        endpoints.fold<int>(0, (sum, row) => sum + row.successes) !=
            successes ||
        endpoints.fold<int>(0, (sum, row) => sum + row.failures) != failures) {
      return null;
    }
    return AdminSystemHealthStepIngestion._(
      contributingHttpProcesses: contributing,
      requests: requests,
      successes: successes,
      failures: failures,
      queuedTimeouts: queuedTimeouts,
      latencyP95Ms: latency.value,
      transactionP95Ms: transaction.value,
      phases: List.unmodifiable(phases),
      endpoints: List.unmodifiable(endpoints),
    );
  }

  final int contributingHttpProcesses;
  final int requests;
  final int successes;
  final int failures;
  final int queuedTimeouts;
  final double? latencyP95Ms;
  final double? transactionP95Ms;
  final List<AdminSystemHealthPhase> phases;
  final List<AdminSystemHealthStepEndpoint> endpoints;
}

class AdminSystemHealthStepEndpoint {
  const AdminSystemHealthStepEndpoint._({
    required this.endpoint,
    required this.requests,
    required this.successes,
    required this.failures,
    required this.queuedTimeouts,
    required this.latencyP95Ms,
    required this.transactionP95Ms,
  });

  static AdminSystemHealthStepEndpoint? _parse(Object? value) {
    final map = _objectMap(value);
    if (map == null || map['endpoint'] is! String) return null;
    final requests = _integer(map['requests']);
    final successes = _integer(map['successes']);
    final failures = _integer(map['failures']);
    final queued = _integer(map['queuedTimeouts']);
    final latency = _optionalDuration(map, 'latencyP95Ms');
    final transaction = _optionalDuration(map, 'transactionP95Ms');
    if (requests == null ||
        successes == null ||
        failures == null ||
        queued == null ||
        queued > failures ||
        successes + failures != requests ||
        latency.invalid ||
        transaction.invalid) {
      return null;
    }
    return AdminSystemHealthStepEndpoint._(
      endpoint: map['endpoint']! as String,
      requests: requests,
      successes: successes,
      failures: failures,
      queuedTimeouts: queued,
      latencyP95Ms: latency.value,
      transactionP95Ms: transaction.value,
    );
  }

  final String endpoint;
  final int requests;
  final int successes;
  final int failures;
  final int queuedTimeouts;
  final double? latencyP95Ms;
  final double? transactionP95Ms;
}

class AdminSystemHealthPhase {
  const AdminSystemHealthPhase._({
    required this.phase,
    required this.observations,
    required this.samplingRate,
    required this.p95Ms,
    required this.maxMs,
  });

  static AdminSystemHealthPhase? _parse(Object? value) {
    final map = _objectMap(value);
    if (map == null ||
        map['phase'] is! String ||
        !_phaseNames.contains(map['phase'])) {
      return null;
    }
    final observations = _integer(map['observations']);
    final sampling = _finiteNumber(map['samplingRate'], max: 1);
    final p95 = _optionalDuration(map, 'p95Ms');
    final max = _optionalDuration(map, 'maxMs');
    if (observations == null ||
        sampling == null ||
        p95.invalid ||
        max.invalid ||
        (observations == 0 && (p95.value != null || max.value != null))) {
      return null;
    }
    return AdminSystemHealthPhase._(
      phase: map['phase']! as String,
      observations: observations,
      samplingRate: sampling,
      p95Ms: p95.value,
      maxMs: max.value,
    );
  }

  final String phase;
  final int observations;
  final double samplingRate;
  final double? p95Ms;
  final double? maxMs;
}

class AdminSystemHealthFailureWindow {
  const AdminSystemHealthFailureWindow._({
    required this.window,
    required this.windowMinutes,
    required this.collectionStatus,
    required this.completeCoverageMinutes,
    required this.partialCoverageMinutes,
    required this.requests,
    required this.successes,
    required this.requestFailures,
    required this.serverFailures,
    required this.endpoints,
  });

  static AdminSystemHealthFailureWindow? _parse(Object? value) {
    final map = _objectMap(value);
    if (map == null || map['window'] is! String) return null;
    final windowMinutes = _integer(map['windowMinutes'], min: 1, max: 10080);
    final collection = _collectionStatus(map['collectionStatus']);
    final complete = _integer(
      map['completeCoverageMinutes'],
      max: windowMinutes ?? 0,
    );
    final partial = _integer(
      map['partialCoverageMinutes'],
      max: windowMinutes ?? 0,
    );
    final requests = _integer(map['requests']);
    final successes = _integer(map['successes']);
    final requestFailures = _integer(map['requestFailures']);
    final serverFailures = _integer(map['serverFailures']);
    final endpointRaw = _objectList(map['endpoints']);
    if (windowMinutes == null ||
        collection == null ||
        complete == null ||
        partial == null ||
        complete + partial > windowMinutes ||
        requests == null ||
        successes == null ||
        requestFailures == null ||
        serverFailures == null ||
        requestFailures != requests - successes ||
        serverFailures > requestFailures ||
        endpointRaw == null ||
        endpointRaw.length != 3 ||
        (collection == AdminSystemHealthCollectionStatus.complete &&
            (complete != windowMinutes || partial != 0))) {
      return null;
    }
    const names = ['steps', 'samples', 'sync-v2'];
    final endpoints = <AdminSystemHealthFailureEndpoint>[];
    for (var i = 0; i < endpointRaw.length; i++) {
      final parsed = AdminSystemHealthFailureEndpoint._parse(endpointRaw[i]);
      if (parsed == null || parsed.endpoint != names[i]) return null;
      endpoints.add(parsed);
    }
    if (endpoints.fold<int>(0, (sum, row) => sum + row.requests) != requests ||
        endpoints.fold<int>(0, (sum, row) => sum + row.successes) !=
            successes ||
        endpoints.fold<int>(0, (sum, row) => sum + row.requestFailures) !=
            requestFailures ||
        endpoints.fold<int>(0, (sum, row) => sum + row.serverFailures) !=
            serverFailures) {
      return null;
    }
    return AdminSystemHealthFailureWindow._(
      window: map['window']! as String,
      windowMinutes: windowMinutes,
      collectionStatus: collection,
      completeCoverageMinutes: complete,
      partialCoverageMinutes: partial,
      requests: requests,
      successes: successes,
      requestFailures: requestFailures,
      serverFailures: serverFailures,
      endpoints: List.unmodifiable(endpoints),
    );
  }

  final String window;
  final int windowMinutes;
  final AdminSystemHealthCollectionStatus collectionStatus;
  final int completeCoverageMinutes;
  final int partialCoverageMinutes;
  final int requests;
  final int successes;
  final int requestFailures;
  final int serverFailures;
  final List<AdminSystemHealthFailureEndpoint> endpoints;
  double? get requestFailureRate =>
      requests == 0 ? null : requestFailures / requests;
  double? get serverFailureRate =>
      requests == 0 ? null : serverFailures / requests;
}

class AdminSystemHealthFailureEndpoint {
  const AdminSystemHealthFailureEndpoint._({
    required this.endpoint,
    required this.requests,
    required this.successes,
    required this.requestFailures,
    required this.serverFailures,
  });

  static AdminSystemHealthFailureEndpoint? _parse(Object? value) {
    final map = _objectMap(value);
    if (map == null || map['endpoint'] is! String) return null;
    final requests = _integer(map['requests']);
    final successes = _integer(map['successes']);
    final requestFailures = _integer(map['requestFailures']);
    final serverFailures = _integer(map['serverFailures']);
    if (requests == null ||
        successes == null ||
        requestFailures == null ||
        serverFailures == null ||
        requestFailures != requests - successes ||
        serverFailures > requestFailures) {
      return null;
    }
    return AdminSystemHealthFailureEndpoint._(
      endpoint: map['endpoint']! as String,
      requests: requests,
      successes: successes,
      requestFailures: requestFailures,
      serverFailures: serverFailures,
    );
  }

  final String endpoint;
  final int requests;
  final int successes;
  final int requestFailures;
  final int serverFailures;
  double? get requestFailureRate =>
      requests == 0 ? null : requestFailures / requests;
  double? get serverFailureRate =>
      requests == 0 ? null : serverFailures / requests;
}

const _phaseNames = {
  'authentication',
  'checkout_wait',
  'transaction_total',
  'scoring_state',
  'daily',
  'sample',
  'scoring_generation',
  'active_race',
  'durable_enqueue',
  'summary_finalization',
  'post_commit',
};

Map<String, Object?>? _objectMap(Object? value) {
  if (value is! Map) return null;
  final result = <String, Object?>{};
  for (final entry in value.entries) {
    if (entry.key is! String) return null;
    result[entry.key as String] = entry.value;
  }
  return result;
}

List<Object?>? _objectList(Object? value) =>
    value is List ? List<Object?>.from(value) : null;

int? _integer(Object? value, {int min = 0, int max = _maxSafeInteger}) {
  if (value is! int || value < min || value > max) return null;
  return value;
}

double? _finiteNumber(
  Object? value, {
  double min = 0,
  double max = double.maxFinite,
}) {
  if (value is! num) return null;
  final number = value.toDouble();
  return number.isFinite && number >= min && number <= max ? number : null;
}

double? _duration(Object? value) => _finiteNumber(value, max: _maxDurationMs);

({double? value, bool invalid}) _optionalDuration(
  Map<String, Object?> map,
  String key,
) {
  if (!map.containsKey(key) || map[key] == null) {
    return (value: null, invalid: false);
  }
  final value = _duration(map[key]);
  return (value: value, invalid: value == null);
}

DateTime? _date(Object? value) {
  if (value is! String) return null;
  final parsed = DateTime.tryParse(value);
  return parsed?.isUtc == true ? parsed : null;
}

String? _identityRole(Object? role, Object? instance) {
  if (role == 'http' && (instance == '0' || instance == '1')) return 'http';
  if ((role == 'resolution' || role == 'cron') && instance == '0') {
    return role as String;
  }
  return null;
}

AdminSystemHealthStatus? _status(Object? value) => switch (value) {
  'available' => AdminSystemHealthStatus.available,
  'partial' => AdminSystemHealthStatus.partial,
  'unavailable' => AdminSystemHealthStatus.unavailable,
  _ => null,
};

AdminSystemHealthOverall? _overall(Object? value) => switch (value) {
  'healthy' => AdminSystemHealthOverall.healthy,
  'pressure' => AdminSystemHealthOverall.pressure,
  'degraded' => AdminSystemHealthOverall.degraded,
  'unknown' => AdminSystemHealthOverall.unknown,
  _ => null,
};

AdminSystemHealthHistoryStatus? _historyStatus(Object? value) =>
    switch (value) {
      'available' => AdminSystemHealthHistoryStatus.available,
      'partial' => AdminSystemHealthHistoryStatus.partial,
      'unavailable' => AdminSystemHealthHistoryStatus.unavailable,
      _ => null,
    };

AdminSystemHealthProcessStatus? _processStatus(Object? value) =>
    switch (value) {
      'healthy' => AdminSystemHealthProcessStatus.healthy,
      'pressure' => AdminSystemHealthProcessStatus.pressure,
      'degraded' => AdminSystemHealthProcessStatus.degraded,
      'unknown' => AdminSystemHealthProcessStatus.unknown,
      _ => null,
    };

AdminSystemHealthCollectionStatus? _collectionStatus(Object? value) =>
    switch (value) {
      'complete' => AdminSystemHealthCollectionStatus.complete,
      'collecting' => AdminSystemHealthCollectionStatus.collecting,
      _ => null,
    };
