import 'dart:io' show Platform;

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'config/backend_config.dart';
import 'constants/powerup_copy.dart';
import 'screens/display_name_screen.dart';
import 'screens/main_shell.dart';
import 'screens/start_screen.dart';
import 'screens/update_required_screen.dart';
import 'services/auth_service.dart';
import 'services/backend_api_service.dart';
import 'services/background_sync_bootstrap_service.dart';
import 'services/deep_link_service.dart';
import 'services/install_attribution_service.dart';
import 'services/notification_service.dart';
import 'styles.dart';
import 'theme_controller.dart';
import 'utils/app_version_gate.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await BackgroundSyncBootstrapService().persistBackendBaseUrl();

  // FCM/Firebase is Android-only. iOS push stays on the native APNs bridge and
  // has no Firebase config, so never initialize Firebase there.
  if (Platform.isAndroid) {
    await Firebase.initializeApp();
  }

  final notificationService = NotificationService();
  await notificationService.initialize();

  // One AuthService shared by the deep-link capture and the widget tree, so a
  // race share token captured from a launch link is persisted into the very
  // instance the session gate + MainShell observe. Capturing the cold-start
  // link before runApp means the token is already persisted when the session
  // gate restores it.
  final authService = AuthService();
  final deepLinkService = DeepLinkService(authService: authService);
  await deepLinkService.initialize();

  // First-launch referral auto-capture for the not-yet-installed case (Android
  // Play Install Referrer / iOS clipboard handoff). Self-gates to run once and
  // defers to a deep-link-captured code if one already exists. Never blocks
  // launch on failure.
  await InstallAttributionService(
    authService: authService,
  ).resolveOnFirstLaunch();

  final themePreference = await AppThemeController.loadPreference();
  final themeController = AppThemeController(preference: themePreference);

  runApp(
    StepTrackerApp(
      notificationService: notificationService,
      authService: authService,
      deepLinkService: deepLinkService,
      themeController: themeController,
    ),
  );
}

class StepTrackerApp extends StatelessWidget {
  const StepTrackerApp({
    super.key,
    required this.notificationService,
    required this.authService,
    required this.deepLinkService,
    required this.themeController,
  });

  final NotificationService notificationService;
  final AuthService authService;

  // Held for its lifetime so the deep-link stream subscription stays alive for
  // the life of the app (links tapped while running).
  final DeepLinkService deepLinkService;
  final AppThemeController themeController;

  @override
  Widget build(BuildContext context) {
    return AppThemeScope(
      controller: themeController,
      child: AnimatedBuilder(
        animation: themeController,
        builder: (context, _) {
          final reduceMotion = WidgetsBinding
              .instance
              .platformDispatcher
              .accessibilityFeatures
              .disableAnimations;
          final dark = themeController.resolvedMode == ThemeMode.dark;
          return MaterialApp(
            title: 'Bara',
            debugShowCheckedModeBanner: false,
            theme: AppThemeData.light(),
            darkTheme: AppThemeData.night(),
            themeMode: themeController.resolvedMode,
            themeAnimationDuration: reduceMotion
                ? Duration.zero
                : const Duration(milliseconds: 250),
            themeAnimationCurve: Curves.easeOutCubic,
            builder: (context, child) => AnnotatedRegion<SystemUiOverlayStyle>(
              value: SystemUiOverlayStyle(
                statusBarColor: Colors.transparent,
                statusBarIconBrightness: dark
                    ? Brightness.light
                    : Brightness.dark,
                statusBarBrightness: dark ? Brightness.dark : Brightness.light,
                systemNavigationBarColor: AppColors.of(context).parchmentLight,
                systemNavigationBarIconBrightness: dark
                    ? Brightness.light
                    : Brightness.dark,
              ),
              child: _EnvironmentBanner(child: child),
            ),
            home: _VersionGate(
              child: _SessionGate(
                authService: authService,
                notificationService: notificationService,
              ),
            ),
          );
        },
      ),
    );
  }
}

/// Wraps the whole app in the server-driven force-update gate. On launch and on
/// every resume it fetches the version policy and compares it to this build:
///   - below the supported floor  -> replace everything with a hard block
///   - behind the latest version  -> a one-time dismissible "update available"
///   - otherwise                  -> render the app untouched
///
/// Fails OPEN: any error (offline, a 404 from a backend that predates the
/// endpoint, a parse failure) leaves the user fully unblocked. Old app builds
/// that predate this gate simply never run it.
class _VersionGate extends StatefulWidget {
  const _VersionGate({required this.child});

  final Widget child;

  @override
  State<_VersionGate> createState() => _VersionGateState();
}

class _VersionGateState extends State<_VersionGate>
    with WidgetsBindingObserver {
  final BackendApiService _api = BackendApiService();
  VersionPolicy? _policy;
  VersionGateStatus _status = VersionGateStatus.ok;
  bool _softNudgeShown = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _check();
    _bootstrapPowerupCopy();
  }

  /// §9.5.4: load the persisted last-known-good powerup copy, then refresh from
  /// the backend. Both are non-blocking and never throw — a failure just leaves
  /// the bundled emergency copy in place until the next launch/foreground.
  Future<void> _bootstrapPowerupCopy() async {
    await PowerupCopy.loadPersisted();
    await _refreshPowerupCopy();
  }

  Future<void> _refreshPowerupCopy() {
    // Concurrent calls are coalesced inside PowerupCopy, so a resume racing the
    // cold-start fetch issues only one request.
    return PowerupCopy.refresh(fetch: _api.fetchPowerupCatalog);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Re-check on resume so flipping the floor on the backend takes effect the
    // next time the app comes to the foreground, not only on a cold start.
    if (state == AppLifecycleState.resumed) {
      _check();
      // A copy fix on the backend reaches users on the next foreground, with no
      // App Store release. A 404/timeout/5xx here is transient by contract, so
      // every later foreground retries.
      _refreshPowerupCopy();
    }
  }

  Future<void> _check() async {
    try {
      final json = await _api.fetchVersionPolicy();
      final policy = VersionPolicy.fromJson(json);
      final info = await PackageInfo.fromPlatform();
      final current = info.version.isEmpty ? 'unknown' : info.version;
      final status = evaluateVersionGate(
        currentVersion: current,
        policy: policy,
      );
      if (!mounted) return;
      setState(() {
        _policy = policy;
        _status = status;
      });
      if (status == VersionGateStatus.updateAvailable) {
        _maybeShowSoftNudge();
      }
    } catch (_) {
      // Fail open — never block on a failed/absent policy.
    }
  }

  void _maybeShowSoftNudge() {
    if (_softNudgeShown) return;
    _softNudgeShown = true;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(
        SnackBar(
          duration: const Duration(seconds: 6),
          content: const Text('A new version of Bara is available.'),
          action: SnackBarAction(label: 'UPDATE', onPressed: _openStore),
        ),
      );
    });
  }

  Future<void> _openStore() async {
    final policy = _policy;
    if (policy == null) return;
    final url = Platform.isIOS ? policy.iosUrl : policy.androidUrl;
    if (url == null) return;
    final uri = Uri.tryParse(url);
    if (uri == null) return;
    await launchUrl(uri, mode: LaunchMode.externalApplication);
  }

  @override
  Widget build(BuildContext context) {
    if (_status == VersionGateStatus.updateRequired) {
      return UpdateRequiredScreen(
        iosUrl: _policy?.iosUrl,
        androidUrl: _policy?.androidUrl,
      );
    }
    return widget.child;
  }
}

class _SessionGate extends StatefulWidget {
  const _SessionGate({
    required this.authService,
    required this.notificationService,
  });

  final AuthService authService;
  final NotificationService notificationService;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  bool _loading = true;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final restored = await widget.authService.restoreSession();
    setState(() {
      _hasSession = restored;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }

    if (_hasSession &&
        (widget.authService.displayName != null ||
            widget.authService.onboardingV2Enabled)) {
      return MainShell(
        authService: widget.authService,
        notificationService: widget.notificationService,
      );
    }

    if (_hasSession) {
      return DisplayNameScreen(
        authService: widget.authService,
        notificationService: widget.notificationService,
      );
    }

    return StartScreen(notificationService: widget.notificationService);
  }
}

class _EnvironmentBanner extends StatelessWidget {
  const _EnvironmentBanner({required this.child});

  final Widget? child;

  @override
  Widget build(BuildContext context) {
    final env = BackendConfig.environment;
    if (env == BackendEnvironment.production) {
      return child ?? const SizedBox.shrink();
    }

    final isStaging = env == BackendEnvironment.staging;
    final label = isStaging
        ? 'This is the staging environment for Bara'
        : 'This is the local environment for Bara';
    final color = isStaging ? Colors.orange.shade700 : Colors.blue.shade700;

    return Material(
      color: color,
      child: SafeArea(
        bottom: false,
        child: Column(
          children: [
            Container(
              width: double.infinity,
              color: color,
              padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 16),
              child: Center(
                child: Text(
                  label,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            ),
            if (child != null) Expanded(child: child!),
          ],
        ),
      ),
    );
  }
}
