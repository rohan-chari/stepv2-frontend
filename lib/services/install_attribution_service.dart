import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'activation_analytics_service.dart';
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
/// Which platform path [InstallAttributionService] should take. Injectable so
/// the funnel classification is testable off-device (under `flutter test` the
/// host is macOS/Linux, where both `Platform.isIOS` and `isAndroid` are false).
enum InstallPlatform { ios, android, other }

/// The single per-install outcome of [InstallAttributionService.resolveOnFirstLaunch].
///
/// Every stage of the handoff gets its own value because the whole point of
/// part C is knowing WHICH stage loses referrals: nothing on the clipboard, a
/// read the iOS paste alert refused, or a read that produced no code.
enum InstallAttributionOutcome {
  /// A deep link had already captured a code; no platform probe was needed.
  deepLink,

  /// iOS `detectPatterns` reported no probable URL (or Android had no
  /// referrer string at all). Nothing was ever there to read.
  detectMiss,

  /// Detect said a URL WAS there, but the read came back nil/failed — the
  /// signature of an iOS "Allow Paste?" denial.
  readDenied,

  /// The read succeeded but carried no `BARA-` code.
  readNoCode,

  /// iOS clipboard handoff succeeded.
  codeCaptured,

  /// Android Play Install Referrer carried the code.
  installReferrer,

  /// The channel threw.
  error,
}

class InstallAttributionService {
  InstallAttributionService({
    required AuthService authService,
    MethodChannel? channel,
    InstallPlatform? platform,
  }) : _authService = authService,
       _channel = channel ?? const MethodChannel('com.steptracker/referral'),
       _platform = platform ?? _hostPlatform();

  static InstallPlatform _hostPlatform() {
    if (Platform.isIOS) return InstallPlatform.ios;
    if (Platform.isAndroid) return InstallPlatform.android;
    return InstallPlatform.other;
  }

  final AuthService _authService;
  final MethodChannel _channel;
  final InstallPlatform _platform;

  static const _keyChecked = 'install_attribution_checked';

  /// The stashed outcome event name, written at cold start (before sign-in, so
  /// it cannot be posted yet) and flushed once after sign-in.
  static const keyPendingOutcomeEvent = 'install_attr_pending_event';

  /// Set when a probable invite URL was detected but could not be read. The
  /// onboarding invite-code step reads this to offer a "Paste invite link"
  /// button whose TAP is the user gesture the iOS paste alert wants.
  static const keyDetectedButUnread = 'install_attr_detect_unread';

  static String eventNameFor(InstallAttributionOutcome outcome) {
    switch (outcome) {
      case InstallAttributionOutcome.deepLink:
        return 'install_attr_deep_link';
      case InstallAttributionOutcome.detectMiss:
        return 'install_attr_detect_miss';
      case InstallAttributionOutcome.readDenied:
        return 'install_attr_read_denied';
      case InstallAttributionOutcome.readNoCode:
        return 'install_attr_read_no_code';
      case InstallAttributionOutcome.codeCaptured:
        return 'install_attr_code_captured';
      case InstallAttributionOutcome.installReferrer:
        return 'install_attr_install_referrer';
      case InstallAttributionOutcome.error:
        return 'install_attr_error';
    }
  }

  /// Resolve install-time attribution exactly once. Safe to call on every cold
  /// start; it self-gates and no-ops after the first run.
  Future<void> resolveOnFirstLaunch() async {
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      if (prefs.getBool(_keyChecked) ?? false) return;

      // A deep link already captured a code (warm/Universal-Link path) — prefer
      // it and don't touch the clipboard / install referrer at all.
      if (_authService.pendingReferralCode != null) {
        await _stashOutcome(prefs, InstallAttributionOutcome.deepLink);
        await prefs.setBool(_keyChecked, true);
        return;
      }

      final resolution = await _resolvePlatformCode();
      if (resolution.code != null) {
        await _authService.setPendingReferralCode(resolution.code);
      }
      if (resolution.raceToken != null) {
        await _authService.setPendingShareToken(resolution.raceToken);
      }
      await _stashOutcome(prefs, resolution.outcome);
      if (resolution.outcome == InstallAttributionOutcome.readDenied) {
        await prefs.setBool(keyDetectedButUnread, true);
      }
      await prefs.setBool(_keyChecked, true);
    } catch (error) {
      debugPrint('InstallAttributionService skipped: $error');
      // The failure itself is the finding — record it rather than losing it,
      // but never let bookkeeping throw into launch.
      try {
        if (prefs != null) {
          await _stashOutcome(prefs, InstallAttributionOutcome.error);
          await prefs.setBool(_keyChecked, true);
        }
      } catch (_) {}
    }
  }

  /// Emits the stashed outcome (if any) and drops it, so exactly one
  /// `install_attr_*` event exists per install. Called after sign-in, where an
  /// auth token exists to flush with.
  Future<void> flushStashedOutcome(ActivationAnalyticsService analytics) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final name = prefs.getString(keyPendingOutcomeEvent);
      if (name == null || name.isEmpty) return;
      // Removed BEFORE recording: a duplicate is worse than a loss here — the
      // funnel counts installs, and one install must contribute one row.
      await prefs.remove(keyPendingOutcomeEvent);
      await analytics.record(name);
    } catch (_) {}
  }

  /// Whether a probable invite URL was detected at launch but never read.
  Future<bool> hasUnreadDetectedInvite() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      return prefs.getBool(keyDetectedButUnread) ?? false;
    } catch (_) {
      return false;
    }
  }

  /// The DEFERRED pasteboard read, performed behind an explicit user tap (the
  /// gesture the iOS paste alert wants). Deliberately separate from
  /// [resolveOnFirstLaunch], which stays at-most-once-per-install — the
  /// prompt-at-launch is the exact behavior this is retiring, so this must
  /// never become a second launch-time read.
  ///
  /// Returns the code, or null when the user denies again (the caller then
  /// falls back to manual entry).
  Future<String?> readInviteCodeFromPasteboard() async {
    try {
      final read = await _readClipboard();
      final code = extractReferralCode(read.value);
      if (code != null) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(keyDetectedButUnread);
      }
      return code;
    } catch (_) {
      return null;
    }
  }

  Future<void> _stashOutcome(
    SharedPreferences prefs,
    InstallAttributionOutcome outcome,
  ) => prefs.setString(keyPendingOutcomeEvent, eventNameFor(outcome));

  Future<_PlatformResolution> _resolvePlatformCode() async {
    switch (_platform) {
      case InstallPlatform.android:
        final raw = await _channel.invokeMethod<String>('getInstallReferrer');
        if (raw == null || raw.trim().isEmpty) {
          return const _PlatformResolution(
            InstallAttributionOutcome.detectMiss,
          );
        }
        final code = extractReferralCode(raw);
        final raceToken = extractRaceShareToken(raw);
        return code == null && raceToken == null
            ? const _PlatformResolution(InstallAttributionOutcome.readNoCode)
            : _PlatformResolution(
                InstallAttributionOutcome.installReferrer,
                code: code,
                raceToken: raceToken,
              );
      case InstallPlatform.ios:
        // Silent presence check first — no "Allow Paste?" prompt fires here.
        final hasUrl =
            await _channel.invokeMethod<bool>('clipboardHasProbableUrl') ??
            false;
        if (!hasUrl) {
          return const _PlatformResolution(
            InstallAttributionOutcome.detectMiss,
          );
        }
        final read = await _readClipboard();
        if (read.denied) {
          return const _PlatformResolution(
            InstallAttributionOutcome.readDenied,
          );
        }
        final code = extractReferralCode(read.value);
        final raceToken = extractRaceShareToken(read.value);
        return code == null && raceToken == null
            ? const _PlatformResolution(InstallAttributionOutcome.readNoCode)
            : _PlatformResolution(
                InstallAttributionOutcome.codeCaptured,
                code: code,
                raceToken: raceToken,
              );
      case InstallPlatform.other:
        return const _PlatformResolution(InstallAttributionOutcome.detectMiss);
    }
  }

  /// Reads the pasteboard through the channel, tolerating BOTH shapes: the
  /// map `{status, value}` the current AppDelegate returns, and the bare
  /// string an older/other host might.
  Future<_ClipboardRead> _readClipboard() async {
    final dynamic raw = await _channel.invokeMethod<dynamic>(
      'readClipboardUrl',
    );
    if (raw is String) {
      return _ClipboardRead(value: raw, denied: raw.trim().isEmpty);
    }
    if (raw is Map) {
      final value = raw['value'];
      final status = raw['status']?.toString();
      final text = value is String ? value : null;
      return _ClipboardRead(
        value: text,
        denied: status != 'ok' || text == null || text.trim().isEmpty,
      );
    }
    // Detect said a URL was there and the read produced nothing: the denial
    // signature. Truthful classification is the whole point of this path.
    return const _ClipboardRead(value: null, denied: true);
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
      try {
        final params = Uri.splitQueryString(value);
        final direct = params['ref'];
        if (direct != null) {
          final fromDirect = extractReferralCode(direct);
          if (fromDirect != null) return fromDirect;
        }
        final referrer = params['referrer'];
        if (referrer != null && referrer.isNotEmpty && referrer != value) {
          final fromParam = extractReferralCode(referrer);
          if (fromParam != null) return fromParam;
        }
      } catch (_) {}
    }

    // Full URL: reuse the deep-link parser (handles /r/<code>).
    if (value.contains('/')) {
      final uri = Uri.tryParse(value);
      if (uri != null) {
        final fromUri =
            DeepLinkService.parseReferralQuery(uri) ??
            DeepLinkService.parseReferralCode(uri);
        if (fromUri != null) return fromUri;
      }
    }

    // Bare code.
    final upper = value.toUpperCase();
    if (RegExp(r'^BARA-[A-Z0-9]{2,32}$').hasMatch(upper)) return upper;
    return null;
  }

  static String? extractRaceShareToken(String? raw) {
    if (raw == null) return null;
    final value = raw.trim();
    if (value.isEmpty) return null;
    if (value.contains('=')) {
      try {
        final params = Uri.splitQueryString(value);
        for (final key in const [
          'race',
          'raceToken',
          'shareToken',
          'referrer',
        ]) {
          final nested = params[key];
          if (nested != null && nested != value) {
            if (key == 'raceToken' &&
                RegExp(r'^[A-Za-z0-9_-]{1,128}$').hasMatch(nested) &&
                !nested.toUpperCase().startsWith(kReferralCodePrefix)) {
              return nested;
            }
            final token = extractRaceShareToken(nested);
            if (token != null) return token;
          }
        }
      } catch (_) {}
    }
    final uri = Uri.tryParse(value);
    if (uri != null) return DeepLinkService.parseShareToken(uri);
    return null;
  }
}

class _PlatformResolution {
  const _PlatformResolution(this.outcome, {this.code, this.raceToken});

  final InstallAttributionOutcome outcome;
  final String? code;
  final String? raceToken;
}

class _ClipboardRead {
  const _ClipboardRead({required this.value, required this.denied});

  final String? value;
  final bool denied;
}
