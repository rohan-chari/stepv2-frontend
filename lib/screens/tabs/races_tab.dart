import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../styles.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/game_container.dart';
import '../../widgets/pill_button.dart';
import '../../widgets/pill_icon_button.dart';
import '../create_race_screen.dart';
import '../race_detail_screen.dart';

class RacesTab extends StatefulWidget {
  final AuthService authService;
  final Map<String, dynamic>? racesData;
  final List<Map<String, dynamic>> friendsSteps;
  final VoidCallback onRacesChanged;
  final Future<void> Function()? onRefresh;
  final String? displayName;
  final VoidCallback? onOpenProfile;

  const RacesTab({
    super.key,
    required this.authService,
    required this.racesData,
    required this.friendsSteps,
    required this.onRacesChanged,
    this.onRefresh,
    this.displayName,
    this.onOpenProfile,
  });

  @override
  State<RacesTab> createState() => _RacesTabState();
}

class _RacesTabState extends State<RacesTab> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  List<Map<String, dynamic>> get _active =>
      (widget.racesData?['active'] as List?)?.cast<Map<String, dynamic>>() ??
      [];

  List<Map<String, dynamic>> get _invites =>
      (widget.racesData?['pending'] as List?)
          ?.cast<Map<String, dynamic>>()
          .where((r) => r['myStatus'] == 'INVITED')
          .toList() ??
      [];

  List<Map<String, dynamic>> get _waiting =>
      (widget.racesData?['pending'] as List?)
          ?.cast<Map<String, dynamic>>()
          .where((r) => r['myStatus'] != 'INVITED')
          .toList() ??
      [];

  List<Map<String, dynamic>> get _completed =>
      (widget.racesData?['completed'] as List?)?.cast<Map<String, dynamic>>() ??
      [];

  String get _myUserId => widget.authService.userId ?? '';

  void _navigateToCreateRace() {
    Navigator.of(context)
        .push<Map<String, dynamic>>(
          MaterialPageRoute(
            builder: (context) =>
                CreateRaceScreen(authService: widget.authService),
          ),
        )
        .then((race) {
          if (race != null && mounted) {
            widget.onRacesChanged();
            _navigateToRaceDetail(race['id'] as String);
          }
        });
  }

  void _navigateToRaceDetail(String raceId) {
    Navigator.of(context)
        .push<bool>(
          MaterialPageRoute(
            builder: (context) => RaceDetailScreen(
              authService: widget.authService,
              raceId: raceId,
              friends: widget.friendsSteps,
            ),
          ),
        )
        .then((_) {
          if (mounted) widget.onRacesChanged();
        });
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;
    final bottomInset = MediaQuery.of(context).padding.bottom;
    final tabBarHeight = 77.5 + bottomInset;

    return Padding(
      padding: EdgeInsets.only(top: topInset + 12, bottom: tabBarHeight),
      child: RefreshIndicator(
        onRefresh: widget.onRefresh ?? () async {},
        color: AppColors.accent,
        backgroundColor: AppColors.parchment,
        child: CustomScrollView(
          physics: const AlwaysScrollableScrollPhysics(),
          slivers: [
            SliverPadding(
              padding: const EdgeInsets.symmetric(horizontal: 16),
              sliver: SliverToBoxAdapter(child: _buildContent()),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildContent() {
    final active = _active;
    final invites = _invites;
    final waiting = _waiting;
    final completed = _completed;
    final hasRaces =
        active.isNotEmpty ||
        invites.isNotEmpty ||
        waiting.isNotEmpty ||
        completed.isNotEmpty;

    return Column(
      children: [
        _buildTopBar(),
        const SizedBox(height: 16),

        // New Race button
        if (widget.displayName != null) ...[
          PillButton(
            label: 'NEW RACE',
            variant: PillButtonVariant.primary,
            fontSize: 14,
            fullWidth: true,
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 14),
            onPressed: _navigateToCreateRace,
          ),
          const SizedBox(height: 16),
        ],

        if (!hasRaces)
          _buildEmptyState()
        else ...[
          // Pending invites
          if (invites.isNotEmpty) ...[
            _buildSectionHeader('INVITES', invites.length),
            const SizedBox(height: 8),
            for (final race in invites) ...[
              _buildRaceCard(race, isInvite: true),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
          ],

          // Waiting to start
          if (waiting.isNotEmpty) ...[
            _buildSectionHeader('WAITING TO START', waiting.length),
            const SizedBox(height: 8),
            for (final race in waiting) ...[
              _buildRaceCard(race),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
          ],

          // Active races
          if (active.isNotEmpty) ...[
            _buildSectionHeader('ACTIVE RACES', active.length),
            const SizedBox(height: 8),
            for (final race in active) ...[
              _buildRaceCard(race),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 8),
          ],

          // Completed races
          if (completed.isNotEmpty) ...[
            _buildSectionHeader('COMPLETED', completed.length),
            const SizedBox(height: 8),
            for (final race in completed) ...[
              _buildRaceCard(race),
              const SizedBox(height: 10),
            ],
          ],
        ],
      ],
    );
  }

  Widget _buildTopBar() {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.center,
      children: [
        Expanded(
          child: Row(
            children: [
              if (widget.displayName != null)
                Flexible(
                  child: Text(
                    widget.displayName!,
                    style: PixelText.title(
                      size: 26,
                      color: AppColors.textDark,
                    ).copyWith(shadows: _textShadows),
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              const SizedBox(width: 8),
              CoinBalanceBadge(
                coins: widget.authService.coins,
                heldCoins: widget.authService.heldCoins,
              ),
            ],
          ),
        ),
        PillIconButton(
          icon: Icons.person_rounded,
          size: 36,
          variant: PillButtonVariant.secondary,
          onPressed: widget.onOpenProfile,
        ),
      ],
    );
  }

  Widget _buildEmptyState() {
    return Column(
      children: [
        const SizedBox(height: 32),
        Icon(
          Icons.directions_run,
          size: 48,
          color: AppColors.textMid.withValues(alpha: 0.6),
        ),
        const SizedBox(height: 12),
        Text(
          'No races yet',
          style: PixelText.title(
            size: 18,
            color: AppColors.textMid,
          ).copyWith(shadows: _textShadows),
          textAlign: TextAlign.center,
        ),
        const SizedBox(height: 6),
        Text(
          'Create a race and invite friends!',
          style: PixelText.body(
            size: 14,
            color: AppColors.textMid,
          ).copyWith(shadows: _textShadows),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }

  Widget _buildSectionHeader(String title, int count) {
    return Row(
      children: [
        Text(
          title,
          style: PixelText.title(
            size: 18,
            color: AppColors.textMid,
          ).copyWith(shadows: _textShadows),
        ),
        const SizedBox(width: 6),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
          decoration: BoxDecoration(
            color: AppColors.textMid.withValues(alpha: 0.2),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Text(
            '$count',
            style: PixelText.title(size: 12, color: AppColors.textMid),
          ),
        ),
      ],
    );
  }

  Widget _buildRaceCard(Map<String, dynamic> race, {bool isInvite = false}) {
    final raceId = race['id'] as String? ?? '';
    final name = race['name'] as String? ?? 'Race';
    final targetSteps = race['targetSteps'] as int? ?? 0;
    final participantCount = race['participantCount'] as int? ?? 0;
    final status = race['status'] as String? ?? '';
    final creator = race['creator'] as Map<String, dynamic>?;
    final creatorName = creator?['displayName'] as String? ?? '';
    final winner = race['winner'] as Map<String, dynamic>?;
    final isCreator = race['isCreator'] as bool? ?? false;

    String statusLabel;
    Color badgeColor;
    if (isInvite && !isCreator) {
      statusLabel = 'INVITE';
      badgeColor = AppColors.pillGoldDark;
    } else if (status == 'ACTIVE') {
      statusLabel = 'ACTIVE';
      badgeColor = AppColors.pillGreenDark;
    } else if (status == 'COMPLETED') {
      if (winner != null && winner['id'] == _myUserId) {
        statusLabel = 'WON';
        badgeColor = AppColors.pillGreenDark;
      } else {
        statusLabel = 'DONE';
        badgeColor = AppColors.textMid;
      }
    } else if (status == 'PENDING' && isCreator) {
      statusLabel = 'SETUP';
      badgeColor = AppColors.pillGoldDark;
    } else {
      statusLabel = status;
      badgeColor = AppColors.textMid;
    }

    final stepsLabel = targetSteps >= 1000
        ? '${(targetSteps / 1000).toStringAsFixed(targetSteps % 1000 == 0 ? 0 : 0)}k steps'
        : '$targetSteps steps';

    return GestureDetector(
      onTap: () => _navigateToRaceDetail(raceId),
      child: GameContainer(
        padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
        child: Row(
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    name,
                    style: PixelText.title(size: 18, color: AppColors.textDark),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                  const SizedBox(height: 3),
                  Text(
                    '$stepsLabel \u2022 $participantCount runner${participantCount == 1 ? '' : 's'}${isInvite && creatorName.isNotEmpty ? ' \u2022 by $creatorName' : ''}',
                    style: PixelText.body(size: 14, color: AppColors.textMid),
                    overflow: TextOverflow.ellipsis,
                    maxLines: 1,
                  ),
                ],
              ),
            ),
            const SizedBox(width: 10),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
              decoration: BoxDecoration(
                color: badgeColor,
                borderRadius: BorderRadius.circular(6),
              ),
              child: Text(
                statusLabel,
                style: PixelText.title(size: 13, color: Colors.white),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
