import 'package:flutter/material.dart';

import '../models/step_data.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import 'tabs/leaderboard_tab.dart';

/// Pushed host for the real leaderboard. The shell stays mounted behind this
/// route, so returning preserves Home's PageStorage scroll offset and no bottom
/// navigation item falsely appears selected for the board.
class StandaloneLeaderboardScreen extends StatelessWidget {
  const StandaloneLeaderboardScreen({
    super.key,
    required this.authService,
    this.backendApiService,
    this.stepData,
    this.displayName,
  });

  final AuthService authService;
  final BackendApiService? backendApiService;
  final StepData? stepData;
  final String? displayName;

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).roofLight,
    appBar: AppBar(
      backgroundColor: AppColors.of(context).roofDark,
      foregroundColor: AppColors.of(context).textLight,
      leading: IconButton(
        key: const Key('standalone-leaderboard-back'),
        tooltip: 'Back',
        onPressed: () => Navigator.of(context).pop(),
        icon: const Icon(Icons.arrow_back_rounded),
      ),
      title: Text(
        'LEADERBOARDS',
        style: PixelText.title(
          size: 18,
          color: AppColors.of(context).textLight,
        ),
      ),
    ),
    body: LeaderboardTab(
      authService: authService,
      backendApiService: backendApiService,
      stepData: stepData,
      displayName: displayName,
      reserveShellFooter: false,
    ),
  );
}
