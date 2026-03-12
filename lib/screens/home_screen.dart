import 'dart:io';

import 'package:flutter/material.dart';

import '../models/step_data.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/health_service.dart';
import '../widgets/game_background.dart';
import '../widgets/step_count_card.dart';
import 'start_screen.dart';

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key, required this.authService});

  final AuthService authService;

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  final HealthService _healthService = HealthService();
  final BackendApiService _backendApiService = BackendApiService();

  bool _healthAuthorized = false;
  bool _isLoading = false;
  String? _error;
  StepData? _stepData;

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

  bool _enablePressed = false;

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
              color: const Color(0xFFF5C842),
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
                    color: const Color(0xFF1565C0).withValues(alpha: 0.4),
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
                  color: const Color(0xFFFF8A80),
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
              const CircularProgressIndicator(color: Color(0xFFF5C842))
            else
              GestureDetector(
                onTapDown: (_) => setState(() => _enablePressed = true),
                onTapUp: (_) {
                  setState(() => _enablePressed = false);
                  _enableHealthData();
                },
                onTapCancel: () => setState(() => _enablePressed = false),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 60),
                  transform: Matrix4.translationValues(
                    0,
                    _enablePressed ? 6 : 0,
                    0,
                  ),
                  decoration: BoxDecoration(
                    borderRadius: BorderRadius.circular(12),
                    color: const Color(0xFFB8860B),
                    boxShadow: _enablePressed
                        ? []
                        : [
                            const BoxShadow(
                              color: Color(0xFF8B6508),
                              offset: Offset(0, 6),
                              blurRadius: 0,
                            ),
                          ],
                  ),
                  child: Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 40,
                      vertical: 16,
                    ),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(12),
                      gradient: const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Color(0xFFF5C842),
                          Color(0xFFEBB030),
                          Color(0xFFD4991E),
                        ],
                      ),
                      border: Border.all(
                        color: const Color(0xFFB8860B),
                        width: 2.5,
                      ),
                    ),
                    child: Text(
                      'ENABLE',
                      style: TextStyle(
                        fontSize: 26,
                        fontWeight: FontWeight.w900,
                        color: const Color(0xFF7A5A00),
                        letterSpacing: 4,
                        shadows: [
                          Shadow(
                            color: const Color(0xFFFFE082).withValues(alpha: 0.6),
                            offset: const Offset(0, 1),
                            blurRadius: 0,
                          ),
                        ],
                      ),
                    ),
                  ),
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildStepsView() {
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
            ),
            const SizedBox(height: 24),
            FilledButton.icon(
              onPressed: _isLoading ? null : _fetchSteps,
              icon: const Icon(Icons.refresh),
              label: const Text('Refresh'),
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
