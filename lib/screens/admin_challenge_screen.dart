import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/content_board.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_background.dart';
import '../widgets/pill_button.dart';
import '../widgets/powerup_icon.dart';
import '../widgets/spinning_crate.dart';
import '../widgets/trail_sign.dart';

const _powerupEntries = [
  (
    type: 'LEG_CRAMP',
    name: 'Leg Cramp',
    description: 'Freeze a rival\'s steps for 2 hours',
  ),
  (
    type: 'RED_CARD',
    name: 'Red Card',
    description: 'Remove 10% of the leader\'s steps',
  ),
  (
    type: 'SHORTCUT',
    name: 'Shortcut',
    description: 'Steal 1,000 steps from a rival',
  ),
  (
    type: 'COMPRESSION_SOCKS',
    name: 'Compression Socks',
    description: 'Shield against the next attack',
  ),
  (
    type: 'PROTEIN_SHAKE',
    name: 'Protein Shake',
    description: '+1,500 bonus steps instantly',
  ),
  (
    type: 'RUNNERS_HIGH',
    name: "Runner's High",
    description: '2x steps for 3 hours',
  ),
  (
    type: 'SECOND_WIND',
    name: 'Second Wind',
    description: 'Bonus steps based on how far behind',
  ),
  (
    type: 'STEALTH_MODE',
    name: 'Stealth Mode',
    description: 'Hide your progress for 4 hours',
  ),
  (
    type: 'WRONG_TURN',
    name: 'Wrong Turn',
    description: 'Reverse a rival\'s steps for 1 hour',
  ),
  (
    type: 'FANNY_PACK',
    name: 'Fanny Pack',
    description: 'Unlock an extra powerup slot',
  ),
  (
    type: 'TRAIL_MIX',
    name: 'Trail Mix',
    description: '+500 steps per unique powerup type used',
  ),
  (
    type: 'DETOUR_SIGN',
    name: 'Detour Sign',
    description: 'Hide the entire leaderboard from a rival for 3 hours',
  ),
];

class AdminChallengeScreen extends StatefulWidget {
  const AdminChallengeScreen({
    super.key,
    required this.authService,
    this.backendApiService,
    this.showToast,
  });

  final AuthService authService;
  final BackendApiService? backendApiService;
  final void Function(BuildContext context, String message)? showToast;

  @override
  State<AdminChallengeScreen> createState() => _AdminChallengeScreenState();
}

class _AdminChallengeScreenState extends State<AdminChallengeScreen> {
  late final BackendApiService _backendApiService;
  late final void Function(BuildContext context, String message) _showToast;

  bool _isLoading = true;
  bool _isRunningAction = false;
  Map<String, dynamic>? _state;

  @override
  void initState() {
    super.initState();
    _backendApiService = widget.backendApiService ?? BackendApiService();
    _showToast = widget.showToast ?? showErrorToast;
    _loadState();
  }

  Future<void> _loadState() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    setState(() => _isLoading = true);

    try {
      final data = await _backendApiService.fetchAdminWeeklyChallenge(
        identityToken: token,
      );

      if (!mounted) return;
      setState(() {
        _state = data;
        _isLoading = false;
      });
    } catch (error) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      _showToast(context, error.toString());
    }
  }

  Future<void> _runAction(
    Future<Map<String, dynamic>> Function(String token) action, {
    required String successMessage,
  }) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;

    setState(() => _isRunningAction = true);

    try {
      await action(token);
      if (!mounted) return;
      _showToast(context, successMessage);
      await _loadState();
    } catch (error) {
      if (!mounted) return;
      _showToast(context, error.toString());
    } finally {
      if (mounted) {
        setState(() => _isRunningAction = false);
      }
    }
  }

  String _stringOrDash(Object? value) {
    final string = value?.toString();
    return string == null || string.isEmpty ? '-' : string;
  }

  Widget _buildRow(String label, String value) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            flex: 3,
            child: Text(
              label,
              style: PixelText.body(size: 13, color: AppColors.textMid),
            ),
          ),
          const SizedBox(width: 8),
          Expanded(
            flex: 4,
            child: Text(
              value,
              style: PixelText.body(size: 13, color: AppColors.textDark),
              textAlign: TextAlign.right,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildInstances(List<Map<String, dynamic>> instances) {
    if (instances.isEmpty) {
      return Text(
        'No challenge instances for this week yet.',
        style: PixelText.body(size: 13, color: AppColors.textMid),
        textAlign: TextAlign.center,
      );
    }

    return Column(
      children: instances.map((instance) {
        final userA =
            instance['userA'] as Map<String, dynamic>? ??
            const <String, dynamic>{};
        final userB =
            instance['userB'] as Map<String, dynamic>? ??
            const <String, dynamic>{};

        return Padding(
          padding: const EdgeInsets.only(bottom: 10),
          child: Container(
            width: double.infinity,
            padding: const EdgeInsets.all(12),
            decoration: BoxDecoration(
              color: AppColors.parchmentLight.withValues(alpha: 0.6),
              border: Border.all(color: AppColors.parchmentBorder, width: 2),
              borderRadius: BorderRadius.circular(8),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '${_stringOrDash(userA['displayName'])} vs ${_stringOrDash(userB['displayName'])}',
                  style: PixelText.title(size: 12, color: AppColors.textDark),
                ),
                const SizedBox(height: 6),
                Text(
                  'Status: ${_stringOrDash(instance['status'])}',
                  style: PixelText.body(size: 12, color: AppColors.textMid),
                ),
                Text(
                  'Stake: ${_stringOrDash(instance['stakeStatus'])}',
                  style: PixelText.body(size: 12, color: AppColors.textMid),
                ),
              ],
            ),
          ),
        );
      }).toList(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final boardWidth = MediaQuery.of(context).size.width - 48;
    final weeklyChallenge =
        _state?['weeklyChallenge'] as Map<String, dynamic>? ?? const {};
    final challenge =
        weeklyChallenge['challenge'] as Map<String, dynamic>? ?? const {};
    final instanceCounts =
        _state?['instanceCounts'] as Map<String, dynamic>? ?? const {};
    final rawInstances = _state?['instances'] as List? ?? const [];
    final instances = rawInstances.cast<Map<String, dynamic>>();

    return Scaffold(
      extendBodyBehindAppBar: true,
      appBar: AppBar(
        leading: IconButton(
          icon: const Icon(Icons.arrow_back, color: AppColors.textDark),
          onPressed: () => Navigator.of(context).pop(),
        ),
        backgroundColor: Colors.transparent,
        elevation: 0,
      ),
      body: GameBackground(
        child: SafeArea(
          child: SingleChildScrollView(
            padding: const EdgeInsets.fromLTRB(24, 60, 24, 32),
            child: Column(
              children: [
                TrailSign(
                  width: boardWidth,
                  child: Text(
                    'ADMIN CHALLENGE TOOLS',
                    style: PixelText.title(size: 22, color: AppColors.textDark),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: _isLoading
                      ? const Padding(
                          padding: EdgeInsets.symmetric(vertical: 24),
                          child: Center(
                            child: CircularProgressIndicator(
                              color: AppColors.accent,
                            ),
                          ),
                        )
                      : Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              challenge.isEmpty
                                  ? 'NO WEEKLY CHALLENGE'
                                  : (challenge['title'] as String? ??
                                        'CURRENT WEEKLY CHALLENGE'),
                              style: PixelText.title(
                                size: 16,
                                color: AppColors.textDark,
                              ),
                              textAlign: TextAlign.center,
                            ),
                            const SizedBox(height: 12),
                            _buildRow(
                              'Week Of',
                              _stringOrDash(weeklyChallenge['weekOf']),
                            ),
                            _buildRow(
                              'Dropped At',
                              _stringOrDash(weeklyChallenge['droppedAt']),
                            ),
                            _buildRow(
                              'Resolved At',
                              _stringOrDash(weeklyChallenge['resolvedAt']),
                            ),
                            _buildRow(
                              'Next Drop',
                              _stringOrDash(_state?['nextDropAt']),
                            ),
                            const SizedBox(height: 12),
                            _buildRow(
                              'Total Instances',
                              _stringOrDash(instanceCounts['total']),
                            ),
                            _buildRow(
                              'Pending Stake',
                              _stringOrDash(instanceCounts['pendingStake']),
                            ),
                            _buildRow(
                              'Active',
                              _stringOrDash(instanceCounts['active']),
                            ),
                            _buildRow(
                              'Completed',
                              _stringOrDash(instanceCounts['completed']),
                            ),
                            const SizedBox(height: 18),
                            PillButton(
                              label: _isRunningAction
                                  ? 'WORKING...'
                                  : 'ENSURE CURRENT WEEK',
                              variant: PillButtonVariant.primary,
                              fontSize: 13,
                              fullWidth: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              onPressed: _isRunningAction
                                  ? null
                                  : () => _runAction(
                                      (token) => _backendApiService
                                          .ensureAdminWeeklyChallenge(
                                            identityToken: token,
                                          ),
                                      successMessage:
                                          'Current weekly challenge ensured.',
                                    ),
                            ),
                            const SizedBox(height: 10),
                            PillButton(
                              label: _isRunningAction
                                  ? 'WORKING...'
                                  : 'RESOLVE CURRENT WEEK',
                              variant: PillButtonVariant.secondary,
                              fontSize: 13,
                              fullWidth: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              onPressed: _isRunningAction
                                  ? null
                                  : () => _runAction(
                                      (token) => _backendApiService
                                          .resolveAdminWeeklyChallenge(
                                            identityToken: token,
                                          ),
                                      successMessage:
                                          'Current weekly challenge resolved.',
                                    ),
                            ),
                            const SizedBox(height: 10),
                            PillButton(
                              label: _isRunningAction
                                  ? 'WORKING...'
                                  : 'RESET CURRENT WEEK',
                              variant: PillButtonVariant.accent,
                              fontSize: 13,
                              fullWidth: true,
                              padding: const EdgeInsets.symmetric(
                                horizontal: 24,
                                vertical: 12,
                              ),
                              onPressed: _isRunningAction
                                  ? null
                                  : () => _runAction(
                                      (token) => _backendApiService
                                          .resetAdminWeeklyChallenge(
                                            identityToken: token,
                                          ),
                                      successMessage:
                                          'Current week reset for testing.',
                                    ),
                            ),
                            const SizedBox(height: 20),
                            Text(
                              'INSTANCES',
                              style: PixelText.title(
                                size: 14,
                                color: AppColors.textDark,
                              ),
                            ),
                            const SizedBox(height: 12),
                            _buildInstances(instances),
                          ],
                        ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'POWERUP ICONS',
                        style: PixelText.title(
                          size: 16,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 12),
                      for (final entry in _powerupEntries)
                        Padding(
                          padding: const EdgeInsets.only(bottom: 10),
                          child: Row(
                            children: [
                              SizedBox(
                                width: 36,
                                height: 36,
                                child: PowerupIcon(
                                  type: entry.type,
                                  size: 28,
                                  spinning: true,
                                  spinDuration: const Duration(
                                    milliseconds: 2800,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      entry.name,
                                      style: PixelText.title(
                                        size: 13,
                                        color: AppColors.textDark,
                                      ),
                                    ),
                                    Text(
                                      entry.description,
                                      style: PixelText.body(
                                        size: 11,
                                        color: AppColors.textMid,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        ),
                    ],
                  ),
                ),
                const SizedBox(height: 24),
                ContentBoard(
                  width: boardWidth,
                  child: Column(
                    children: [
                      Text(
                        'POWERUP CRATE',
                        style: PixelText.title(
                          size: 16,
                          color: AppColors.textDark,
                        ),
                      ),
                      const SizedBox(height: 16),
                      const SpinningCrate(size: 100),
                      const SizedBox(height: 8),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
