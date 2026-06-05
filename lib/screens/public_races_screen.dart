import 'package:flutter/material.dart';

import '../models/loadable.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import '../widgets/arcade_page.dart';
import '../widgets/error_toast.dart';
import '../widgets/loading_skeleton.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';
import 'create_race_screen.dart';

class PublicRacesScreen extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;

  PublicRacesScreen({
    super.key,
    required this.authService,
    BackendApiService? backendApiService,
  }) : backendApiService = backendApiService ?? BackendApiService();

  @override
  State<PublicRacesScreen> createState() => _PublicRacesScreenState();
}

class _PublicRacesScreenState extends State<PublicRacesScreen> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  bool _loading = true;
  String? _joiningRaceId;
  List<Map<String, dynamic>> _races = const [];
  Loadable<List<Map<String, dynamic>>> _racesState = const Loadable.initial();

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _racesState = const Loadable.error('Not signed in.');
      });
      return;
    }
    setState(() {
      _loading = true;
      _racesState = _races.isEmpty
          ? const Loadable.loading()
          : Loadable.refreshing(_races);
    });
    try {
      final races = await widget.backendApiService.fetchPublicRaces(
        identityToken: token,
      );
      if (!mounted) return;
      setState(() {
        _races = races;
        _loading = false;
        _racesState = Loadable.success(races);
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _loading = false;
        _racesState = Loadable.error(
          e.toString(),
          data: _races.isEmpty ? null : _races,
        );
      });
      showErrorToast(context, e.toString());
    }
  }

  void _navigateToCreateRace() {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (context) => CreateRaceScreen(authService: widget.authService),
      ),
    );
  }

  Future<void> _join(Map<String, dynamic> race) async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final raceId = race['id'] as String;
    final buyIn = (race['buyInAmount'] as int?) ?? 0;
    if (buyIn > 0 && buyIn > widget.authService.coins) {
      showErrorToast(context, 'Not enough gold for this buy-in');
      return;
    }
    setState(() => _joiningRaceId = raceId);
    try {
      await widget.backendApiService.joinPublicRace(
        identityToken: token,
        raceId: raceId,
      );
      try {
        final user = await widget.backendApiService.fetchMe(
          identityToken: token,
        );
        await widget.authService.updateCoins(
          user['coins'] as int? ?? widget.authService.coins,
        );
        await widget.authService.updateHeldCoins(
          user['heldCoins'] as int? ?? widget.authService.heldCoins,
        );
      } catch (_) {}
      if (!mounted) return;
      Navigator.of(context).pop(true);
    } catch (e) {
      if (!mounted) return;
      setState(() => _joiningRaceId = null);
      showErrorToast(context, e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: ArcadePageBackground(
        headerHeight: 56,
        headerColor: AppColors.roofLight,
        child: SafeArea(
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          color: AppColors.parchmentLight,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'PUBLIC RACES',
                      style: PixelText.title(
                        size: 22,
                        color: AppColors.parchmentLight,
                      ).copyWith(shadows: _textShadows),
                    ),
                  ],
                ),
              ),
              Expanded(
                child: RefreshIndicator(
                  onRefresh: _load,
                  color: AppColors.accent,
                  backgroundColor: AppColors.parchment,
                  child: _buildBody(),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBody() {
    final state = _racesState;
    final races = state.data ?? _races;

    if (state.shouldShowInitialLoading || _loading && races.isEmpty) {
      return const Padding(
        padding: EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        child: ListSkeleton(itemCount: 4),
      );
    }

    if (state.isError && !state.hasData) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 48,
                  ),
                  child: LoadErrorPanel(
                    title: 'Couldn’t load public races',
                    message: 'Check your connection and try again.',
                    onRetry: _load,
                  ),
                ),
              ),
            ),
          );
        },
      );
    }

    if (races.isEmpty) {
      return LayoutBuilder(
        builder: (context, constraints) {
          return SingleChildScrollView(
            physics: const AlwaysScrollableScrollPhysics(),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: constraints.maxHeight),
              child: Center(
                child: Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 32,
                    vertical: 48,
                  ),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.flag_outlined,
                        size: 48,
                        color: AppColors.textMid.withValues(alpha: 0.6),
                      ),
                      const SizedBox(height: 12),
                      Text(
                        'NO PUBLIC RACES',
                        textAlign: TextAlign.center,
                        style: PixelText.title(
                          size: 18,
                          color: AppColors.textMid,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Text(
                        'Check back later or start your own.',
                        textAlign: TextAlign.center,
                        style: PixelText.body(
                          size: 14,
                          color: AppColors.textMid,
                        ),
                      ),
                      const SizedBox(height: 24),
                      PillButton(
                        label: 'CREATE A RACE',
                        variant: PillButtonVariant.primary,
                        fontSize: 13,
                        onPressed: _navigateToCreateRace,
                      ),
                    ],
                  ),
                ),
              ),
            ),
          );
        },
      );
    }
    return ListView.builder(
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      itemCount: races.length,
      itemBuilder: (context, i) => _buildRaceCard(races[i]),
    );
  }

  Widget _buildRaceCard(Map<String, dynamic> race) {
    final raceId = race['id'] as String;
    final name = race['name'] as String? ?? 'Race';
    final endsAt = DateTime.tryParse(race['endsAt'] as String? ?? '');
    final maxDurationDays = race['maxDurationDays'] as int? ?? 7;
    final participantCount = race['participantCount'] as int? ?? 0;
    final maxParticipants = race['maxParticipants'] as int? ?? 10;
    final buyIn = race['buyInAmount'] as int? ?? 0;
    final creator = race['creator'] as Map<String, dynamic>?;
    final creatorName = creator?['displayName'] as String? ?? 'Someone';
    final powerupsEnabled = race['powerupsEnabled'] as bool? ?? false;
    final finishReward = race['finishReward'] as Map<String, dynamic>?;
    final finishRewardPool = (finishReward?['pool'] as num?)?.toInt() ?? 0;
    final isJoining = _joiningRaceId == raceId;

    // Races are time-based: show time remaining, not a step target.
    String timeLeftLabel;
    if (endsAt != null) {
      final remaining = endsAt.difference(DateTime.now());
      if (remaining.isNegative) {
        timeLeftLabel = 'soon';
      } else if (remaining.inDays > 0) {
        timeLeftLabel =
            '${remaining.inDays}d ${remaining.inHours.remainder(24)}h';
      } else if (remaining.inHours > 0) {
        timeLeftLabel =
            '${remaining.inHours}h ${remaining.inMinutes.remainder(60)}m';
      } else {
        timeLeftLabel = '${remaining.inMinutes}m';
      }
    } else {
      timeLeftLabel = '${maxDurationDays}d';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: RetroCard(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              name.toUpperCase(),
              style: PixelText.title(size: 16, color: AppColors.textDark),
            ),
            const SizedBox(height: 4),
            Text(
              'BY ${atName(creatorName)}'.toUpperCase(),
              style: PixelText.body(size: 11, color: AppColors.textMid),
            ),
            const SizedBox(height: 12),
            Row(
              children: [
                _buildStat('ENDS IN', timeLeftLabel),
                const SizedBox(width: 16),
                _buildStat('RUNNERS', '$participantCount/$maxParticipants'),
                if (buyIn > 0) ...[
                  const SizedBox(width: 16),
                  _buildStat('BUY-IN', '$buyIn'),
                ],
                if (finishRewardPool > 0) ...[
                  const SizedBox(width: 16),
                  _buildStat('TOP 50%', '$finishRewardPool'),
                ],
                if (powerupsEnabled) ...[
                  const SizedBox(width: 16),
                  _buildStat('POWERUPS', 'ON'),
                ],
              ],
            ),
            const SizedBox(height: 14),
            PillButton(
              label: isJoining ? 'JOINING...' : 'JOIN',
              variant: PillButtonVariant.primary,
              fontSize: 13,
              fullWidth: true,
              padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 12),
              onPressed: isJoining ? null : () => _join(race),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStat(String label, String value) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(label, style: PixelText.body(size: 10, color: AppColors.textMid)),
        const SizedBox(height: 2),
        Text(
          value,
          style: PixelText.title(size: 14, color: AppColors.textDark),
        ),
      ],
    );
  }
}
