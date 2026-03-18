import 'package:flutter/material.dart';

import 'main_shell.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/capybara.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/pill_button.dart';
import '../widgets/trail_sign.dart';

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

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(
      text: widget.authService.displayName ?? '',
    );
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _onContinue() async {
    final displayName = _controller.text.trim();

    if (displayName.isEmpty) {
      showErrorToast(context, 'Please enter a display name.');
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
    final groundHeight = MediaQuery.of(context).size.height * 0.22;

    return Scaffold(
      resizeToAvoidBottomInset: false,
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

            // Trail sign at top
            Positioned.fill(
              child: SafeArea(
                child: Padding(
                  padding: const EdgeInsets.only(left: 24, right: 24, top: 60),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      TrailSign(
                        width: 340,
                        child: Column(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'CHOOSE A\nDISPLAY NAME',
                              style: PixelText.title(
                                size: 22,
                                color: AppColors.textDark,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 10),
                            Text(
                              'This is how friends will find you',
                              style: PixelText.body(
                                size: 14,
                                color: AppColors.textMid,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 16),
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
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),

            // Continue button above the grass
            Positioned(
              left: 24,
              right: 24,
              bottom: groundHeight + 16,
              child: Center(
                child: _isSaving
                    ? const CircularProgressIndicator(
                        color: AppColors.accent,
                      )
                    : SizedBox(
                        width: 340,
                        child: PillButton(
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
                      ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
