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

  /// An opted-in Home pull arrived inside the server-authoritative cooldown.
  /// No steps were persisted and, unlike an ordinary failure, Home should end
  /// its indicator immediately without changing the visible cards.
  cooldown,
}

enum GlobalEventSummaryWorkState {
  waitingSync,
  queued,
  processing,
  waitingRaces,
  created,
  allZero,
  unscorable,
  expiredUndelivered;

  static GlobalEventSummaryWorkState? tryParse(Object? raw) {
    switch (raw) {
      case 'WAITING_SYNC':
        return GlobalEventSummaryWorkState.waitingSync;
      case 'QUEUED':
        return GlobalEventSummaryWorkState.queued;
      case 'PROCESSING':
        return GlobalEventSummaryWorkState.processing;
      case 'WAITING_RACES':
        return GlobalEventSummaryWorkState.waitingRaces;
      case 'CREATED':
        return GlobalEventSummaryWorkState.created;
      case 'ALL_ZERO':
        return GlobalEventSummaryWorkState.allZero;
      case 'UNSCORABLE':
        return GlobalEventSummaryWorkState.unscorable;
      case 'EXPIRED_UNDELIVERED':
        return GlobalEventSummaryWorkState.expiredUndelivered;
      default:
        return null;
    }
  }

  bool get isCreated => this == GlobalEventSummaryWorkState.created;

  bool get isTerminal =>
      isCreated ||
      this == GlobalEventSummaryWorkState.allZero ||
      this == GlobalEventSummaryWorkState.unscorable ||
      this == GlobalEventSummaryWorkState.expiredUndelivered;
}

class GlobalEventSummaryWorkStatus {
  const GlobalEventSummaryWorkStatus({
    required this.state,
    required this.expiresAt,
  });

  final GlobalEventSummaryWorkState state;
  final DateTime expiresAt;

  static GlobalEventSummaryWorkStatus? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final state = GlobalEventSummaryWorkState.tryParse(raw['state']);
    final rawExpiresAt = raw['expiresAt'];
    final expiresAt = rawExpiresAt is String
        ? DateTime.tryParse(rawExpiresAt)?.toUtc()
        : null;
    if (state == null || expiresAt == null) return null;
    return GlobalEventSummaryWorkStatus(state: state, expiresAt: expiresAt);
  }
}

class GlobalEventSummaryWorkReceipt extends GlobalEventSummaryWorkStatus {
  const GlobalEventSummaryWorkReceipt({
    required this.id,
    required super.state,
    required super.expiresAt,
  });

  final String id;

  static GlobalEventSummaryWorkReceipt? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'];
    final status = GlobalEventSummaryWorkStatus.tryParse(raw);
    if (id is! String || id.isEmpty || status == null) return null;
    return GlobalEventSummaryWorkReceipt(
      id: id,
      state: status.state,
      expiresAt: status.expiresAt,
    );
  }
}

class StepSyncV2Result {
  const StepSyncV2Result({
    required this.kind,
    this.jobId,
    this.generation,
    this.resolvedRaceCount = 0,
    this.boxStateCurrent = false,
    this.retryAfterSeconds,
    this.diagnostic,
    this.globalEventSummaryWork,
  });

  final StepSyncV2Kind kind;
  final String? jobId;
  final int? generation;
  final int resolvedRaceCount;
  final bool boxStateCurrent;

  /// Server-provided, rounded-up Home-pull cooldown delay. It is null unless
  /// the response matched the complete additive cooldown contract.
  final int? retryAfterSeconds;

  /// Non-null when this outcome is a client-side contract alarm that should be
  /// logged (malformed success, idempotency conflict).
  final String? diagnostic;

  /// Owner-bound lifecycle receipt for today's optional 2x recap. Missing or
  /// malformed additive data remains null so sync success is unaffected when
  /// talking to an older/newer backend.
  final GlobalEventSummaryWorkReceipt? globalEventSummaryWork;

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

  bool get isCooldown => kind == StepSyncV2Kind.cooldown;
}
