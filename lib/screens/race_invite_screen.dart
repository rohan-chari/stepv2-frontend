import 'package:flutter/material.dart';

import '../styles.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';

class RaceInviteScreen extends StatefulWidget {
  final List<Map<String, dynamic>> friends;
  final Set<String> existingParticipantIds;

  const RaceInviteScreen({
    super.key,
    required this.friends,
    this.existingParticipantIds = const {},
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
        .where((f) =>
            !widget.existingParticipantIds.contains(f['id'] as String? ?? ''))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final friends = _availableFriends;

    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [Color(0xFF87CEEB), Color(0xFFB0E0F0), Color(0xFFD4F1F9)],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding:
                    const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: const Padding(
                        padding: EdgeInsets.all(8),
                        child: Icon(Icons.arrow_back,
                            color: AppColors.textDark, size: 24),
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
                                    size: 22, color: AppColors.textDark)
                                .copyWith(shadows: _textShadows),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Select friends to race against',
                            style: PixelText.body(
                                    size: 13, color: AppColors.textMid)
                                .copyWith(shadows: _textShadows),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 8),

              // Friend list
              Expanded(
                child: friends.isEmpty
                    ? Center(
                        child: Text(
                          'No friends available to invite',
                          style: PixelText.body(
                              size: 14, color: AppColors.textMid),
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        itemCount: friends.length,
                        itemBuilder: (context, index) =>
                            _buildFriendCard(friends[index]),
                      ),
              ),

              // Invite button
              if (_selectedIds.isNotEmpty)
                Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  child: PillButton(
                    label:
                        'INVITE ${_selectedIds.length} FRIEND${_selectedIds.length == 1 ? '' : 'S'}',
                    variant: PillButtonVariant.primary,
                    fontSize: 14,
                    fullWidth: true,
                    padding: const EdgeInsets.symmetric(
                        horizontal: 24, vertical: 14),
                    onPressed: () =>
                        Navigator.of(context).pop(_selectedIds.toList()),
                  ),
                ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendCard(Map<String, dynamic> friend) {
    final id = friend['id'] as String? ?? '';
    final name = friend['displayName'] as String? ?? '???';
    final selected = _selectedIds.contains(id);

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () {
          setState(() {
            if (selected) {
              _selectedIds.remove(id);
            } else {
              _selectedIds.add(id);
            }
          });
        },
        child: RetroCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Container(
                width: 24,
                height: 24,
                decoration: BoxDecoration(
                  color:
                      selected ? AppColors.pillGreenDark : Colors.transparent,
                  border: Border.all(
                    color: selected
                        ? AppColors.pillGreenDark
                        : AppColors.textMid,
                    width: 2,
                  ),
                  borderRadius: BorderRadius.circular(6),
                ),
                child: selected
                    ? const Icon(Icons.check, size: 16, color: Colors.white)
                    : null,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(
                  name,
                  style: PixelText.title(size: 18, color: AppColors.textDark),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
