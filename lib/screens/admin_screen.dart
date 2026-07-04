import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../styles.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart' as error_toast;
import '../widgets/game_background.dart';
import '../widgets/info_toast.dart' as info_toast;
import '../widgets/pill_button.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/spinning_crate.dart';
import '../widgets/trail_sign.dart';
import 'admin_accessory_tuner_screen.dart';

const _powerupEntries = [
  (
    type: 'LEG_CRAMP',
    name: 'Leg Cramp',
    description: 'Freeze a rival\'s steps for 2 hours',
  ),
  (
    type: 'RED_CARD',
    name: 'Red Card',
    description: 'Remove 10% of the leader\'s steps',
  ),
  (
    type: 'SHORTCUT',
    name: 'Shortcut',
    description: 'Steal 1,000 steps from a rival',
  ),
  (
    type: 'COMPRESSION_SOCKS',
    name: 'Compression Socks',
    description: 'Shield against the next attack',
  ),
  (
    type: 'PROTEIN_SHAKE',
    name: 'Protein Shake',
    description: '+1,500 bonus steps instantly',
  ),
  (
    type: 'RUNNERS_HIGH',
    name: "Runner's High",
    description: '2x steps for 3 hours',
  ),
  (
    type: 'SECOND_WIND',
    name: 'Second Wind',
    description: 'Bonus steps based on how far behind',
  ),
  (
    type: 'STEALTH_MODE',
    name: 'Stealth Mode',
    description: 'Hide your progress for 4 hours',
  ),
  (
    type: 'WRONG_TURN',
    name: 'Wrong Turn',
    description: 'Reverse a rival\'s steps for 1 hour',
  ),
  (
    type: 'FANNY_PACK',
    name: 'Fanny Pack',
    description: 'Unlock an extra powerup slot',
  ),
  (
    type: 'TRAIL_MIX',
    name: 'Trail Mix',
    description: '+100 steps per unique powerup type used',
  ),
  (
    type: 'DETOUR_SIGN',
    name: 'Detour Sign',
    description: 'Hide the entire leaderboard from a rival for 3 hours',
  ),
  (
    type: 'CLEANSE',
    name: 'Cleanse',
    description: 'Remove all debuffs an opponent placed on you',
  ),
  (
    type: 'IMPOSTER',
    name: 'Imposter',
    description:
        'Swap leaderboard positions with a rival for 1 hour (cosmetic)',
  ),
  (
    type: 'RAINSTORM',
    name: 'Rainstorm',
    description:
        'Everyone else\'s steps count for half for 1 hour (shields protect)',
  ),
];

class AdminScreen extends StatelessWidget {
  const AdminScreen({
    super.key,
    required this.authService,
    this.showInfoToast = info_toast.showInfoToast,
    this.showErrorToast = error_toast.showErrorToast,
  });

  final AuthService authService;
  final void Function(BuildContext context, String message) showInfoToast;
  final void Function(BuildContext context, String message) showErrorToast;

  @override
  Widget build(BuildContext context) {
    final boardWidth = MediaQuery.of(context).size.width - 48;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GameBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
            child: Column(
              children: [
                TrailSign(
                  width: boardWidth,
                  child: Text(
                    'ADMIN TOOLS',
                    style: PixelText.title(size: 22, color: AppColors.textDark),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'TOAST TESTS',
                        style: PixelText.title(
                          size: 14,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: PillButton(
                              label: 'TEST INFO TOAST',
                              variant: PillButtonVariant.primary,
                              fontSize: 11,
                              fullWidth: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 12,
                              ),
                              onPressed: () => showInfoToast(
                                context,
                                'This is a test notification toast.',
                              ),
                            ),
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: PillButton(
                              label: 'TEST ERROR TOAST',
                              variant: PillButtonVariant.accent,
                              fontSize: 11,
                              fullWidth: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                                vertical: 12,
                              ),
                              onPressed: () => showErrorToast(
                                context,
                                'This is a test error toast.',
                              ),
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'POWERUP ICONS',
                        style: PixelText.title(
                          size: 16,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final entry in _powerupEntries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: PowerupIcon(
                                  type: entry.type,
                                  size: 28,
                                  spinning: true,
                                  spinDuration: const Duration(
                                    milliseconds: 2800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.name,
                                      style: PixelText.title(
                                        size: 13,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                    Text(
                                      entry.description,
                                      style: PixelText.body(
                                        size: 11,
                                        color: AppColors.textMid,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'COSMETICS',
                        style: PixelText.title(
                          size: 16,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      PillButton(
                        label: 'ACCESSORY RENDER TUNER',
                        variant: PillButtonVariant.primary,
                        fontSize: 13,
                        fullWidth: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 24,
                          vertical: 12,
                        ),
                        onPressed: () => Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => AdminAccessoryTunerScreen(
                              authService: authService,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    children: [
                      Text(
                        'POWERUP CRATE',
                        style: PixelText.title(
                          size: 16,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SpinningCrate(size: 100),
                      const SizedBox(height: 8),
                    ],
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
