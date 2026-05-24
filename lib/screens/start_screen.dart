import 'package:flutter/material.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' as apple;

import 'display_name_screen.dart';
import 'main_shell.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/capybara.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/feature_highlights_row.dart';
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

  // Hidden 5-tap-in-3s gesture on the top-right corner opens a reviewer
  // sign-in modal. Apple reviewers are given the gesture + credentials in
  // App Store Connect; real users won't trigger it accidentally.
  static const int _reviewerTapTarget = 5;
  static const Duration _reviewerTapWindow = Duration(seconds: 3);
  final List<DateTime> _reviewerTapTimestamps = [];

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  void _onReviewerCornerTap() {
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
      body: Stack(
        children: [
          ArcadePageBackground(
            child: SafeArea(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: _buildContent(),
              ),
            ),
          ),
          // Invisible tap target for the reviewer-login gesture (top-right corner).
          Positioned(
            top: 0,
            right: 0,
            child: SafeArea(
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTap: _onReviewerCornerTap,
                child: const SizedBox(width: 64, height: 64),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildContent() {
    return Column(
      children: [
        const Spacer(flex: 2),
        Text(
          'Bara',
          style: PixelText.title(
            size: 48,
            color: AppColors.textDark,
          ).copyWith(shadows: _textShadows),
        ),
        const SizedBox(height: 8),
        Text(
          'Track your steps and race friends\nfor coins and bragging rights.',
          style: PixelText.body(
            size: 14,
            color: AppColors.textMid,
          ).copyWith(shadows: _textShadows),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 32),
        const FeatureHighlightsRow(),
        const SizedBox(height: 16),
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
        const SizedBox(
          height: 96,
          child: WalkingCapybara(
            walkDuration: Duration(seconds: 12),
            size: 96,
          ),
        ),
        const SizedBox(height: 16),
        _isSigningIn
            ? const CircularProgressIndicator(color: AppColors.accent)
            : SizedBox(
                width: double.infinity,
                child: apple.SignInWithAppleButton(
                  onPressed: _onStart,
                  height: 54,
                  borderRadius: BorderRadius.circular(8),
                  iconAlignment: apple.IconAlignment.left,
                ),
              ),
        const Spacer(flex: 1),
      ],
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
        TextButton(
          onPressed: _submit,
          child: const Text('Sign in'),
        ),
      ],
    );
  }
}
