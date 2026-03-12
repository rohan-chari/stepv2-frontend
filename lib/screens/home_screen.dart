import 'dart:io';

import 'package:flutter/material.dart';

import '../models/step_data.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/health_service.dart';
import '../styles.dart';
import '../widgets/game_background.dart';
import '../widgets/game_button.dart';
import '../widgets/step_count_card.dart';
import 'start_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> with WidgetsBindingObserver {
  final HealthService _healthService = HealthService();
  final BackendApiService _backendApiService = BackendApiService();

  bool _healthAuthorized = false;
  bool _isLoading = false;
  String? _error;
  StepData? _stepData;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _restoreAndFetch();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed && _healthAuthorized) {
      _fetchSteps();
    }
  }

  Future<void> _restoreAndFetch() async {
    final wasAuthorized = await _healthService.restoreHealthAuthState();
    if (!wasAuthorized || !mounted) return;

    setState(() => _healthAuthorized = true);
    await _fetchSteps();
  }

  Future<void> _enableHealthData() async {
    setState(() => _isLoading = true);

    try {
      final authorized = await _healthService.requestAuthorization();
      if (!authorized) {
        setState(() {
          _isLoading = false;
          _error = 'Health data access not granted.\nPlease allow access in Settings.';
        });
        return;
      }

      setState(() => _healthAuthorized = true);
      await _fetchSteps();
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to request health access:\n$e';
      });
    }
  }

  Future<void> _fetchSteps() async {
    setState(() {
      _isLoading = true;
      _error = null;
    });

    try {
      final stepData = await _healthService.getStepsToday();
      String? syncWarning;

      try {
        final identityToken = widget.authService.identityToken;

        if (identityToken == null || identityToken.isEmpty) {
          throw const HttpException('You are no longer signed in.');
        }

        await _backendApiService.recordSteps(
          identityToken: identityToken,
          stepData: stepData,
        );
      } catch (e) {
        syncWarning = 'Steps loaded, but backend sync failed. ${e.toString()}';
      }

      setState(() {
        _stepData = stepData;
        _isLoading = false;
        _error = null;
      });

      if (syncWarning != null && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(syncWarning)));
      }
    } catch (e) {
      setState(() {
        _isLoading = false;
        _error = 'Failed to fetch steps:\n$e';
      });
    }
  }

  Widget _buildPermissionView() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.directions_walk,
              size: 72,
              color: AppColors.accent,
              shadows: [
                Shadow(
                  color: Colors.black.withValues(alpha: 0.3),
                  offset: const Offset(0, 3),
                  blurRadius: 8,
                ),
              ],
            ),
            const SizedBox(height: 24),
            Text(
              'Health Data Access',
              style: TextStyle(
                fontSize: 28,
                fontWeight: FontWeight.w900,
                color: Colors.white,
                letterSpacing: 1.5,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.3),
                    offset: const Offset(0, 3),
                    blurRadius: 10,
                  ),
                  Shadow(
                    color: AppColors.titleShadow.withValues(alpha: 0.4),
                    offset: const Offset(0, 2),
                    blurRadius: 16,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 20),
            Text(
              'Step Tracker needs access to your health data to count your daily steps. '
              'That\'s all we use — just your step count. No other health data is accessed or stored.',
              style: TextStyle(
                fontSize: 16,
                fontWeight: FontWeight.w500,
                color: Colors.white.withValues(alpha: 0.9),
                height: 1.5,
                shadows: [
                  Shadow(
                    color: Colors.black.withValues(alpha: 0.25),
                    offset: const Offset(0, 2),
                    blurRadius: 8,
                  ),
                ],
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 36),
            if (_error != null) ...[
              Text(
                _error!,
                style: TextStyle(
                  color: AppColors.error,
                  fontWeight: FontWeight.w600,
                  shadows: [
                    Shadow(
                      color: Colors.black.withValues(alpha: 0.3),
                      offset: const Offset(0, 1),
                      blurRadius: 4,
                    ),
                  ],
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 16),
            ],
            if (_isLoading)
              const CircularProgressIndicator(color: AppColors.accent)
            else
              GameButton(
                label: 'ENABLE',
                onPressed: _enableHealthData,
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsView() {
    final zeroHint = _stepData != null && _stepData!.steps == 0 && !_isLoading
        ? 'Showing 0 steps? Make sure Step Tracker has access in Settings > Health > Data Access.'
        : null;

    return Center(
      child: Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            StepCountCard(
              stepData: _stepData,
              isLoading: _isLoading,
              error: _error,
              hint: zeroHint,
            ),
            const SizedBox(height: 24),
            if (_isLoading)
              const CircularProgressIndicator(color: AppColors.accent)
            else
              GameButton(
                label: 'REFRESH',
                fontSize: 22,
                padding: const EdgeInsets.symmetric(horizontal: 32, vertical: 14),
                onPressed: _fetchSteps,
              ),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back),
          onPressed: () {
            Navigator.of(context).pushReplacement(
              PageRouteBuilder(
                pageBuilder: (context, animation, secondaryAnimation) =>
                    const StartScreen(),
                transitionsBuilder:
                    (context, animation, secondaryAnimation, child) {
                      return FadeTransition(opacity: animation, child: child);
                    },
                transitionDuration: const Duration(milliseconds: 600),
              ),
            );
          },
        ),
        title: const Text('Step Tracker'),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GameBackground(
        child: _healthAuthorized ? _buildStepsView() : _buildPermissionView(),
      ),
    );
  }
}
