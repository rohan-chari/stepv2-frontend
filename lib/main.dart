import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/display_name_screen.dart';
import 'screens/main_shell.dart';
import 'screens/start_screen.dart';
import 'services/auth_service.dart';
import 'services/background_sync_service.dart';
import 'services/notification_service.dart';
import 'styles.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);

  final notificationService = NotificationService();
  await notificationService.initialize();

  runApp(StepTrackerApp(notificationService: notificationService));
}

class StepTrackerApp extends StatelessWidget {
  const StepTrackerApp({super.key, required this.notificationService});

  final NotificationService notificationService;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Step Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent),
        useMaterial3: true,
      ),
      home: _SessionGate(notificationService: notificationService),
    );
  }
}

class _SessionGate extends StatefulWidget {
  const _SessionGate({required this.notificationService});

  final NotificationService notificationService;

  @override
  State<_SessionGate> createState() => _SessionGateState();
}

class _SessionGateState extends State<_SessionGate> {
  final AuthService _authService = AuthService();
  bool _loading = true;
  bool _hasSession = false;

  @override
  void initState() {
    super.initState();
    _checkSession();
  }

  Future<void> _checkSession() async {
    final restored = await _authService.restoreSession();
    setState(() {
      _hasSession = restored;
      _loading = false;
    });
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    if (_hasSession && _authService.displayName != null) {
      return MainShell(
        authService: _authService,
        notificationService: widget.notificationService,
      );
    }

    if (_hasSession) {
      return DisplayNameScreen(
        authService: _authService,
        notificationService: widget.notificationService,
      );
    }

    return StartScreen(notificationService: widget.notificationService);
  }
}
