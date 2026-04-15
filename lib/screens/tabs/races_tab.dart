import 'package:flutter/material.dart';

import '../../services/auth_service.dart';
import '../../styles.dart';
import '../../utils/race_participant_display.dart';
import '../../widgets/app_avatar.dart';
import '../../widgets/coin_balance_badge.dart';
import '../../widgets/game_container.dart';
import '../../widgets/info_board_card.dart';
import '../../widgets/pill_button.dart';
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

  final Set<String> _collapsedSections = {};

  void _toggleSection(String sectionKey) {
    setState(() {
      if (_collapsedSections.contains(sectionKey)) {
        _collapsedSections.remove(sectionKey);
      } else {
        _collapsedSections.add(sectionKey);
      }
    });
  }

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

        // Races explainer + CTA
        InfoBoardCard(
          badgeLabel: 'RACES',
          title: 'First to the finish line wins.',
          subtitle:
              'Set a step target, invite friends, and race. The first runner to hit the target takes the pot.',
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 16),
          children: [
            if (widget.displayName != null) ...[
              const SizedBox(height: 14),
              PillButton(
                label: 'NEW RACE',
                variant: PillButtonVariant.secondary,
                fontSize: 14,
                fullWidth: true,
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 12,
                ),
                onPressed: _navigateToCreateRace,
              ),
            ],
          ],
        ),
        const SizedBox(height: 16),

        if (!hasRaces)
          _buildEmptyState()
        else ...[
          if (invites.isNotEmpty)
            _buildRaceSection(
              title: 'INVITES',
              sectionKey: 'invites',
              races: invites,
              isInvite: true,
            ),
          if (waiting.isNotEmpty)
            _buildRaceSection(
              title: 'WAITING TO START',
              sectionKey: 'waiting',
              races: waiting,
            ),
          if (active.isNotEmpty)
            _buildRaceSection(
              title: 'ACTIVE RACES',
              sectionKey: 'active',
              races: active,
            ),
          if (completed.isNotEmpty)
            _buildRaceSection(
              title: 'COMPLETED',
              sectionKey: 'completed',
              races: completed,
            ),
        ],
      ],
    );
  }

  Widget _buildRaceSection({
    required String title,
    required String sectionKey,
    required List<Map<String, dynamic>> races,
    bool isInvite = false,
  }) {
    final collapsed = _collapsedSections.contains(sectionKey);
    return Padding(
      padding: const EdgeInsets.only(bottom: 16),
      child: Column(
        children: [
          _buildSectionHeader(title, races.length, sectionKey, collapsed),
          if (!collapsed) ...[
            const SizedBox(height: 8),
            _buildRaceList(races, isInvite: isInvite),
          ],
        ],
      ),
    );
  }

  Widget _buildRaceList(
    List<Map<String, dynamic>> races, {
    bool isInvite = false,
  }) {
    return GameContainer(
      padding: const EdgeInsets.symmetric(vertical: 6, horizontal: 0),
      child: Column(
        children: [
          for (int i = 0; i < races.length; i++) ...[
            if (i > 0)
              Container(
                height: 1,
                margin: const EdgeInsets.symmetric(horizontal: 14),
                color: AppColors.parchmentBorder.withValues(alpha: 0.45),
              ),
            _buildRaceRow(races[i], i, isInvite: isInvite),
          ],
        ],
      ),
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
        ProfileAvatarButton(
          name: widget.displayName ?? 'You',
          imageUrl: widget.authService.profilePhotoUrl,
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

  Widget _buildSectionHeader(
    String title,
    int count,
    String sectionKey,
    bool collapsed,
  ) {
    return GestureDetector(
      onTap: () => _toggleSection(sectionKey),
      behavior: HitTestBehavior.opaque,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: 4),
        child: Row(
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
            const Spacer(),
            _SectionToggleButton(
              key: Key('race-section-toggle-$sectionKey'),
              collapsed: collapsed,
              onTap: () => _toggleSection(sectionKey),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRaceRow(
    Map<String, dynamic> race,
    int index, {
    bool isInvite = false,
  }) {
    final raceId = race['id'] as String? ?? '';
    final name = race['name'] as String? ?? 'Race';
    final targetSteps = race['targetSteps'] as int? ?? 0;
    final participantCount = race['participantCount'] as int? ?? 0;
    final status = race['status'] as String? ?? '';
    final creator = race['creator'] as Map<String, dynamic>?;
    final creatorName = creator?['displayName'] as String? ?? '';
    final winner = race['winner'] as Map<String, dynamic>?;
    final isCreator = race['isCreator'] as bool? ?? false;
    final myPlacement = race['myPlacement'] as int?;
    final queuedBoxCount = race['queuedBoxCount'] as int? ?? 0;

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

    return Material(
      color: index.isOdd
          ? AppColors.parchmentDark.withValues(alpha: 0.25)
          : Colors.transparent,
      child: InkWell(
        onTap: () => _navigateToRaceDetail(raceId),
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 14),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    key: Key('race-card-header-$raceId'),
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      Expanded(
                        child: Text(
                          name,
                          style: PixelText.title(
                            size: 18,
                            color: AppColors.textDark,
                          ),
                          overflow: TextOverflow.ellipsis,
                          maxLines: 1,
                        ),
                      ),
                      if (myPlacement != null || queuedBoxCount > 0) ...[
                        const SizedBox(width: 8),
                        if (myPlacement != null)
                          _buildMetaChip(
                            '${formatOrdinal(myPlacement)} PLACE',
                            backgroundColor: AppColors.pillGreenDark.withValues(
                              alpha: 0.16,
                            ),
                            textColor: AppColors.pillGreenDark,
                          ),
                        if (queuedBoxCount > 0) ...[
                          if (myPlacement != null) const SizedBox(width: 6),
                          _buildMetaChip(
                            '$queuedBoxCount QUEUED',
                            backgroundColor: AppColors.coinLight.withValues(
                              alpha: 0.18,
                            ),
                            textColor: AppColors.coinDark,
                          ),
                        ],
                      ],
                    ],
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
      ),
    );
  }

  Widget _buildMetaChip(
    String label, {
    required Color backgroundColor,
    required Color textColor,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      decoration: BoxDecoration(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(999),
      ),
      child: Text(label, style: PixelText.title(size: 11, color: textColor)),
    );
  }
}

class _SectionToggleButton extends StatelessWidget {
  const _SectionToggleButton({
    super.key,
    required this.collapsed,
    required this.onTap,
  });

  final bool collapsed;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: onTap,
      behavior: HitTestBehavior.opaque,
      child: Container(
        width: 26,
        height: 26,
        decoration: BoxDecoration(
          color: AppColors.parchmentLight,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: AppColors.parchmentBorder,
            width: 1.2,
          ),
        ),
        alignment: Alignment.center,
        child: Icon(
          collapsed ? Icons.add_rounded : Icons.remove_rounded,
          size: 18,
          color: AppColors.textMid,
        ),
      ),
    );
  }
}
