import 'package:flutter/material.dart';
import 'package:workmanager/workmanager.dart';
import 'screens/display_name_screen.dart';
import 'screens/home_screen.dart';
import 'screens/start_screen.dart';
import 'services/auth_service.dart';
import 'services/background_sync_service.dart';
import 'styles.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Workmanager().initialize(callbackDispatcher, isInDebugMode: false);
  runApp(const StepTrackerApp());
}

class StepTrackerApp extends StatelessWidget {
  const StepTrackerApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Step Tracker',
      debugShowCheckedModeBanner: false,
      theme: ThemeData(
        colorScheme: ColorScheme.fromSeed(seedColor: AppColors.accent),
        useMaterial3: true,
      ),
      home: const _SessionGate(),
    );
  }
}

class _SessionGate extends StatefulWidget {
  const _SessionGate();

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
      return HomeScreen(authService: _authService);
    }

    if (_hasSession) {
      return DisplayNameScreen(authService: _authService);
    }

    return const StartScreen();
  }
}
