import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import 'pill_button.dart';

/// Opens the suggestion sheet with the exact `showModalBottomSheet`
/// configuration Settings has always used (scroll-controlled so the keyboard
/// doesn't clip it, parchment background, 16px top radius).
///
/// Extracted from `settings_screen.dart` (batch 2026-08-10b item 5) so Home can
/// offer the same sheet. Every widget key is preserved verbatim —
/// `feedback-sheet`, `feedback-input`, `feedback-error`, `feedback-submit` —
/// because the settings tests assert on them and are the check on this move.
Future<void> showFeedbackSheet({
  required BuildContext context,
  required AuthService authService,
  required BackendApiService backendApiService,
}) {
  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    backgroundColor: AppColors.of(context).parchment,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
    ),
    builder: (ctx) => FeedbackSheet(
      authService: authService,
      backendApiService: backendApiService,
    ),
  );
}

/// Batch 2026-08-08 item 7 — the suggestion sheet. Offline keeps the text and
/// offers a retry; the user never loses what they typed.
class FeedbackSheet extends StatefulWidget {
  const FeedbackSheet({
    super.key,
    required this.authService,
    required this.backendApiService,
  });

  final AuthService authService;
  final BackendApiService backendApiService;

  @override
  State<FeedbackSheet> createState() => _FeedbackSheetState();
}

class _FeedbackSheetState extends State<FeedbackSheet> {
  static const int _maxChars = 2000;

  final TextEditingController _controller = TextEditingController();
  bool _sending = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller.addListener(() => setState(() {}));
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    final text = _controller.text.trim();
    if (text.isEmpty || _sending) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    setState(() {
      _sending = true;
      _error = null;
    });
    try {
      await widget.backendApiService.submitSuggestion(
        identityToken: token,
        text: text,
      );
      if (!mounted) return;
      Navigator.of(context).pop();
      // The toast belongs to the screen underneath, which outlives the sheet.
    } on ApiException catch (e) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        // Keep the text. The retry button re-posts exactly what they wrote.
        _error = e.statusCode == 429
            ? "That's plenty for today. Thanks! Try again tomorrow."
            : "Couldn't send that. Check your connection and try again.";
      });
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _sending = false;
        _error = "Couldn't send that. Check your connection and try again.";
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final length = _controller.text.characters.length;
    final tooLong = length > _maxChars;
    final canSend = _controller.text.trim().isNotEmpty && !tooLong && !_sending;

    return Padding(
      padding: EdgeInsets.only(
        bottom: MediaQuery.of(context).viewInsets.bottom,
      ),
      child: SafeArea(
        key: const Key('feedback-sheet'),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'SEND FEEDBACK',
                textAlign: TextAlign.center,
                style: PixelText.title(size: 17, color: colors.textDark),
              ),
              const SizedBox(height: 4),
              Text(
                'Ideas, bugs, gripes. We read every one.',
                textAlign: TextAlign.center,
                style: PixelText.body(size: 12, color: colors.textMid),
              ),
              const SizedBox(height: 12),
              TextField(
                key: const Key('feedback-input'),
                controller: _controller,
                autofocus: true,
                maxLines: 5,
                minLines: 3,
                enabled: !_sending,
                textCapitalization: TextCapitalization.sentences,
                style: PixelText.body(size: 14, color: colors.textDark),
                decoration: InputDecoration(
                  hintText: 'What would make Bara better?',
                  hintStyle: PixelText.body(size: 13, color: colors.textMid),
                  filled: true,
                  fillColor: colors.parchmentLight,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(10),
                    borderSide: BorderSide(
                      color: colors.parchmentBorder,
                      width: 1.5,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Align(
                alignment: Alignment.centerRight,
                child: Text(
                  '$length / $_maxChars',
                  style: PixelText.body(
                    size: 11,
                    color: tooLong ? colors.error : colors.textMid,
                  ),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: 4),
                Text(
                  _error!,
                  key: const Key('feedback-error'),
                  style: PixelText.body(size: 12, color: colors.error),
                ),
              ],
              const SizedBox(height: 10),
              PillButton(
                key: const Key('feedback-submit'),
                // The label becomes RETRY once a send has failed, so the
                // button says what it will do rather than repeating itself.
                label: _error == null ? 'SUBMIT' : 'RETRY',
                variant: PillButtonVariant.primary,
                fullWidth: true,
                loading: _sending,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: canSend ? _submit : null,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
