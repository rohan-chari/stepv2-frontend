import 'package:flutter/material.dart';

import '../styles.dart';
import '../widgets/retro_card.dart';

class FriendPickerScreen extends StatelessWidget {
  final List<Map<String, dynamic>> friends;

  const FriendPickerScreen({
    super.key,
    required this.friends,
  });

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Container(
        decoration: const BoxDecoration(
          gradient: LinearGradient(
            begin: Alignment.topCenter,
            end: Alignment.bottomCenter,
            colors: [
              Color(0xFF87CEEB),
              Color(0xFFB0E0F0),
              Color(0xFFD4F1F9),
            ],
          ),
        ),
        child: SafeArea(
          child: Column(
            children: [
              // Header
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                child: Row(
                  children: [
                    GestureDetector(
                      onTap: () => Navigator.of(context).pop(),
                      child: Container(
                        padding: const EdgeInsets.all(8),
                        child: Icon(
                          Icons.arrow_back,
                          color: AppColors.textDark,
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
                            'CHALLENGE A FRIEND',
                            style: PixelText.title(size: 22, color: AppColors.textDark)
                                .copyWith(shadows: _textShadows),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pick someone to battle this week',
                            style: PixelText.body(size: 13, color: AppColors.textMid)
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
                child: ListView.builder(
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  itemCount: friends.length,
                  itemBuilder: (context, index) =>
                      _buildFriendCard(context, friends[index]),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildFriendCard(BuildContext context, Map<String, dynamic> friend) {
    final id = friend['id'] as String? ?? '';
    final name = friend['displayName'] as String? ?? '???';

    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: GestureDetector(
        onTap: () => Navigator.of(context).pop((id, name)),
        child: RetroCard(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  name,
                  style: PixelText.title(size: 18, color: AppColors.textDark),
                ),
              ),
              const Icon(
                Icons.chevron_right,
                color: AppColors.textMid,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
