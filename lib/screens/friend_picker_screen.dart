import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/at_name.dart';
import '../widgets/arcade_page.dart';
import '../widgets/retro_card.dart';

class FriendPickerScreen extends StatelessWidget {
  final List<Map<String, dynamic>> friends;

  const FriendPickerScreen({super.key, required this.friends});

  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  @override
  Widget build(BuildContext context) {
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
                      child: Container(
                        padding: const EdgeInsets.all(8),
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
                            'CHALLENGE A FRIEND',
                            style: PixelText.title(
                              size: 22,
                              color: AppColors.of(context).textLight,
                            ).copyWith(shadows: _textShadows),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'Pick someone to battle this week',
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
                child: ListView.builder(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                  itemCount: friends.length,
                  itemBuilder: (context, index) =>
                      _buildFriendCard(context, friends[index]),
                ),
              ),
            ),
          ],
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
                  atName(name),
                  style: PixelText.title(
                    size: 18,
                    color: AppColors.of(context).textDark,
                  ),
                ),
              ),
              Icon(
                Icons.chevron_right,
                color: AppColors.of(context).textMid,
                size: 24,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
