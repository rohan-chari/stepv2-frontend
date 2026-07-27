import 'package:flutter/material.dart';

import '../models/race_payouts.dart';
import '../models/race_prize_pool.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/team_race.dart';
import '../utils/tournament.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/powerup_interval_note.dart';
import '../widgets/retro_card.dart';
import 'tournament_detail_screen.dart';

class CreateRaceScreen extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;
  final List<String> presetInviteeIds;
  final bool initialCustomizeExpanded;

  CreateRaceScreen({
    super.key,
    required this.authService,
    BackendApiService? backendApiService,
    this.presetInviteeIds = const [],
    this.initialCustomizeExpanded = false,
  }) : backendApiService = backendApiService ?? BackendApiService();

  @override
  State<CreateRaceScreen> createState() => CreateRaceScreenState();
}

class CreateRaceScreenState extends State<CreateRaceScreen> {
  final _nameController = TextEditingController();
  int _selectedDuration = 3;
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
  DateTime? _scheduledStartAt;
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

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  // Every option lands on a prize-pool band boundary (D3), so the previewed
  // pool always reflects the exact multiplier the backend will apply.
  static const _durationOptions = [1, 3, 7, 14];
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

  // -- App-funded prize pool preview ---------------------------------------
  //
  // The race doesn't exist yet, so the pool is computed client-side from the
  // mirrored duration table in `models/race_prize_pool.dart` (guarded against
  // the backend's fixtures by `race_prize_pool_test`). It is a PROJECTION off
  // the field cap — the settled pool counts only runners who actually walked —
  // so the copy says "up to", never "you will win".

  /// The field size the preview projects against: the team-race field is fixed
  /// at 2 × teamSize, otherwise it's the runner cap. Null = NO LIMIT, which
  /// saturates the ceiling.
  int? get _projectedFieldSize {
    if (_isTeamRace) return _teamSize * 2;
    if (_noLimit) return null;
    return _maxParticipants;
  }

  int get _projectedPrizePool {
    final field = _projectedFieldSize;
    if (field == null) return kPrizePoolMaxCoins;
    return computePrizePool(
      playerCount: field,
      durationDays: _selectedDuration,
    );
  }

  String get _projectedPrizeDerivation {
    final field = _projectedFieldSize;
    final days = _selectedDuration == 1 ? '1 DAY' : '$_selectedDuration DAYS';
    final players = field == null
        ? 'UNLIMITED PLAYERS'
        : (field == 1 ? '1 PLAYER' : '$field PLAYERS');
    return '$players × $days';
  }

  /// The carved gold plaque that carries a pool figure: an "up to" number that
  /// re-stamps itself whenever the field or the duration changes, its own
  /// arithmetic spelled out underneath so the number is never a mystery.
  Widget _prizePoolPlaque({
    required int coins,
    required bool atMax,
    required String derivation,
    // Optional trailing line. Nothing on this screen sets it any more, but the
    // plaque keeps the slot for callers that still want one.
    String? footnote,
    Key? key,
    Key? coinsKey,
    Key? derivationKey,
    Key? maxKey,
  }) {
    final palette = AppColors.of(context);
    return Container(
      key: key,
      width: double.infinity,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: palette.coinLight.withValues(alpha: 0.18),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: palette.coinDark.withValues(alpha: 0.45),
          width: 2,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'PRIZE POOL',
                  style: PixelText.title(size: 12, color: palette.textMid),
                ),
              ),
              if (atMax)
                Container(
                  key: maxKey,
                  padding: const EdgeInsets.symmetric(
                    horizontal: 7,
                    vertical: 3,
                  ),
                  decoration: BoxDecoration(
                    color: palette.coinDark,
                    borderRadius: BorderRadius.circular(5),
                  ),
                  child: Text(
                    'MAX',
                    style: PixelText.title(size: 9, color: Colors.white),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 6),
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              Image.asset(
                'assets/images/coin.png',
                width: 24,
                height: 24,
                fit: BoxFit.contain,
                errorBuilder: (_, _, _) =>
                    Icon(Icons.paid_rounded, size: 22, color: palette.coinDark),
              ),
              const SizedBox(width: 8),
              Text(
                'UP TO',
                style: PixelText.body(size: 10, color: palette.textMid),
              ),
              const SizedBox(width: 6),
              // Re-stamps with a quick punch on every change, so a bigger
              // field visibly pays more.
              Flexible(
                child: TweenAnimationBuilder<double>(
                  key: ValueKey(coins),
                  tween: Tween<double>(begin: 0.84, end: 1),
                  duration: const Duration(milliseconds: 220),
                  curve: Curves.easeOutBack,
                  builder: (_, value, child) => Transform.scale(
                    scale: value,
                    alignment: Alignment.centerLeft,
                    child: child,
                  ),
                  child: Text(
                    formatPrizeCoins(coins),
                    key: coinsKey,
                    maxLines: 1,
                    style: PixelText.number(size: 28, color: palette.coinDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            derivation,
            key: derivationKey,
            style: PixelText.body(size: 11, color: palette.textMid),
          ),
          if (footnote != null && footnote.isNotEmpty) ...[
            const SizedBox(height: 2),
            Text(
              footnote,
              style: PixelText.body(size: 10, color: palette.textMid),
            ),
          ],
        ],
      ),
    );
  }

  /// The race-side preview card, shown under the duration picker.
  Widget _buildPrizePoolPreview() {
    final coins = _projectedPrizePool;
    // A field that can't pay anybody shows nothing rather than a hollow 0.
    if (coins <= 0) return const SizedBox.shrink();
    return RetroCard(
      padding: const EdgeInsets.all(16),
      child: _prizePoolPlaque(
        key: const Key('create-prize-pool-preview'),
        coinsKey: const Key('create-prize-pool-coins'),
        derivationKey: const Key('create-prize-pool-derivation'),
        maxKey: const Key('create-prize-pool-max'),
        coins: coins,
        atMax: coins >= kPrizePoolMaxCoins,
        derivation: _projectedPrizeDerivation,
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

  // Bara-themed wrapper for the stock Material date/time pickers: parchment
  // surfaces, accent-green selection, wood-frame border — so they read like
  // the app's RetroCard/GameContainer dialogs instead of raw Material 3.
  Widget _themedPicker(BuildContext context, Widget? child) {
    final base = Theme.of(context);
    return Theme(
      data: base.copyWith(
        colorScheme: base.colorScheme.copyWith(
          primary: AppColors.of(context).accent,
          onPrimary: AppColors.of(context).parchment,
          secondary: AppColors.of(context).accentLight,
          surface: AppColors.of(context).parchment,
          onSurface: AppColors.of(context).textDark,
          onSurfaceVariant: AppColors.of(context).textMid,
        ),
        datePickerTheme: DatePickerThemeData(
          backgroundColor: AppColors.of(context).parchment,
          headerBackgroundColor: AppColors.of(context).accent,
          headerForegroundColor: AppColors.of(context).parchment,
          weekdayStyle: PixelText.body(
            size: 13,
            color: AppColors.of(context).textMid,
          ),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.of(context).accent, width: 2),
          ),
        ),
        timePickerTheme: TimePickerThemeData(
          backgroundColor: AppColors.of(context).parchment,
          dialBackgroundColor: AppColors.of(context).parchmentDark,
          dialHandColor: AppColors.of(context).accent,
          hourMinuteColor: AppColors.of(context).parchmentDark,
          hourMinuteTextColor: AppColors.of(context).textDark,
          dayPeriodTextColor: AppColors.of(context).textDark,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(16),
            side: BorderSide(color: AppColors.of(context).accent, width: 2),
          ),
        ),
        textButtonTheme: TextButtonThemeData(
          style: TextButton.styleFrom(
            foregroundColor: AppColors.of(context).accent,
            textStyle: PixelText.button(
              size: 14,
              color: AppColors.of(context).buttonText,
            ),
          ),
        ),
      ),
      child: child!,
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

  Future<void> _create() async {
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
          _isTournament && e.code != null
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
                  key: const Key('race-format-ffa'),
                  label: 'SOLO',
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
          style: PixelText.body(
            size: 11,
            color: AppColors.of(context).textMid,
          ),
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
        const SizedBox(height: 12),
        _prizePoolPlaque(
          key: const Key('tournament-prize-pool-preview'),
          coinsKey: const Key('tournament-prize-pool-coins'),
          derivationKey: const Key('tournament-prize-pool-derivation'),
          maxKey: const Key('tournament-prize-pool-max'),
          coins: _tournamentPrizePool,
          atMax: _tournamentPrizePool >= kTournamentPrizePoolMaxCoins,
          derivation: '$_bracketSize PLAYERS × $_tournamentTotalDays DAYS',
        ),
      ],
    );
  }

  /// The whole bracket's length in days — every round back to back (D9).
  int get _tournamentTotalDays =>
      tournamentRoundsForSize(_bracketSize) * _matchupDuration;

  /// A bracket only starts full, so the projected field is the bracket size.
  int get _tournamentPrizePool => computePrizePool(
    playerCount: _bracketSize,
    durationDays: _tournamentTotalDays,
    max: kTournamentPrizePoolMaxCoins,
  );

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
                            widget.authService.teamRacesEnabled) ...[
                          _buildFormatCard(),
                          const SizedBox(height: 12),
                        ],

                        // Duration + scheduled-start are hidden for tournaments:
                        // matchup length is fixed by the bracket picker and
                        // tournaments never schedule-auto-start (spec §9).
                        if (!_isTournament) ...[
                          // Duration
                          RetroCard(
                            padding: const EdgeInsets.all(16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  'DURATION',
                                  style: PixelText.title(
                                    size: 13,
                                    color: AppColors.of(context).textMid,
                                  ),
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: _durationOptions.map((days) {
                                    final selected = _selectedDuration == days;
                                    return Expanded(
                                      child: GestureDetector(
                                        key: Key('duration-option-$days'),
                                        onTap: () => setState(
                                          () => _selectedDuration = days,
                                        ),
                                        child: Container(
                                          margin: const EdgeInsets.symmetric(
                                            horizontal: 3,
                                          ),
                                          padding: const EdgeInsets.symmetric(
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
                                          alignment: Alignment.center,
                                          child: Text(
                                            '${days}d',
                                            style: PixelText.title(
                                              size: 15,
                                              color: selected
                                                  ? Colors.white
                                                  : AppColors.of(
                                                      context,
                                                    ).textDark,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),

                          // What the field is racing for. Sits right under the
                          // duration + (below) the runner cap, because those
                          // two controls are what move the number.
                          _buildPrizePoolPreview(),
                          const SizedBox(height: 12),

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
                                  color: AppColors.of(context).parchmentBorder,
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
                                        color: AppColors.of(context).textLight,
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
                          const SizedBox(height: 12),

                          // Scheduled start (optional auto-start)
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
                          if (_customizeExpanded) const SizedBox(height: 12),
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
                        PillButton(
                          label: _isCreating ? 'CREATING...' : 'CREATE RACE',
                          variant: PillButtonVariant.primary,
                          fontSize: 15,
                          fullWidth: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          onPressed: _isCreating ? null : _create,
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
