import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' as apple;

import 'display_name_screen.dart';
import 'main_shell.dart';
import '../config/start_cape_metadata.dart';
import '../services/auth_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart';
import '../widgets/home_course_track.dart';
import '../widgets/home_hero_scene.dart';

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
        builder: (context) =>
            _authService.displayName != null || _authService.onboardingV2Enabled
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

  Future<void> _onStart({required bool withGoogle}) async {
    setState(() => _isSigningIn = true);

    final hasSession = await _authService.restoreSession();
    if (hasSession) {
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) =>
              _authService.displayName != null ||
                  _authService.onboardingV2Enabled
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

    final success = withGoogle
        ? await _authService.signInWithGoogle()
        : await _authService.signInWithApple();

    if (!mounted) return;
    setState(() => _isSigningIn = false);

    if (success) {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(
          builder: (context) =>
              _authService.displayName != null ||
                  _authService.onboardingV2Enabled
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
    final errorMessage = _authService.lastErrorMessage;
    // Closing an Apple/Google account picker is a normal navigation choice,
    // not an error. AuthService leaves the message null for that path.
    if (errorMessage == null) return;
    showErrorToast(context, errorMessage);
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: const SystemUiOverlayStyle(
        statusBarColor: Colors.transparent,
        statusBarIconBrightness: Brightness.light,
        statusBarBrightness: Brightness.dark,
      ),
      child: Scaffold(backgroundColor: colors.parchment, body: _buildContent()),
    );
  }

  Widget _buildContent() {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final groundHeight = compact ? 72.0 : 88.0;

        return Column(
          children: [
            Expanded(
              child: HomeHeroScene(
                groundHeight: groundHeight,
                skyAlignment: const Alignment(0.6, 1),
                child: SafeArea(
                  bottom: false,
                  child: _buildBrandHero(
                    compact: compact,
                    groundHeight: groundHeight,
                  ),
                ),
              ),
            ),
            _buildSignInDock(compact: compact),
          ],
        );
      },
    );
  }

  Widget _buildBrandHero({
    required bool compact,
    required double groundHeight,
  }) {
    final capySize = compact ? 146.0 : 184.0;
    return Stack(
      children: [
        Positioned(
          top: compact ? 8 : 18,
          left: 20,
          right: 20,
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _onReviewerTitleTap,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  'Bara',
                  textAlign: TextAlign.center,
                  style:
                      PixelText.title(
                        size: compact ? 58 : 70,
                        color: AppColors.of(context).textLight,
                      ).copyWith(
                        height: 0.92,
                        fontWeight: FontWeight.w800,
                        shadows: _textShadows,
                      ),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: groundHeight - 4 - capySize * 0.22,
          child: Center(child: _CapeCapybara(size: capySize)),
        ),
      ],
    );
  }

  Widget _buildSignInDock({required bool compact}) {
    final colors = AppColors.of(context);
    return Container(
      key: const Key('start-sign-in-dock'),
      width: double.infinity,
      decoration: BoxDecoration(
        color: colors.parchment,
        border: Border(top: BorderSide(color: colors.woodDark, width: 3)),
        boxShadow: [
          BoxShadow(
            color: colors.woodShadow.withValues(alpha: 0.28),
            offset: const Offset(0, -5),
            blurRadius: 14,
          ),
        ],
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.fromLTRB(24, compact ? 13 : 16, 24, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'READY TO RACE?',
                style: PixelText.title(
                  size: compact ? 16 : 18,
                  color: colors.textDark,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 4),
              Text(
                'Race your friends, earn powerups, and climb the leaderboard.',
                style: PixelText.body(
                  size: compact ? 12 : 13,
                  color: colors.textMid,
                ),
                textAlign: TextAlign.center,
              ),
              SizedBox(height: compact ? 10 : 13),
              _buildSignInButtons(compact: compact),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildSignInButtons({required bool compact}) {
    if (_isSigningIn) {
      return SizedBox(
        height: compact ? 52 : 54,
        child: Center(
          child: CircularProgressIndicator(color: AppColors.of(context).accent),
        ),
      );
    }

    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        // Android is Google-only. iOS leads with Apple (App Store requirement
        // + where existing accounts live) and offers Google underneath when
        // this build carries an iOS Google client id (see kGoogleIosClientId).
        if (!Platform.isAndroid)
          SizedBox(
            width: double.infinity,
            child: apple.SignInWithAppleButton(
              onPressed: () => _onStart(withGoogle: false),
              height: compact ? 52 : 54,
              borderRadius: BorderRadius.circular(8),
              iconAlignment: apple.IconAlignment.left,
            ),
          ),
        if (Platform.isAndroid || isGoogleSignInAvailable) ...[
          if (!Platform.isAndroid) SizedBox(height: compact ? 10 : 12),
          SizedBox(
            width: double.infinity,
            child: _buildGoogleSignInButton(compact: compact),
          ),
        ],
      ],
    );
  }

  // White Google-branded twin of SignInWithAppleButton(iconAlignment: left):
  // replicates that widget's exact geometry — 16px horizontal padding, a
  // left-edge icon slot of 28/44 × height, centered text at 0.43 × height in
  // .SF Pro Text, and a trailing spacer mirroring the icon slot — so the two
  // stacked buttons align logo-for-logo and glyph-for-glyph. The "G" is
  // Google's official logo asset (assets/images/google_g_logo.png).
  Widget _buildGoogleSignInButton({required bool compact}) {
    final height = compact ? 52.0 : 54.0;
    final fontSize = height * 0.43;
    final iconSlotWidth = height * (28 / 44);

    return SizedBox(
      height: height,
      child: ElevatedButton(
        onPressed: () => _onStart(withGoogle: true),
        style: ElevatedButton.styleFrom(
          backgroundColor: Colors.white,
          foregroundColor: const Color(0xFF1F1F1F),
          elevation: 0,
          padding: const EdgeInsets.symmetric(horizontal: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: const BorderSide(color: Color(0xFFDADCE0)),
          ),
        ),
        child: Row(
          children: [
            SizedBox(
              width: iconSlotWidth,
              child: Center(
                child: Image.asset(
                  'assets/images/google_g_logo.png',
                  width: fontSize,
                  height: fontSize,
                ),
              ),
            ),
            Expanded(
              child: Text(
                'Sign in with Google',
                textAlign: TextAlign.center,
                maxLines: 1,
                style: TextStyle(
                  inherit: false,
                  fontSize: fontSize,
                  color: const Color(0xFF1F1F1F),
                  fontFamily: '.SF Pro Text',
                  letterSpacing: -0.41,
                ),
              ),
            ),
            SizedBox(width: iconSlotWidth),
          ],
        ),
      ),
    );
  }
}

class _CapeCapybara extends StatefulWidget {
  const _CapeCapybara({required this.size});

  final double size;

  @override
  State<_CapeCapybara> createState() => _CapeCapybaraState();
}

class _CapeCapybaraState extends State<_CapeCapybara> {
  // Starts on the compiled prod-tuning snapshot, then swaps to the cached
  // tuner item (bobble + renderMetadata, saved by the shop-catalog funnel)
  // once loaded — so this renders exactly what the Accessory Tuner renders,
  // without a pre-auth network dependency.
  Map<String, dynamic> _capeItem = StartCapeMetadata.fallback;

  @override
  void initState() {
    super.initState();
    StartCapeMetadata.load().then((item) {
      if (mounted && !identical(item, StartCapeMetadata.fallback)) {
        setState(() => _capeItem = item);
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Capybara wearing a red racing cape',
      child: CapybaraCustomizationPreview(
        key: const Key('start-cape-capybara'),
        accessories: [
          {
            'assetKey': 'cape',
            'slot': 'BACK',
            'bobble': _capeItem['bobble'] == true,
            'renderMetadata': _capeItem['renderMetadata'],
          },
        ],
        size: widget.size,
        showShadow: false,
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
      backgroundColor: AppColors.of(context).parchment,
      title: Text(
        'App Reviewer Sign In',
        style: PixelText.title(size: 16, color: AppColors.of(context).textDark),
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
