import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';

class CreateRaceScreen extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;

  CreateRaceScreen({
    super.key,
    required this.authService,
    BackendApiService? backendApiService,
  }) : backendApiService = backendApiService ?? BackendApiService();

  @override
  State<CreateRaceScreen> createState() => _CreateRaceScreenState();
}

class _CreateRaceScreenState extends State<CreateRaceScreen> {
  final _nameController = TextEditingController();
  final _stepsController = TextEditingController();
  int _selectedDuration = 7;
  bool _isCreating = false;
  bool _powerupsEnabled = false;
  int _powerupInterval = 5000;
  bool _buyInEnabled = false;
  int _buyInAmount = 100;
  String _payoutPreset = 'WINNER_TAKES_ALL';

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  static const _durationOptions = [3, 5, 7, 14];
  static const _stepPresets = [25000, 50000, 100000, 250000];
  static const _intervalPresets = [2500, 5000, 10000, 25000];
  static const _buyInPresets = [50, 100, 250, 500];
  static const _payoutOptions = [
    ('WINNER TAKE ALL', 'WINNER_TAKES_ALL'),
    ('TOP 3 70/20/10', 'TOP3_70_20_10'),
    ('TOP 3 80/15/5', 'TOP3_80_15_5'),
  ];

  @override
  void dispose() {
    _nameController.dispose();
    _stepsController.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    final name = _nameController.text.trim();
    if (name.isEmpty) {
      showErrorToast(context, 'Enter a race name');
      return;
    }

    final steps = int.tryParse(_stepsController.text.replaceAll(',', ''));
    if (steps == null || steps < 1000) {
      showErrorToast(context, 'Target must be at least 1,000 steps');
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
        targetSteps: steps,
        maxDurationDays: _selectedDuration,
        powerupsEnabled: _powerupsEnabled,
        powerupStepInterval: _powerupsEnabled ? _powerupInterval : null,
        buyInAmount: _buyInEnabled ? _buyInAmount : 0,
        payoutPreset: _buyInEnabled ? _payoutPreset : 'WINNER_TAKES_ALL',
      );

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
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFFB0E0F0), Color(0xFFD4F1F9)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.arrow_back,
                            color: AppColors.textDark, size: 24),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'NEW RACE',
                      style: PixelText.title(size: 22, color: AppColors.textDark)
                          .copyWith(shadows: _textShadows),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              Expanded(
                child: SingleChildScrollView(
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
                            Text('RACE NAME',
                                style: PixelText.title(
                                    size: 13, color: AppColors.textMid)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _nameController,
                              maxLength: 50,
                              style: PixelText.body(
                                  size: 16, color: AppColors.textDark),
                              decoration: InputDecoration(
                                hintText: 'e.g. Weekend Warriors',
                                hintStyle: PixelText.body(
                                    size: 16, color: AppColors.textMid.withValues(alpha: 0.5)),
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
                            Text('TARGET STEPS',
                                style: PixelText.title(
                                    size: 13, color: AppColors.textMid)),
                            const SizedBox(height: 8),
                            TextField(
                              controller: _stepsController,
                              keyboardType: TextInputType.number,
                              inputFormatters: [
                                FilteringTextInputFormatter.digitsOnly
                              ],
                              style: PixelText.number(
                                  size: 28, color: AppColors.accent),
                              decoration: InputDecoration(
                                hintText: '50000',
                                hintStyle: PixelText.number(
                                    size: 28,
                                    color:
                                        AppColors.accent.withValues(alpha: 0.3)),
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
                                    ? '${(preset / 1000).toStringAsFixed(preset % 1000 == 0 ? 0 : 0)}k'
                                    : '$preset';
                                return GestureDetector(
                                  onTap: () => _stepsController.text =
                                      preset.toString(),
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 12, vertical: 6),
                                    decoration: BoxDecoration(
                                      color: AppColors.parchmentDark,
                                      borderRadius: BorderRadius.circular(6),
                                    ),
                                    child: Text(label,
                                        style: PixelText.title(
                                            size: 13,
                                            color: AppColors.textDark)),
                                  ),
                                );
                              }).toList(),
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
                            Text('DURATION',
                                style: PixelText.title(
                                    size: 13, color: AppColors.textMid)),
                            const SizedBox(height: 10),
                            Row(
                              children: _durationOptions.map((days) {
                                final selected = _selectedDuration == days;
                                return Expanded(
                                  child: GestureDetector(
                                    onTap: () =>
                                        setState(() => _selectedDuration = days),
                                    child: Container(
                                      margin: const EdgeInsets.symmetric(
                                          horizontal: 3),
                                      padding: const EdgeInsets.symmetric(
                                          vertical: 10),
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

                      // Powerups
                      RetroCard(
                        padding: const EdgeInsets.all(16),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('POWERUPS',
                                    style: PixelText.title(
                                        size: 13, color: AppColors.textMid)),
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
                                    size: 11, color: AppColors.textMid),
                              ),
                              const SizedBox(height: 8),
                              Row(
                                children: _intervalPresets.map((interval) {
                                  final selected =
                                      _powerupInterval == interval;
                                  final label = interval >= 1000
                                      ? '${(interval / 1000).toStringAsFixed(interval % 1000 == 0 ? 0 : 1)}k'
                                      : '$interval';
                                  return Expanded(
                                    child: GestureDetector(
                                      onTap: () => setState(
                                          () => _powerupInterval = interval),
                                      child: Container(
                                        margin: const EdgeInsets.symmetric(
                                            horizontal: 3),
                                        padding: const EdgeInsets.symmetric(
                                            vertical: 10),
                                        decoration: BoxDecoration(
                                          color: selected
                                              ? AppColors.pillGreenDark
                                              : AppColors.parchmentDark,
                                          borderRadius:
                                              BorderRadius.circular(8),
                                        ),
                                        alignment: Alignment.center,
                                        child: Text(
                                          '$label steps',
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
                                    activeTrackColor:
                                        AppColors.pillGreenDark,
                                    onChanged: (value) => setState(
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
                              Wrap(
                                spacing: 8,
                                runSpacing: 8,
                                children: _buyInPresets.map((preset) {
                                  final selected = _buyInAmount == preset;
                                  return GestureDetector(
                                    onTap: () => setState(
                                      () => _buyInAmount = preset,
                                    ),
                                    child: Container(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 14,
                                        vertical: 8,
                                      ),
                                      decoration: BoxDecoration(
                                        color: selected
                                            ? AppColors.coinMid
                                            : AppColors.parchmentDark,
                                        borderRadius: BorderRadius.circular(8),
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
                                  );
                                }).toList(),
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
                                children: _payoutOptions.map((option) {
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
                                          borderRadius: BorderRadius.circular(8),
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

                      // Create button
                      PillButton(
                        label: _isCreating ? 'CREATING...' : 'CREATE RACE',
                        variant: PillButtonVariant.primary,
                        fontSize: 15,
                        fullWidth: true,
                        padding: const EdgeInsets.symmetric(
                            horizontal: 24, vertical: 14),
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
    );
  }
}
