import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'auth_service.dart';
import 'deep_link_service.dart';

/// First-launch referral auto-capture for the *not-yet-installed* case, where a
/// Universal/App Link can't deliver the code (the app didn't exist when the link
/// was tapped). Two platform paths, both resolving to [AuthService.setPendingReferralCode]:
///
///  * Android — Play Install Referrer returns the `&referrer=BARA-…` we bake into
///    the store URL on the /r/ landing page. Deterministic and SILENT.
///  * iOS — `UIPasteboard.detectPatterns` silently reports whether a URL is on
///    the clipboard (no prompt); only then do we read it. The landing page put
///    the full invite URL there behind a user tap.
///
/// Runs at most ONCE per install (a SharedPreferences flag gates it), so iOS
/// never re-reads the clipboard on later launches and Android never re-queries.
/// Never throws — any failure leaves attribution to the deep-link / manual paths.
class InstallAttributionService {
  InstallAttributionService({
    required AuthService authService,
    MethodChannel? channel,
  }) : _authService = authService,
       _channel = channel ?? const MethodChannel('com.steptracker/referral');

  final AuthService _authService;
  final MethodChannel _channel;

  static const _keyChecked = 'install_attribution_checked';

  /// Resolve install-time attribution exactly once. Safe to call on every cold
  /// start; it self-gates and no-ops after the first run.
  Future<void> resolveOnFirstLaunch() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyChecked) ?? false) return;

      // A deep link already captured a code (warm/Universal-Link path) — prefer
      // it and don't touch the clipboard / install referrer at all.
      if (_authService.pendingReferralCode != null) {
        await prefs.setBool(_keyChecked, true);
        return;
      }

      final code = await _resolvePlatformCode();
      if (code != null) {
        await _authService.setPendingReferralCode(code);
      }
      await prefs.setBool(_keyChecked, true);
    } catch (error) {
      debugPrint('InstallAttributionService skipped: $error');
    }
  }

  Future<String?> _resolvePlatformCode() async {
    if (Platform.isAndroid) {
      final raw = await _channel.invokeMethod<String>('getInstallReferrer');
      return extractReferralCode(raw);
    }
    if (Platform.isIOS) {
      // Silent presence check first — no "Allow Paste?" prompt fires here.
      final hasUrl =
          await _channel.invokeMethod<bool>('clipboardHasProbableUrl') ?? false;
      if (!hasUrl) return null;
      final raw = await _channel.invokeMethod<String>('readClipboardUrl');
      return extractReferralCode(raw);
    }
    return null;
  }

  /// Pulls a BARA- referral code out of whatever the platform handed back:
  ///  * an Android referrer query string ("referrer=BARA-7F3K&utm_source=…")
  ///  * a full invite URL ("https://steptracker-api.org/r/BARA-7F3K")
  ///  * a bare code ("BARA-7F3K")
  /// Returns the normalized (uppercase) code, or null if none is present.
  /// Static + side-effect-free for unit testing.
  static String? extractReferralCode(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;

    // Android referrer query string: pull the `referrer` param and recurse.
    if (value.contains('=')) {
      final params = Uri.splitQueryString(value);
      final referrer = params['referrer'];
      if (referrer != null && referrer.isNotEmpty && referrer != value) {
        final fromParam = extractReferralCode(referrer);
        if (fromParam != null) return fromParam;
      }
    }

    // Full URL: reuse the deep-link parser (handles /r/<code>).
    if (value.contains('/')) {
      final uri = Uri.tryParse(value);
      if (uri != null) {
        final fromUri = DeepLinkService.parseReferralCode(uri);
        if (fromUri != null) return fromUri;
      }
    }

    // Bare code.
    final upper = value.toUpperCase();
    if (RegExp(r'^BARA-[A-Z0-9]{2,32}$').hasMatch(upper)) return upper;
    return null;
  }
}
