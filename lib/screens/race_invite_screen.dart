import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/at_name.dart';
import '../widgets/app_avatar.dart';
import '../widgets/arcade_page.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';

class RaceInviteScreen extends StatefulWidget {
  final List<Map<String, dynamic>> friends;
  final Set<String> existingParticipantIds;

  /// TR-708: when inviting to a TEAM race, friends whose last-seen client
  /// lacks the team_races capability (`teamRaceEligible: false`) are grayed
  /// out with a "needs app update" badge instead of failing after selection.
  /// A missing flag (older backend) stays selectable — the server still
  /// hard-blocks at invite time (TR-707).
  final bool teamRaceMode;

  const RaceInviteScreen({
    super.key,
    required this.friends,
    this.existingParticipantIds = const {},
    this.teamRaceMode = false,
  });

  @override
  State<RaceInviteScreen> createState() => _RaceInviteScreenState();
}

class _RaceInviteScreenState extends State<RaceInviteScreen> {
  final Set<String> _selectedIds = {};

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  List<Map<String, dynamic>> get _availableFriends {
    return widget.friends
        .where(
          (f) =>
              !widget.existingParticipantIds.contains(f['id'] as String? ?? ''),
        )
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final friends = _availableFriends;
    final topInset = MediaQuery.of(context).padding.top;
    final headerBottom = topInset + const ArcadePageBackground().headerHeight;

    return Scaffold(
      body: ArcadePageBackground(
        child: Stack(
          children: [
            Positioned(
              top: topInset,
              left: 0,
              right: 0,
              child: Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 8,
                ),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          color: AppColors.of(context).textLight,
                          size: 24,
                        ),
                      ),
                    ),
                    const SizedBox(width: 8),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'INVITE FRIENDS',
                            style: PixelText.title(
                              size: 22,
                              color: AppColors.of(context).textLight,
                            ).copyWith(shadows: _textShadows),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Select friends to race against',
                            style: PixelText.body(
                              size: 13,
                              color: AppColors.of(context).textLight,
                            ).copyWith(shadows: _textShadows),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Positioned.fill(
              top: headerBottom,
              child: SafeArea(
                top: false,
                child: Column(
                  children: [
                    Expanded(
                      child: friends.isEmpty
                          ? Center(
                              child: Text(
                                'No friends available to invite',
                                style: PixelText.body(
                                  size: 14,
                                  color: AppColors.of(context).textMid,
                                ),
                              ),
                            )
                          : ListView.builder(
                              padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                              itemCount: friends.length,
                              itemBuilder: (context, index) =>
                                  _buildFriendCard(friends[index]),
                            ),
                    ),
                    if (_selectedIds.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        child: PillButton(
                          label:
                              'INVITE ${_selectedIds.length} FRIEND${_selectedIds.length == 1 ? '' : 'S'}',
                          variant: PillButtonVariant.primary,
                          fontSize: 14,
                          fullWidth: true,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 24,
                            vertical: 14,
                          ),
                          onPressed: () =>
                              Navigator.of(context).pop(_selectedIds.toList()),
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> friend) {
    final id = friend['id'] as String? ?? '';
    final name = friend['displayName'] as String? ?? '???';
    final profilePhotoUrl = friend['profilePhotoUrl'] as String?;
    final selected = _selectedIds.contains(id);
    // Only an explicit false blocks (defensive: older backends omit the flag).
    final ineligible =
        widget.teamRaceMode && friend['teamRaceEligible'] == false;

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: ineligible
            ? null
            : () {
                setState(() {
                  if (selected) {
                    _selectedIds.remove(id);
                  } else {
                    _selectedIds.add(id);
                  }
                });
              },
        child: Opacity(
          opacity: ineligible ? 0.55 : 1,
          child: RetroCard(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
            child: Row(
              children: [
                Container(
                  width: 24,
                  height: 24,
                  decoration: BoxDecoration(
                    color: selected
                        ? AppColors.of(context).pillGreenDark
                        : Colors.transparent,
                    border: Border.all(
                      color: selected
                          ? AppColors.of(context).pillGreenDark
                          : AppColors.of(context).textMid,
                      width: 2,
                    ),
                    borderRadius: BorderRadius.circular(6),
                  ),
                  child: selected
                      ? const Icon(Icons.check, size: 16, color: Colors.white)
                      : null,
                ),
                const SizedBox(width: 12),
                AppAvatar(name: name, imageUrl: profilePhotoUrl, size: 34),
                const SizedBox(width: 12),
                Expanded(
                  child: Text(
                    atName(name),
                    style: PixelText.title(
                      size: 18,
                      color: ineligible
                          ? AppColors.of(context).textMid
                          : AppColors.of(context).textDark,
                    ),
                  ),
                ),
                if (ineligible)
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 7,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: AppColors.of(context).parchmentDark,
                      borderRadius: BorderRadius.circular(6),
                      border: Border.all(
                        color: AppColors.of(context).parchmentBorder,
                        width: 1.5,
                      ),
                    ),
                    child: Text(
                      'NEEDS APP UPDATE',
                      style: PixelText.title(
                        size: 8.5,
                        color: AppColors.of(context).textMid,
                      ),
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
