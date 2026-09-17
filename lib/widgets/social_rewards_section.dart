import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/social_rewards_controller.dart';
import '../styles.dart';
import 'pill_button.dart';
import 'spinning_coin.dart';

/// Social follow rewards live with the Home Today's coins surface. This is a
/// real Home child, rather than the retired standalone GetCoinsScreen, so the
/// offer remains reachable from the production navigation path.
class SocialRewardsSection extends StatefulWidget {
  const SocialRewardsSection({
    super.key,
    required this.auth,
    required this.api,
  });

  final AuthService auth;
  final BackendApiService api;

  @override
  State<SocialRewardsSection> createState() => _SocialRewardsSectionState();
}

class _SocialRewardsSectionState extends State<SocialRewardsSection> {
  late final SocialRewardsController _controller;

  @override
  void initState() {
    super.initState();
    _controller = SocialRewardsController(auth: widget.auth, api: widget.api)
      ..addListener(_changed);
    unawaited(_controller.refresh(impression: true));
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    _controller.removeListener(_changed);
    _controller.dispose();
    super.dispose();
  }

  Future<void> _open(SocialRewardItem reward) async {
    final opened = await showModalBottomSheet<bool>(
      context: context,
      backgroundColor: AppColors.of(context).parchment,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 20, 20, 16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'FOLLOW BARA ON ${reward.label.toUpperCase()}',
                style: PixelText.title(
                  size: 20,
                  color: AppColors.of(sheetContext).textDark,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                'Follow us on ${reward.label}, then come back to claim 200 coins.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(sheetContext).textMid,
                ),
              ),
              const SizedBox(height: 16),
              Row(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  const SpinningCoin(size: 20),
                  const SizedBox(width: 6),
                  Text(
                    '200 COINS',
                    style: PixelText.title(
                      size: 16,
                      color: AppColors.of(sheetContext).textDark,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              PillButton(
                label: 'OPEN ${reward.label.toUpperCase()}',
                variant: PillButtonVariant.primary,
                fullWidth: true,
                onPressed: _controller.busy.contains(reward.platform)
                    ? null
                    : () async {
                        final success = await _controller.launchAndOpen(reward);
                        if (sheetContext.mounted && success) {
                          Navigator.of(sheetContext).pop(true);
                        }
                      },
              ),
            ],
          ),
        ),
      ),
    );
    if (opened == true) await _controller.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final items = [
      'instagram',
      'tiktok',
      'x',
    ].map(_controller.item).whereType<SocialRewardItem>().toList();
    if (items.length != 3) return const SizedBox.shrink();
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
      child: Container(
        key: const Key('home-social-rewards'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.of(context).parchment,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: AppColors.of(context).roofDark.withValues(alpha: .55),
            width: 2,
          ),
          boxShadow: const [
            BoxShadow(color: Color(0x66000000), offset: Offset(0, 3)),
          ],
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'Follow Bara',
              style: PixelText.title(
                size: 16,
                color: AppColors.of(context).textDark,
              ),
            ),
            const SizedBox(height: 8),
            for (final reward in items) _card(reward),
          ],
        ),
      ),
    );
  }

  Widget _card(SocialRewardItem reward) {
    final claimed = reward.isClaimed;
    final opened = reward.isOpened;
    final busy = _controller.busy.contains(reward.platform);
    return Padding(
      padding: const EdgeInsets.only(bottom: 8),
      child: Container(
        key: Key('home-social-${reward.platform}'),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: AppColors.of(context).parchmentDark,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          children: [
            _platformLogo(reward.platform),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    reward.label,
                    style: PixelText.title(
                      size: 15,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                  Text(
                    reward.handle,
                    style: PixelText.body(
                      size: 12,
                      color: AppColors.of(context).textMid,
                    ),
                  ),
                  Text(
                    '+200 coins',
                    style: PixelText.body(
                      size: 12,
                      color: AppColors.of(context).textMid,
                    ),
                  ),
                ],
              ),
            ),
            PillButton(
              label: busy
                  ? 'LOADING...'
                  : claimed
                  ? 'CLAIMED'
                  : opened
                  ? 'CLAIM 200'
                  : 'FOLLOW',
              variant: PillButtonVariant.rewardedAd,
              onPressed: claimed || busy
                  ? null
                  : () async {
                      if (opened) {
                        await _controller.claim(reward);
                      } else {
                        await _open(reward);
                      }
                    },
            ),
          ],
        ),
      ),
    );
  }

  Widget _platformLogo(String platform) {
    final colors = AppColors.of(context);
    final (asset, icon, color) = switch (platform) {
      'instagram' => ('assets/images/social_instagram.png', null, colors.ink),
      'x' => ('assets/images/social_x.png', null, colors.ink),
      'tiktok' => (null, Icons.music_note_rounded, colors.ink),
      _ => (null, Icons.public_rounded, colors.textMid),
    };
    return Container(
      width: 38,
      height: 38,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: color.withValues(alpha: .13),
        shape: BoxShape.circle,
        border: Border.all(color: color.withValues(alpha: .45)),
      ),
      child: asset != null
          ? Image.asset(
              asset,
              width: 18,
              height: 18,
              color: color,
              filterQuality: FilterQuality.medium,
            )
          : Icon(icon, size: 20, color: color),
    );
  }
}
