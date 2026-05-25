import 'dart:async';

import 'package:flutter/material.dart';

import '../tutorial/tutorial_screen.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';

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

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

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
          _availabilityMessage = available
              ? null
              : (result['reason'] as String? ?? 'That name is taken');
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
      showErrorToast(
        context,
        'Must be at least $_minDisplayNameLength characters.',
      );
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
            builder: (context) => const TutorialScreen(),
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

  void _dismissKeyboard() {
    FocusManager.instance.primaryFocus?.unfocus();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      resizeToAvoidBottomInset: true,
      body: ArcadePageBackground(
        child: SafeArea(
          child: GestureDetector(
            behavior: HitTestBehavior.opaque,
            onTap: _dismissKeyboard,
            child: LayoutBuilder(
              builder: (context, constraints) {
                final canPop = Navigator.of(context).canPop();
                final bottomInset = MediaQuery.viewInsetsOf(context).bottom;

                return SingleChildScrollView(
                  keyboardDismissBehavior:
                      ScrollViewKeyboardDismissBehavior.onDrag,
                  padding: EdgeInsets.fromLTRB(24, 8, 24, bottomInset + 24),
                  child: ConstrainedBox(
                    constraints: BoxConstraints(
                      minHeight: constraints.maxHeight,
                    ),
                    child: IntrinsicHeight(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          Padding(
                            padding: const EdgeInsets.symmetric(vertical: 8),
                            child: Row(
                              children: [
                                if (canPop)
                                  GestureDetector(
                                    onTap: () => Navigator.of(context).pop(),
                                    child: Container(
                                      padding: const EdgeInsets.all(8),
                                      child: const Icon(
                                        Icons.arrow_back,
                                        color: AppColors.parchmentLight,
                                        size: 24,
                                      ),
                                    ),
                                  ),
                                Expanded(
                                  child: Text(
                                    'CHOOSE A DISPLAY NAME',
                                    style: PixelText.title(
                                      size: 20,
                                      color: AppColors.parchmentLight,
                                    ).copyWith(shadows: _textShadows),
                                    textAlign: TextAlign.center,
                                  ),
                                ),
                                if (canPop) const SizedBox(width: 40),
                              ],
                            ),
                          ),
                          const Spacer(),
                          Center(
                            child: ConstrainedBox(
                              constraints: const BoxConstraints(maxWidth: 420),
                              child: Column(
                                mainAxisSize: MainAxisSize.min,
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Text(
                                    'This is how friends will find you',
                                    style: PixelText.body(
                                      color: AppColors.textMid,
                                    ).copyWith(shadows: _textShadows),
                                    textAlign: TextAlign.center,
                                  ),
                                  const SizedBox(height: 20),
                                  TextField(
                                    controller: _controller,
                                    textAlign: TextAlign.center,
                                    textCapitalization:
                                        TextCapitalization.words,
                                    textInputAction: TextInputAction.done,
                                    onSubmitted: (_) => _dismissKeyboard(),
                                    onTapOutside: (_) => _dismissKeyboard(),
                                    scrollPadding: EdgeInsets.only(
                                      bottom: bottomInset + 120,
                                    ),
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
                                      contentPadding:
                                          const EdgeInsets.symmetric(
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
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                const SizedBox(
                                                  width: 12,
                                                  height: 12,
                                                  child:
                                                      CircularProgressIndicator(
                                                        strokeWidth: 2,
                                                        color:
                                                            AppColors.textMid,
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
                                              textAlign: TextAlign.center,
                                            )
                                          : Text(
                                              _availabilityMessage ?? '',
                                              style: PixelText.body(
                                                color: Colors.red.shade700,
                                              ),
                                              textAlign: TextAlign.center,
                                            ),
                                    ),
                                ],
                              ),
                            ),
                          ),
                          const Spacer(),
                          _isSaving
                              ? const Center(
                                  child: CircularProgressIndicator(
                                    color: AppColors.accent,
                                  ),
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
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
