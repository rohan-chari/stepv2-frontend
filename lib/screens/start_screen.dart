import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' as apple;

import 'display_name_screen.dart';
import 'main_shell.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart';

class StartScreen extends StatefulWidget {
  const StartScreen({super.key, this.notificationService});

  final NotificationService? notificationService;

  @override
  State<StartScreen> createState() => _StartScreenState();
}

class _StartScreenState extends State<StartScreen> {
  final AuthService _authService = AuthService();
  bool _isSigningIn = false;

  // Hidden 6-tap-in-3s gesture on the "Bara" title opens a reviewer
  // sign-in modal. Apple reviewers are given the gesture + credentials in
  // App Store Connect; real users won't trigger it accidentally.
  static const int _reviewerTapTarget = 6;
  static const Duration _reviewerTapWindow = Duration(seconds: 3);
  final List<DateTime> _reviewerTapTimestamps = [];

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  void _onReviewerTitleTap() {
    final now = DateTime.now();
    _reviewerTapTimestamps
      ..add(now)
      ..removeWhere((t) => now.difference(t) > _reviewerTapWindow);
    if (_reviewerTapTimestamps.length >= _reviewerTapTarget) {
      _reviewerTapTimestamps.clear();
      _openReviewerSignInModal();
    }
  }

  Future<void> _openReviewerSignInModal() async {
    final result = await showDialog<_ReviewerCredentials>(
      context: context,
      builder: (ctx) => const _ReviewerSignInDialog(),
    );
    if (result == null || !mounted) return;

    setState(() => _isSigningIn = true);
    final success = await _authService.signInAsReviewer(
      email: result.email,
      password: result.password,
    );
    if (!mounted) return;
    setState(() => _isSigningIn = false);

    if (!success) {
      showErrorToast(
        context,
        _authService.lastErrorMessage ?? 'Reviewer sign-in failed.',
      );
      return;
    }

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
  }

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

    // Android signs in with Google; iOS keeps Sign in with Apple.
    final success = Platform.isAndroid
        ? await _authService.signInWithGoogle()
        : await _authService.signInWithApple();

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
      _authService.lastErrorMessage ??
          (Platform.isAndroid
              ? 'Google sign-in failed.'
              : 'Apple sign-in failed.'),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: AppColors.roofLight,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(
        backgroundColor: AppColors.roofLight,
        body: Stack(
          children: [
            const Positioned.fill(
              child: CustomPaint(
                painter: ArcadeCheckerPainter(drawBottomStripe: false),
              ),
            ),
            SafeArea(child: _buildContent()),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 680;

        return Padding(
          padding: const EdgeInsets.fromLTRB(25, 12, 25, 28),
          child: Stack(
            children: [
              Align(
                alignment: Alignment(0, compact ? -0.12 : -0.06),
                child: _buildBrandHero(compact: compact),
              ),
              Align(
                alignment: Alignment(0, compact ? 0.84 : 0.88),
                child: _buildAppleSignInPrompt(compact: compact),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildBrandHero({required bool compact}) {
    return GestureDetector(
      behavior: HitTestBehavior.opaque,
      onTap: _onReviewerTitleTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            SizedBox(
              width: compact ? 260 : 322,
              height: compact ? 92 : 112,
              child: Stack(
                clipBehavior: Clip.none,
                alignment: Alignment.center,
                children: [
                  Positioned(
                    left: compact ? -24 : -44,
                    bottom: compact ? -12 : -18,
                    child: _WalkingInPlaceCapybara(size: compact ? 92 : 112),
                  ),
                  Center(
                    child: Text(
                      'Bara',
                      textAlign: TextAlign.center,
                      style:
                          PixelText.title(
                            size: compact ? 66 : 82,
                            color: AppColors.parchment,
                          ).copyWith(
                            height: 0.9,
                            fontWeight: FontWeight.w800,
                            shadows: _textShadows,
                          ),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 0),
            Text(
              'step races',
              style:
                  PixelText.body(
                    size: compact ? 13 : 15,
                    color: AppColors.parchment,
                  ).copyWith(
                    letterSpacing: 5.5,
                    fontWeight: FontWeight.w500,
                    shadows: _textShadows,
                  ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildAppleSignInPrompt({required bool compact}) {
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Text(
          'Race your friends, earn powerups,\nand climb the leaderboard.',
          style: PixelText.body(
            size: compact ? 13 : 14,
            color: AppColors.parchmentLight.withValues(alpha: 0.9),
          ).copyWith(shadows: _textShadows),
          textAlign: TextAlign.center,
        ),
        SizedBox(height: compact ? 12 : 16),
        _isSigningIn
            ? const SizedBox(
                height: 54,
                child: Center(
                  child: CircularProgressIndicator(color: AppColors.parchment),
                ),
              )
            : SizedBox(
                width: double.infinity,
                child: Platform.isAndroid
                    ? _buildGoogleSignInButton(compact: compact)
                    : apple.SignInWithAppleButton(
                        onPressed: _onStart,
                        height: compact ? 52 : 54,
                        borderRadius: BorderRadius.circular(8),
                        iconAlignment: apple.IconAlignment.left,
                      ),
              ),
      ],
    );
  }

  Widget _buildGoogleSignInButton({required bool compact}) {
    return SizedBox(
      height: compact ? 52 : 54,
      child: ElevatedButton(
        onPressed: _onStart,
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          elevation: 0,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
          ),
        ),
        child: const Text(
          'Sign in with Google',
          style: TextStyle(fontSize: 17, fontWeight: FontWeight.w500),
        ),
      ),
    );
  }
}

class _WalkingInPlaceCapybara extends StatefulWidget {
  const _WalkingInPlaceCapybara({required this.size});

  final double size;

  @override
  State<_WalkingInPlaceCapybara> createState() =>
      _WalkingInPlaceCapybaraState();
}

class _WalkingInPlaceCapybaraState extends State<_WalkingInPlaceCapybara>
    with SingleTickerProviderStateMixin {
  static const int _frameCount = 6;

  late final AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 760),
    )..repeat();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final size = widget.size;

    return SizedBox(
      width: size,
      height: size,
      child: AnimatedBuilder(
        animation: _controller,
        builder: (context, child) {
          final frameIndex =
              (_controller.value * _frameCount).floor() % _frameCount;

          return ClipRect(
            child: OverflowBox(
              maxWidth: double.infinity,
              alignment: Alignment.centerLeft,
              child: Transform.translate(
                offset: Offset(-frameIndex * size, 0),
                child: Image.asset(
                  'assets/images/capybara_walk_right.png',
                  width: size * _frameCount,
                  height: size,
                  fit: BoxFit.contain,
                  alignment: Alignment.centerLeft,
                  filterQuality: FilterQuality.none,
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _ReviewerCredentials {
  final String email;
  final String password;
  const _ReviewerCredentials(this.email, this.password);
}

class _ReviewerSignInDialog extends StatefulWidget {
  const _ReviewerSignInDialog();

  @override
  State<_ReviewerSignInDialog> createState() => _ReviewerSignInDialogState();
}

class _ReviewerSignInDialogState extends State<_ReviewerSignInDialog> {
  final TextEditingController _emailController = TextEditingController();
  final TextEditingController _passwordController = TextEditingController();

  @override
  void dispose() {
    _emailController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  void _submit() {
    final email = _emailController.text.trim();
    final password = _passwordController.text;
    if (email.isEmpty || password.isEmpty) return;
    Navigator.of(context).pop(_ReviewerCredentials(email, password));
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      backgroundColor: AppColors.parchment,
      title: Text(
        'App Reviewer Sign In',
        style: PixelText.title(size: 16, color: AppColors.textDark),
      ),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: _emailController,
            autocorrect: false,
            keyboardType: TextInputType.emailAddress,
            decoration: const InputDecoration(labelText: 'Email'),
          ),
          const SizedBox(height: 8),
          TextField(
            controller: _passwordController,
            obscureText: true,
            decoration: const InputDecoration(labelText: 'Password'),
            onSubmitted: (_) => _submit(),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        TextButton(onPressed: _submit, child: const Text('Sign in')),
      ],
    );
  }
}
