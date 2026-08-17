import 'package:flutter/material.dart';

import '../models/race_payouts.dart';
import '../models/race_prize_pool.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/team_race.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/powerup_interval_note.dart';
import '../widgets/prize_pool_plaque.dart';
import '../widgets/race_timeline_card.dart';
import '../widgets/retro_card.dart';

/// Full-screen editor for race settings. Available only to the creator while
/// the race is still PENDING. Mirrors [CreateRaceScreen] but pre-populates
/// from the race detail and PATCHes the changed fields.
class EditRaceScreen extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;
  final String raceId;
  final Map<String, dynamic> race;

  /// True field sizes, passed in by the parent screen rather than re-derived
  /// here. [race] may carry only a PAGE of `participants` (race-details
  /// participants pagination), and counting that page would let the creator
  /// set `maxParticipants`/`teamSize` BELOW the real field. Null => no count
  /// was available, so the legacy array scan below is used.
  final int? acceptedCount;
  final int? teamAAcceptedCount;
  final int? teamBAcceptedCount;

  EditRaceScreen({
    super.key,
    required this.authService,
    required this.raceId,
    required this.race,
    this.acceptedCount,
    this.teamAAcceptedCount,
    this.teamBAcceptedCount,
    BackendApiService? backendApiService,
  }) : backendApiService = backendApiService ?? BackendApiService();

  @override
  State<EditRaceScreen> createState() => EditRaceScreenState();
}

class EditRaceScreenState extends State<EditRaceScreen> {
  late final TextEditingController _nameController;

  bool _isSaving = false;

  // Initial values (used to compute "changed" diff for PATCH)
  late final String _initialName;
  late final int _initialMaxDurationDays;
  late final bool _initialPowerupsEnabled;

  /// The race's own spacing, read once for display only. Never sent back: the
  /// interval is fixed at 2,000 for new races and frozen for existing ones.
  late final int _storedPowerupInterval;
  late final String _initialPayoutPreset;
  late final bool _initialIsPublic;
  // null => no participant limit (unlimited).
  late final int? _initialMaxParticipants;

  // Live values
  late int _maxDurationDays;
  late bool _powerupsEnabled;
  late String _payoutPreset;
  late bool _isPublic;
  // null => no participant limit (unlimited).
  late int? _maxParticipants;

  // Issue 4: the buy-in stays EDITABLE while PENDING even when runners have
  // paid in (raise / lower / toggle paid<->free); the backend reconciles
  // refunds and re-charges. The consequence warning shows whenever there are
  // accepted runners to reconcile. A raise nobody can afford is blocked
  // server-side (BUYIN_UNAFFORDABLE), naming the offending player.
  late final int _acceptedCount;

  // TR-105: team names + size are editable while PENDING. `isTeamRace` itself
  // is immutable, so it's read once and never offered as a control.
  late final bool _isTeamRace;
  late final String _initialTeamAName;
  late final String _initialTeamBName;
  late final int _initialTeamSize;
  late final TextEditingController _teamANameController;
  late final TextEditingController _teamBNameController;
  late int _teamSize;
  // Accepted members per side — a shrink below either is rejected (TR-105).
  late final int _teamACount;
  late final int _teamBCount;

  // Race timeline options. The window is editable only while PENDING: a
  // started race's end is stamped into `endsAt` and the server answers any
  // edit with 400 RACE_ALREADY_STARTED, so the card renders read-only instead
  // of offering a control that cannot work.
  late final bool _isPending;
  late final DateTime? _stampedEndsAt;
  late final DateTime? _initialScheduledStartAt;
  late final DateTime? _initialScheduledEndAt;
  late DateTime? _scheduledStartAt;
  late DateTime? _scheduledEndAt;
  late bool _customSelected;
  late final bool _initialCustomSelected;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  // The preset chips live in `widgets/race_timeline_card.dart`
  // (kRaceTimelinePresets), shared with the create screen so they can't drift.
  static const _maxParticipantsPresets = [5, 10, 25, 50, 100];

  @override
  void initState() {
    super.initState();
    final race = widget.race;

    _initialName = (race['name'] as String?) ?? '';
    _initialMaxDurationDays = _readInt(race['maxDurationDays'], 7);
    _initialPowerupsEnabled = race['powerupsEnabled'] == true;
    // Defensive read: a missing, null, or nonsense interval falls back to the
    // fixed 2,000 rather than throwing or rendering "null" (spec §7.3).
    final storedInterval = _readInt(
      race['powerupStepInterval'],
      kFixedPowerupStepInterval,
    );
    _storedPowerupInterval = storedInterval > 0
        ? storedInterval
        : kFixedPowerupStepInterval;
    _initialPayoutPreset =
        (race['payoutPreset'] as String?) ?? 'WINNER_TAKES_ALL';
    _initialIsPublic = race['isPublic'] == true;
    _initialMaxParticipants = _readNullableMax(race['maxParticipants']);

    final participants =
        (race['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    // Prefer the counts handed down by the parent (or, failing that, the
    // additive summary fields on the payload itself). The array is only a page
    // once the backend pages this route, so scanning it is the last resort.
    _acceptedCount =
        widget.acceptedCount ??
        _readNullableCount(race['acceptedCount']) ??
        participants.where((p) => p['status'] == 'ACCEPTED').length;
    _isTeamRace = TeamRace.isTeamRace(race);
    _initialTeamAName = TeamRace.teamName(race, RaceTeam.teamA);
    _initialTeamBName = TeamRace.teamName(race, RaceTeam.teamB);
    _initialTeamSize = (TeamRace.teamSize(race) ?? 1).clamp(1, 5);
    _teamSize = _initialTeamSize;
    _teamANameController = TextEditingController(text: _initialTeamAName);
    _teamBNameController = TextEditingController(text: _initialTeamBName);
    _teamACount =
        widget.teamAAcceptedCount ??
        _readNullableCount(race['teamAAcceptedCount']) ??
        participants
            .where(
              (p) =>
                  p['status'] == 'ACCEPTED' &&
                  TeamRace.participantTeam(p) == RaceTeam.teamA,
            )
            .length;
    _teamBCount =
        widget.teamBAcceptedCount ??
        _readNullableCount(race['teamBAcceptedCount']) ??
        participants
            .where(
              (p) =>
                  p['status'] == 'ACCEPTED' &&
                  TeamRace.participantTeam(p) == RaceTeam.teamB,
            )
            .length;

    _nameController = TextEditingController(text: _initialName);

    // Timeline. Every read is defensive: `scheduledStartAt`/`scheduledEndAt`
    // are additive keys a backend older than this build simply omits, in which
    // case the screen behaves exactly as it does today (preset chips only).
    final status = race['status'];
    // Absent/garbled status reads as NOT pending: the server rejects a window
    // edit on anything else, so read-only is the safe default.
    _isPending = status is String && status.toUpperCase() == 'PENDING';
    _stampedEndsAt = _readInstant(race['endsAt']);
    _initialScheduledStartAt = _readInstant(race['scheduledStartAt']);
    _initialScheduledEndAt = _readInstant(race['scheduledEndAt']);
    _scheduledStartAt = _initialScheduledStartAt;
    _scheduledEndAt = _initialScheduledEndAt;
    _initialCustomSelected = _initialScheduledEndAt != null;
    _customSelected = _initialCustomSelected;

    _maxDurationDays = _initialMaxDurationDays;
    _powerupsEnabled = _initialPowerupsEnabled;
    _payoutPreset = _initialPayoutPreset;
    _isPublic = _initialIsPublic;
    _maxParticipants = _initialMaxParticipants;
  }

  /// What the note says this race's spacing is. A race that already runs
  /// powerups keeps its own stored interval — a grandfathered 5,000-step race
  /// says 5,000, not 2,000. Switching powerups on now starts the race from
  /// nothing, so it gets the fixed 2,000.
  int get _displayedPowerupInterval => _initialPowerupsEnabled
      ? _storedPowerupInterval
      : kFixedPowerupStepInterval;

  Widget _maxRunnersChip({
    required String label,
    required bool selected,
    required bool disabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: disabled ? null : onTap,
      child: Opacity(
        opacity: disabled ? 0.4 : 1.0,
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
          decoration: BoxDecoration(
            color: selected
                ? AppColors.of(context).pillGreenDark
                : AppColors.of(context).parchmentDark,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: PixelText.title(
              size: 13,
              color: selected ? Colors.white : AppColors.of(context).textDark,
            ),
          ),
        ),
      ),
    );
  }

  /// Who can join — the same two-segment control the create screen uses. The
  /// old single switch flipped its own label (PRIVATE RACE / PUBLIC RACE), so
  /// an off switch next to the word "PRIVATE" read as "private is off" and
  /// people set the opposite of what they meant. Both options are named at
  /// once; only the selection moves.
  Widget _buildVisibilityPicker() {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'WHO CAN JOIN',
          style: PixelText.title(
            size: 13,
            color: AppColors.of(context).textMid,
          ),
        ),
        const SizedBox(height: 10),
        Container(
          padding: const EdgeInsets.all(4),
          decoration: BoxDecoration(
            color: AppColors.of(context).parchmentDark,
            borderRadius: BorderRadius.circular(12),
            border: Border.all(
              color: AppColors.of(context).parchmentBorder,
              width: 2,
            ),
          ),
          child: Row(
            children: [
              _visibilitySegment(
                key: const Key('race-visibility-private'),
                label: 'PRIVATE',
                icon: Icons.lock_rounded,
                selected: !_isPublic,
                onTap: () => setState(() => _isPublic = false),
              ),
              const SizedBox(width: 4),
              _visibilitySegment(
                key: const Key('race-visibility-public'),
                label: 'PUBLIC',
                icon: Icons.public_rounded,
                selected: _isPublic,
                onTap: () => setState(() => _isPublic = true),
              ),
            ],
          ),
        ),
        const SizedBox(height: 8),
        Text(
          _isPublic ? 'ANYONE CAN JOIN' : 'INVITE ONLY',
          key: const Key('race-visibility-subcopy'),
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
      ],
    );
  }

  /// One carved segment, matching the create screen's RACE FORMAT signpost.
  Widget _visibilitySegment({
    required Key key,
    required String label,
    required IconData icon,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return Expanded(
      child: GestureDetector(
        key: key,
        onTap: onTap,
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          curve: Curves.easeOut,
          padding: const EdgeInsets.symmetric(vertical: 10),
          decoration: BoxDecoration(
            gradient: selected
                ? LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      AppColors.of(context).roofLight,
                      AppColors.of(context).roofMid,
                    ],
                  )
                : null,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? AppColors.of(context).roofDark
                  : Colors.transparent,
              width: 2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.of(context).roofDark,
                      offset: const Offset(0, 2),
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 15,
                color: selected ? Colors.white : AppColors.of(context).textMid,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(
                  label,
                  maxLines: 1,
                  softWrap: false,
                  overflow: TextOverflow.fade,
                  style: PixelText.title(
                    size: 11.5,
                    color: selected
                        ? Colors.white
                        : AppColors.of(context).textMid,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// TR-105: the PENDING team-race editor — the two team-name plaques and
  /// the carved size stepper, matching the create flow's signpost language.
  Widget _buildTeamCard() {
    return RetroCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'TEAMS',
            style: PixelText.title(
              size: 13,
              color: AppColors.of(context).textMid,
            ),
          ),
          const SizedBox(height: 10),
          _buildTeamSizeStepper(),
          const SizedBox(height: 14),
          Text(
            'TEAM NAMES',
            style: PixelText.body(
              size: 11,
              color: AppColors.of(context).textMid,
            ),
          ),
          const SizedBox(height: 8),
          _teamNamePlaque(
            key: const Key('edit-team-plaque-a'),
            team: RaceTeam.teamA,
            controller: _teamANameController,
          ),
          const SizedBox(height: 8),
          _teamNamePlaque(
            key: const Key('edit-team-plaque-b'),
            team: RaceTeam.teamB,
            controller: _teamBNameController,
          ),
          if (_teamACount > 0 || _teamBCount > 0) ...[
            const SizedBox(height: 8),
            Text(
              '$_teamACount on ${_teamANameController.text.trim()}, '
              '$_teamBCount on ${_teamBNameController.text.trim()} already.',
              style: PixelText.body(
                size: 11,
                color: AppColors.of(context).textMid,
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildTeamSizeStepper() {
    // Can't shrink below whichever side is fuller (TR-105).
    final floor = _teamACount > _teamBCount ? _teamACount : _teamBCount;
    return Container(
      key: const Key('edit-team-size-stepper'),
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.of(context).parchmentBorder,
          width: 2,
        ),
      ),
      child: Row(
        children: [
          _teamStepperButton(
            key: const Key('edit-team-size-minus'),
            icon: Icons.remove_rounded,
            enabled: _teamSize > 1,
            onTap: () =>
                setState(() => _teamSize = (_teamSize - 1).clamp(1, 5)),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${_teamSize}v$_teamSize',
                  style: PixelText.number(
                    size: 30,
                    color: AppColors.of(context).textDark,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  _teamSize < floor
                      ? 'TOO SMALL. $floor ALREADY IN'
                      : '${_teamSize * 2} RACERS MAX',
                  style: PixelText.body(
                    size: 10,
                    color: _teamSize < floor
                        ? AppColors.of(context).error
                        : AppColors.of(context).textMid,
                  ),
                ),
              ],
            ),
          ),
          _teamStepperButton(
            key: const Key('edit-team-size-plus'),
            icon: Icons.add_rounded,
            enabled: _teamSize < 5,
            onTap: () =>
                setState(() => _teamSize = (_teamSize + 1).clamp(1, 5)),
          ),
        ],
      ),
    );
  }

  Widget _teamStepperButton({
    required Key key,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: enabled ? onTap : null,
      child: Opacity(
        opacity: enabled ? 1 : 0.35,
        child: Container(
          width: 44,
          height: 44,
          decoration: BoxDecoration(
            gradient: LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [
                AppColors.of(context).buttonLight,
                AppColors.of(context).buttonFace,
              ],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(
              color: AppColors.of(context).buttonDark,
              width: 2.5,
            ),
            boxShadow: [
              BoxShadow(
                color: AppColors.of(context).buttonShadow,
                offset: Offset(0, 3),
                blurRadius: 0,
              ),
            ],
          ),
          child: Icon(icon, size: 26, color: Colors.white),
        ),
      ),
    );
  }

  Widget _teamNamePlaque({
    required Key key,
    required RaceTeam team,
    required TextEditingController controller,
  }) {
    final color = TeamRace.color(team, context);
    final colorLight = TeamRace.colorLight(team, context);
    final colorDark = TeamRace.colorDark(team, context);
    return Container(
      key: key,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
          colors: [colorLight, color],
        ),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: colorDark, width: 2.5),
        boxShadow: [
          BoxShadow(
            color: colorDark,
            offset: const Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Row(
        children: [
          Icon(
            Icons.flag_rounded,
            size: 16,
            color: Colors.white.withValues(alpha: 0.9),
          ),
          const SizedBox(width: 8),
          Expanded(
            child: TextField(
              controller: controller,
              maxLength: 24,
              onChanged: (_) => setState(() {}),
              style: PixelText.title(size: 14, color: Colors.white),
              cursorColor: Colors.white,
              decoration: InputDecoration(
                counterText: '',
                border: InputBorder.none,
                isDense: true,
                contentPadding: EdgeInsets.zero,
                hintText: team == RaceTeam.teamA ? 'Team A' : 'Team B',
                hintStyle: PixelText.title(
                  size: 14,
                  color: Colors.white.withValues(alpha: 0.5),
                ),
              ),
            ),
          ),
          Icon(
            Icons.edit_outlined,
            size: 14,
            color: Colors.white.withValues(alpha: 0.7),
          ),
        ],
      ),
    );
  }

  int _readInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  /// Reads an additive count field: absent, null, negative or non-numeric all
  /// degrade to null so the caller falls through to its own fallback.
  int? _readNullableCount(dynamic value) {
    final int? parsed = value is int
        ? value
        : value is num
        ? value.toInt()
        : value is String
        ? int.tryParse(value)
        : null;
    if (parsed == null || parsed < 0) return null;
    return parsed;
  }

  /// Reads an ISO-8601 instant from a payload. Absent, null, non-string or
  /// unparseable all degrade to null — never a throw, never a crash on a
  /// backend that is a different version than this build expects.
  DateTime? _readInstant(dynamic value) {
    if (value is! String || value.isEmpty) return null;
    return DateTime.tryParse(value)?.toLocal();
  }

  /// Whether the CUSTOM chip is offered (`featureFlags.customRaceWindowEnabled`,
  /// default false). A race that ALREADY has a custom window still shows it
  /// with the flag off — hiding the chip would silently misreport the race.
  bool get _customWindowAvailable =>
      widget.authService.customRaceWindowEnabled;

  /// Read-only means DEAD END, and only a started race is one: the server
  /// rejects every field of a non-PENDING edit with a 400, so no chip on the
  /// card could do anything.
  ///
  /// The kill switch deliberately does NOT land here. With
  /// `customRaceWindowEnabled` off the server still accepts
  /// `scheduledEndAt: null` — clearing a window stays available so a creator is
  /// never stranded holding one the server no longer honors. Only SETTING a
  /// window is killed, so the CUSTOM chip goes and the presets stay live.
  bool get _timelineReadOnly => !_isPending;

  DateTime get _effectiveWindowStart => _scheduledStartAt ?? DateTime.now();

  /// Whether the user actually MOVED either end of the window in this session.
  ///
  /// This is the client twin of the backend's architect-R3 rule
  /// (`editRace.js:258` gates validation on `startProvided || endProvided`).
  /// `_effectiveWindowStart` falls back to `now` on a manual-start race, so a
  /// stored window shrinks in real time; once its end is under 24h out, an
  /// untouched window is permanently "invalid". Gating the SAVE button on that
  /// would lock the creator out of renaming their own race, changing the runner
  /// cap, powerups or the payout — over a field they never touched.
  bool get _windowMoved =>
      _scheduledEndAt != _initialScheduledEndAt ||
      _scheduledStartAt != _initialScheduledStartAt;

  /// The window error, but only where it should BLOCK a save: the user moved
  /// the window and it is now illegal. The message itself still renders
  /// unconditionally — a stale window is worth telling the user about, it just
  /// must not hold their other edits hostage.
  String? get _blockingWindowError => _windowMoved ? _customWindowError : null;

  /// The same four rules the server enforces, mirrored so SAVE never
  /// round-trips to a 400 (spec §4.4).
  String? get _customWindowError {
    // Nothing to validate when the window cannot be edited: a started race, or
    // the kill switch being off. Blocking SAVE on an untouchable window would
    // strand every OTHER edit (a rename, the runner cap) behind it.
    if (!_customSelected || _timelineReadOnly || !_customWindowAvailable) {
      return null;
    }
    final end = _scheduledEndAt;
    if (end == null) return 'Pick an end date and time';
    final start = _effectiveWindowStart;
    if (!end.isAfter(start)) return 'The end has to be after the start';
    if (!end.isAfter(DateTime.now())) return 'Pick an end time in the future';
    final window = end.difference(start);
    if (window < const Duration(days: 1)) {
      return 'A race has to run at least 1 day';
    }
    if (window > const Duration(days: 30)) {
      return 'A race can run at most 30 days';
    }
    return null;
  }

  /// The day count the pool is priced on — the server's own derivation for a
  /// custom window, so the plaque matches the race that comes back.
  int get _pricedDurationDays {
    if (_customSelected && _scheduledEndAt != null) {
      return prizePoolDurationDaysForWindow(
        _effectiveWindowStart,
        _scheduledEndAt!,
      );
    }
    return _maxDurationDays;
  }

  int? get _projectedFieldSize {
    if (_isTeamRace) return _teamSize * 2;
    return _maxParticipants;
  }

  /// Test-only hook: moves the window without driving the platform pickers.
  @visibleForTesting
  void debugSetCustomWindow({DateTime? start, DateTime? end}) {
    setState(() {
      _customSelected = true;
      if (start != null) _scheduledStartAt = start;
      if (end != null) _scheduledEndAt = end;
    });
  }

  void _selectCustomTimeline() {
    setState(() {
      _customSelected = true;
      // Rounded UP (see the create screen): truncating shaves minutes off a
      // 1-day seed and lands under the 24h floor immediately.
      _scheduledEndAt ??= _ceilToHour(
        _effectiveWindowStart.add(Duration(days: _maxDurationDays)),
      );
    });
  }

  /// Tapping a preset replaces a custom window. The clear is sent EXPLICITLY on
  /// save rather than relying on the server's implicit
  /// "maxDurationDays without scheduledEndAt clears it" rule (spec §6).
  void _selectPresetTimeline(int days) {
    setState(() {
      _customSelected = false;
      _maxDurationDays = days;
      _scheduledEndAt = null;
    });
  }

  static DateTime _ceilToHour(DateTime t) {
    final floored = DateTime(t.year, t.month, t.day, t.hour);
    return floored == t ? floored : floored.add(const Duration(hours: 1));
  }

  /// Reads maxParticipants where a null/absent value means "no limit"
  /// (unlimited). Defensive: a newer backend serializes unlimited races as null.
  int? _readNullableMax(dynamic value) {
    if (value == null) return null;
    return _readInt(value, 10);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _teamANameController.dispose();
    _teamBNameController.dispose();
    super.dispose();
  }

  /// The same "up to" plaque the create screen shows, brought along so a
  /// control that changes the pool also shows the pool (§10.1 risk 6).
  Widget _buildPrizePoolPreview() {
    final field = _projectedFieldSize;
    final coins = field == null
        ? kPrizePoolMaxCoins
        : computePrizePool(
            playerCount: field,
            durationDays: _pricedDurationDays,
          );
    if (coins <= 0) return const SizedBox.shrink();
    final priced = _pricedDurationDays;
    final days = priced == 1 ? '1 DAY' : '$priced DAYS';
    final players = field == null
        ? 'UNLIMITED PLAYERS'
        : (field == 1 ? '1 PLAYER' : '$field PLAYERS');
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RetroCard(
        padding: const EdgeInsets.all(16),
        child: PrizePoolPlaque(
          key: const Key('edit-prize-pool-preview'),
          coinsKey: const Key('edit-prize-pool-coins'),
          derivationKey: const Key('edit-prize-pool-derivation'),
          maxKey: const Key('edit-prize-pool-max'),
          coins: coins,
          atMax: coins >= kPrizePoolMaxCoins,
          derivation: '$players × $days',
        ),
      ),
    );
  }

  Future<void> _pickScheduledStart() async {
    final now = DateTime.now();
    final initial = _scheduledStartAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: raceThemedPickerBuilder,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: raceThemedPickerBuilder,
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    if (picked.isAfter(DateTime.now())) {
      setState(() => _scheduledStartAt = picked);
    } else if (mounted) {
      showErrorToast(context, 'Pick a time in the future');
    }
  }

  Future<void> _pickCustomEnd() async {
    final now = DateTime.now();
    // A PENDING race's scheduledStartAt can already be in the past (the cron
    // retries a race that never reached two accepted runners). An unclamped
    // anchor gives showDatePicker firstDate > lastDate, which asserts.
    final rawStart = _effectiveWindowStart;
    final windowStart = rawStart.isBefore(now) ? now : rawStart;
    // Ceil an hour past the 24h floor — see the create screen: `start + 24h`
    // exactly is not `> 24h`, so an unbuffered default is illegal the moment
    // it is accepted.
    final earliest = _ceilToHour(
      windowStart.add(const Duration(days: 1, hours: 1)),
    );
    final stored = _scheduledEndAt;
    final initial = (stored == null || stored.isBefore(earliest))
        ? earliest
        : stored;
    final date = await showDatePicker(
      context: context,
      initialDate: initial,
      firstDate: earliest,
      lastDate: windowStart.add(const Duration(days: 30)),
      builder: raceThemedPickerBuilder,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: raceThemedPickerBuilder,
    );
    if (time == null || !mounted) return;
    setState(() {
      _scheduledEndAt = DateTime(
        date.year,
        date.month,
        date.day,
        time.hour,
        time.minute,
      );
    });
  }

  bool get _hasChanges {
    final name = _nameController.text.trim();
    if (name != _initialName.trim()) return true;
    if (_maxDurationDays != _initialMaxDurationDays) return true;
    if (_powerupsEnabled != _initialPowerupsEnabled) return true;
    if (_isPublic != _initialIsPublic) return true;
    if (_maxParticipants != _initialMaxParticipants) return true;
    if (_isTeamRace) {
      if (_teamANameController.text.trim() != _initialTeamAName.trim()) {
        return true;
      }
      if (_teamBNameController.text.trim() != _initialTeamBName.trim()) {
        return true;
      }
      if (_teamSize != _initialTeamSize) return true;
    }

    if (_payoutPreset != _initialPayoutPreset) return true;

    // Timeline: switching between a custom window and a preset counts, and so
    // does moving either end of an existing window.
    if (_customSelected != _initialCustomSelected) return true;
    if (_customSelected) {
      if (_scheduledEndAt != _initialScheduledEndAt) return true;
      if (_scheduledStartAt != _initialScheduledStartAt) return true;
    }

    return false;
  }

  Future<void> _save() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showErrorToast(context, 'Enter a race name');
      return;
    }
    if (name.length > 50) {
      showErrorToast(context, 'Race name must be 50 characters or less');
      return;
    }

    if (_maxDurationDays < 1 || _maxDurationDays > 30) {
      showErrorToast(context, 'Duration must be between 1 and 30 days');
      return;
    }

    if (!_isTeamRace &&
        _maxParticipants != null &&
        _maxParticipants! < _acceptedCount) {
      showErrorToast(
        context,
        'Cannot reduce max runners below $_acceptedCount accepted',
      );
      return;
    }

    // TR-105 team edits: names must be present and distinct; the size can't
    // shrink below either side's accepted member count (server also answers
    // TEAM_SIZE_TOO_SMALL / TEAM_NAMES_IDENTICAL).
    var teamAName = '';
    var teamBName = '';
    if (_isTeamRace) {
      teamAName = _teamANameController.text.trim();
      teamBName = _teamBNameController.text.trim();
      if (teamAName.isEmpty || teamBName.isEmpty) {
        showErrorToast(context, 'Give both teams a name');
        return;
      }
      if (teamAName.toLowerCase() == teamBName.toLowerCase()) {
        showErrorToast(context, teamRaceErrorCopy('TEAM_NAMES_IDENTICAL'));
        return;
      }
      if (_teamSize < _teamACount || _teamSize < _teamBCount) {
        showErrorToast(context, teamRaceErrorCopy('TEAM_SIZE_TOO_SMALL'));
        return;
      }
    }

    // Build a sparse PATCH body — only send changed fields.
    final updates = <String, dynamic>{};
    if (name != _initialName.trim()) updates['name'] = name;
    if (_maxDurationDays != _initialMaxDurationDays) {
      updates['maxDurationDays'] = _maxDurationDays;
    }
    if (_powerupsEnabled != _initialPowerupsEnabled) {
      updates['powerupsEnabled'] = _powerupsEnabled;
    }
    // powerupStepInterval is deliberately never sent (spec §4.3): lowering a
    // running race's interval back-mints every box the tighter spacing says the
    // runner should already have earned.
    if (_isPublic != _initialIsPublic) updates['isPublic'] = _isPublic;
    // maxParticipants is derived (2 x teamSize) for team races — never sent.
    if (!_isTeamRace && _maxParticipants != _initialMaxParticipants) {
      updates['maxParticipants'] = _maxParticipants;
    }
    if (_isTeamRace) {
      if (teamAName != _initialTeamAName.trim()) {
        updates['teamAName'] = teamAName;
      }
      if (teamBName != _initialTeamBName.trim()) {
        updates['teamBName'] = teamBName;
      }
      if (_teamSize != _initialTeamSize) updates['teamSize'] = _teamSize;
    }

    // No buy-in field is ever sent: entry is free and the pool is app-funded.
    if (_payoutPreset != _initialPayoutPreset) {
      updates['payoutPreset'] = _payoutPreset;
    }

    // Timeline (spec §5.2 / §6). PENDING only — a started race's window is
    // history and the server rejects the edit outright.
    if (!_timelineReadOnly) {
      // Setting or moving a window requires the flag; CLEARING one does not.
      // Validation runs only when a window field actually moved — never on a
      // PATCH that just renames the race (architect R3, mirrored).
      if (_customSelected && _customWindowAvailable && _windowMoved) {
        final windowError = _customWindowError;
        if (windowError != null) {
          showErrorToast(context, windowError);
          return;
        }
        if (_scheduledEndAt != _initialScheduledEndAt) {
          updates['scheduledEndAt'] = _scheduledEndAt;
        }
        // Only ever a real instant. `scheduledStartAt: null` is answered with
        // 400 SCHEDULED_START_NOT_CLEARABLE, so it is never sent — clearing a
        // schedule would mean "start within 5 minutes", not "start manually".
        if (_scheduledStartAt != null &&
            _scheduledStartAt != _initialScheduledStartAt) {
          updates['scheduledStartAt'] = _scheduledStartAt;
        }
      } else if (!_customSelected && _initialCustomSelected) {
        // Guarded on the user actually LEAVING custom, not just on the branch
        // above being skipped: with the flag off `_customSelected` stays true
        // and an unrelated save (a rename) would otherwise silently clear the
        // window the user never touched.
        //
        // The preset replaces the custom window. Cleared EXPLICITLY rather
        // than leaning on the server's implicit "maxDurationDays without
        // scheduledEndAt clears it" compat rule for frozen clients.
        updates['clearScheduledEndAt'] = true;
        updates['maxDurationDays'] = _maxDurationDays;
      }
    }

    if (updates.isEmpty) {
      Navigator.of(context).pop();
      return;
    }

    setState(() => _isSaving = true);

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      // maxParticipants needs a key-presence signal: a null value is a real
      // change (set to unlimited), not "unchanged". setMaxParticipantsUnlimited
      // tells the sparse PATCH builder to send an explicit null.
      final maxChanged = updates.containsKey('maxParticipants');
      final result = await widget.backendApiService.updateRace(
        identityToken: token,
        raceId: widget.raceId,
        name: updates['name'] as String?,
        maxDurationDays: updates['maxDurationDays'] as int?,
        isPublic: updates['isPublic'] as bool?,
        powerupsEnabled: updates['powerupsEnabled'] as bool?,
        payoutPreset: updates['payoutPreset'] as String?,
        maxParticipants: updates['maxParticipants'] as int?,
        setMaxParticipantsUnlimited: maxChanged && _maxParticipants == null,
        teamAName: updates['teamAName'] as String?,
        teamBName: updates['teamBName'] as String?,
        teamSize: updates['teamSize'] as int?,
        scheduledStartAt: updates['scheduledStartAt'] as DateTime?,
        scheduledEndAt: updates['scheduledEndAt'] as DateTime?,
        clearScheduledEndAt: updates['clearScheduledEndAt'] == true,
      );

      if (mounted) {
        Navigator.of(context).pop(result['race'] as Map<String, dynamic>?);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showErrorToast(context, _friendlyEditError(e));
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showErrorToast(context, 'Could not save changes. Give it another try!');
      }
    }
  }

  /// Issue 4: for BUYIN_UNAFFORDABLE the server puts the specific player
  /// name(s) in `error`, so we show that verbatim (falling back to the generic
  /// only if the message is somehow empty). Other coded errors map to the
  /// playful team-race copy; an uncoded error shows the server message.
  String _friendlyEditError(ApiException e) {
    if (e.code == 'BUYIN_UNAFFORDABLE') {
      final msg = e.message.trim();
      return msg.isNotEmpty ? msg : teamRaceErrorCopy(e.code);
    }
    if (e.code != null) return teamRaceErrorCopy(e.code);
    final msg = e.message.trim();
    return msg.isNotEmpty
        ? msg
        : 'Could not save changes. Give it another try!';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: () => FocusScope.of(context).unfocus(),
        child: ArcadePageBackground(
          child: SafeArea(
            child: Column(
              children: [
                // Header
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      GestureDetector(
                        onTap: () => Navigator.of(context).pop(),
                        child: Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.arrow_back,
                            color: AppColors.of(context).textLight,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'EDIT RACE',
                        style: PixelText.title(
                          size: 22,
                          color: AppColors.of(context).textLight,
                        ).copyWith(shadows: _textShadows),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),

                Expanded(
                  child: SingleChildScrollView(
                    keyboardDismissBehavior:
                        ScrollViewKeyboardDismissBehavior.onDrag,
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Race name
                        RetroCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'RACE NAME',
                                style: PixelText.title(
                                  size: 13,
                                  color: AppColors.of(context).textMid,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _nameController,
                                maxLength: 50,
                                onChanged: (_) => setState(() {}),
                                style: PixelText.body(
                                  size: 16,
                                  color: AppColors.of(context).textDark,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Weekend Warriors',
                                  hintStyle: PixelText.body(
                                    size: 16,
                                    color: AppColors.of(
                                      context,
                                    ).textMid.withValues(alpha: 0.5),
                                  ),
                                  counterText: '',
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 12),

                        // TR-105: team names + size, editable while PENDING.
                        // isTeamRace itself is immutable — no control for it.
                        if (_isTeamRace) ...[
                          _buildTeamCard(),
                          const SizedBox(height: 12),
                        ],

                        // TIMELINE — the shared card (create + edit). Editable
                        // while PENDING; a started race renders it read-only
                        // against its stamped end.
                        RaceTimelineCard(
                          selectedDays: _maxDurationDays,
                          customSelected: _customSelected,
                          customChipEnabled: _customWindowAvailable,
                          customStartAt: _scheduledStartAt,
                          customEndAt: _scheduledEndAt,
                          windowError: _customWindowError,
                          onPresetSelected: _selectPresetTimeline,
                          onCustomSelected: _selectCustomTimeline,
                          onPickStart: _pickScheduledStart,
                          onPickEnd: _pickCustomEnd,
                          readOnly: _timelineReadOnly,
                          readOnlyEndsAt: _stampedEndsAt ?? _initialScheduledEndAt,
                        ),
                        const SizedBox(height: 12),

                        // §10.1 risk 6: the timeline moves the pool, so the
                        // pool has to be visible here too — otherwise re-picking
                        // a window shows no consequence until the user backs out
                        // to the race-detail scorecard.
                        _buildPrizePoolPreview(),

                        // Powerups
                        RetroCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    'POWERUPS',
                                    style: PixelText.title(
                                      size: 13,
                                      color: AppColors.of(context).textMid,
                                    ),
                                  ),
                                  SizedBox(
                                    key: const Key('powerups-toggle'),
                                    height: 28,
                                    child: Switch.adaptive(
                                      value: _powerupsEnabled,
                                      activeTrackColor: AppColors.of(
                                        context,
                                      ).pillGreenDark,
                                      onChanged: (v) =>
                                          setState(() => _powerupsEnabled = v),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 10),
                              // The interval is no longer editable: changing a
                              // running race's spacing would back-mint every box
                              // the new spacing says the runner already earned.
                              PowerupIntervalNote(
                                key: const Key('powerup-interval-note'),
                                enabled: _powerupsEnabled,
                                stepInterval: _displayedPowerupInterval,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Payout mode — how the app-funded prize pool is
                        // split. Buy-ins are gone, so this is no longer behind
                        // a paid/free toggle. Team races split evenly (TR-102),
                        // so they get a line instead of a picker.
                        if (!_isTeamRace) ...[
                          RetroCard(
                            key: const Key('payout-mode-card'),
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'PAYOUT MODE',
                                  style: PixelText.title(
                                    size: 13,
                                    color: AppColors.of(context).textMid,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Column(
                                  children: payoutPresetOptions.map((option) {
                                    final selected = _payoutPreset == option.$2;
                                    return Padding(
                                      padding: const EdgeInsets.only(bottom: 8),
                                      child: GestureDetector(
                                        onTap: () => setState(
                                          () => _payoutPreset = option.$2,
                                        ),
                                        child: Container(
                                          width: double.infinity,
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 12,
                                            vertical: 10,
                                          ),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? AppColors.of(
                                                    context,
                                                  ).pillGreenDark
                                                : AppColors.of(
                                                    context,
                                                  ).parchmentDark,
                                            borderRadius: BorderRadius.circular(
                                              8,
                                            ),
                                          ),
                                          child: Text(
                                            option.$1,
                                            style: PixelText.title(
                                              size: 12,
                                              color: selected
                                                  ? Colors.white
                                                  : AppColors.of(
                                                      context,
                                                    ).textDark,
                                            ),
                                            textAlign: TextAlign.center,
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                                SizedBox(
                                  width: double.infinity,
                                  child: Text(
                                    payoutHelpText(_payoutPreset),
                                    style: PixelText.body(
                                      size: 12,
                                      color: AppColors.of(context).textMid,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 24),
                        ],

                        // Public race
                        RetroCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildVisibilityPicker(),
                              // TR-101/105: a team race's field cap is derived
                              // (2 x teamSize) — the runner-cap chips don't
                              // apply; the size stepper above owns it.
                              if (!_isTeamRace) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'MAX RUNNERS',
                                  style: PixelText.body(
                                    size: 11,
                                    color: AppColors.of(context).textMid,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: [
                                    ..._maxParticipantsPresets.map((preset) {
                                      final selected =
                                          _maxParticipants == preset;
                                      final disabled = preset < _acceptedCount;
                                      return _maxRunnersChip(
                                        label: '$preset',
                                        selected: selected,
                                        disabled: disabled,
                                        onTap: () => setState(
                                          () => _maxParticipants = preset,
                                        ),
                                      );
                                    }),
                                    _maxRunnersChip(
                                      label: 'NO LIMIT',
                                      selected: _maxParticipants == null,
                                      disabled: false,
                                      onTap: () => setState(
                                        () => _maxParticipants = null,
                                      ),
                                    ),
                                  ],
                                ),
                                if (_acceptedCount > 1) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    '$_acceptedCount runners already accepted.',
                                    style: PixelText.body(
                                      size: 11,
                                      color: AppColors.of(context).textMid,
                                    ),
                                  ),
                                ],
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Save button
                        PillButton(
                          label: _isSaving ? 'SAVING...' : 'SAVE CHANGES',
                          variant: PillButtonVariant.primary,
                          fontSize: 15,
                          fullWidth: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          onPressed:
                              (_isSaving ||
                                  !_hasChanges ||
                                  _blockingWindowError != null)
                              ? null
                              : _save,
                        ),
                        const SizedBox(height: 12),
                        PillButton(
                          label: 'DISCARD',
                          variant: PillButtonVariant.secondary,
                          fontSize: 13,
                          fullWidth: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 12,
                          ),
                          onPressed: _isSaving
                              ? null
                              : () => Navigator.of(context).pop(),
                        ),
                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
