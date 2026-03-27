import 'dart:async';
import 'dart:math';

import 'package:flutter/material.dart';

import 'main_shell.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/capybara.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/wooden_tab_bar.dart';

const _minDisplayNameLength = 8;

class DisplayNameScreen extends StatefulWidget {
  const DisplayNameScreen({
    super.key,
    required this.authService,
    this.notificationService,
  });

  final AuthService authService;
  final NotificationService? notificationService;

  @override
  State<DisplayNameScreen> createState() => _DisplayNameScreenState();
}

class _DisplayNameScreenState extends State<DisplayNameScreen> {
  final BackendApiService _backendApiService = BackendApiService();
  late final TextEditingController _controller;
  bool _isSaving = false;
  Timer? _debounce;
  String? _availabilityMessage;
  bool? _isAvailable;
  bool _isChecking = false;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.authService.displayName ?? '',
    );
    _controller.addListener(_onNameChanged);
  }

  @override
  void dispose() {
    _debounce?.cancel();
    _controller.removeListener(_onNameChanged);
    _controller.dispose();
    super.dispose();
  }

  void _onNameChanged() {
    _debounce?.cancel();
    final text = _controller.text.trim();

    if (text.length < _minDisplayNameLength) {
      setState(() {
        _isAvailable = null;
        _isChecking = false;
        _availabilityMessage = text.isEmpty
            ? null
            : 'Must be at least $_minDisplayNameLength characters';
      });
      return;
    }

    // Same as current name — no need to check
    if (text == widget.authService.displayName) {
      setState(() {
        _isAvailable = true;
        _isChecking = false;
        _availabilityMessage = null;
      });
      return;
    }

    setState(() => _isChecking = true);

    _debounce = Timer(const Duration(milliseconds: 500), () async {
      final token = widget.authService.authToken;
      if (token == null || token.isEmpty) return;

      try {
        final result = await _backendApiService.checkDisplayName(
          identityToken: token,
          name: text,
        );
        if (!mounted || _controller.text.trim() != text) return;

        final available = result['available'] == true;
        setState(() {
          _isAvailable = available;
          _isChecking = false;
          _availabilityMessage =
              available ? null : (result['reason'] as String? ?? 'That name is taken');
        });
      } catch (_) {
        if (!mounted) return;
        setState(() {
          _isChecking = false;
          _isAvailable = null;
          _availabilityMessage = null;
        });
      }
    });
  }

  Future<void> _onContinue() async {
    final displayName = _controller.text.trim();

    if (displayName.isEmpty) {
      showErrorToast(context, 'Please enter a display name.');
      return;
    }

    if (displayName.length < _minDisplayNameLength) {
      showErrorToast(context, 'Must be at least $_minDisplayNameLength characters.');
      return;
    }

    setState(() => _isSaving = true);

    try {
      final identityToken = widget.authService.authToken;

      if (identityToken == null || identityToken.isEmpty) {
        throw Exception('not signed in');
      }

      await _backendApiService.setDisplayName(
        identityToken: identityToken,
        displayName: displayName,
      );

      await widget.authService.updateDisplayName(displayName);

      if (!mounted) return;

      if (Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      } else {
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (context) => MainShell(
              authService: widget.authService,
              notificationService: widget.notificationService,
            ),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isSaving = false);
      final raw = e.toString();
      final String message;
      if (raw.contains('already taken')) {
        message = 'That name is taken \u2014 try another!';
      } else if (raw.contains('at least')) {
        message = 'Must be at least $_minDisplayNameLength characters.';
      } else if (raw.contains('non-empty string')) {
        message = 'Please enter a valid display name.';
      } else {
        message = 'Couldn\u2019t save your display name. Please try again.';
      }
      showErrorToast(context, message);
    }
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    final bottomInset = MediaQuery.of(context).padding.bottom;
    final tabBarHeight = 77.5 + bottomInset;
    const grassHeight = 110.0;

    return Scaffold(
      resizeToAvoidBottomInset: false,
      body: Stack(
        children: [
          // Sky gradient background
          Positioned.fill(
            child: Container(
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
            ),
          ),

          // Content: board fills from top safe area to above grass
          Positioned(
            left: 0,
            right: 0,
            top: topInset + 24,
            bottom: tabBarHeight + grassHeight,
            child: ContentBoard(
              expand: true,
              child: Column(
                children: [
                  // Header
                  Padding(
                    padding: const EdgeInsets.only(top: 4, bottom: 8),
                    child: Text(
                      'CHOOSE A DISPLAY NAME',
                      style: PixelText.title(size: 24, color: AppColors.textDark),
                      textAlign: TextAlign.center,
                    ),
                  ),
                  Container(
                    height: 1,
                    color: AppColors.parchmentBorder.withValues(alpha: 0.5),
                  ),
                  // Centered content
                  Expanded(
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                      Text(
                        'This is how friends will find you',
                        style: PixelText.body(color: AppColors.textMid),
                        textAlign: TextAlign.center,
                      ),
                      const SizedBox(height: 20),
                      TextField(
                        controller: _controller,
                        textAlign: TextAlign.center,
                        textCapitalization: TextCapitalization.words,
                        style: PixelText.body(
                          size: 18,
                          color: AppColors.textDark,
                        ),
                        decoration: InputDecoration(
                          filled: true,
                          fillColor: AppColors.parchmentLight,
                          hintText: 'Choose your name',
                          hintStyle: PixelText.body(
                            size: 18,
                            color: AppColors.parchmentBorder,
                          ),
                          border: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.parchmentBorder,
                            ),
                            borderRadius: BorderRadius.circular(8),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(
                              color: AppColors.parchmentBorder,
                            ),
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
                      if (_isChecking ||
                          _availabilityMessage != null ||
                          _isAvailable == true)
                        Padding(
                          padding: const EdgeInsets.only(top: 8),
                          child: _isChecking
                              ? Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    const SizedBox(
                                      width: 12,
                                      height: 12,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: AppColors.textMid,
                                      ),
                                    ),
                                    const SizedBox(width: 6),
                                    Text(
                                      'Checking...',
                                      style: PixelText.body(
                                        color: AppColors.textMid,
                                      ),
                                    ),
                                  ],
                                )
                              : _isAvailable == true
                                  ? Text(
                                      'Name is available!',
                                      style: PixelText.body(
                                        color: Colors.green.shade700,
                                      ),
                                    )
                                  : Text(
                                      _availabilityMessage ?? '',
                                      style: PixelText.body(
                                        color: Colors.red.shade700,
                                      ),
                                    ),
                        ),
                      const SizedBox(height: 24),
                      _isSaving
                          ? const CircularProgressIndicator(
                              color: AppColors.accent,
                            )
                          : PillButton(
                              label: 'CONTINUE',
                              variant: PillButtonVariant.primary,
                              fontSize: 16,
                              fullWidth: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 48,
                                vertical: 16,
                              ),
                              onPressed: _onContinue,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),

          // Grass strip
          Positioned(
            left: 0,
            right: 0,
            bottom: tabBarHeight,
            height: grassHeight,
            child: CustomPaint(painter: _GrassPainter()),
          ),

          // Capybara walking on the grass
          Positioned(
            left: 0,
            right: 0,
            bottom: tabBarHeight + 10,
            height: 112,
            child: const WalkingCapybara(
              walkDuration: Duration(seconds: 10),
              size: 112,
            ),
          ),

          // Nav bar at bottom (visual only)
          Positioned(
            left: 0,
            right: 0,
            bottom: 0,
            child: WoodenTabBar(
              currentIndex: 0,
              onTap: (_) {},
              items: const [
                WoodenTabItem(icon: Icons.home_rounded, label: 'Home'),
                WoodenTabItem(icon: Icons.emoji_events_rounded, label: 'Challenges'),
                WoodenTabItem(icon: Icons.people_rounded, label: 'Friends'),
                WoodenTabItem(icon: Icons.leaderboard_rounded, label: 'Leaderboard'),
                WoodenTabItem(icon: Icons.person_rounded, label: 'Profile'),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _GrassPainter extends CustomPainter {
  @override
  void paint(Canvas canvas, Size size) {
    final dirtPath = Path()..moveTo(0, size.height * 0.3);
    for (double x = 0; x <= size.width; x += 4) {
      dirtPath.lineTo(x, size.height * 0.3 + sin(x * 0.008) * 6 + cos(x * 0.015) * 4);
    }
    dirtPath.lineTo(size.width, size.height);
    dirtPath.lineTo(0, size.height);
    dirtPath.close();
    canvas.drawPath(dirtPath, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [AppColors.dirtLight, AppColors.dirtMid, AppColors.dirtDark],
      ).createShader(Offset.zero & size));

    final grassPath = Path()..moveTo(0, size.height * 0.2);
    for (double x = 0; x <= size.width; x += 4) {
      grassPath.lineTo(x, size.height * 0.2 + sin(x * 0.008) * 6 + cos(x * 0.015) * 4);
    }
    grassPath.lineTo(size.width, size.height * 0.4);
    for (double x = size.width; x >= 0; x -= 4) {
      grassPath.lineTo(x, size.height * 0.4 + sin(x * 0.008) * 4 + cos(x * 0.015) * 3);
    }
    grassPath.close();
    canvas.drawPath(grassPath, Paint()
      ..shader = const LinearGradient(
        begin: Alignment.topCenter, end: Alignment.bottomCenter,
        colors: [AppColors.grassBright, AppColors.grassMid, AppColors.grassDark],
      ).createShader(Offset.zero & size));

    final hlPath = Path();
    for (double x = 0; x <= size.width; x += 4) {
      final y = size.height * 0.2 + sin(x * 0.008) * 6 + cos(x * 0.015) * 4;
      if (x == 0) hlPath.moveTo(x, y); else hlPath.lineTo(x, y);
    }
    canvas.drawPath(hlPath, Paint()
      ..color = const Color(0xFFA5D6A7)..style = PaintingStyle.stroke..strokeWidth = 2);
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}
