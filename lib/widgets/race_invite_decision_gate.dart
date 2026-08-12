import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/team_race.dart';
import '../utils/tournament.dart';
import 'pill_button.dart';
import 'spinning_coin.dart';

enum _GatePhase { unverified, checking, decision, open, error }

class _InviteDecision {
  const _InviteDecision({required this.isTournament, required this.data});
  final bool isTournament;
  final Map<String, dynamic> data;

  String get id {
    final raw = data['id'];
    return raw is String ? raw : '';
  }

  DateTime? get sortTime {
    final candidates = isTournament
        ? [data['createdAt']]
        : [
            data['myInviteExpiresAt'],
            data['scheduledStartAt'],
            data['createdAt'],
          ];
    for (final raw in candidates) {
      if (raw is String) {
        final parsed = DateTime.tryParse(raw);
        if (parsed != null) return parsed;
      }
    }
    return null;
  }
}

/// Opaque shell-level preflight. The race list remains built behind this
/// widget for state retention, but is never painted or exposed to semantics
/// until a fresh epoch is verified open.
class RaceInviteDecisionGate extends StatefulWidget {
  const RaceInviteDecisionGate({
    super.key,
    required this.enabled,
    required this.active,
    required this.entryEpoch,
    required this.authService,
    required this.backendApiService,
    required this.onVerifiedData,
    required this.onExitHome,
    required this.onBlockingChanged,
    required this.child,
  });

  final bool enabled;
  final bool active;
  final int entryEpoch;
  final AuthService authService;
  final BackendApiService backendApiService;
  final ValueChanged<Map<String, dynamic>> onVerifiedData;
  final VoidCallback onExitHome;
  final ValueChanged<bool> onBlockingChanged;
  final Widget child;

  @override
  State<RaceInviteDecisionGate> createState() => _RaceInviteDecisionGateState();
}

class _RaceInviteDecisionGateState extends State<RaceInviteDecisionGate> {
  _GatePhase _phase = _GatePhase.unverified;
  List<_InviteDecision> _queue = const [];
  int _requestSerial = 0;
  bool _acting = false;
  bool? _accepting;
  String? _error;

  bool get _blocking => widget.enabled && _phase != _GatePhase.open;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _reportBlocking();
      if (mounted && widget.enabled && widget.active) {
        _check(widget.entryEpoch);
      }
    });
  }

  @override
  void didUpdateWidget(covariant RaceInviteDecisionGate oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!widget.enabled) {
      _phase = _GatePhase.open;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportBlocking());
      return;
    }
    if (!widget.active && oldWidget.active) {
      _requestSerial++;
      _phase = _GatePhase.unverified;
      _queue = const [];
      _error = null;
      WidgetsBinding.instance.addPostFrameCallback((_) => _reportBlocking());
    }
    if (widget.active &&
        (!oldWidget.enabled ||
            !oldWidget.active ||
            widget.entryEpoch != oldWidget.entryEpoch)) {
      _check(widget.entryEpoch);
    }
  }

  void _reportBlocking() {
    if (mounted) widget.onBlockingChanged(_blocking);
  }

  Future<void> _check(int epoch) async {
    final serial = ++_requestSerial;
    setState(() {
      _phase = _GatePhase.checking;
      _error = null;
      _acting = false;
    });
    _reportBlocking();
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      if (mounted) _setError('Sign in again to check invitations.');
      return;
    }
    try {
      final data = await widget.backendApiService.fetchRaces(
        identityToken: token,
      );
      if (!mounted || serial != _requestSerial || epoch != widget.entryEpoch) {
        return;
      }
      widget.onVerifiedData(data);
      final queue = _orderedQueue(data);
      setState(() {
        _queue = queue;
        _phase = queue.isEmpty ? _GatePhase.open : _GatePhase.decision;
      });
      _reportBlocking();
    } catch (_) {
      if (!mounted || serial != _requestSerial || epoch != widget.entryEpoch) {
        return;
      }
      _setError(
        'Couldn’t check invitations. You’re still safely outside Races.',
      );
    }
  }

  List<_InviteDecision> _orderedQueue(Map<String, dynamic> data) {
    final tournaments = <_InviteDecision>[];
    final seenTournamentIds = <String>{};
    final rawTournaments = data['tournaments'];
    if (rawTournaments is List) {
      for (final raw in rawTournaments) {
        if (raw is! Map) continue;
        final row = _safeRow(raw);
        final id = row['id'];
        if (Tournament.myStatus(row) == 'INVITED' &&
            id is String &&
            id.isNotEmpty &&
            seenTournamentIds.add(id)) {
          tournaments.add(_InviteDecision(isTournament: true, data: row));
        }
      }
    }
    final races = <_InviteDecision>[];
    final seenRaceIds = <String>{};
    for (final section in [data['pending'], data['active']]) {
      if (section is List) {
        for (final raw in section) {
          if (raw is! Map) continue;
          final row = _safeRow(raw);
          final id = row['id'];
          if (row['myStatus'] == 'INVITED' &&
              id is String &&
              id.isNotEmpty &&
              seenRaceIds.add(id)) {
            races.add(_InviteDecision(isTournament: false, data: row));
          }
        }
      }
    }
    int compare(_InviteDecision a, _InviteDecision b) {
      final at = a.sortTime;
      final bt = b.sortTime;
      if (at != null && bt != null) {
        final value = at.compareTo(bt);
        if (value != 0) return value;
      } else if (at == null && bt != null) {
        return 1;
      } else if (at != null && bt == null) {
        return -1;
      }
      return a.id.compareTo(b.id);
    }

    tournaments.sort(compare);
    races.sort(compare);
    return [...tournaments, ...races];
  }

  Map<String, dynamic> _safeRow(Map<dynamic, dynamic> raw) => {
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };

  void _setError(String message) {
    setState(() {
      _phase = _GatePhase.error;
      _error = message;
      _acting = false;
      _accepting = null;
    });
    _reportBlocking();
  }

  void _setDecisionError(String message) {
    setState(() {
      _phase = _GatePhase.decision;
      _error = message;
      _acting = false;
      _accepting = null;
    });
    _reportBlocking();
  }

  Future<void> _respond(bool accept) async {
    if (_acting || _queue.isEmpty) return;
    final decision = _queue.first;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      _setDecisionError('Sign in again to answer this invitation.');
      return;
    }
    setState(() {
      _acting = true;
      _accepting = accept;
      _error = null;
    });
    try {
      if (decision.isTournament) {
        await widget.backendApiService.respondToTournamentInvite(
          identityToken: token,
          tournamentId: decision.id,
          accept: accept,
        );
      } else {
        await widget.backendApiService.respondToRaceInvite(
          identityToken: token,
          raceId: decision.id,
          accept: accept,
        );
      }
      await _check(widget.entryEpoch);
    } on ApiException catch (error) {
      final answeredElsewhere =
          (error.statusCode == 400 || error.statusCode == 409) &&
          error.code == 'ALREADY_RESPONDED';
      if (answeredElsewhere) {
        await _check(widget.entryEpoch);
        return;
      }
      if (mounted) _setDecisionError(error.message);
    } catch (_) {
      if (mounted) {
        _setDecisionError('Couldn’t answer. Check your connection and retry.');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled || _phase == _GatePhase.open) return widget.child;
    return PopScope(
      canPop: false,
      child: Stack(
        fit: StackFit.expand,
        children: [
          ExcludeSemantics(
            child: ColoredBox(
              color: AppColors.of(context).roofLight,
              child: CustomPaint(
                painter: const ArcadeCheckerPainter(drawBottomStripe: false),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.all(20),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 440),
                  child: _phase == _GatePhase.decision && _queue.isNotEmpty
                      ? _decisionCard(_queue.first)
                      : _statusCard(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _statusCard() {
    final checking =
        _phase == _GatePhase.checking || _phase == _GatePhase.unverified;
    return _card(
      key: const Key('races-invite-gate-status'),
      children: [
        if (checking)
          const SizedBox.square(
            dimension: 28,
            child: CircularProgressIndicator(strokeWidth: 3),
          )
        else
          Icon(Icons.wifi_off_rounded, color: AppColors.of(context).error),
        const SizedBox(height: 14),
        Text(
          checking ? 'CHECKING THE START LINE' : 'RACES ARE STILL LOCKED',
          textAlign: TextAlign.center,
          style: PixelText.title(
            size: 17,
            color: AppColors.of(context).textDark,
          ),
        ),
        if (!checking) ...[
          const SizedBox(height: 8),
          Text(
            _error ?? 'Couldn’t verify invitations.',
            textAlign: TextAlign.center,
            style: PixelText.body(
              size: 13,
              color: AppColors.of(context).textMid,
            ),
          ),
          const SizedBox(height: 16),
          PillButton(
            key: const Key('races-gate-retry'),
            label: 'RETRY',
            variant: PillButtonVariant.decision,
            fullWidth: true,
            onPressed: () => _check(widget.entryEpoch),
          ),
          const SizedBox(height: 10),
          PillButton(
            key: const Key('races-gate-home'),
            label: 'BACK TO HOME',
            variant: PillButtonVariant.destructive,
            fullWidth: true,
            onPressed: widget.onExitHome,
          ),
        ],
      ],
    );
  }

  Widget _decisionCard(_InviteDecision decision) {
    final data = decision.data;
    final creator = data['creator'];
    final creatorName = creator is Map && creator['displayName'] is String
        ? creator['displayName'] as String
        : 'A runner';
    final name = data['name'] is String
        ? data['name'] as String
        : decision.isTournament
        ? 'Tournament invitation'
        : 'Race invitation';
    final durationValue = decision.isTournament
        ? data['matchupDurationDays']
        : data['maxDurationDays'];
    final days = durationValue is num ? durationValue.toInt() : null;
    final buyIn = data['buyInAmount'] is num
        ? (data['buyInAmount'] as num).toInt()
        : 0;
    final team = !decision.isTournament && TeamRace.isTeamRace(data);
    return _card(
      key: const Key('races-invite-decision'),
      children: [
        Text(
          decision.isTournament ? 'BRACKET INVITE' : 'RACE INVITE',
          style: PixelText.title(
            size: 11,
            color: AppColors.of(context).coinDark,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          name,
          textAlign: TextAlign.center,
          style: PixelText.title(
            size: 20,
            color: AppColors.of(context).textDark,
          ),
        ),
        const SizedBox(height: 7),
        Text(
          'Invited by @$creatorName',
          textAlign: TextAlign.center,
          style: PixelText.body(size: 13, color: AppColors.of(context).textMid),
        ),
        const SizedBox(height: 12),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: 8,
          runSpacing: 6,
          children: [
            if (days != null) _fact('$days ${days == 1 ? 'DAY' : 'DAYS'}'),
            if (data['status'] == 'ACTIVE') _fact('UNDERWAY'),
            if (team) _fact('TEAM AUTO-ASSIGN'),
            if (buyIn > 0) _fact('$buyIn GOLD'),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: 10),
          Text(
            _error!,
            textAlign: TextAlign.center,
            style: PixelText.body(size: 12, color: AppColors.of(context).error),
          ),
          const SizedBox(height: 8),
          PillButton(
            key: const Key('races-gate-answer-retry'),
            label: 'RETRY CHECK',
            variant: PillButtonVariant.secondary,
            fullWidth: true,
            fontSize: 11,
            onPressed: _acting ? null : () => _check(widget.entryEpoch),
          ),
          const SizedBox(height: 8),
          PillButton(
            key: const Key('races-gate-answer-home'),
            label: 'BACK TO HOME',
            variant: PillButtonVariant.destructive,
            fullWidth: true,
            fontSize: 11,
            onPressed: _acting ? null : widget.onExitHome,
          ),
        ],
        const SizedBox(height: 18),
        Row(
          children: [
            Expanded(
              child: PillButton(
                key: const Key('races-gate-accept'),
                label: _acting && _accepting == true
                    ? 'JOINING…'
                    : buyIn > 0
                    ? 'ACCEPT · $buyIn'
                    : 'ACCEPT',
                leading: buyIn > 0 ? const SpinningCoin(size: 14) : null,
                variant: PillButtonVariant.decision,
                fullWidth: true,
                fontSize: 12,
                loading: _acting && _accepting == true,
                onPressed: _acting ? null : () => _respond(true),
              ),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: PillButton(
                key: const Key('races-gate-decline'),
                label: _acting && _accepting == false
                    ? 'DECLINING…'
                    : 'DECLINE',
                variant: PillButtonVariant.destructive,
                fullWidth: true,
                fontSize: 12,
                loading: _acting && _accepting == false,
                onPressed: _acting ? null : () => _respond(false),
              ),
            ),
          ],
        ),
      ],
    );
  }

  Widget _fact(String label) => Container(
    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
    decoration: BoxDecoration(
      color: AppColors.of(context).parchmentDark,
      borderRadius: BorderRadius.circular(5),
    ),
    child: Text(
      label,
      style: PixelText.title(size: 9, color: AppColors.of(context).textMid),
    ),
  );

  Widget _card({required Key key, required List<Widget> children}) => Container(
    key: key,
    padding: const EdgeInsets.fromLTRB(20, 22, 20, 20),
    decoration: BoxDecoration(
      color: AppColors.of(context).parchment,
      borderRadius: BorderRadius.circular(14),
      border: Border.all(
        color: AppColors.of(context).parchmentBorder,
        width: 2,
      ),
      boxShadow: [
        BoxShadow(
          color: AppColors.of(context).woodDarker.withValues(alpha: 0.55),
          offset: const Offset(0, 6),
        ),
      ],
    ),
    child: Column(mainAxisSize: MainAxisSize.min, children: children),
  );
}
