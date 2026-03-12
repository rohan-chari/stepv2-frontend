import 'package:flutter/material.dart';

import 'home_screen.dart';
import '../services/auth_service.dart';
import '../widgets/capybara.dart';
import '../widgets/game_background.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key});

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final AuthService _authService = AuthService();
  bool _buttonPressed = false;
  bool _isSigningIn = false;

  Future<void> _onStart() async {
    setState(() => _isSigningIn = true);

    // Check for existing session first
    final hasSession = await _authService.restoreSession();
    if (hasSession) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) => HomeScreen(authService: _authService),
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
          builder: (context) => HomeScreen(authService: _authService),
        ),
      );
      return;
    }

    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(
      SnackBar(
        content: Text(_authService.lastErrorMessage ?? 'Apple sign-in failed.'),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final groundHeight = MediaQuery.of(context).size.height * 0.22;

    return Scaffold(
      body: GameBackground(
        child: Stack(
          children: [
            // Capybara walking
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

            // Title and button
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    'Step Tracker',
                    style: TextStyle(
                      fontSize: 42,
                      fontWeight: FontWeight.w900,
                      color: Colors.white,
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.3),
                          offset: const Offset(0, 4),
                          blurRadius: 12,
                        ),
                        Shadow(
                          color: const Color(0xFF1565C0).withValues(alpha: 0.4),
                          offset: const Offset(0, 2),
                          blurRadius: 20,
                        ),
                      ],
                      letterSpacing: 2,
                    ),
                  ),
                  const SizedBox(height: 8),
                  Text(
                    'Your daily walking companion',
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w500,
                      color: Colors.white.withValues(alpha: 0.9),
                      shadows: [
                        Shadow(
                          color: Colors.black.withValues(alpha: 0.25),
                          offset: const Offset(0, 2),
                          blurRadius: 8,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 50),

                  // 3D Start button
                  if (_isSigningIn)
                    const CircularProgressIndicator(color: Colors.white)
                  else
                    GestureDetector(
                      onTapDown: (_) => setState(() => _buttonPressed = true),
                      onTapUp: (_) {
                        setState(() => _buttonPressed = false);
                        _onStart();
                      },
                      onTapCancel: () => setState(() => _buttonPressed = false),
                      child: AnimatedContainer(
                        duration: const Duration(milliseconds: 60),
                        transform: Matrix4.translationValues(
                          0,
                          _buttonPressed ? 6 : 0,
                          0,
                        ),
                        decoration: BoxDecoration(
                          borderRadius: BorderRadius.circular(12),
                          color: const Color(0xFFB8860B),
                          boxShadow: _buttonPressed
                              ? []
                              : [
                                  const BoxShadow(
                                    color: Color(0xFF8B6508),
                                    offset: Offset(0, 6),
                                    blurRadius: 0,
                                  ),
                                ],
                        ),
                        child: Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 60,
                            vertical: 18,
                          ),
                          decoration: BoxDecoration(
                            borderRadius: BorderRadius.circular(12),
                            gradient: const LinearGradient(
                              begin: Alignment.topCenter,
                              end: Alignment.bottomCenter,
                              colors: [
                                Color(0xFFF5C842),
                                Color(0xFFEBB030),
                                Color(0xFFD4991E),
                              ],
                            ),
                            border: Border.all(
                              color: const Color(0xFFB8860B),
                              width: 2.5,
                            ),
                          ),
                          child: Text(
                            'START',
                            style: TextStyle(
                              fontSize: 30,
                              fontWeight: FontWeight.w900,
                              color: const Color(0xFF7A5A00),
                              letterSpacing: 4,
                              shadows: [
                                Shadow(
                                  color: const Color(
                                    0xFFFFE082,
                                  ).withValues(alpha: 0.6),
                                  offset: const Offset(0, 1),
                                  blurRadius: 0,
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
