import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
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
  late final TextEditingController _stepsController;
  late final TextEditingController _buyInController;

  bool _isSaving = false;

  // Initial values (used to compute "changed" diff for PATCH)
  late final String _initialName;
  late final int _initialTargetSteps;
  late final bool _initialPowerupsEnabled;
  late final int _initialPowerupInterval;
  late final bool _initialBuyInEnabled;
  late final int _initialBuyInAmount;
  late final String _initialPayoutPreset;
  late final bool _initialIsPublic;
  late final int _initialMaxParticipants;

  // Live values
  late bool _powerupsEnabled;
  late int _powerupInterval;
  late bool _buyInEnabled;
  late int _buyInAmount;
  late String _payoutPreset;
  late bool _isPublic;
  late int _maxParticipants;

  // Locked = participants have paid in; buy-in becomes non-editable
  late final bool _buyInLocked;
  late final int _acceptedCount;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const _stepPresets = [25000, 50000, 100000, 250000];
  static const _intervalPresets = [2000, 3000, 4000, 5000, 10000, 25000];
  static const _maxParticipantsPresets = [5, 10, 25, 50, 100];
  static const _payoutOptions = [
    ('WINNER TAKE ALL', 'WINNER_TAKES_ALL'),
    ('TOP 3 70/20/10', 'TOP3_70_20_10'),
    ('TOP 3 80/15/5', 'TOP3_80_15_5'),
  ];

  @override
  void initState() {
    super.initState();
    final race = widget.race;

    _initialName = (race['name'] as String?) ?? '';
    _initialTargetSteps = _readInt(race['targetSteps'], 50000);
    _initialPowerupsEnabled = race['powerupsEnabled'] == true;
    _initialPowerupInterval =
        _readInt(race['powerupStepInterval'], 5000).clamp(2000, 50000);
    _initialBuyInAmount = _readInt(race['buyInAmount'], 0);
    _initialBuyInEnabled = _initialBuyInAmount > 0;
    _initialPayoutPreset =
        (race['payoutPreset'] as String?) ?? 'WINNER_TAKES_ALL';
    _initialIsPublic = race['isPublic'] == true;
    _initialMaxParticipants = _readInt(race['maxParticipants'], 10);

    final participants =
        (race['participants'] as List?)?.cast<Map<String, dynamic>>() ?? [];
    _acceptedCount = participants
        .where((p) => p['status'] == 'ACCEPTED')
        .length;
    _buyInLocked = participants.any((p) {
      final status = p['buyInStatus'] as String?;
      return status == 'HELD' || status == 'COMMITTED';
    });

    _nameController = TextEditingController(text: _initialName);
    _stepsController =
        TextEditingController(text: _initialTargetSteps.toString());
    _buyInController = TextEditingController(
      text: (_initialBuyInEnabled ? _initialBuyInAmount : 100).toString(),
    );

    _powerupsEnabled = _initialPowerupsEnabled;
    _powerupInterval = _initialPowerupInterval;
    _buyInEnabled = _initialBuyInEnabled;
    _buyInAmount = _initialBuyInAmount > 0 ? _initialBuyInAmount : 100;
    _payoutPreset = _initialPayoutPreset;
    _isPublic = _initialIsPublic;
    _maxParticipants = _initialMaxParticipants;
  }

  int _readInt(dynamic value, int fallback) {
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value is String) return int.tryParse(value) ?? fallback;
    return fallback;
  }

  @override
  void dispose() {
    _nameController.dispose();
    _stepsController.dispose();
    _buyInController.dispose();
    super.dispose();
  }

  bool get _hasChanges {
    final name = _nameController.text.trim();
    if (name != _initialName.trim()) return true;
    final steps = int.tryParse(_stepsController.text.replaceAll(',', ''));
    if (steps != _initialTargetSteps) return true;
    if (_powerupsEnabled != _initialPowerupsEnabled) return true;
    if (_powerupsEnabled && _powerupInterval != _initialPowerupInterval) {
      return true;
    }
    if (_isPublic != _initialIsPublic) return true;
    if (_maxParticipants != _initialMaxParticipants) return true;

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

    final steps = int.tryParse(_stepsController.text.replaceAll(',', ''));
    if (steps == null || steps < 1000) {
      showErrorToast(context, 'Target must be at least 1,000 steps');
      return;
    }
    if (steps > 1000000) {
      showErrorToast(context, 'Target must be 1,000,000 steps or less');
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

    if (_maxParticipants < _acceptedCount) {
      showErrorToast(
        context,
        'Cannot reduce max runners below $_acceptedCount accepted',
      );
      return;
    }

    // Build a sparse PATCH body — only send changed fields.
    final updates = <String, dynamic>{};
    if (name != _initialName.trim()) updates['name'] = name;
    if (steps != _initialTargetSteps) updates['targetSteps'] = steps;
    if (_powerupsEnabled != _initialPowerupsEnabled) {
      updates['powerupsEnabled'] = _powerupsEnabled;
    }
    if (_powerupsEnabled && _powerupInterval != _initialPowerupInterval) {
      updates['powerupStepInterval'] = _powerupInterval;
    }
    if (_isPublic != _initialIsPublic) updates['isPublic'] = _isPublic;
    if (_maxParticipants != _initialMaxParticipants) {
      updates['maxParticipants'] = _maxParticipants;
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

      final result = await widget.backendApiService.updateRace(
        identityToken: token,
        raceId: widget.raceId,
        name: updates['name'] as String?,
        targetSteps: updates['targetSteps'] as int?,
        isPublic: updates['isPublic'] as bool?,
        powerupsEnabled: updates['powerupsEnabled'] as bool?,
        powerupStepInterval: updates['powerupStepInterval'] as int?,
        buyInAmount: updates['buyInAmount'] as int?,
        payoutPreset: updates['payoutPreset'] as String?,
        maxParticipants: updates['maxParticipants'] as int?,
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

                        // Target steps
                        RetroCard(
                          padding: const EdgeInsets.all(16),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Text(
                                'TARGET STEPS',
                                style: PixelText.title(
                                  size: 13,
                                  color: AppColors.textMid,
                                ),
                              ),
                              const SizedBox(height: 8),
                              TextField(
                                controller: _stepsController,
                                keyboardType: TextInputType.number,
                                onChanged: (_) => setState(() {}),
                                inputFormatters: [
                                  FilteringTextInputFormatter.digitsOnly,
                                ],
                                style: PixelText.number(
                                  size: 28,
                                  color: AppColors.accent,
                                ),
                                decoration: InputDecoration(
                                  hintText: '50000',
                                  hintStyle: PixelText.number(
                                    size: 28,
                                    color: AppColors.accent.withValues(
                                      alpha: 0.3,
                                    ),
                                  ),
                                  border: InputBorder.none,
                                  isDense: true,
                                  contentPadding: EdgeInsets.zero,
                                ),
                              ),
                              const SizedBox(height: 10),
                              Wrap(
                                spacing: 8,
                                children: _stepPresets.map((preset) {
                                  final label = preset >= 1000
                                      ? '${(preset / 1000).toStringAsFixed(0)}k'
                                      : '$preset';
                                  return GestureDetector(
                                    onTap: () => setState(() {
                                      _stepsController.text =
                                          preset.toString();
                                    }),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 12,
                                        vertical: 6,
                                      ),
                                      decoration: BoxDecoration(
                                        color: AppColors.parchmentDark,
                                        borderRadius:
                                            BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        label,
                                        style: PixelText.title(
                                          size: 13,
                                          color: AppColors.textDark,
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
                                  children: _payoutOptions.map((option) {
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
                                    _payoutPreset == 'WINNER_TAKES_ALL'
                                        ? 'Winner takes the whole pot.'
                                        : 'Top 3 payouts need at least 4 accepted runners before the race can start.',
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
                                        'PUBLIC RACE',
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
                                children:
                                    _maxParticipantsPresets.map((preset) {
                                  final selected =
                                      _maxParticipants == preset;
                                  final disabled = preset < _acceptedCount;
                                  return GestureDetector(
                                    onTap: disabled
                                        ? null
                                        : () => setState(
                                              () => _maxParticipants = preset,
                                            ),
                                    child: Opacity(
                                      opacity: disabled ? 0.4 : 1.0,
                                      child: Container(
                                        padding: const EdgeInsets.symmetric(
                                          horizontal: 14,
                                          vertical: 8,
                                        ),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? AppColors.pillGreenDark
                                              : AppColors.parchmentDark,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        child: Text(
                                          '$preset',
                                          style: PixelText.title(
                                            size: 13,
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
