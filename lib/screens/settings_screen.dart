import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../widgets/error_toast.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/capybara.dart';
import '../widgets/game_background.dart';
import '../widgets/game_button.dart';
import '../widgets/trail_sign.dart';

class SettingsScreen extends StatefulWidget {
  const SettingsScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends State<SettingsScreen> {
  final BackendApiService _backendApiService = BackendApiService();

  Future<void> _showStepGoalDialog() async {
    final currentGoal = widget.authService.stepGoal;
    final controller = TextEditingController(
      text: currentGoal?.toString() ?? '',
    );

    final result = await showDialog<int>(
      context: context,
      builder: (context) {
        return Dialog(
          backgroundColor: Colors.transparent,
          child: TrailSign(
            width: 300,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'STEP GOAL',
                  style: PixelText.title(size: 18, color: AppColors.textDark),
                ),
                const SizedBox(height: 8),
                Text(
                  'How many steps per day?',
                  style: PixelText.body(size: 14, color: AppColors.textMid),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: controller,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  style: PixelText.number(size: 24, color: AppColors.textDark),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: AppColors.parchmentLight,
                    border: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: AppColors.parchmentBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderSide:
                          BorderSide(color: AppColors.parchmentBorder),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderSide: BorderSide(
                        color: AppColors.accent,
                        width: 2,
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                    contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 12,
                    ),
                  ),
                ),
                const SizedBox(height: 16),
                Row(
                  children: [
                    Expanded(
                      child: GameButton(
                        label: 'CANCEL',
                        fontSize: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        onPressed: () => Navigator.of(context).pop(),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: GameButton(
                        label: 'SAVE',
                        fontSize: 14,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 10,
                        ),
                        onPressed: () {
                          final value = int.tryParse(controller.text);
                          if (value != null && value > 0) {
                            Navigator.of(context).pop(value);
                          }
                        },
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        );
      },
    );

    if (result == null || !mounted) return;

    await widget.authService.updateStepGoal(result);

    try {
      final identityToken = widget.authService.identityToken;
      if (identityToken != null && identityToken.isNotEmpty) {
        await _backendApiService.setStepGoal(
          identityToken: identityToken,
          stepGoal: result,
        );
      }
    } catch (e) {
      if (mounted) {
        showErrorToast(context, 'Failed to save step goal: $e');
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final groundHeight = MediaQuery.of(context).size.height * 0.22;

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: Colors.white),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GameBackground(
        child: Stack(
          children: [
            Positioned(
              left: 0,
              right: 0,
              bottom: groundHeight * 0.45,
              height: 128,
              child: const WalkingCapybara(
                walkDuration: Duration(seconds: 12),
                size: 128,
              ),
            ),

            // Billboard + centered button
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 60),
                  child: Column(
                    children: [
                      TrailSign(
                        width: 340,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'SETTINGS',
                              style: PixelText.title(
                                size: 26,
                                color: AppColors.textDark,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      SizedBox(
                        width: 340,
                        child: GameButton(
                          label: 'CHANGE STEP GOAL',
                          fontSize: 16,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 48,
                            vertical: 16,
                          ),
                          onPressed: _showStepGoalDialog,
                        ),
                      ),
                      const Spacer(),
                    ],
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
