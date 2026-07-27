import 'dart:io' show Platform;

import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:sign_in_with_apple/sign_in_with_apple.dart' as apple;
import 'package:url_launcher/url_launcher.dart';

import 'display_name_screen.dart';
import 'main_shell.dart';
import '../config/backend_config.dart';
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

  late final TapGestureRecognizer _privacyTapRecognizer = TapGestureRecognizer()
    ..onTap = _openPrivacyPolicy;

  @override
  void dispose() {
    _privacyTapRecognizer.dispose();
    super.dispose();
  }

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

  Future<void> _openPrivacyPolicy() async {
    final uri = Uri.parse('${BackendConfig.baseUrl}/privacy.html');
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // The title screen is a fixed brand moment, not a themed surface: it
    // always renders the daytime sky/ground art over the light-mode green
    // field, whatever the device's dark-mode setting is. Everything below
    // resolves its colors out of this forced-light Theme.
    return Theme(
      data: AppThemeData.light(),
      child: Builder(
        builder: (context) => AnnotatedRegion<SystemUiOverlayStyle>(
          value: const SystemUiOverlayStyle(
            statusBarColor: Colors.transparent,
            statusBarIconBrightness: Brightness.light,
            statusBarBrightness: Brightness.dark,
          ),
          child: Scaffold(
            backgroundColor: AppColors.of(context).roofLight,
            body: _buildContent(context),
          ),
        ),
      ),
    );
  }

  Widget _buildContent(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final compact = constraints.maxHeight < 720;
        final groundHeight = compact ? 72.0 : 88.0;

        return Column(
          children: [
            Expanded(
              child: HomeHeroScene(
                groundHeight: groundHeight,
                // Same forward-motion trick as the home hero: the mascot walks
                // in place, so the ground slides under it.
                groundScrollSpeed: 26,
                // Crops the sky so its baked-in sun clears the centered
                // wordmark instead of washing out the tagline behind it.
                skyAlignment: const Alignment(0.2, 1),
                child: Stack(
                  children: [
                    SafeArea(
                      bottom: false,
                      child: _buildBrandHero(
                        context,
                        compact: compact,
                        groundHeight: groundHeight,
                        heroHeight: constraints.maxHeight,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            _buildSignInDock(context, compact: compact),
          ],
        );
      },
    );
  }

  Widget _buildBrandHero(
    BuildContext context, {
    required bool compact,
    required double groundHeight,
    required double heroHeight,
  }) {
    final colors = AppColors.of(context);
    // Tall phones leave a lot of empty sky between the wordmark and the
    // ground, so the mascot scales up with the available height.
    final capySize = compact ? 146.0 : (heroHeight > 840 ? 214.0 : 184.0);
    return Stack(
      children: [
        // No horizon hedge here: the title screen shows the same bare
        // sky + ground scene the home tab's hero uses.
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
                  style: PixelText.display(
                    size: compact ? 76 : 92,
                    color: colors.textLight,
                  ).copyWith(shadows: PixelText.skyOutline(compact ? 2.4 : 3)),
                ),
                SizedBox(height: compact ? 2 : 4),
                Text(
                  'STEP. RACE. WIN.',
                  textAlign: TextAlign.center,
                  style: PixelText.display(
                    size: compact ? 24 : 28,
                    color: AppColors.pillGold,
                    letterSpacing: 1.6,
                  ).copyWith(shadows: PixelText.skyOutline(1.4)),
                ),
              ],
            ),
          ),
        ),
        Positioned(
          left: 0,
          right: 0,
          bottom: groundHeight - 4 - capySize * 0.22,
          child: Center(child: _HeroCapybara(size: capySize)),
        ),
      ],
    );
  }

  Widget _buildSignInDock(BuildContext context, {required bool compact}) {
    final colors = AppColors.of(context);
    // Same surface the home tab puts below its hero (home_tab.dart): green
    // field + arcade checkers, with the soft dirt shadow along the top edge
    // that blends the scene's soil into the green instead of hard-cutting.
    return ColoredBox(
      key: const Key('start-sign-in-dock'),
      color: colors.roofLight,
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: SafeArea(
          top: false,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Deeper than the home tab's 16px version: brown-to-green is a
              // hue jump, not just a value jump, so the soil veil needs more
              // runway here where nothing else covers the boundary.
              Container(
                height: 34,
                decoration: BoxDecoration(
                  gradient: LinearGradient(
                    begin: Alignment.topCenter,
                    end: Alignment.bottomCenter,
                    colors: [
                      colors.dirtDark.withValues(alpha: 0.62),
                      colors.dirtDark.withValues(alpha: 0.26),
                      colors.dirtDark.withValues(alpha: 0),
                    ],
                    stops: const [0, 0.42, 1],
                  ),
                ),
              ),
              Padding(
                padding: EdgeInsets.fromLTRB(24, compact ? 10 : 14, 24, 14),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    _FeatureRow(compact: compact),
                    SizedBox(height: compact ? 12 : 16),
                    _buildSignInButtons(compact: compact),
                    SizedBox(height: compact ? 8 : 10),
                    _buildLegalLine(context, compact: compact),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildLegalLine(BuildContext context, {required bool compact}) {
    final colors = AppColors.of(context);
    final base = PixelText.body(
      size: compact ? 12.5 : 13.5,
      color: colors.textLight.withValues(alpha: 0.86),
    ).copyWith(fontWeight: FontWeight.w500);
    return Text.rich(
      TextSpan(
        children: [
          const TextSpan(text: 'By continuing, you agree to our '),
          TextSpan(
            text: 'Privacy Policy',
            style: base.copyWith(
              color: AppColors.pillGold,
              fontWeight: FontWeight.w700,
              decoration: TextDecoration.underline,
              decorationColor: AppColors.pillGold,
            ),
            recognizer: _privacyTapRecognizer,
          ),
          const TextSpan(text: '.'),
        ],
      ),
      style: base,
      textAlign: TextAlign.center,
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

/// The title-screen mascot: the plain walking capybara, no accessories.
class _HeroCapybara extends StatelessWidget {
  const _HeroCapybara({required this.size});

  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      image: true,
      label: 'Capybara walking',
      child: CapybaraCustomizationPreview(
        key: const Key('start-hero-capybara'),
        accessories: const [],
        size: size,
        showShadow: false,
      ),
    );
  }
}

/// The three "what this app is" beats, each a generated pixel icon over its
/// label. Deliberately backgroundless so it floats on the dock's gradient
/// rather than sitting in a boxed-off band.
class _FeatureRow extends StatelessWidget {
  const _FeatureRow({required this.compact});

  final bool compact;

  static const _features = <({String asset, String label})>[
    (asset: 'assets/images/title_feat_trophy.png', label: 'RACE\nFRIENDS'),
    (asset: 'assets/images/title_feat_box.png', label: 'EARN\nPOWERUPS'),
    (
      asset: 'assets/images/title_feat_board.png',
      label: 'CLIMB THE\nLEADERBOARD',
    ),
  ];

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final iconSize = compact ? 54.0 : 64.0;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        for (final f in _features)
          Expanded(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Image.asset(
                  f.asset,
                  width: iconSize,
                  height: iconSize,
                  filterQuality: FilterQuality.none,
                  // A missing icon must not blank the title screen: an old
                  // build that somehow lacks the asset just shows the label.
                  errorBuilder: (_, _, _) => SizedBox(height: iconSize),
                ),
                SizedBox(height: compact ? 5 : 7),
                Text(
                  f.label,
                  textAlign: TextAlign.center,
                  style: PixelText.title(
                    size: compact ? 10 : 11,
                    color: colors.textLight,
                  ).copyWith(height: 1.22, letterSpacing: 0.4),
                ),
              ],
            ),
          ),
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
