/// State of a durable race-resolution job (spec §6.5). `notFound`/`unknown` are
/// client-only: the server never returns them, but the client maps a 404 or an
/// unparseable/failed read into one so the polling loop can decide when to stop.
enum RaceResolutionState {
  queued,
  running,
  succeeded,
  failed,
  superseded,

  /// 404 from the status endpoint (job not owned/unknown, or endpoint absent).
  notFound,

  /// Malformed body or transient read error; the caller may retry on schedule.
  unknown,
}

class RaceResolutionStatus {
  const RaceResolutionStatus(this.state);

  final RaceResolutionState state;

  static RaceResolutionState parseState(Object? raw) {
    switch (raw) {
      case 'QUEUED':
        return RaceResolutionState.queued;
      case 'RUNNING':
        return RaceResolutionState.running;
      case 'SUCCEEDED':
        return RaceResolutionState.succeeded;
      case 'FAILED':
        return RaceResolutionState.failed;
      case 'SUPERSEDED':
        return RaceResolutionState.superseded;
      default:
        return RaceResolutionState.unknown;
    }
  }

  bool get isSucceeded => state == RaceResolutionState.succeeded;

  /// The poll loop stops on any terminal state. `unknown` is NOT terminal (the
  /// caller may poll again on schedule), but the loop's fixed attempt cap still
  /// bounds it.
  bool get isTerminal =>
      state == RaceResolutionState.succeeded ||
      state == RaceResolutionState.failed ||
      state == RaceResolutionState.superseded ||
      state == RaceResolutionState.notFound;
}
