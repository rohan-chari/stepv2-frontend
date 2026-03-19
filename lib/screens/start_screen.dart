import 'package:flutter/material.dart';

import 'display_name_screen.dart';
import 'main_shell.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/capybara.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/pill_button.dart';
import '../widgets/trail_sign.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key, this.notificationService});

  final NotificationService? notificationService;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final AuthService _authService = AuthService();
  bool _isSigningIn = false;

  Future<void> _onStart() async {
    setState(() => _isSigningIn = true);

    // Check for existing session first
    final hasSession = await _authService.restoreSession();
    if (hasSession) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => _authService.displayName != null
              ? MainShell(
                  authService: _authService,
                  notificationService: widget.notificationService,
                )
              : DisplayNameScreen(
                  authService: _authService,
                  notificationService: widget.notificationService,
                ),
        ),
      );
      return;
    }

    final success = await _authService.signInWithApple();

    if (!mounted) return;
    setState(() => _isSigningIn = false);

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => _authService.displayName != null
              ? MainShell(
                  authService: _authService,
                  notificationService: widget.notificationService,
                )
              : DisplayNameScreen(
                  authService: _authService,
                  notificationService: widget.notificationService,
                ),
        ),
      );
      return;
    }

    if (!mounted) return;
    showErrorToast(
      context,
      _authService.lastErrorMessage ?? 'Apple sign-in failed.',
    );
  }

  @override
  Widget build(BuildContext context) {
    final groundHeight = MediaQuery.of(context).size.height * 0.22;

    return Scaffold(
      body: GameBackground(
        child: Stack(
          children: [
            // Capybara walking on the grass
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
                              'Bara',
                              style: PixelText.title(
                                size: 26,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'Track your steps, challenge friends, and put a stake on the week.',
                              style: PixelText.body(
                                size: 14,
                                color: AppColors.textMid,
                              ),
                              textAlign: TextAlign.center,
                            ),
                          ],
                        ),
                      ),
                      const Spacer(),
                      _isSigningIn
                          ? const CircularProgressIndicator(
                              color: AppColors.accent,
                            )
                          : SizedBox(
                              width: 340,
                              child: PillButton(
                                label: 'START',
                                variant: PillButtonVariant.primary,
                                fontSize: 16,
                                fullWidth: true,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 48,
                                  vertical: 16,
                                ),
                                onPressed: _onStart,
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
