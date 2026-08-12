import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/onboarding_scene.dart';
import '../widgets/pill_button.dart';

class DiscoverableIdentityFlow extends StatefulWidget {
  const DiscoverableIdentityFlow({
    super.key,
    required this.authService,
    this.backendApiService,
    this.initialFirstName,
    this.initialLastName,
    this.onCompleted,
  });

  final AuthService authService;
  final BackendApiService? backendApiService;
  final String? initialFirstName;
  final String? initialLastName;
  final VoidCallback? onCompleted;

  @override
  State<DiscoverableIdentityFlow> createState() =>
      _DiscoverableIdentityFlowState();
}

class _DiscoverableIdentityFlowState extends State<DiscoverableIdentityFlow> {
  late final BackendApiService _api;
  late final TextEditingController _firstName;
  late final TextEditingController _lastName;
  late final TextEditingController _raceName;
  late final bool _requiredOnboarding;
  final _firstFocus = FocusNode();
  final _raceFocus = FocusNode();
  int _page = 0;
  bool _saving = false;
  bool _resumeSuggestionFailed = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
    _requiredOnboarding = widget.authService.nameSetupOnboardingRequired;
    _firstName = TextEditingController(
      text: widget.authService.firstName ?? widget.initialFirstName ?? '',
    );
    _lastName = TextEditingController(
      text: widget.authService.lastName ?? widget.initialLastName ?? '',
    );
    _raceName = TextEditingController(
      text: widget.authService.displayName ?? '',
    );
    final resumesPendingPageTwo =
        widget.authService.nameSetupCompletedAt == null &&
        (widget.authService.firstName?.trim().isNotEmpty ?? false);
    if (resumesPendingPageTwo) {
      _page = 1;
      if (_requiredOnboarding || _raceName.text.isEmpty) {
        _saving = true;
        WidgetsBinding.instance.addPostFrameCallback(
          (_) => _resumeSuggestion(),
        );
      }
    }
  }

  @override
  void dispose() {
    _firstName.dispose();
    _lastName.dispose();
    _raceName.dispose();
    _firstFocus.dispose();
    _raceFocus.dispose();
    super.dispose();
  }

  Future<void> _saveName() async {
    final first = _firstName.text.trim();
    if (first.isEmpty || _saving) {
      if (first.isEmpty) setState(() => _error = 'First name is required.');
      return;
    }
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Sign in again to continue.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = await _api.updateDiscoverableName(
        identityToken: token,
        firstName: first,
        lastName: _lastName.text.trim().isEmpty ? null : _lastName.text.trim(),
      );
      final user = payload['user'];
      if (user is Map) {
        await widget.authService.syncFromBackendUser(_safeMap(user));
      }
      final suggested = payload['suggestedDisplayName'];
      if ((_requiredOnboarding || widget.authService.displayName == null) &&
          suggested is String &&
          suggested.trim().isNotEmpty) {
        _raceName.text = suggested.trim();
      }
      if (!mounted) return;
      setState(() {
        _page = 1;
        _saving = false;
      });
      _raceFocus.requestFocus();
    } on ApiException catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = switch (error.code) {
          'INVALID_FIRST_NAME' => 'Check your first name and try again.',
          'INVALID_LAST_NAME' => 'Check your last name and try again.',
          _ => error.message,
        };
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn’t save your name. Check your connection and retry.';
        });
      }
    }
  }

  Future<void> _complete() async {
    final raceName = _raceName.text.trim();
    if (raceName.isEmpty || _saving) {
      if (raceName.isEmpty) setState(() => _error = 'Race name is required.');
      return;
    }
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Sign in again to continue.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final payload = await _api.updateDisplayName(
        identityToken: token,
        displayName: raceName,
        completeDiscoverableNameSetup: true,
      );
      final user = payload['user'];
      if (user is! Map) {
        throw const ApiException('Couldn’t confirm your race name.');
      }
      await widget.authService.syncFromBackendUser(_safeMap(user));
      if (!mounted) return;
      widget.onCompleted?.call();
      if (Navigator.of(context).canPop()) Navigator.of(context).pop(true);
    } on ApiException catch (error) {
      if (!mounted) return;
      final suggested = error.details?['suggestedDisplayName'];
      if (error.code == 'DISPLAY_NAME_TAKEN' && suggested is String) {
        _raceName.text = suggested;
      }
      setState(() {
        _saving = false;
        _error = error.code == 'DISPLAY_NAME_TAKEN'
            ? 'That race name was just taken.'
            : error.message;
      });
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Couldn’t confirm your race name. Retry when you’re online.';
        });
      }
    }
  }

  Future<void> _resumeSuggestion() async {
    final token = widget.authService.authToken;
    final first = widget.authService.firstName?.trim();
    if (token == null || token.isEmpty || first == null || first.isEmpty) {
      if (mounted) {
        setState(() {
          _saving = false;
          _resumeSuggestionFailed = true;
          _error = 'Sign in again to continue.';
        });
      }
      return;
    }
    try {
      final payload = await _api.updateDiscoverableName(
        identityToken: token,
        firstName: first,
        lastName: widget.authService.lastName,
      );
      final user = payload['user'];
      if (user is Map) {
        await widget.authService.syncFromBackendUser(_safeMap(user));
      }
      final suggestion = payload['suggestedDisplayName'];
      if (suggestion is String && suggestion.trim().isNotEmpty) {
        _raceName.text = suggestion.trim();
      }
      if (mounted) {
        setState(() {
          _saving = false;
          _resumeSuggestionFailed = false;
          _error = null;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _saving = false;
          _resumeSuggestionFailed = true;
          _error = 'Couldn’t reload your race name. Retry when you’re online.';
        });
      }
    }
  }

  Map<String, dynamic> _safeMap(Map<dynamic, dynamic> raw) => {
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };

  void _back() {
    if (_saving) return;
    if (_page == 1) {
      setState(() {
        _page = 0;
        _error = null;
      });
      _firstFocus.requestFocus();
    } else if (Navigator.of(context).canPop()) {
      Navigator.of(context).pop(false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final isNamePage = _page == 0;
    final colors = AppColors.of(context);
    return PopScope(
      canPop: _page == 0 && !_saving,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop && _page == 1) _back();
      },
      child: Scaffold(
        resizeToAvoidBottomInset: true,
        body: Stack(
          children: [
            OnboardingScene(
              headline: isNamePage
                  ? 'Help friends find you'
                  : 'Choose your race name',
              dockLabel: 'NAME SETUP · ${_page + 1} OF 2',
              dockBody: isNamePage
                  ? 'Add the name people know you by. It is only used so friends can find you in Bara.'
                  : 'This is what people will see in races. We combined your name to get you started — change it if you want.',
              dockExtra: Container(
                key: Key('identity-page-${_page + 1}'),
                child: isNamePage
                    ? _buildNameFields(colors)
                    : _buildRaceNameField(colors),
              ),
              error: _error,
              actions: isNamePage
                  ? [_identityButton(label: "THAT'S ME", onPressed: _saveName)]
                  : [
                      if (_resumeSuggestionFailed) ...[
                        _identityButton(
                          key: const Key('identity-resume-retry'),
                          label: 'RETRY',
                          onPressed: () {
                            setState(() {
                              _saving = true;
                              _resumeSuggestionFailed = false;
                              _error = null;
                            });
                            _resumeSuggestion();
                          },
                        ),
                        const SizedBox(height: 8),
                      ],
                      _identityButton(
                        label: 'CONFIRM RACE NAME',
                        onPressed: _complete,
                      ),
                    ],
            ),
            SafeArea(
              bottom: false,
              child: Container(
                key: const Key('identity-step-header'),
                height: 48,
                padding: const EdgeInsets.symmetric(horizontal: 8),
                alignment: Alignment.centerLeft,
                child: IconButton(
                  key: const Key('identity-back'),
                  tooltip: 'Back',
                  onPressed: _saving ? null : _back,
                  icon: const Icon(
                    Icons.arrow_back_rounded,
                    color: Colors.white,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNameFields(AppPalette colors) => Column(
    key: const ValueKey('name-page'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field(
        key: const Key('identity-first-name-field'),
        controller: _firstName,
        focusNode: _firstFocus,
        label: 'First name',
        action: TextInputAction.next,
      ),
      const SizedBox(height: 10),
      _field(
        key: const Key('identity-last-name-field'),
        controller: _lastName,
        label: 'Last name (optional)',
        action: TextInputAction.done,
        onSubmitted: (_) => _saveName(),
      ),
    ],
  );

  Widget _buildRaceNameField(AppPalette colors) => Column(
    key: const ValueKey('race-name-page'),
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      _field(
        key: const Key('identity-race-name-field'),
        controller: _raceName,
        focusNode: _raceFocus,
        label: 'Race name',
        action: TextInputAction.done,
        onSubmitted: (_) => _complete(),
      ),
      const SizedBox(height: 7),
      if (_error == null)
        Text(
          '4–30 letters, numbers, or underscores. No spaces.',
          key: const Key('identity-helper'),
          style: PixelText.body(
            size: 11.5,
            color: colors.textLight.withValues(alpha: 0.82),
          ),
        ),
    ],
  );

  Widget _identityButton({
    Key? key,
    required String label,
    required VoidCallback onPressed,
  }) => SizedBox(
    key: key,
    width: double.infinity,
    height: 54,
    child: PillButton(
      label: _saving ? 'SAVING...' : label,
      variant: PillButtonVariant.secondary,
      fullWidth: true,
      padding: EdgeInsets.zero,
      onPressed: _saving ? null : onPressed,
    ),
  );

  Widget _field({
    required Key key,
    required TextEditingController controller,
    required String label,
    required TextInputAction action,
    FocusNode? focusNode,
    ValueChanged<String>? onSubmitted,
  }) => Column(
    crossAxisAlignment: CrossAxisAlignment.stretch,
    children: [
      Padding(
        padding: const EdgeInsets.only(left: 2, bottom: 5),
        child: Text(
          label,
          style: PixelText.body(
            size: 11.5,
            color: AppColors.of(context).textLight.withValues(alpha: 0.9),
          ).copyWith(fontWeight: FontWeight.w700),
        ),
      ),
      TextField(
        key: key,
        controller: controller,
        focusNode: focusNode,
        textCapitalization: label == 'Race name'
            ? TextCapitalization.none
            : TextCapitalization.words,
        autocorrect: label != 'Race name',
        textInputAction: action,
        onSubmitted: onSubmitted,
        onChanged: (_) {
          if (_error != null) setState(() => _error = null);
        },
        decoration: InputDecoration(
          filled: true,
          fillColor: AppColors.of(context).parchmentLight,
          contentPadding: const EdgeInsets.symmetric(
            horizontal: 14,
            vertical: 14,
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(
              color: AppColors.of(context).parchmentBorder,
              width: 1.5,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(9),
            borderSide: BorderSide(
              color: AppColors.of(context).accent,
              width: 2,
            ),
          ),
        ),
      ),
    ],
  );
}
