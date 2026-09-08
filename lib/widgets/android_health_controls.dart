import 'package:flutter/material.dart';
import '../services/health_service.dart';
import '../styles.dart';
import 'pill_button.dart';

Future<void> showAndroidStepHelp(BuildContext context, HealthService health) {
  String? launchError;
  return showDialog<void>(
    context: context,
    builder: (context) => StatefulBuilder(
      builder: (context, setDialogState) => AlertDialog(
        backgroundColor: AppColors.of(context).parchment,
        title: Text('Connect your step app', style: PixelText.title(size: 20)),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                'Google Fit needs to share steps with Health Connect before Bara can read them.\n\n'
                'In Google Fit, tap the Profile tab at the bottom, then the gear at the top. '
                'Turn on “Sync Fit with Health Connect”.\n\n'
                'In Health Connect, allow Google Fit to write Steps and Bara to read Steps. '
                'Other step apps need their own Health Connect sharing enabled.\n\n'
                'After walking, open your step app, then return to Bara. '
                'If you have not walked today, zero steps is normal.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(context).textDark,
                ),
              ),
              if (launchError != null)
                Padding(
                  padding: const EdgeInsets.only(top: 12),
                  child: Text(
                    launchError!,
                    style: PixelText.body(
                      size: 13,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('CLOSE'),
          ),
          TextButton(
            onPressed: () async {
              final opened = await health.openPlatformHealthSettings();
              if (!context.mounted) return;
              if (opened) {
                Navigator.pop(context);
              } else {
                setDialogState(
                  () => launchError =
                      'Couldn’t open settings. Open phone Settings → Health Connect → App permissions.',
                );
              }
            },
            child: const Text('OPEN HEALTH CONNECT'),
          ),
        ],
      ),
    ),
  );
}

/// Persistent, optional Android connection tools; never requests on mount.
class AndroidHealthControls extends StatefulWidget {
  const AndroidHealthControls({super.key, required this.healthService});
  final HealthService healthService;
  @override
  State<AndroidHealthControls> createState() => _AndroidHealthControlsState();
}

class _AndroidHealthControlsState extends State<AndroidHealthControls>
    with WidgetsBindingObserver {
  BackgroundStepAccess? _access;
  bool _busy = false;
  String? _message;
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _load();
  }

  Future<void> _load() async {
    final access = await widget.healthService.backgroundStepAccess();
    if (mounted) setState(() => _access = access);
  }

  Future<void> _request() async {
    if (_busy) return;
    setState(() {
      _busy = true;
      _message = null;
    });
    final access = await widget.healthService.requestBackgroundSteps();
    if (!mounted) return;
    setState(() {
      _busy = false;
      _access = access;
      if (access != BackgroundStepAccess.granted) {
        _message =
            'Background access is optional. You can allow it in Health Connect; '
            'opening Bara still updates your steps.';
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          PillButton(
            label: 'CONNECT GOOGLE FIT',
            variant: PillButtonVariant.secondary,
            fontSize: 12,
            onPressed: () => showAndroidStepHelp(context, widget.healthService),
          ),
          const SizedBox(height: 8),
          Text(switch (_access) {
            BackgroundStepAccess.granted => 'Background steps connected',
            BackgroundStepAccess.unsupported =>
              'Open Bara to update your steps. Background access is unavailable on this device.',
            BackgroundStepAccess.needsSteps =>
              'Connect step access first. Background updates are optional.',
            BackgroundStepAccess.available =>
              'Allow background steps to keep race progress updated while Bara is closed.',
            BackgroundStepAccess.unknown =>
              'Couldn’t check background access. Open Health Connect to check permissions.',
            null => 'Checking background access…',
          }, style: PixelText.body(size: 12, color: colors.textMid)),
          if (_access == BackgroundStepAccess.available) ...[
            const SizedBox(height: 8),
            OutlinedButton(
              style: OutlinedButton.styleFrom(
                foregroundColor: colors.textDark,
                backgroundColor: colors.parchmentDark,
                side: BorderSide(color: colors.parchmentBorder, width: 1.5),
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 12,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(18),
                ),
              ),
              onPressed: _busy ? null : _request,
              child: Text(
                _busy ? 'CHECKING…' : 'ALLOW BACKGROUND STEPS',
                textAlign: TextAlign.center,
                style: PixelText.body(size: 12),
              ),
            ),
          ],
          if (_message != null)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _message!,
                style: PixelText.body(size: 12, color: colors.textMid),
              ),
            ),
        ],
      ),
    );
  }
}
