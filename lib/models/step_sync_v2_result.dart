/// Outcome of a `POST /steps/sync-v2` attempt, as interpreted by the client's
/// defensive contract rules (spec §6.4 / §9.1). The orchestration layer maps
/// each [StepSyncV2Kind] to a home-batch strategy and decides whether a legacy
/// step write is permitted.
enum StepSyncV2Kind {
  /// 202, `uploaderReconciliation.state == CURRENT`. The uploader's own totals
  /// and box/powerup state are current: safe to fetch Home with
  /// `homePersistedTotals=1` and to poll the job.
  current,

  /// 202, `uploaderReconciliation.state == DEFERRED` (or missing/unknown, which
  /// we treat as DEFERRED for safety). Persisted, but use the live-computation
  /// Home path so a stale own-progress card cannot replace good UI.
  deferred,

  /// 404: endpoint absent on this backend. Cached unsupported for the session;
  /// the caller must run the legacy `/steps` (+ `/steps/samples`) flow.
  unsupported,

  /// 503 `ASYNC_DISABLED` before any persistence. The caller must run the legacy
  /// flow; the server guarantees nothing was written.
  asyncDisabled,

  /// Persisted-but-status-unknown: malformed 2xx body, or `409
  /// IDEMPOTENCY_CONFLICT`. The server may already hold the data, so the caller
  /// never issues a legacy write; it uses the live-computation Home path, skips
  /// job polling, and emits a contract diagnostic.
  persistedStatusUnknown,

  /// Timeout / connection loss / 500 that persisted after the single permitted
  /// retry. Persistence is unknown, so no legacy write is issued; the caller
  /// retains prior surfaces and shows the existing sync-error state.
  ambiguousFailure,

  /// Definite pre-persistence rejection with no legacy path (400/401/413). The
  /// caller shows the sync-error state and does not claim success.
  failed,
}

class StepSyncV2Result {
  const StepSyncV2Result({
    required this.kind,
    this.jobId,
    this.generation,
    this.resolvedRaceCount = 0,
    this.boxStateCurrent = false,
    this.diagnostic,
  });

  final StepSyncV2Kind kind;
  final String? jobId;
  final int? generation;
  final int resolvedRaceCount;
  final bool boxStateCurrent;

  /// Non-null when this outcome is a client-side contract alarm that should be
  /// logged (malformed success, idempotency conflict).
  final String? diagnostic;

  /// The uploader's own progress/box state is current -> fetch Home with
  /// `homePersistedTotals=1`.
  bool get usePersistedHome => kind == StepSyncV2Kind.current;

  /// Only a definite 404 or pre-persistence `ASYNC_DISABLED` permits a legacy
  /// write. Every ambiguous or persisted-unknown outcome forbids it.
  bool get shouldLegacyFallback =>
      kind == StepSyncV2Kind.unsupported ||
      kind == StepSyncV2Kind.asyncDisabled;

  /// Step/sample data is (very likely) persisted server-side.
  bool get persisted =>
      kind == StepSyncV2Kind.current ||
      kind == StepSyncV2Kind.deferred ||
      kind == StepSyncV2Kind.persistedStatusUnknown;

  /// A durable job exists that can be polled for completion.
  bool get hasJob =>
      jobId != null &&
      generation != null &&
      (kind == StepSyncV2Kind.current || kind == StepSyncV2Kind.deferred);

  /// The refresh could not be acknowledged as successful.
  bool get isError =>
      kind == StepSyncV2Kind.ambiguousFailure || kind == StepSyncV2Kind.failed;
}
