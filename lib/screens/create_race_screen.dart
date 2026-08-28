import 'package:flutter/material.dart';

import '../models/race_payouts.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/funded_exposure_error_copy.dart';
import '../utils/team_race.dart';
import '../utils/tournament.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/powerup_interval_note.dart';
import '../widgets/race_timeline_card.dart';
import '../widgets/retro_card.dart';
import 'tournament_detail_screen.dart';

class CreateRaceScreen extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;
  final List<String> presetInviteeIds;
  final bool initialCustomizeExpanded;

  /// Seeds the name field. The onboarding demo uses it so the tutorial's first
  /// beat is a decision (how long?) rather than a keyboard.
  final String? initialName;

  /// Onboarding-demo chrome only (spec §5.1, same shape as
  /// `RaceDetailScreen.demoMode`): hides the back arrow and the CUSTOMIZE
  /// section. Teams, tournaments, visibility, payout presets and scheduled
  /// starts are all reachable from there, and every one of them is a way to
  /// dead-end a scripted tutorial. It changes **nothing** about what gets sent.
  final bool demoMode;

  /// Optional coach-mark anchors. Null in the shipped app (the wrapping
  /// KeyedSubtrees are then transparent); the demo passes keys so its overlay
  /// can measure these elements on the real screen.
  final GlobalKey? tutorialDurationKey;
  final GlobalKey? tutorialCreateKey;

  CreateRaceScreen({
    super.key,
    required this.authService,
    BackendApiService? backendApiService,
    this.presetInviteeIds = const [],
    this.initialCustomizeExpanded = false,
    this.initialName,
    this.demoMode = false,
    this.tutorialDurationKey,
    this.tutorialCreateKey,
  }) : backendApiService = backendApiService ?? BackendApiService();

  @override
  State<CreateRaceScreen> createState() => CreateRaceScreenState();
}

class CreateRaceScreenState extends State<CreateRaceScreen> {
  final _nameController = TextEditingController();
  // 7 is the default now that the 3-day chip is retired from the picker: a
  // default the picker cannot express would leave nothing selected on open.
  int _selectedDuration = 7;
  bool _isCreating = false;
  // Powerups are the point of a race, so they start ON. A creator who never
  // opens the customize section still sends powerupsEnabled: true plus the
  // fixed 2,000-step interval (both create paths already send them explicitly).
  bool _powerupsEnabled = true;
  String _payoutPreset = 'WINNER_TAKES_ALL';
  bool _isPublic = false;
  // Participant cap. Required selection: the user must pick a preset number or
  // NO LIMIT before creating. `_noLimit == false && _maxParticipants == null`
  // means "nothing chosen yet". NO LIMIT sends maxParticipants: null (unlimited).
  int? _maxParticipants = 10;
  bool _noLimit = false;
  // 1.1.7: optional future auto-start. Null = instant/manual race (default).
  //
  // Race timeline options §4.3: there is exactly ONE of these in state. The
  // CUSTOM "STARTS" row and the SCHEDULED START card are two surfaces onto the
  // same field, and only one of them is ever mounted.
  DateTime? _scheduledStartAt;
  // The CUSTOM timeline: an exact end instant, honoured verbatim by the
  // backend. Null (or `!_customSelected`) means today's duration-derived end.
  bool _customSelected = false;
  DateTime? _scheduledEndAt;
  late bool _customizeExpanded;

  // Team races (TR-801). Plaque names come from the backend's ≥50-name pool
  // (TR-103, contract §3b); the local pool is only an offline/older-backend
  // fallback. Whatever is DISPLAYED is sent as the creator's override at
  // creation, so the plaques never lie. TR-104: creator's side defaults to A.
  bool _isTeamRace = false;
  int _teamSize = 2;
  late final TextEditingController _teamANameController;
  late final TextEditingController _teamBNameController;
  RaceTeam _creatorSide = RaceTeam.teamA;
  // True once the server pool has seeded the plaques, so entering Teams mode
  // doesn't re-fetch (and clobber) names the user may have typed.
  bool _teamNamesSeeded = false;
  bool _suggestingNames = false;

  // Tournaments (spec §9). A single-elimination bracket mode, mutually
  // exclusive with FFA/Teams. Entry is free — the bracket pool is app-funded
  // off the total bracket length (app-funded prize pools, D9).
  bool _isTournament = false;
  int _bracketSize = 8;
  // §3.5 — rounds are at least 2 days; 1-day matchups were removed.
  int _matchupDuration = 2;

  @override
  void initState() {
    super.initState();
    _customizeExpanded = widget.initialCustomizeExpanded;
    final seed = widget.initialName?.trim();
    if (seed != null && seed.isNotEmpty) _nameController.text = seed;
    // Seed synchronously from the local pool so the plaques are never blank,
    // then upgrade to the real backend pool in the background.
    final pair = randomTeamNamePair();
    _teamANameController = TextEditingController(text: pair.$1);
    _teamBNameController = TextEditingController(text: pair.$2);
  }

  /// Pulls a fresh distinct pair from the backend pool, falling back to the
  /// local preview pool on any failure (older backend, offline). Cosmetic —
  /// never blocks or fails race creation.
  Future<void> _suggestTeamNames({bool force = false}) async {
    if (_suggestingNames) return;
    if (_teamNamesSeeded && !force) return;
    _suggestingNames = true;

    (String, String)? pair;
    final token = widget.authService.authToken;
    if (token != null && token.isNotEmpty) {
      pair = await widget.backendApiService.fetchTeamNameSuggestion(
        identityToken: token,
      );
    }
    // Fallback: local pool. A reroll must still feel like a roll, so avoid
    // handing back the exact pair already on the plaques.
    if (pair == null) {
      var local = randomTeamNamePair();
      if (local.$1 == _teamANameController.text &&
          local.$2 == _teamBNameController.text) {
        local = (local.$2, local.$1);
      }
      pair = local;
    }

    _suggestingNames = false;
    if (!mounted) return;
    setState(() {
      _teamANameController.text = pair!.$1;
      _teamBNameController.text = pair.$2;
      _teamNamesSeeded = true;
    });
  }

  void _rerollTeamNames() {
    // The dice always pulls a genuinely new pair, server-side when available.
    _suggestTeamNames(force: true);
  }

  /// Test-only hook so widget tests can set the scheduled start without driving
  /// the platform date/time picker dialogs.
  @visibleForTesting
  void debugSetScheduledStart(DateTime? value) {
    setState(() => _scheduledStartAt = value);
  }

  /// Same, for the CUSTOM window's end instant.
  @visibleForTesting
  void debugSetCustomEnd(DateTime? value) {
    setState(() => _scheduledEndAt = value);
  }

  @visibleForTesting
  DateTime? get debugCustomEnd => _scheduledEndAt;

  /// Reaches the create path directly, past the disabled button — the way a
  /// stale frame or a queued tap would. Exists so a test can prove `_create`
  /// refuses an illegal window itself rather than trusting the button.
  @visibleForTesting
  Future<void> debugCreateForTest() => _create();

  /// Whether the CUSTOM chip is offered at all. Absent flag => false => the
  /// screen is behaviorally identical to today (spec §6, "Feature gating").
  bool get _customWindowAvailable => widget.authService.customRaceWindowEnabled;

  /// The custom window is only ACTIVE where it is both chosen and offered.
  ///
  /// The flag is read live off `/auth/me`, so it can flip to false mid-session
  /// (that is the kill switch). Deriving every consumer from this one getter
  /// means the screen then degrades cleanly back to the preset UI — the
  /// SCHEDULED START card returns, the plaque re-prices off the preset, and
  /// nothing half-hidden can still be feeding the create call.
  ///
  /// Tournaments are excluded because the whole TIMELINE card is hidden for
  /// them: an invalid window left behind by a mode switch must not keep CREATE
  /// disabled with no visible cause.
  bool get _customActive =>
      _customSelected && _customWindowAvailable && !_isTournament;

  /// The instant the window is measured from: the scheduled start when one is
  /// picked, else now — the server's "effective start".
  DateTime get _effectiveWindowStart => _scheduledStartAt ?? DateTime.now();

  /// Mirrors the server's validation (spec §4.4) so the user never round-trips
  /// to a 400. Null when the window is fine (or not in play at all).
  String? get _customWindowError {
    if (!_customActive) return null;
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

  /// True only while a CUSTOM window is selected AND legal — the one condition
  /// under which `scheduledEndAt` goes on the wire.
  bool get _sendsCustomWindow =>
      _customActive && _scheduledEndAt != null && _customWindowError == null;

  /// Entering CUSTOM seeds the window from whatever the user already chose:
  /// the existing scheduled start (or "when everyone's in"), and the current
  /// preset's length as the end.
  void _selectCustomTimeline() {
    setState(() {
      _customSelected = true;
      // Rounded UP, never down: truncating to the hour would shave minutes off
      // a 1-day preset and seed a window that is instantly under the 24h floor,
      // greeting the user with an error and a dead CREATE for a choice they
      // never made.
      _scheduledEndAt ??= _ceilToHour(
        _effectiveWindowStart.add(Duration(days: _selectedDuration)),
      );
    });
  }

  /// Leaving CUSTOM keeps `_scheduledStartAt` intact (§4.3) — only the surface
  /// that renders it changes — and drops the end, which the preset replaces.
  void _selectPresetTimeline(int days) {
    setState(() {
      _customSelected = false;
      _selectedDuration = days;
      _scheduledEndAt = null;
    });
  }

  static DateTime _ceilToHour(DateTime t) {
    final floored = DateTime(t.year, t.month, t.day, t.hour);
    return floored == t ? floored : floored.add(const Duration(hours: 1));
  }

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  // The preset chips live in `widgets/race_timeline_card.dart` now
  // (kRaceTimelinePresets) so the create and edit screens cannot drift.
  static const _maxParticipantsPresets = [5, 10, 25, 50, 100];

  @override
  void dispose() {
    _nameController.dispose();
    _teamANameController.dispose();
    _teamBNameController.dispose();
    super.dispose();
  }

  static const _monthAbbrev = [
    'Jan',
    'Feb',
    'Mar',
    'Apr',
    'May',
    'Jun',
    'Jul',
    'Aug',
    'Sep',
    'Oct',
    'Nov',
    'Dec',
  ];

  Widget _maxRunnersChip({
    required String label,
    required bool selected,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      onTap: onTap,
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
    );
  }

  String _formatScheduledStart(DateTime t) {
    final local = t.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '${_monthAbbrev[local.month - 1]} ${local.day} · $h:$m $ampm';
  }

  // Bara-themed wrapper for the stock Material date/time pickers, now shared
  // with the edit screen (`widgets/race_timeline_card.dart`). Required, not
  // decorative: an unthemed picker renders black-on-black under the
  // onboarding pinned-light theme and at night.
  Widget _themedPicker(BuildContext context, Widget? child) =>
      raceThemedPickerBuilder(context, child);

  Future<void> _pickScheduledStart() async {
    final now = DateTime.now();
    final initial = _scheduledStartAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
      builder: _themedPicker,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: _themedPicker,
    );
    if (time == null || !mounted) return;
    final picked = DateTime(
      date.year,
      date.month,
      date.day,
      time.hour,
      time.minute,
    );
    // Guard against a picked moment that's already in the past (e.g. today +
    // an earlier time). The backend also rejects past times defensively.
    if (picked.isAfter(DateTime.now())) {
      setState(() => _scheduledStartAt = picked);
    } else {
      if (mounted) {
        showErrorToast(context, 'Pick a time in the future');
      }
    }
  }

  /// The CUSTOM window's end. Mirrors [_pickScheduledStart] deliberately —
  /// including `_themedPicker`, which is not optional: an unthemed picker
  /// renders black-on-black under the onboarding pinned-light theme and at
  /// night (§10.1 risk 7).
  Future<void> _pickCustomEnd() async {
    final now = DateTime.now();
    // Clamp the anchor to now: a scheduled start can already be in the past
    // (a PENDING race the cron has not managed to start yet), and an unclamped
    // anchor produces firstDate > lastDate / initialDate < firstDate, which is
    // an assertion failure inside showDatePicker rather than a bad value.
    final rawStart = _effectiveWindowStart;
    final windowStart = rawStart.isBefore(now) ? now : rawStart;
    // The floor is a day, so the earliest LEGAL end is start + 24h — but the
    // picker must never offer, or default to, a value that fails validation the
    // instant it is accepted. Exactly `start + 24h` is not `> 24h`, so tapping
    // OK on both pickers without changing anything would kill CREATE with
    // "A race has to run at least 1 day" while the earliest offered value is
    // the one that just failed. Ceil an hour past the floor, the same rounding
    // `_selectCustomTimeline` seeds with, which also absorbs the seconds that
    // elapse inside the picker on a manual-start race (where the window is
    // measured against a moving `now`).
    final earliest = _ceilToHour(
      windowStart.add(const Duration(days: 1, hours: 1)),
    );
    final initial = _scheduledEndAt ?? earliest;
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(earliest) ? earliest : initial,
      firstDate: earliest,
      lastDate: windowStart.add(const Duration(days: 30)),
      builder: _themedPicker,
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
      builder: _themedPicker,
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
    // An illegal pick is NOT silently snapped forward: the derived label names
    // the rule and CREATE stays disabled until the user fixes it (§4.4).
  }

  Future<void> _create() async {
    // The button is disabled while the window is illegal, but the window can
    // go stale between rebuilds (the 24h floor is measured against a moving
    // "now" when there is no scheduled start). Without this the create would
    // fall through and silently post a PRESET race the user never asked for.
    final windowError = _customWindowError;
    if (windowError != null) {
      showErrorToast(context, windowError);
      return;
    }

    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showErrorToast(context, 'Enter a race name');
      return;
    }

    // Tournament name is capped tighter (1–30) so the generated matchup-race
    // names fit (spec §6.1/§6.5).
    if (_isTournament && name.length > 30) {
      showErrorToast(context, 'Tournament name must be 30 characters or less');
      return;
    }

    String teamAName = '';
    String teamBName = '';
    if (_isTeamRace) {
      teamAName = _teamANameController.text.trim();
      teamBName = _teamBNameController.text.trim();
      if (teamAName.isEmpty || teamBName.isEmpty) {
        showErrorToast(context, 'Give both teams a name');
        return;
      }
      // TR-103: the two names must differ (case-insensitive). Mirror the
      // server rule client-side so the plaques never lie post-create.
      if (teamAName.toLowerCase() == teamBName.toLowerCase()) {
        showErrorToast(context, teamRaceErrorCopy('TEAM_NAMES_IDENTICAL'));
        return;
      }
    }

    // Entry is free: there is no buy-in to validate and nothing to afford.
    // Prize pools are funded by the app (app-funded prize pools, §4).

    setState(() => _isCreating = true);

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      if (_isTournament) {
        final res = await widget.backendApiService.createTournament(
          identityToken: token,
          name: name,
          bracketSize: _bracketSize,
          matchupDurationDays: _matchupDuration,
          powerupsEnabled: _powerupsEnabled,
          powerupStepInterval: _powerupsEnabled
              ? kFixedPowerupStepInterval
              : null,
          isPublic: _isPublic,
          inviteeIds: widget.presetInviteeIds,
        );
        final t = res['tournament'] as Map<String, dynamic>?;
        final tournamentId = t?['id'] as String?;
        // Nothing is charged for a bracket any more, but keep the wallet in
        // sync anyway — it's cheap and the header shows it.
        try {
          final user = await widget.backendApiService.fetchMe(
            identityToken: token,
          );
          await widget.authService.updateCoins(
            user['coins'] as int? ?? widget.authService.coins,
          );
          await widget.authService.updateHeldCoins(
            user['heldCoins'] as int? ?? widget.authService.heldCoins,
          );
        } catch (_) {}
        if (!mounted) return;
        if (tournamentId != null) {
          // Replace this screen with the new bracket lobby.
          Navigator.of(context).pushReplacement(
            MaterialPageRoute(
              builder: (_) => TournamentDetailScreen(
                authService: widget.authService,
                tournamentId: tournamentId,
                backendApiService: widget.backendApiService,
              ),
            ),
          );
        } else {
          Navigator.of(context).pop();
        }
        return;
      }

      final result = _isTeamRace
          ? await widget.backendApiService.createTeamRace(
              identityToken: token,
              name: name,
              teamSize: _teamSize,
              maxDurationDays: _selectedDuration,
              powerupsEnabled: _powerupsEnabled,
              powerupStepInterval: _powerupsEnabled
                  ? kFixedPowerupStepInterval
                  : null,
              isPublic: _isPublic,
              scheduledStartAt: _scheduledStartAt,
              // Omitted from the body entirely when null, so a preset race's
              // request is byte-identical to today's (spec §6).
              scheduledEndAt: _sendsCustomWindow ? _scheduledEndAt : null,
              teamAName: teamAName,
              teamBName: teamBName,
              creatorTeam: _creatorSide.wireValue,
            )
          : await widget.backendApiService.createRace(
              identityToken: token,
              name: name,
              maxDurationDays: _selectedDuration,
              powerupsEnabled: _powerupsEnabled,
              powerupStepInterval: _powerupsEnabled
                  ? kFixedPowerupStepInterval
                  : null,
              // Every race has a funded pool now, so the preset always counts.
              payoutPreset: _payoutPreset,
              isPublic: _isPublic,
              maxParticipants: _noLimit ? null : _maxParticipants,
              scheduledStartAt: _scheduledStartAt,
              scheduledEndAt: _sendsCustomWindow ? _scheduledEndAt : null,
            );

      final createdRace = result['race'] as Map<String, dynamic>?;
      final createdRaceId = createdRace?['id'] as String?;
      if (widget.presetInviteeIds.isNotEmpty && createdRaceId != null) {
        try {
          await widget.backendApiService.inviteToRace(
            identityToken: token,
            raceId: createdRaceId,
            inviteeIds: widget.presetInviteeIds,
          );
        } catch (_) {
          // Preset-invite send failure shouldn't block race creation. User can
          // re-invite from the race detail screen.
        }
      }

      final user = await widget.backendApiService.fetchMe(identityToken: token);
      await widget.authService.updateCoins(
        user['coins'] as int? ?? widget.authService.coins,
      );
      await widget.authService.updateHeldCoins(
        user['heldCoins'] as int? ?? widget.authService.heldCoins,
      );

      if (mounted) {
        Navigator.of(context).pop(result['race'] as Map<String, dynamic>?);
      }
    } on ApiException catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        showErrorToast(
          context,
          isActiveCompetitionLimitError(e)
              ? fundedExposureErrorCopy(e)
              : _isTournament && e.code != null
              ? tournamentErrorCopy(e.code)
              : e.message,
        );
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
        showErrorToast(context, e.toString());
      }
    }
  }

  /// TR-801: the "Free-for-all / Teams" wooden signpost plus, in Teams mode,
  /// the carved 1v1..5v5 stepper, the two team-name plaques (dice-reroll +
  /// tap-to-edit) and the creator's side pick (TR-104).
  /// Item 13 — the one-line explanation of the selected race format.
  String get _formatDescription {
    if (_isTournament) {
      return 'Advance through head-to-head rounds until one winner remains.';
    }
    if (_isTeamRace) {
      return 'Two teams compete for the highest combined step total.';
    }
    return 'Every player competes individually. Invite friends or let anyone join.';
  }

  Widget _buildFormatCard() {
    return RetroCard(
      padding: const EdgeInsets.all(16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'RACE FORMAT',
            style: PixelText.title(
              size: 13,
              color: AppColors.of(context).textMid,
            ),
          ),
          const SizedBox(height: 10),
          // The signpost: two carved segments sharing one wooden bar.
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
                _formatSegment(
                  // Item 13 (batch 2026-08-08): the LABEL is now CLASSIC, but
                  // the key stays `race-format-ffa` and the analytics value
                  // stays `solo` — renaming either would break existing tests
                  // and split every dashboard series in half.
                  key: const Key('race-format-ffa'),
                  label: 'CLASSIC',
                  icon: Icons.emoji_events_rounded,
                  selected: !_isTeamRace && !_isTournament,
                  onTap: () => setState(() {
                    _isTeamRace = false;
                    _isTournament = false;
                  }),
                ),
                const SizedBox(width: 4),
                _formatSegment(
                  key: const Key('race-format-teams'),
                  label: 'TEAMS',
                  icon: Icons.groups_rounded,
                  selected: _isTeamRace,
                  onTap: () {
                    setState(() {
                      _isTeamRace = true;
                      _isTournament = false;
                    });
                    // Upgrade the locally-seeded plaques to the real backend
                    // pool the first time Teams is opened (TR-103). Guarded so
                    // it never clobbers a name the user typed.
                    _suggestTeamNames();
                  },
                ),
                const SizedBox(width: 4),
                _formatSegment(
                  key: const Key('race-format-tournament'),
                  label: 'BRACKET',
                  icon: Icons.account_tree_rounded,
                  selected: _isTournament,
                  onTap: () => setState(() {
                    final entering = !_isTournament;
                    _isTournament = true;
                    _isTeamRace = false;
                    // Powerups default ON for tournaments — set only on entry so
                    // a later manual toggle-off isn't stomped by re-tapping.
                    if (entering) _powerupsEnabled = true;
                  }),
                ),
              ],
            ),
          ),
          // Item 13: one shared description line under the signpost, swapping
          // with the selection. Per-segment copy won't fit a third-width pill.
          const SizedBox(height: 8),
          Text(
            key: const Key('race-format-description'),
            _formatDescription,
            style: PixelText.body(
              size: 11.5,
              color: AppColors.of(context).textMid,
            ),
          ),
          // Tournament reveal — bracket size + matchup duration pickers.
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            alignment: Alignment.topCenter,
            child: _isTournament
                ? _buildTournamentReveal()
                : const SizedBox(width: double.infinity),
          ),
          // Teams reveal — size stepper, plaques, your-side pick.
          AnimatedSize(
            duration: const Duration(milliseconds: 260),
            curve: Curves.easeOutBack,
            alignment: Alignment.topCenter,
            child: _isTeamRace
                ? Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const SizedBox(height: 16),
                      _buildTeamSizeStepper(),
                      const SizedBox(height: 16),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'TEAM NAMES',
                            style: PixelText.body(
                              size: 11,
                              color: AppColors.of(context).textMid,
                            ),
                          ),
                          GestureDetector(
                            key: const Key('team-name-reroll'),
                            onTap: _rerollTeamNames,
                            child: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.of(context).pillGold,
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(
                                  color: AppColors.of(context).pillGoldShadow,
                                  width: 2,
                                ),
                                boxShadow: [
                                  BoxShadow(
                                    color: AppColors.of(context).pillGoldShadow,
                                    offset: Offset(0, 2),
                                    blurRadius: 0,
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.casino_rounded,
                                    size: 14,
                                    color: AppColors.of(context).textDark,
                                  ),
                                  const SizedBox(width: 4),
                                  Text(
                                    'REROLL',
                                    style: PixelText.title(
                                      size: 10,
                                      color: AppColors.of(context).textDark,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                      _teamNamePlaque(
                        key: const Key('team-plaque-a'),
                        team: RaceTeam.teamA,
                        controller: _teamANameController,
                      ),
                      const SizedBox(height: 8),
                      _teamNamePlaque(
                        key: const Key('team-plaque-b'),
                        team: RaceTeam.teamB,
                        controller: _teamBNameController,
                      ),
                      const SizedBox(height: 14),
                      Text(
                        'YOUR SIDE',
                        style: PixelText.body(
                          size: 11,
                          color: AppColors.of(context).textMid,
                        ),
                      ),
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          _sideChip(
                            key: const Key('team-side-a'),
                            team: RaceTeam.teamA,
                          ),
                          const SizedBox(width: 8),
                          _sideChip(
                            key: const Key('team-side-b'),
                            team: RaceTeam.teamB,
                          ),
                        ],
                      ),
                    ],
                  )
                : const SizedBox(width: double.infinity),
          ),
        ],
      ),
    );
  }

  Widget _formatSegment({
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
            border: selected
                ? Border.all(color: AppColors.of(context).roofDark, width: 2)
                : Border.all(color: Colors.transparent, width: 2),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: AppColors.of(context).roofDark,
                      offset: Offset(0, 2),
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

  /// Who can join. This used to be one switch whose label flipped between
  /// PRIVATE RACE and PUBLIC RACE — with the switch off, "PRIVATE RACE" read
  /// as "private is the setting that's turned off", so people flipped it to
  /// get a private race and got a public one. Both options are now named at
  /// once on the same carved bar as RACE FORMAT, so the selection is the only
  /// thing that changes and the subcopy only ever describes what's picked.
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
              _formatSegment(
                key: const Key('race-visibility-private'),
                label: 'PRIVATE',
                icon: Icons.lock_rounded,
                selected: !_isPublic,
                onTap: () => setState(() => _isPublic = false),
              ),
              const SizedBox(width: 4),
              _formatSegment(
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

  /// The tournament reveal: bracket-size picker (4/8/16) + matchup-duration
  /// chips (1/2/3 days). Buy-in / powerups / public are the shared cards below.
  Widget _buildTournamentReveal() {
    return Column(
      key: const Key('tournament-reveal'),
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        const SizedBox(height: 16),
        Text(
          'BRACKET SIZE',
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final size in kTournamentBracketSizes) ...[
              if (size != kTournamentBracketSizes.first)
                const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  key: Key('bracket-size-$size'),
                  onTap: () => setState(() => _bracketSize = size),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _bracketSize == size
                          ? AppColors.of(context).pillGreenDark
                          : AppColors.of(context).parchmentDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '$size',
                      style: PixelText.title(
                        size: 16,
                        color: _bracketSize == size
                            ? Colors.white
                            : AppColors.of(context).textDark,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          Tournament.sizeSubcopy(_bracketSize),
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
        const SizedBox(height: 16),
        Text(
          'MATCHUP LENGTH',
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            for (final days in kTournamentDurations) ...[
              if (days != kTournamentDurations.first) const SizedBox(width: 8),
              Expanded(
                child: GestureDetector(
                  key: Key('matchup-duration-$days'),
                  onTap: () => setState(() => _matchupDuration = days),
                  child: Container(
                    padding: const EdgeInsets.symmetric(vertical: 10),
                    alignment: Alignment.center,
                    decoration: BoxDecoration(
                      color: _matchupDuration == days
                          ? AppColors.of(context).pillGreenDark
                          : AppColors.of(context).parchmentDark,
                      borderRadius: BorderRadius.circular(8),
                    ),
                    child: Text(
                      '${days}d',
                      style: PixelText.title(
                        size: 15,
                        color: _matchupDuration == days
                            ? Colors.white
                            : AppColors.of(context).textDark,
                      ),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
        const SizedBox(height: 6),
        Text(
          'Every round is a $_matchupDuration-day 1v1. '
          'The champion takes the whole prize pool.',
          style: PixelText.body(size: 11, color: AppColors.of(context).textMid),
        ),
      ],
    );
  }

  Widget _buildTeamSizeStepper() {
    return Container(
      key: const Key('team-size-stepper'),
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
          _stepperButton(
            key: const Key('team-size-minus'),
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
                  '${_teamSize * 2} RACERS TOTAL',
                  style: PixelText.body(
                    size: 10,
                    color: AppColors.of(context).textMid,
                  ),
                ),
              ],
            ),
          ),
          _stepperButton(
            key: const Key('team-size-plus'),
            icon: Icons.add_rounded,
            enabled: _teamSize < 5,
            onTap: () =>
                setState(() => _teamSize = (_teamSize + 1).clamp(1, 5)),
          ),
        ],
      ),
    );
  }

  Widget _stepperButton({
    required Key key,
    required IconData icon,
    required bool enabled,
    required VoidCallback onTap,
  }) {
    return GestureDetector(
      key: key,
      onTap: enabled ? onTap : null,
      child: AnimatedOpacity(
        duration: const Duration(milliseconds: 120),
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

  Widget _sideChip({required Key key, required RaceTeam team}) {
    final selected = _creatorSide == team;
    final color = TeamRace.color(team, context);
    final colorDark = TeamRace.colorDark(team, context);
    final controller = team == RaceTeam.teamA
        ? _teamANameController
        : _teamBNameController;
    final name = controller.text.trim().isEmpty
        ? (team == RaceTeam.teamA ? 'TEAM A' : 'TEAM B')
        : controller.text.trim().toUpperCase();
    return Expanded(
      child: GestureDetector(
        key: key,
        onTap: () => setState(() => _creatorSide = team),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 160),
          padding: const EdgeInsets.symmetric(vertical: 9, horizontal: 8),
          decoration: BoxDecoration(
            color: selected ? color : AppColors.of(context).parchmentDark,
            borderRadius: BorderRadius.circular(9),
            border: Border.all(
              color: selected
                  ? colorDark
                  : AppColors.of(context).parchmentBorder,
              width: 2,
            ),
            boxShadow: selected
                ? [
                    BoxShadow(
                      color: colorDark,
                      offset: const Offset(0, 2),
                      blurRadius: 0,
                    ),
                  ]
                : null,
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (selected) ...[
                const Icon(
                  Icons.check_circle_rounded,
                  size: 14,
                  color: Colors.white,
                ),
                const SizedBox(width: 5),
              ],
              Flexible(
                child: Text(
                  name,
                  overflow: TextOverflow.ellipsis,
                  style: PixelText.title(
                    size: 11,
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
                      // The demo owns its own exit (the coach's SKIP chip); a
                      // back arrow here would drop the user out of onboarding
                      // into a half-built race.
                      if (!widget.demoMode)
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
                        'NEW RACE',
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
                                key: const Key('race-name-field'),
                                controller: _nameController,
                                maxLength: 50,
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

                        // Race format — wooden signpost (TR-801). Hidden
                        // entirely when the remote kill switch is off (TR-107).
                        if (_customizeExpanded &&
                            !widget.demoMode &&
                            widget.authService.teamRacesEnabled) ...[
                          _buildFormatCard(),
                          const SizedBox(height: 12),
                        ],

                        // Duration + scheduled-start are hidden for tournaments:
                        // matchup length is fixed by the bracket picker and
                        // tournaments never schedule-auto-start (spec §9).
                        if (!_isTournament) ...[
                          // TIMELINE — the shared card (create + edit).
                          RaceTimelineCard(
                            outerKey: widget.tutorialDurationKey,
                            selectedDays: _selectedDuration,
                            customSelected: _customActive,
                            customChipEnabled: _customWindowAvailable,
                            customStartAt: _scheduledStartAt,
                            customEndAt: _scheduledEndAt,
                            windowError: _customWindowError,
                            onPresetSelected: _selectPresetTimeline,
                            onCustomSelected: _selectCustomTimeline,
                            onPickStart: _pickScheduledStart,
                            onPickEnd: _pickCustomEnd,
                          ),
                          const SizedBox(height: 12),

                          if (!widget.demoMode)
                            GestureDetector(
                              key: const Key('customize-race-toggle'),
                              onTap: () => setState(
                                () => _customizeExpanded = !_customizeExpanded,
                              ),
                              child: Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                                decoration: BoxDecoration(
                                  color: AppColors.of(context).roofDark,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: AppColors.of(
                                      context,
                                    ).parchmentBorder,
                                    width: 2,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Icons.tune_rounded,
                                      color: AppColors.of(context).textLight,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Text(
                                        'CUSTOMIZE RACE',
                                        style: PixelText.title(
                                          size: 13,
                                          color: AppColors.of(
                                            context,
                                          ).textLight,
                                        ),
                                      ),
                                    ),
                                    Icon(
                                      _customizeExpanded
                                          ? Icons.expand_less_rounded
                                          : Icons.expand_more_rounded,
                                      color: AppColors.of(context).textLight,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          if (!widget.demoMode) const SizedBox(height: 12),

                          // Scheduled start (optional auto-start).
                          //
                          // Hidden — not greyed — while CUSTOM is selected: the
                          // TIMELINE card's STARTS row owns `scheduledStartAt`
                          // then, and two controls writing one field is how
                          // they end up disagreeing (§4.3).
                          if (_customizeExpanded &&
                              !widget.demoMode &&
                              !_customActive)
                            RetroCard(
                              padding: const EdgeInsets.all(16),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Column(
                                        crossAxisAlignment:
                                            CrossAxisAlignment.start,
                                        children: [
                                          Text(
                                            'SCHEDULED START',
                                            style: PixelText.title(
                                              size: 13,
                                              color: AppColors.of(
                                                context,
                                              ).textMid,
                                            ),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            _scheduledStartAt == null
                                                ? 'START MANUALLY'
                                                : 'AUTO-START',
                                            style: PixelText.body(
                                              size: 11,
                                              color: _scheduledStartAt == null
                                                  ? AppColors.of(
                                                      context,
                                                    ).textMid
                                                  : AppColors.of(
                                                      context,
                                                    ).pillGreenDark,
                                            ),
                                          ),
                                        ],
                                      ),
                                      SizedBox(
                                        height: 28,
                                        child: Switch.adaptive(
                                          value: _scheduledStartAt != null,
                                          activeTrackColor: AppColors.of(
                                            context,
                                          ).pillGreenDark,
                                          onChanged: (v) {
                                            if (v) {
                                              _pickScheduledStart();
                                            } else {
                                              setState(
                                                () => _scheduledStartAt = null,
                                              );
                                            }
                                          },
                                        ),
                                      ),
                                    ],
                                  ),
                                  if (_scheduledStartAt != null) ...[
                                    const SizedBox(height: 12),
                                    GestureDetector(
                                      onTap: _pickScheduledStart,
                                      child: Container(
                                        width: double.infinity,
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 12,
                                          vertical: 10,
                                        ),
                                        decoration: BoxDecoration(
                                          color: AppColors.of(
                                            context,
                                          ).parchmentDark,
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
                                        ),
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.event_outlined,
                                              size: 16,
                                              color: AppColors.of(
                                                context,
                                              ).textMid,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'Starts at ${_formatScheduledStart(_scheduledStartAt!)}',
                                                style: PixelText.body(
                                                  size: 13,
                                                  color: AppColors.of(
                                                    context,
                                                  ).textDark,
                                                ),
                                              ),
                                            ),
                                            Icon(
                                              Icons.edit_outlined,
                                              size: 14,
                                              color: AppColors.of(
                                                context,
                                              ).textMid.withValues(alpha: 0.6),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                            ),
                          // Gated on the card above, not just on the section:
                          // an ungated spacer leaves a stray gap inside
                          // CUSTOMIZE RACE when the card is hidden (§10.1
                          // risk 8).
                          if (_customizeExpanded &&
                              !widget.demoMode &&
                              !_customActive)
                            const SizedBox(height: 12),
                        ],

                        // Powerups
                        if (_customizeExpanded)
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
                                        onChanged: (v) => setState(
                                          () => _powerupsEnabled = v,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                // The creator no longer picks the spacing —
                                // every race earns a box every 2,000 steps.
                                PowerupIntervalNote(
                                  key: const Key('powerup-interval-note'),
                                  enabled: _powerupsEnabled,
                                ),
                              ],
                            ),
                          ),
                        if (_customizeExpanded) const SizedBox(height: 24),

                        // Payout mode — how the app-funded prize pool is
                        // carved up. Every race has a pool now, so this is no
                        // longer gated behind a buy-in toggle. Team races split
                        // their pool evenly and brackets are winner-takes-all,
                        // so neither offers a picker (TR-102 / bracket rules).
                        if (_customizeExpanded &&
                            !_isTournament &&
                            !_isTeamRace) ...[
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
                        if (_customizeExpanded)
                          RetroCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                _buildVisibilityPicker(),
                                // TR-101: a team race's field cap is fixed at
                                // 2 x teamSize — no free-form runner cap.
                                if (_isTournament) ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    'FIELD SIZE',
                                    style: PixelText.body(
                                      size: 11,
                                      color: AppColors.of(context).textMid,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    Tournament.sizeSubcopy(_bracketSize),
                                    style: PixelText.title(
                                      size: 13,
                                      color: AppColors.of(context).textDark,
                                    ),
                                  ),
                                ] else if (!_isTeamRace) ...[
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
                                            !_noLimit &&
                                            _maxParticipants == preset;
                                        return _maxRunnersChip(
                                          label: '$preset',
                                          selected: selected,
                                          onTap: () => setState(() {
                                            _noLimit = false;
                                            _maxParticipants = preset;
                                          }),
                                        );
                                      }),
                                      _maxRunnersChip(
                                        label: 'NO LIMIT',
                                        selected: _noLimit,
                                        onTap: () => setState(() {
                                          _noLimit = true;
                                          _maxParticipants = null;
                                        }),
                                      ),
                                    ],
                                  ),
                                ] else ...[
                                  const SizedBox(height: 12),
                                  Text(
                                    'FIELD SIZE',
                                    style: PixelText.body(
                                      size: 11,
                                      color: AppColors.of(context).textMid,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    '${_teamSize}v$_teamSize · '
                                    '${_teamSize * 2} racers max',
                                    style: PixelText.title(
                                      size: 13,
                                      color: AppColors.of(context).textDark,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        const SizedBox(height: 24),

                        // Create button
                        KeyedSubtree(
                          key: widget.tutorialCreateKey,
                          child: PillButton(
                            label: _isCreating ? 'CREATING...' : 'CREATE RACE',
                            variant: PillButtonVariant.primary,
                            fontSize: 15,
                            fullWidth: true,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 24,
                              vertical: 14,
                            ),
                            // Disabled while the custom window is illegal, so
                            // the user never round-trips to a 400 (§4.4).
                            onPressed:
                                (_isCreating || _customWindowError != null)
                                ? null
                                : _create,
                          ),
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
