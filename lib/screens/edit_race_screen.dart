import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/race_payouts.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/team_race.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';

/// Full-screen editor for race settings. Available only to the creator while
/// the race is still PENDING. Mirrors [CreateRaceScreen] but pre-populates
/// from the race detail and PATCHes the changed fields.
class EditRaceScreen extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;
  final String raceId;
  final Map<String, dynamic> race;

  EditRaceScreen({
    super.key,
    required this.authService,
    required this.raceId,
    required this.race,
    BackendApiService? backendApiService,
  }) : backendApiService = backendApiService ?? BackendApiService();

  @override
  State<EditRaceScreen> createState() => _EditRaceScreenState();
}

class _EditRaceScreenState extends State<EditRaceScreen> {
  late final TextEditingController _nameController;
  late final TextEditingController _buyInController;

  bool _isSaving = false;

  // Initial values (used to compute "changed" diff for PATCH)
  late final String _initialName;
  late final int _initialMaxDurationDays;
  late final bool _initialPowerupsEnabled;
  late final int _initialPowerupInterval;
  late final bool _initialBuyInEnabled;
  late final int _initialBuyInAmount;
  late final String _initialPayoutPreset;
  late final bool _initialIsPublic;
  // null => no participant limit (unlimited).
  late final int? _initialMaxParticipants;

  // Live values
  late int _maxDurationDays;
  late bool _powerupsEnabled;
  late int _powerupInterval;
  late bool _buyInEnabled;
  late int _buyInAmount;
  late String _payoutPreset;
  late bool _isPublic;
  // null => no participant limit (unlimited).
  late int? _maxParticipants;

  // Locked = participants have paid in; buy-in becomes non-editable
  late final bool _buyInLocked;
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

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const _durationOptions = [3, 5, 7, 14];
  static const _intervalPresets = [2000, 3000, 4000, 5000, 10000, 25000];
  static const _maxParticipantsPresets = [5, 10, 25, 50, 100];

  @override
  void initState() {
    super.initState();
    final race = widget.race;

    _initialName = (race['name'] as String?) ?? '';
    _initialMaxDurationDays = _readInt(race['maxDurationDays'], 7);
    _initialPowerupsEnabled = race['powerupsEnabled'] == true;
    _initialPowerupInterval =
        _readInt(race['powerupStepInterval'], 5000).clamp(2000, 50000);
    _initialBuyInAmount = _readInt(race['buyInAmount'], 0);
    _initialBuyInEnabled = _initialBuyInAmount > 0;
    _initialPayoutPreset =
        (race['payoutPreset'] as String?) ?? 'WINNER_TAKES_ALL';
    _initialIsPublic = race['isPublic'] == true;
    _initialMaxParticipants = _readNullableMax(race['maxParticipants']);

    final participants =
        (race['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    _acceptedCount = participants
        .where((p) => p['status'] == 'ACCEPTED')
        .length;
    _buyInLocked = participants.any((p) {
      final status = p['buyInStatus'] as String?;
      return status == 'HELD' || status == 'COMMITTED';
    });

    _isTeamRace = TeamRace.isTeamRace(race);
    _initialTeamAName = TeamRace.teamName(race, RaceTeam.teamA);
    _initialTeamBName = TeamRace.teamName(race, RaceTeam.teamB);
    _initialTeamSize = (TeamRace.teamSize(race) ?? 1).clamp(1, 5);
    _teamSize = _initialTeamSize;
    _teamANameController = TextEditingController(text: _initialTeamAName);
    _teamBNameController = TextEditingController(text: _initialTeamBName);
    _teamACount = participants
        .where(
          (p) =>
              p['status'] == 'ACCEPTED' &&
              TeamRace.participantTeam(p) == RaceTeam.teamA,
        )
        .length;
    _teamBCount = participants
        .where(
          (p) =>
              p['status'] == 'ACCEPTED' &&
              TeamRace.participantTeam(p) == RaceTeam.teamB,
        )
        .length;

    _nameController = TextEditingController(text: _initialName);
    _buyInController = TextEditingController(
      text: (_initialBuyInEnabled ? _initialBuyInAmount : 100).toString(),
    );

    _maxDurationDays = _initialMaxDurationDays;
    _powerupsEnabled = _initialPowerupsEnabled;
    _powerupInterval = _initialPowerupInterval;
    _buyInEnabled = _initialBuyInEnabled;
    _buyInAmount = _initialBuyInAmount > 0 ? _initialBuyInAmount : 100;
    _payoutPreset = _initialPayoutPreset;
    _isPublic = _initialIsPublic;
    _maxParticipants = _initialMaxParticipants;
  }

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
            color: selected ? AppColors.pillGreenDark : AppColors.parchmentDark,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            label,
            style: PixelText.title(
              size: 13,
              color: selected ? Colors.white : AppColors.textDark,
            ),
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
            style: PixelText.title(size: 13, color: AppColors.textMid),
          ),
          const SizedBox(height: 10),
          _buildTeamSizeStepper(),
          const SizedBox(height: 14),
          Text(
            'TEAM NAMES',
            style: PixelText.body(size: 11, color: AppColors.textMid),
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
              style: PixelText.body(size: 11, color: AppColors.textMid),
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
        color: AppColors.parchmentDark,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.parchmentBorder, width: 2),
      ),
      child: Row(
        children: [
          _teamStepperButton(
            key: const Key('edit-team-size-minus'),
            icon: Icons.remove_rounded,
            enabled: _teamSize > 1,
            onTap: () => setState(() => _teamSize = (_teamSize - 1).clamp(1, 5)),
          ),
          Expanded(
            child: Column(
              children: [
                Text(
                  '${_teamSize}v$_teamSize',
                  style: PixelText.number(size: 30, color: AppColors.textDark),
                ),
                const SizedBox(height: 2),
                Text(
                  _teamSize < floor
                      ? 'TOO SMALL — $floor ALREADY IN'
                      : '${_teamSize * 2} RACERS MAX',
                  style: PixelText.body(
                    size: 10,
                    color: _teamSize < floor
                        ? AppColors.error
                        : AppColors.textMid,
                  ),
                ),
              ],
            ),
          ),
          _teamStepperButton(
            key: const Key('edit-team-size-plus'),
            icon: Icons.add_rounded,
            enabled: _teamSize < 5,
            onTap: () => setState(() => _teamSize = (_teamSize + 1).clamp(1, 5)),
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
            gradient: const LinearGradient(
              begin: Alignment.topCenter,
              end: Alignment.bottomCenter,
              colors: [AppColors.buttonLight, AppColors.buttonFace],
            ),
            borderRadius: BorderRadius.circular(10),
            border: Border.all(color: AppColors.buttonDark, width: 2.5),
            boxShadow: const [
              BoxShadow(
                color: AppColors.buttonShadow,
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
    final color = TeamRace.color(team);
    final colorLight = TeamRace.colorLight(team);
    final colorDark = TeamRace.colorDark(team);
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
          BoxShadow(color: colorDark, offset: const Offset(0, 3), blurRadius: 0),
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

  /// Reads maxParticipants where a null/absent value means "no limit"
  /// (unlimited). Defensive: a newer backend serializes unlimited races as null.
  int? _readNullableMax(dynamic value) {
    if (value == null) return null;
    return _readInt(value, 10);
  }

  @override
  void dispose() {
    _nameController.dispose();
    _buyInController.dispose();
    _teamANameController.dispose();
    _teamBNameController.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final name = _nameController.text.trim();
    if (name != _initialName.trim()) return true;
    if (_maxDurationDays != _initialMaxDurationDays) return true;
    if (_powerupsEnabled != _initialPowerupsEnabled) return true;
    if (_powerupsEnabled && _powerupInterval != _initialPowerupInterval) {
      return true;
    }
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

    final effectiveBuyIn = _buyInEnabled ? _buyInAmount : 0;
    if (effectiveBuyIn != _initialBuyInAmount) return true;
    final effectivePreset =
        _buyInEnabled ? _payoutPreset : _initialPayoutPreset;
    if (effectivePreset != _initialPayoutPreset) return true;

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

    if (_buyInEnabled && _buyInAmount > 0 && _buyInAmount < 10) {
      showErrorToast(context, 'Buy-in must be at least 10 coins');
      return;
    }
    if (_buyInEnabled && _buyInAmount > 200) {
      showErrorToast(context, 'Buy-in cannot exceed 200 coins');
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
    if (_powerupsEnabled && _powerupInterval != _initialPowerupInterval) {
      updates['powerupStepInterval'] = _powerupInterval;
    }
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

    final effectiveBuyIn = _buyInEnabled ? _buyInAmount : 0;
    if (effectiveBuyIn != _initialBuyInAmount) {
      updates['buyInAmount'] = effectiveBuyIn;
    }
    if (_buyInEnabled && _payoutPreset != _initialPayoutPreset) {
      updates['payoutPreset'] = _payoutPreset;
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
        powerupStepInterval: updates['powerupStepInterval'] as int?,
        buyInAmount: updates['buyInAmount'] as int?,
        payoutPreset: updates['payoutPreset'] as String?,
        maxParticipants: updates['maxParticipants'] as int?,
        setMaxParticipantsUnlimited: maxChanged && _maxParticipants == null,
        teamAName: updates['teamAName'] as String?,
        teamBName: updates['teamBName'] as String?,
        teamSize: updates['teamSize'] as int?,
      );

      if (mounted) {
        Navigator.of(context).pop(result['race'] as Map<String, dynamic>?);
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isSaving = false);
        showErrorToast(context, e.toString());
      }
    }
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
                        child: const Padding(
                          padding: EdgeInsets.all(8),
                          child: Icon(
                            Icons.arrow_back,
                            color: AppColors.parchmentLight,
                            size: 24,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        'EDIT RACE',
                        style: PixelText.title(
                          size: 22,
                          color: AppColors.parchmentLight,
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
                                  color: AppColors.textMid,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _nameController,
                                maxLength: 50,
                                onChanged: (_) => setState(() {}),
                                style: PixelText.body(
                                  size: 16,
                                  color: AppColors.textDark,
                                ),
                                decoration: InputDecoration(
                                  hintText: 'e.g. Weekend Warriors',
                                  hintStyle: PixelText.body(
                                    size: 16,
                                    color: AppColors.textMid.withValues(
                                      alpha: 0.5,
                                    ),
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
                                  color: AppColors.textMid,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Row(
                                children: _durationOptions.map((days) {
                                  final selected = _maxDurationDays == days;
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(
                                        () => _maxDurationDays = days,
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
                                              ? AppColors.pillGreenDark
                                              : AppColors.parchmentDark,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '${days}d',
                                          style: PixelText.title(
                                            size: 15,
                                            color: selected
                                                ? Colors.white
                                                : AppColors.textDark,
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
                                      color: AppColors.textMid,
                                    ),
                                  ),
                                  SizedBox(
                                    height: 28,
                                    child: Switch.adaptive(
                                      value: _powerupsEnabled,
                                      activeTrackColor:
                                          AppColors.pillGreenDark,
                                      onChanged: (v) => setState(
                                        () => _powerupsEnabled = v,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_powerupsEnabled) ...[
                                const SizedBox(height: 8),
                                Text(
                                  'POWERUP EVERY',
                                  style: PixelText.body(
                                    size: 11,
                                    color: AppColors.textMid,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Wrap(
                                  spacing: 8,
                                  runSpacing: 8,
                                  children: _intervalPresets.map((interval) {
                                    final selected =
                                        _powerupInterval == interval;
                                    final label = interval >= 1000
                                        ? '${(interval / 1000).toStringAsFixed(interval % 1000 == 0 ? 0 : 1)}k'
                                        : '$interval';
                                    return SizedBox(
                                      width: 72,
                                      child: GestureDetector(
                                        onTap: () => setState(
                                          () => _powerupInterval = interval,
                                        ),
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            vertical: 10,
                                            horizontal: 6,
                                          ),
                                          decoration: BoxDecoration(
                                            color: selected
                                                ? AppColors.pillGreenDark
                                                : AppColors.parchmentDark,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          alignment: Alignment.center,
                                          child: Text(
                                            label,
                                            style: PixelText.title(
                                              size: 11,
                                              color: selected
                                                  ? Colors.white
                                                  : AppColors.textDark,
                                            ),
                                          ),
                                        ),
                                      ),
                                    );
                                  }).toList(),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Buy-in
                        RetroCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  GestureDetector(
                                    onTap: _buyInLocked
                                        ? null
                                        : () => setState(
                                              () => _buyInEnabled =
                                                  !_buyInEnabled,
                                            ),
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          'BUY-IN',
                                          style: PixelText.title(
                                            size: 13,
                                            color: AppColors.textMid,
                                          ),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          _buyInLocked
                                              ? 'LOCKED — RUNNERS PAID'
                                              : (_buyInEnabled
                                                  ? 'PAID RACE'
                                                  : 'FREE RACE'),
                                          style: PixelText.body(
                                            size: 11,
                                            color: _buyInLocked
                                                ? AppColors.textMid
                                                : (_buyInEnabled
                                                    ? AppColors.coinDark
                                                    : AppColors.textMid),
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  SizedBox(
                                    height: 28,
                                    child: Switch.adaptive(
                                      value: _buyInEnabled,
                                      activeTrackColor:
                                          AppColors.pillGreenDark,
                                      onChanged: _buyInLocked
                                          ? null
                                          : (value) => setState(
                                                () => _buyInEnabled = value,
                                              ),
                                    ),
                                  ),
                                ],
                              ),
                              if (_buyInEnabled) ...[
                                const SizedBox(height: 12),
                                Text(
                                  'BUY-IN PER RUNNER',
                                  style: PixelText.body(
                                    size: 11,
                                    color: AppColors.textMid,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Container(
                                  decoration: BoxDecoration(
                                    color: AppColors.parchment,
                                    border: Border.all(
                                      color: AppColors.parchmentBorder,
                                      width: 2,
                                    ),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 12,
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.edit_outlined,
                                        size: 16,
                                        color: AppColors.textMid.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: TextField(
                                          controller: _buyInController,
                                          enabled: !_buyInLocked,
                                          keyboardType: TextInputType.number,
                                          inputFormatters: [
                                            FilteringTextInputFormatter
                                                .digitsOnly,
                                          ],
                                          onChanged: (value) {
                                            setState(() {
                                              _buyInAmount =
                                                  int.tryParse(value) ?? 0;
                                            });
                                          },
                                          style: PixelText.number(
                                            size: 24,
                                            color: AppColors.coinDark,
                                          ),
                                          decoration: InputDecoration(
                                            hintText: '0',
                                            hintStyle: PixelText.number(
                                              size: 24,
                                              color: AppColors.coinDark
                                                  .withValues(alpha: 0.3),
                                            ),
                                            border: InputBorder.none,
                                            isDense: true,
                                            contentPadding: EdgeInsets.zero,
                                            suffixText: 'coins',
                                            suffixStyle: PixelText.body(
                                              size: 12,
                                              color: AppColors.textMid,
                                            ),
                                          ),
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                if (_buyInLocked) ...[
                                  const SizedBox(height: 8),
                                  Text(
                                    'Buy-in is locked — a runner has already paid in.',
                                    style: PixelText.body(
                                      size: 11,
                                      color: AppColors.textMid,
                                    ),
                                  ),
                                ],
                                const SizedBox(height: 12),
                                Text(
                                  'PAYOUT MODE',
                                  style: PixelText.body(
                                    size: 11,
                                    color: AppColors.textMid,
                                  ),
                                ),
                                const SizedBox(height: 8),
                                Column(
                                  children: payoutPresetOptions.map((option) {
                                    final selected =
                                        _payoutPreset == option.$2;
                                    return Padding(
                                      padding:
                                          const EdgeInsets.only(bottom: 8),
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
                                                ? AppColors.pillGreenDark
                                                : AppColors.parchmentDark,
                                            borderRadius:
                                                BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            option.$1,
                                            style: PixelText.title(
                                              size: 12,
                                              color: selected
                                                  ? Colors.white
                                                  : AppColors.textDark,
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
                                      color: AppColors.textMid,
                                    ),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                              ],
                            ],
                          ),
                        ),
                        const SizedBox(height: 24),

                        // Public race
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
                                        _isPublic
                                            ? 'PUBLIC RACE'
                                            : 'PRIVATE RACE',
                                        style: PixelText.title(
                                          size: 13,
                                          color: AppColors.textMid,
                                        ),
                                      ),
                                      const SizedBox(height: 2),
                                      Text(
                                        _isPublic
                                            ? 'ANYONE CAN JOIN'
                                            : 'INVITE ONLY',
                                        style: PixelText.body(
                                          size: 11,
                                          color: _isPublic
                                              ? AppColors.pillGreenDark
                                              : AppColors.textMid,
                                        ),
                                      ),
                                    ],
                                  ),
                                  SizedBox(
                                    height: 28,
                                    child: Switch.adaptive(
                                      value: _isPublic,
                                      activeTrackColor:
                                          AppColors.pillGreenDark,
                                      onChanged: (v) =>
                                          setState(() => _isPublic = v),
                                    ),
                                  ),
                                ],
                              ),
                              // TR-101/105: a team race's field cap is derived
                              // (2 x teamSize) — the runner-cap chips don't
                              // apply; the size stepper above owns it.
                              if (!_isTeamRace) ...[
                              const SizedBox(height: 12),
                              Text(
                                'MAX RUNNERS',
                                style: PixelText.body(
                                  size: 11,
                                  color: AppColors.textMid,
                                ),
                              ),
                              const SizedBox(height: 8),
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: [
                                  ..._maxParticipantsPresets.map((preset) {
                                    final selected = _maxParticipants == preset;
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
                                    color: AppColors.textMid,
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
                          onPressed: (_isSaving || !_hasChanges)
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
