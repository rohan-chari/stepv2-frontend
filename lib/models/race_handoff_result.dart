enum RaceHandoffKind { joined, created }

/// Typed navigation result shared by public join and create flows.
class RaceHandoffResult {
  const RaceHandoffResult({
    required this.raceId,
    required this.status,
    required this.kind,
  });

  final String raceId;
  final String status;
  final RaceHandoffKind kind;

  bool get isActive => status == 'ACTIVE';
}
