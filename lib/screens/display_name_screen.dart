import 'dart:async';

import 'package:flutter/material.dart';

import 'main_shell.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/notification_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';

const _minDisplayNameLength = 4;
const _maxDisplayNameLength = 30;

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

    if (text.contains(RegExp(r'\s'))) {
      setState(() {
        _isAvailable = null;
        _isChecking = false;
        _availabilityMessage = 'Display name cannot contain spaces';
      });
      return;
    }

    if (text.isNotEmpty && !RegExp(r'^[A-Za-z0-9_]+$').hasMatch(text)) {
      setState(() {
        _isAvailable = null;
        _isChecking = false;
        _availabilityMessage = 'Only letters, numbers, and underscores allowed';
      });
      return;
    }

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

    if (text.length > _maxDisplayNameLength) {
      setState(() {
        _isAvailable = null;
        _isChecking = false;
        _availabilityMessage =
            'Must be no more than $_maxDisplayNameLength characters';
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

    if (displayName.contains(RegExp(r'\s'))) {
      showErrorToast(context, 'Display name cannot contain spaces.');
      return;
    }

    if (!RegExp(r'^[A-Za-z0-9_]+$').hasMatch(displayName)) {
      showErrorToast(
        context,
        'Only letters, numbers, and underscores allowed.',
      );
      return;
    }

    if (displayName.length < _minDisplayNameLength) {
      showErrorToast(
        context,
        'Must be at least $_minDisplayNameLength characters.',
      );
      return;
    }

    if (displayName.length > _maxDisplayNameLength) {
      showErrorToast(
        context,
        'Must be no more than $_maxDisplayNameLength characters.',
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
        // First run: this screen is the root route (StartScreen pushReplaced
        // into it), so there is nothing to pop back to — route forward into the
        // app. The tutorial is no longer shown here; it lives as a step inside
        // MainShell's onboarding sequence (after the permission gates), where
        // finishing it grants the one-time 100-coin reward.
        Navigator.of(context).pushReplacement(
          MaterialPageRoute(
            builder: (_) => MainShell(
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
      } else if (raw.contains('cannot contain spaces')) {
        message = 'Display name cannot contain spaces.';
      } else if (raw.contains('letters, numbers, and underscores')) {
        message = 'Only letters, numbers, and underscores allowed.';
      } else if (raw.contains('inappropriate')) {
        message = 'Please choose a different display name.';
      } else if (raw.contains('no more than')) {
        message = 'Must be no more than $_maxDisplayNameLength characters.';
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
    final canPop = Navigator.of(context).canPop();
    final bottomInset = MediaQuery.viewInsetsOf(context).bottom;
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      resizeToAvoidBottomInset: true,
      backgroundColor: Colors.transparent,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.of(context).roofLight,
              child: CustomPaint(
                painter: ArcadeCheckerPainter(drawBottomStripe: false),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: topInset),
            child: GestureDetector(
              behavior: HitTestBehavior.opaque,
              onTap: _dismissKeyboard,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  _buildHeader(canPop: canPop),
                  Expanded(
                    child: ColoredBox(
                      color: AppColors.of(context).parchment,
                      child: SingleChildScrollView(
                        keyboardDismissBehavior:
                            ScrollViewKeyboardDismissBehavior.onDrag,
                        padding: EdgeInsets.fromLTRB(
                          16,
                          20,
                          16,
                          bottomInset + 24,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            TextField(
                              controller: _controller,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.done,
                              onSubmitted: (_) => _dismissKeyboard(),
                              onTapOutside: (_) => _dismissKeyboard(),
                              scrollPadding: EdgeInsets.only(
                                bottom: bottomInset + 120,
                              ),
                              style: PixelText.body(
                                size: 18,
                                color: AppColors.of(context).textDark,
                              ),
                              decoration: InputDecoration(
                                filled: true,
                                fillColor: AppColors.of(context).parchmentLight,
                                // Visual-only handle hint; the '@' never enters
                                // the controller, so the stored/validated value
                                // stays bare.
                                prefixText: '@',
                                prefixStyle: PixelText.body(
                                  size: 18,
                                  color: AppColors.of(context).textMid,
                                ),
                                hintText: 'Choose your name',
                                hintStyle: PixelText.body(
                                  size: 18,
                                  color: AppColors.of(context).parchmentBorder,
                                ),
                                border: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppColors.of(
                                      context,
                                    ).parchmentBorder,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppColors.of(
                                      context,
                                    ).parchmentBorder,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderSide: BorderSide(
                                    color: AppColors.of(context).accent,
                                    width: 2,
                                  ),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 14,
                                ),
                              ),
                            ),
                            const SizedBox(height: 8),
                            _buildAvailabilityRow(),
                            const SizedBox(height: 14),
                            Text(
                              '4–30 characters. Letters, numbers, and underscores only.',
                              style: PixelText.body(
                                size: 13,
                                color: AppColors.of(context).textMid,
                              ),
                            ),
                            const SizedBox(height: 28),
                            _isSaving
                                ? Center(
                                    child: CircularProgressIndicator(
                                      color: AppColors.of(context).accent,
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
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader({required bool canPop}) {
    return DecoratedBox(
      decoration: BoxDecoration(
        color: AppColors.of(context).roofLight,
        border: Border(
          bottom: BorderSide(color: AppColors.of(context).roofDark, width: 1),
        ),
      ),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (canPop)
                Padding(
                  padding: const EdgeInsets.only(bottom: 4),
                  child: Align(
                    alignment: Alignment.centerLeft,
                    child: IconButton(
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                      icon: Icon(
                        Icons.arrow_back,
                        color: AppColors.of(context).textLight,
                      ),
                      onPressed: () => Navigator.of(context).pop(),
                    ),
                  ),
                ),
              Text(
                'DISPLAY NAME',
                style: PixelText.title(
                  size: 30,
                  color: AppColors.of(context).textLight,
                ).copyWith(shadows: _textShadows),
              ),
              const SizedBox(height: 5),
              Text(
                'This is how friends will find you.',
                style: PixelText.body(
                  size: 15,
                  color: AppColors.of(
                    context,
                  ).textLight.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildAvailabilityRow() {
    if (_isChecking) {
      return Row(
        children: [
          SizedBox(
            width: 12,
            height: 12,
            child: CircularProgressIndicator(
              strokeWidth: 2,
              color: AppColors.of(context).textMid,
            ),
          ),
          const SizedBox(width: 8),
          Text(
            'Checking…',
            style: PixelText.body(
              size: 13,
              color: AppColors.of(context).textMid,
            ),
          ),
        ],
      );
    }
    if (_isAvailable == true) {
      return Row(
        children: [
          Icon(
            Icons.check_circle_rounded,
            size: 16,
            color: AppColors.of(context).successText,
          ),
          const SizedBox(width: 6),
          Text(
            'Name is available',
            style: PixelText.body(
              size: 13,
              color: AppColors.of(context).successText,
            ),
          ),
        ],
      );
    }
    if (_availabilityMessage != null) {
      return Row(
        children: [
          Icon(
            Icons.error_outline_rounded,
            size: 16,
            color: AppColors.of(context).error,
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              _availabilityMessage!,
              style: PixelText.body(
                size: 13,
                color: AppColors.of(context).error,
              ),
            ),
          ),
        ],
      );
    }
    return const SizedBox(height: 16);
  }
}
