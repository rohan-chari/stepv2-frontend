import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../models/race_payouts.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';

class CreateRaceScreen extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;
  final List<String> presetInviteeIds;

  CreateRaceScreen({
    super.key,
    required this.authService,
    BackendApiService? backendApiService,
    this.presetInviteeIds = const [],
  }) : backendApiService = backendApiService ?? BackendApiService();

  @override
  State<CreateRaceScreen> createState() => CreateRaceScreenState();
}

class CreateRaceScreenState extends State<CreateRaceScreen> {
  final _nameController = TextEditingController();
  final _buyInController = TextEditingController(text: '100');
  int _selectedDuration = 7;
  bool _isCreating = false;
  bool _powerupsEnabled = false;
  int _powerupInterval = 2000;
  bool _buyInEnabled = false;
  int _buyInAmount = 100;
  String _payoutPreset = 'WINNER_TAKES_ALL';
  bool _isPublic = false;
  // Participant cap. Required selection: the user must pick a preset number or
  // NO LIMIT before creating. `_noLimit == false && _maxParticipants == null`
  // means "nothing chosen yet". NO LIMIT sends maxParticipants: null (unlimited).
  int? _maxParticipants;
  bool _noLimit = false;
  // 1.1.7: optional future auto-start. Null = instant/manual race (default).
  DateTime? _scheduledStartAt;

  /// Test-only hook so widget tests can set the scheduled start without driving
  /// the platform date/time picker dialogs.
  @visibleForTesting
  void debugSetScheduledStart(DateTime? value) {
    setState(() => _scheduledStartAt = value);
  }

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const _durationOptions = [3, 5, 7, 14];
  static const _intervalPresets = [2000, 3000, 4000, 5000, 10000, 25000];
  static const _maxParticipantsPresets = [5, 10, 25, 50, 100];

  @override
  void dispose() {
    _nameController.dispose();
    _buyInController.dispose();
    super.dispose();
  }

  static const _monthAbbrev = [
    'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
    'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
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
    );
  }

  String _formatScheduledStart(DateTime t) {
    final local = t.toLocal();
    final h = local.hour % 12 == 0 ? 12 : local.hour % 12;
    final m = local.minute.toString().padLeft(2, '0');
    final ampm = local.hour < 12 ? 'AM' : 'PM';
    return '${_monthAbbrev[local.month - 1]} ${local.day} · $h:$m $ampm';
  }

  Future<void> _pickScheduledStart() async {
    final now = DateTime.now();
    final initial = _scheduledStartAt ?? now.add(const Duration(hours: 1));
    final date = await showDatePicker(
      context: context,
      initialDate: initial.isBefore(now) ? now : initial,
      firstDate: now,
      lastDate: now.add(const Duration(days: 365)),
    );
    if (date == null || !mounted) return;
    final time = await showTimePicker(
      context: context,
      initialTime: TimeOfDay.fromDateTime(initial),
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

    if (!_noLimit && _maxParticipants == null) {
      showErrorToast(context, 'Pick a max runners option');
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

    if (_buyInEnabled && _buyInAmount > widget.authService.coins) {
      showErrorToast(context, 'You do not have enough gold for this buy-in');
      return;
    }

    setState(() => _isCreating = true);

    try {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      final result = await widget.backendApiService.createRace(
        identityToken: token,
        name: name,
        maxDurationDays: _selectedDuration,
        powerupsEnabled: _powerupsEnabled,
        powerupStepInterval: _powerupsEnabled ? _powerupInterval : null,
        buyInAmount: _buyInEnabled ? _buyInAmount : 0,
        payoutPreset: _buyInEnabled ? _payoutPreset : 'WINNER_TAKES_ALL',
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
    } catch (e) {
      if (mounted) {
        setState(() => _isCreating = false);
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
                      'NEW RACE',
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
                                final selected = _selectedDuration == days;
                                return Expanded(
                                  child: GestureDetector(
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
                                            ? AppColors.pillGreenDark
                                            : AppColors.parchmentDark,
                                        borderRadius: BorderRadius.circular(8),
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

                      // Scheduled start (optional auto-start)
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
                                        color: AppColors.textMid,
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
                                            ? AppColors.textMid
                                            : AppColors.pillGreenDark,
                                      ),
                                    ),
                                  ],
                                ),
                                SizedBox(
                                  height: 28,
                                  child: Switch.adaptive(
                                    value: _scheduledStartAt != null,
                                    activeTrackColor:
                                        AppColors.pillGreenDark,
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
                                    color: AppColors.parchmentDark,
                                    borderRadius: BorderRadius.circular(8),
                                  ),
                                  child: Row(
                                    children: [
                                      Icon(
                                        Icons.event_outlined,
                                        size: 16,
                                        color: AppColors.textMid,
                                      ),
                                      const SizedBox(width: 8),
                                      Expanded(
                                        child: Text(
                                          'Starts at ${_formatScheduledStart(_scheduledStartAt!)}',
                                          style: PixelText.body(
                                            size: 13,
                                            color: AppColors.textDark,
                                          ),
                                        ),
                                      ),
                                      Icon(
                                        Icons.edit_outlined,
                                        size: 14,
                                        color: AppColors.textMid.withValues(
                                          alpha: 0.6,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ],
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
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
                                    activeTrackColor: AppColors.pillGreenDark,
                                    onChanged: (v) =>
                                        setState(() => _powerupsEnabled = v),
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
                                  final selected = _powerupInterval == interval;
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
                                          borderRadius: BorderRadius.circular(
                                            8,
                                          ),
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                GestureDetector(
                                  onTap: () => setState(
                                    () => _buyInEnabled = !_buyInEnabled,
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
                                        _buyInEnabled
                                            ? 'PAID RACE'
                                            : 'FREE RACE',
                                        style: PixelText.body(
                                          size: 11,
                                          color: _buyInEnabled
                                              ? AppColors.coinDark
                                              : AppColors.textMid,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                                SizedBox(
                                  height: 28,
                                  child: Switch.adaptive(
                                    value: _buyInEnabled,
                                    activeTrackColor: AppColors.pillGreenDark,
                                    onChanged: (value) =>
                                        setState(() => _buyInEnabled = value),
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
                                              ? AppColors.pillGreenDark
                                              : AppColors.parchmentDark,
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
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      _isPublic ? 'PUBLIC RACE' : 'PRIVATE RACE',
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
                                    activeTrackColor: AppColors.pillGreenDark,
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
                              children: [
                                ..._maxParticipantsPresets.map((preset) {
                                  final selected =
                                      !_noLimit && _maxParticipants == preset;
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
