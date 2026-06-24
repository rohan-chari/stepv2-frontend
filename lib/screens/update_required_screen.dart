import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:url_launcher/url_launcher.dart';

import '../styles.dart';
import '../widgets/pill_button.dart';

/// Hard, non-dismissible block shown when the running build is below the
/// backend's supported floor. There is no way past it but to update — no close
/// button, no back gesture — so it fully replaces the app UI until the user
/// installs a newer build.
class UpdateRequiredScreen extends StatelessWidget {
  const UpdateRequiredScreen({super.key, this.iosUrl, this.androidUrl});

  /// Store links from the version policy. Either may be null (old/partial
  /// backend); the button falls back to opening the platform store generically.
  final String? iosUrl;
  final String? androidUrl;

  String? get _storeUrl => Platform.isIOS ? iosUrl : androidUrl;

  Future<void> _openStore() async {
    final url = _storeUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    // Swallow the system back gesture/button so the block can't be dismissed.
    return PopScope(
      canPop: false,
      child: Scaffold(
        backgroundColor: AppColors.parchment,
        body: SafeArea(
          child: Center(
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 32),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(
                    Icons.system_update,
                    size: 72,
                    color: AppColors.accent,
                  ),
                  const SizedBox(height: 24),
                  Text(
                    'Update Required',
                    textAlign: TextAlign.center,
                    style: PixelText.title(size: 28),
                  ),
                  const SizedBox(height: 12),
                  Text(
                    'This version of Bara is no longer supported. '
                    'Please update to the latest version to keep playing.',
                    textAlign: TextAlign.center,
                    style: PixelText.body(size: 15, color: AppColors.textMid),
                  ),
                  const SizedBox(height: 32),
                  if (_storeUrl != null)
                    PillButton(
                      label: 'UPDATE NOW',
                      fullWidth: true,
                      icon: Icons.download_rounded,
                      onPressed: _openStore,
                    ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
