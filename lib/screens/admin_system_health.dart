import 'package:flutter/material.dart';

import '../models/admin_system_health.dart';
import '../styles.dart';
import '../widgets/spinning_crate.dart';

class AdminSystemHealthBody extends StatelessWidget {
  const AdminSystemHealthBody({
    super.key,
    required this.health,
    required this.loading,
    required this.emptyStatus,
    required this.failed,
    required this.stale,
    required this.onRefresh,
  });

  final AdminSystemHealthEnvelope? health;
  final bool loading;
  final AdminSystemHealthFetchStatus? emptyStatus;
  final bool failed;
  final bool stale;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final health = this.health;
    if (loading && health == null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 16),
          child: Semantics(
            label: 'Loading system health',
            child: const SpinningCrate(size: 46),
          ),
        ),
      );
    }
    if (health == null) {
      final message = switch (emptyStatus) {
        AdminSystemHealthFetchStatus.routeUnavailable =>
          'Requires server update',
        AdminSystemHealthFetchStatus.malformed =>
          'Telemetry response malformed',
        _ => 'Couldn’t load system health.',
      };
      return _SystemHealthStatePanel(message: message, onRetry: onRefresh);
    }
    return _SystemHealthContent(
      health: health,
      loading: loading,
      stale: stale,
      refreshFailed: failed,
      onRefresh: onRefresh,
    );
  }
}

class _SystemHealthStatePanel extends StatelessWidget {
  const _SystemHealthStatePanel({required this.message, required this.onRetry});

  final String message;
  final VoidCallback onRetry;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(message, style: PixelText.body(size: 12, color: colors.textMid)),
          const SizedBox(height: 6),
          TextButton(
            key: const Key('admin-system-health-retry'),
            onPressed: onRetry,
            child: Text(
              'RETRY',
              style: PixelText.title(size: 12, color: colors.textAccent),
            ),
          ),
        ],
      ),
    );
  }
}

class _SystemHealthContent extends StatelessWidget {
  const _SystemHealthContent({
    required this.health,
    required this.loading,
    required this.stale,
    required this.refreshFailed,
    required this.onRefresh,
  });

  final AdminSystemHealthEnvelope health;
  final bool loading;
  final bool stale;
  final bool refreshFailed;
  final VoidCallback onRefresh;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _StatusPlate(health: health),
        if (stale && refreshFailed) ...[
          const SizedBox(height: 8),
          Text(
            'STALE — REFRESH FAILED',
            style: PixelText.title(size: 11, color: colors.error),
          ),
        ],
        const SizedBox(height: 14),
        _PoolNow(health: health),
        const SizedBox(height: 14),
        _LastHour(health: health),
        const SizedBox(height: 14),
        _FailureRates(health: health),
        const SizedBox(height: 14),
        Wrap(
          spacing: 10,
          runSpacing: 6,
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            Text(
              'Updated ${_relativeTime(health.generatedAt)}',
              style: PixelText.body(size: 10, color: colors.textMid),
            ),
            TextButton(
              key: const Key('admin-system-health-refresh'),
              onPressed: loading ? null : onRefresh,
              child: Text(
                loading ? 'REFRESHING…' : 'REFRESH',
                style: PixelText.title(
                  size: 11,
                  color: loading ? colors.textMid : colors.textAccent,
                ),
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class _StatusPlate extends StatelessWidget {
  const _StatusPlate({required this.health});

  final AdminSystemHealthEnvelope health;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final collecting =
        health.status == AdminSystemHealthStatus.available &&
        health.overall == AdminSystemHealthOverall.unknown &&
        health.windowCoverageMinutes < 60;
    final label = collecting
        ? 'COLLECTING — LAST ${health.windowCoverageMinutes} MINUTES'
        : switch (health.overall) {
            AdminSystemHealthOverall.healthy => 'HEALTHY',
            AdminSystemHealthOverall.pressure => 'PRESSURE',
            AdminSystemHealthOverall.degraded => 'DEGRADED',
            AdminSystemHealthOverall.unknown => 'UNKNOWN',
          };
    final accent = switch (health.overall) {
      AdminSystemHealthOverall.healthy => colors.success,
      AdminSystemHealthOverall.pressure => colors.pillGoldDark,
      AdminSystemHealthOverall.degraded => colors.error,
      AdminSystemHealthOverall.unknown => colors.textMid,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: accent.withValues(alpha: colors.isDark ? 0.20 : 0.10),
        border: Border.all(color: accent, width: 2),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Text(
        label,
        textAlign: TextAlign.center,
        style: PixelText.title(size: 14, color: accent),
      ),
    );
  }
}

class _PoolNow extends StatelessWidget {
  const _PoolNow({required this.health});

  final AdminSystemHealthEnvelope health;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('POOL NOW'),
        if (health.processes.isEmpty)
          Text(
            'POOL TELEMETRY UNAVAILABLE',
            style: PixelText.body(size: 11, color: colors.textMid),
          ),
        for (final identity in const [
          ('http', '0', 'HTTP 0'),
          ('http', '1', 'HTTP 1'),
          ('resolution', '0', 'RESOLUTION 0'),
          ('cron', '0', 'CRON 0'),
        ])
          _ProcessRow(
            label: identity.$3,
            process: health.process(identity.$1, identity.$2),
            missingReason: _missingReason(health, identity.$1, identity.$2),
          ),
      ],
    );
  }
}

class _ProcessRow extends StatelessWidget {
  const _ProcessRow({
    required this.label,
    required this.process,
    required this.missingReason,
  });

  final String label;
  final AdminSystemHealthProcess? process;
  final String? missingReason;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final process = this.process;
    return Container(
      margin: const EdgeInsets.only(top: 7),
      padding: const EdgeInsets.all(9),
      decoration: BoxDecoration(
        color: colors.parchmentDark.withValues(alpha: 0.66),
        border: Border.all(color: colors.parchmentBorder),
        borderRadius: BorderRadius.circular(3),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: PixelText.title(size: 11, color: colors.textDark)),
          const SizedBox(height: 4),
          if (process == null)
            Text(
              'MISSING${missingReason == null ? '' : ' · ${missingReason!.toUpperCase()}'}',
              style: PixelText.title(size: 10, color: colors.error),
            )
          else ...[
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _TinyValue(
                  label: 'CHECKED OUT',
                  value: '${process.pool.checkedOut} / ${process.pool.max}',
                ),
                _TinyValue(label: 'WAITING', value: '${process.pool.waiting}'),
                _TinyValue(
                  label: 'FRESHNESS',
                  value: _relativeTime(process.capturedAt).toUpperCase(),
                ),
              ],
            ),
            const SizedBox(height: 4),
            Wrap(
              spacing: 12,
              runSpacing: 4,
              children: [
                _TinyValue(
                  label: 'CPU',
                  value:
                      '${process.resources.cpuOneCorePercent.toStringAsFixed(1)}%',
                ),
                _TinyValue(
                  label: 'RSS',
                  value: _bytes(process.resources.rssBytes),
                ),
                _TinyValue(
                  label: 'LOOP P99',
                  value: _milliseconds(process.resources.eventLoopP99Ms),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}

class _LastHour extends StatelessWidget {
  const _LastHour({required this.health});

  final AdminSystemHealthEnvelope health;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final rows = health.processes;
    final step = health.stepIngestion;
    final heading = health.windowCoverageMinutes < 60
        ? 'LAST ${health.windowCoverageMinutes} MINUTES'
        : 'LAST 60 MIN';
    if (rows.isEmpty && step == null) {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          _Heading(heading),
          Text(
            'POOL AND STEP SUMMARY UNAVAILABLE',
            style: PixelText.body(size: 11, color: colors.textMid),
          ),
        ],
      );
    }
    int sum(int Function(AdminSystemHealthInterval value) select) =>
        rows.fold(0, (sum, process) => sum + select(process.last60m));
    double? maxOf(double? Function(AdminSystemHealthInterval value) select) {
      double? result;
      for (final process in rows) {
        final value = select(process.last60m);
        if (value != null && (result == null || value > result)) result = value;
      }
      return result;
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        _Heading(heading),
        _MetricLine(
          label: 'QUEUED TIMEOUTS',
          value: rows.isEmpty
              ? 'UNAVAILABLE'
              : _number(sum((value) => value.queuedTimeouts)),
        ),
        _MetricLine(
          label: 'WAIT P95 / MAX · WORST PROCESS',
          value: rows.isEmpty
              ? 'UNAVAILABLE'
              : '${_millisecondsOrUnavailable(maxOf((value) => value.queuedWaitP95Ms))} / '
                    '${_millisecondsOrUnavailable(maxOf((value) => value.queuedWaitMaxMs))}',
        ),
        _MetricLine(
          label: 'PHYSICAL TIMEOUTS / ERRORS',
          value: rows.isEmpty
              ? 'UNAVAILABLE'
              : '${_number(sum((value) => value.physicalTimeouts))} / '
                    '${_number(sum((value) => value.physicalErrors))}',
        ),
        _MetricLine(
          label: 'STEP FAILURES',
          value: step == null ? 'UNAVAILABLE' : _number(step.failures),
        ),
        _MetricLine(
          label: 'STEP LATENCY P95',
          value: _millisecondsOrUnavailable(step?.latencyP95Ms),
        ),
        _MetricLine(
          label: 'TRANSACTION P95',
          value: _millisecondsOrUnavailable(step?.transactionP95Ms),
        ),
        if (step != null)
          for (final endpoint in step.endpoints)
            _EndpointSummaryRow(endpoint: endpoint),
      ],
    );
  }
}

class _EndpointSummaryRow extends StatelessWidget {
  const _EndpointSummaryRow({required this.endpoint});

  final AdminSystemHealthStepEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 6),
      child: Text(
        '${endpoint.endpoint.toUpperCase()} · ${_number(endpoint.failures)} FAIL · '
        '${_millisecondsOrUnavailable(endpoint.latencyP95Ms)} REQUEST P95 · '
        '${_millisecondsOrUnavailable(endpoint.transactionP95Ms)} TX P95',
        style: PixelText.body(size: 10, color: colors.textMid),
      ),
    );
  }
}

class _FailureRates extends StatelessWidget {
  const _FailureRates({required this.health});

  final AdminSystemHealthEnvelope health;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const _Heading('REQUEST FAILURE RATE'),
        if (health.failureWindows.isEmpty)
          Text(
            'FAILURE HISTORY UNAVAILABLE',
            style: PixelText.body(size: 11, color: colors.textMid),
          )
        else ...[
          if (health.historyStatus == AdminSystemHealthHistoryStatus.partial)
            Padding(
              padding: const EdgeInsets.only(bottom: 7),
              child: Text(
                'HISTORY PARTIAL',
                style: PixelText.title(size: 10, color: colors.error),
              ),
            ),
          for (final window in health.failureWindows)
            _FailureWindowCard(window: window),
        ],
      ],
    );
  }
}

class _FailureWindowCard extends StatelessWidget {
  const _FailureWindowCard({required this.window});

  final AdminSystemHealthFailureWindow window;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final title = switch (window.window) {
      '60m' => '60 MIN',
      '24h' => '24 HOURS',
      '7d' => '7 DAYS',
      _ => 'UNAVAILABLE',
    };
    final collection =
        window.collectionStatus == AdminSystemHealthCollectionStatus.complete
        ? 'TELEMETRY COMPLETE'
        : 'TELEMETRY COLLECTING — ${_number(window.completeCoverageMinutes)} '
              'OF ${_number(window.windowMinutes)} MINUTES';
    return Container(
      margin: const EdgeInsets.only(top: 8),
      padding: const EdgeInsets.all(10),
      decoration: BoxDecoration(
        color: colors.parchmentLight.withValues(alpha: 0.75),
        border: Border.all(color: colors.parchmentBorder),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: PixelText.title(size: 12, color: colors.textDark)),
          const SizedBox(height: 3),
          Text(
            collection,
            style: PixelText.title(size: 9, color: colors.textAccent),
          ),
          if (window.partialCoverageMinutes > 0)
            Text(
              '+${_number(window.partialCoverageMinutes)} PARTIAL',
              style: PixelText.body(size: 9, color: colors.textMid),
            ),
          const SizedBox(height: 7),
          Text(
            'OBSERVED TELEMETRY',
            style: PixelText.body(size: 9, color: colors.textMid),
          ),
          _MetricLine(
            label: 'REQUEST FAILURES',
            value: _rate(
              window.requestFailures,
              window.requests,
              window.requestFailureRate,
            ),
          ),
          _MetricLine(
            label: 'SERVER FAILURES',
            value: _rate(
              window.serverFailures,
              window.requests,
              window.serverFailureRate,
            ),
          ),
          for (final endpoint in window.endpoints)
            _FailureEndpointRow(endpoint: endpoint),
        ],
      ),
    );
  }
}

class _FailureEndpointRow extends StatelessWidget {
  const _FailureEndpointRow({required this.endpoint});

  final AdminSystemHealthFailureEndpoint endpoint;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.only(top: 7),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            endpoint.endpoint.toUpperCase(),
            style: PixelText.title(size: 9, color: colors.textDark),
          ),
          Text(
            'REQUEST ${_rate(endpoint.requestFailures, endpoint.requests, endpoint.requestFailureRate)}'
            ' · SERVER ${_rate(endpoint.serverFailures, endpoint.requests, endpoint.serverFailureRate)}',
            style: PixelText.body(size: 9, color: colors.textMid),
          ),
        ],
      ),
    );
  }
}

class _Heading extends StatelessWidget {
  const _Heading(this.text);

  final String text;

  @override
  Widget build(BuildContext context) => Padding(
    padding: const EdgeInsets.only(bottom: 5),
    child: Text(
      text,
      style: PixelText.title(size: 12, color: AppColors.of(context).textDark),
    ),
  );
}

class _MetricLine extends StatelessWidget {
  const _MetricLine({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 3),
      child: Wrap(
        spacing: 8,
        runSpacing: 2,
        alignment: WrapAlignment.spaceBetween,
        children: [
          Text(label, style: PixelText.body(size: 10, color: colors.textMid)),
          Text(
            value,
            textAlign: TextAlign.end,
            style: PixelText.title(size: 10, color: colors.textDark),
          ),
        ],
      ),
    );
  }
}

class _TinyValue extends StatelessWidget {
  const _TinyValue({required this.label, required this.value});

  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Text(
      '$label $value',
      style: PixelText.body(size: 9, color: colors.textMid),
    );
  }
}

String? _missingReason(
  AdminSystemHealthEnvelope health,
  String role,
  String instance,
) {
  for (final missing in health.missingProcesses) {
    if (missing.role == role && missing.instance == instance) {
      return missing.reason;
    }
  }
  return null;
}

String _rate(int numerator, int denominator, double? rate) => denominator == 0
    ? 'NO REQUESTS'
    : '${(rate! * 100).toStringAsFixed(1)}% · '
          '${_number(numerator)} / ${_number(denominator)}';

String _milliseconds(double value) =>
    '${value.toStringAsFixed(value % 1 == 0 ? 0 : 1)} MS';

String _millisecondsOrUnavailable(double? value) =>
    value == null ? 'UNAVAILABLE' : _milliseconds(value);

String _bytes(int value) {
  if (value < 1024 * 1024) return '${(value / 1024).toStringAsFixed(1)} KB';
  return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
}

String _number(int value) {
  final digits = value.toString();
  final output = StringBuffer();
  for (var i = 0; i < digits.length; i++) {
    if (i > 0 && (digits.length - i) % 3 == 0) output.write(',');
    output.write(digits[i]);
  }
  return output.toString();
}

String _relativeTime(DateTime timestamp) {
  final difference = DateTime.now().toUtc().difference(timestamp.toUtc());
  if (difference.isNegative || difference.inSeconds < 5) return 'just now';
  if (difference.inMinutes < 1) return '${difference.inSeconds}s ago';
  if (difference.inHours < 1) return '${difference.inMinutes}m ago';
  if (difference.inDays < 1) return '${difference.inHours}h ago';
  return '${difference.inDays}d ago';
}
