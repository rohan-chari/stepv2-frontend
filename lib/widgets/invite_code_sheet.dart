import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/deep_link_service.dart';
import '../services/onboarding_state_service.dart';
import '../styles.dart';
import 'game_container.dart';
import 'home_chrome.dart';
import 'pill_button.dart';

class InviteCodeOutcome {
  const InviteCodeOutcome({
    required this.attributed,
    required this.terminal,
    required this.message,
  });
  final bool attributed;
  final bool terminal;
  final String message;
}

Future<InviteCodeOutcome?> showInviteCodeSheet({
  required BuildContext context,
  required AuthService authService,
  required BackendApiService backendApiService,
}) {
  return showModalBottomSheet<InviteCodeOutcome>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Colors.transparent,
    builder: (_) => InviteCodeSheet(
      authService: authService,
      backendApiService: backendApiService,
    ),
  );
}

class InviteCodeSheet extends StatefulWidget {
  const InviteCodeSheet({
    super.key,
    required this.authService,
    required this.backendApiService,
  });

  final AuthService authService;
  final BackendApiService backendApiService;

  @override
  State<InviteCodeSheet> createState() => _InviteCodeSheetState();
}

class _InviteCodeSheetState extends State<InviteCodeSheet> {
  final _controller = TextEditingController();
  bool _submitting = false;
  bool _pasting = false;
  String? _error;

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _paste() async {
    if (_pasting || _submitting) return;
    setState(() => _pasting = true);
    String? pasted;
    try {
      pasted = (await Clipboard.getData(Clipboard.kTextPlain))?.text;
    } catch (_) {
      // The manual field remains available if the OS declines paste access.
    }
    if (!mounted) return;
    final uri = pasted == null ? null : Uri.tryParse(pasted.trim());
    final parsed = pasted == null
        ? null
        : (uri == null
                  ? null
                  : DeepLinkService.parseReferralQuery(uri) ??
                        DeepLinkService.parseReferralCode(uri)) ??
              pasted.trim().toUpperCase();
    setState(() {
      _pasting = false;
      if (parsed != null && parsed.isNotEmpty) {
        _controller.text = parsed;
        _error = null;
      }
    });
  }

  String _reason(Object? reason) => switch (reason) {
    'self_referral' => "You can't use your own invite code.",
    'already_attributed' => 'You already have an invite credited.',
    'already_raced' => 'Invite codes only work before your first race.',
    'unknown_code' || 'invalid_code' => "That code doesn't look right.",
    _ => "Couldn't apply that code. Please try again.",
  };

  Future<void> _apply() async {
    final code = _controller.text.trim().toUpperCase();
    if (code.isEmpty || _submitting) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      setState(() => _error = 'Sign in again to enter an invite code.');
      return;
    }
    setState(() {
      _submitting = true;
      _error = null;
    });
    try {
      final result = await widget.backendApiService.redeemReferralCode(
        identityToken: token,
        code: code,
      );
      if (!mounted) return;
      final attributed = result['attributed'] == true;
      final reason = result['reason'];
      final terminal =
          reason == 'already_attributed' || reason == 'already_raced';
      if (attributed || terminal) {
        await OnboardingStateService().markInviteCodePromptResolved();
        widget.authService.markInviteCodePromptResolvedThisSession();
        if (!mounted) return;
        Navigator.of(context).pop(
          InviteCodeOutcome(
            attributed: attributed,
            terminal: terminal,
            message: attributed
                ? 'Invite credited! Your reward unlocks after your first qualifying race.'
                : _reason(reason),
          ),
        );
      } else {
        setState(() {
          _submitting = false;
          _error = _reason(reason);
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _submitting = false;
          _error = "Couldn't apply that code. Please try again.";
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      top: false,
      child: SingleChildScrollView(
        padding: EdgeInsets.fromLTRB(
          18,
          18,
          18,
          18 + MediaQuery.viewInsetsOf(context).bottom,
        ),
        child: GameContainer(
          frameColor: AppColors.of(context).accent,
          surfaceColor: AppColors.of(context).parchmentLight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'ENTER INVITE CODE',
                textAlign: TextAlign.center,
                style: HomeText.display(
                  size: 21,
                  color: AppColors.of(context).ink,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                "If a friend invited you, enter their code. You'll both earn coins after your first qualifying race.",
                textAlign: TextAlign.center,
                style: HomeText.body(
                  size: 13,
                  color: AppColors.of(context).muted,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                key: const Key('invite-code-field'),
                controller: _controller,
                autofocus: true,
                textCapitalization: TextCapitalization.characters,
                textInputAction: TextInputAction.done,
                onSubmitted: (_) => _apply(),
                decoration: InputDecoration(
                  hintText: 'BARA-XXXX',
                  errorText: _error,
                  filled: true,
                  fillColor: AppColors.of(context).parchment,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                  ),
                ),
              ),
              const SizedBox(height: 10),
              PillButton(
                key: const Key('invite-code-paste'),
                label: _pasting ? 'PASTING…' : 'PASTE INVITE LINK',
                icon: Icons.content_paste_rounded,
                variant: PillButtonVariant.secondary,
                fullWidth: true,
                onPressed: (_pasting || _submitting) ? null : _paste,
              ),
              const SizedBox(height: 12),
              PillButton(
                key: const Key('invite-code-apply'),
                label: _submitting ? 'APPLYING…' : 'APPLY',
                fullWidth: true,
                onPressed: _submitting ? null : _apply,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
