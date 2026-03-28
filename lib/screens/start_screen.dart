import 'package:flutter/material.dart';

import 'display_name_screen.dart';
import 'main_shell.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/capybara.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import '../widgets/spinning_coin.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key, this.notificationService});

  final NotificationService? notificationService;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final AuthService _authService = AuthService();
  bool _isSigningIn = false;

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  Future<void> _onStart() async {
    setState(() => _isSigningIn = true);

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
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF87CEEB),
              Color(0xFFB0E0F0),
              Color(0xFFD4F1F9),
            ],
          ),
        ),
        child: SafeArea(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 24),
            child: Column(
              children: [
                const Spacer(flex: 2),

                // App title
                Text(
                  'Bara',
                  style: PixelText.title(size: 48, color: AppColors.textDark)
                      .copyWith(shadows: _textShadows),
                ),
                const SizedBox(height: 8),
                Text(
                  'Track your steps, challenge friends,\nand put a stake on the week.',
                  style: PixelText.body(size: 14, color: AppColors.textMid)
                      .copyWith(shadows: _textShadows),
                  textAlign: TextAlign.center,
                ),

                const SizedBox(height: 32),

                // Feature cards
                Row(
                  children: [
                    Expanded(
                      child: _FeatureCard(
                        icon: Icons.directions_walk_rounded,
                        label: 'TRACK',
                        description: 'Daily steps',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FeatureCard(
                        icon: Icons.emoji_events_rounded,
                        label: 'COMPETE',
                        description: 'Weekly challenges',
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: _FeatureCard(
                        icon: Icons.handshake_rounded,
                        label: 'STAKE',
                        description: 'Raise the stakes',
                      ),
                    ),
                  ],
                ),

                const SizedBox(height: 16),

                // Coin reward teaser
                RetroCard(
                  padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const SpinningCoin(size: 24),
                      const SizedBox(width: 8),
                      Text(
                        'Earn coins by hitting your daily goals',
                        style: PixelText.body(size: 13, color: AppColors.textDark),
                      ),
                    ],
                  ),
                ),

                const Spacer(flex: 2),

                // Capybara
                const SizedBox(
                  height: 96,
                  child: WalkingCapybara(
                    walkDuration: Duration(seconds: 12),
                    size: 96,
                  ),
                ),

                const SizedBox(height: 16),

                // Start button
                _isSigningIn
                    ? const CircularProgressIndicator(
                        color: AppColors.accent,
                      )
                    : PillButton(
                        label: 'GET STARTED',
                        variant: PillButtonVariant.primary,
                        fontSize: 18,
                        fullWidth: true,
                        padding: const EdgeInsets.symmetric(
                          horizontal: 48,
                          vertical: 18,
                        ),
                        onPressed: _onStart,
                      ),

                const Spacer(flex: 1),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _FeatureCard extends StatelessWidget {
  final IconData icon;
  final String label;
  final String description;

  const _FeatureCard({
    required this.icon,
    required this.label,
    required this.description,
  });

  @override
  Widget build(BuildContext context) {
    return RetroCard(
      padding: const EdgeInsets.symmetric(vertical: 14, horizontal: 8),
      child: Column(
        children: [
          Icon(icon, size: 28, color: AppColors.accent),
          const SizedBox(height: 6),
          Text(
            label,
            style: PixelText.title(size: 12, color: AppColors.textDark),
            textAlign: TextAlign.center,
          ),
          const SizedBox(height: 2),
          Text(
            description,
            style: PixelText.body(size: 10, color: AppColors.textMid),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }
}
