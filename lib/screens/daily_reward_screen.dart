import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_container.dart';
import '../widgets/home_chrome.dart';
import '../widgets/pill_button.dart';
import '../widgets/spinning_coin.dart';

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

class DailyRewardScreen extends StatefulWidget {
  final AuthService authService;
  final BackendApiService backendApiService;
  final VoidCallback? onClaimed;

  const DailyRewardScreen({
    super.key,
    required this.authService,
    required this.backendApiService,
    this.onClaimed,
  });

  @override
  State<DailyRewardScreen> createState() => _DailyRewardScreenState();
}

class _DailyRewardScreenState extends State<DailyRewardScreen> {
  Map<String, dynamic>? _status;
  bool _isLoading = true;
  bool _isClaiming = false;
  Map<String, dynamic>? _claimedReward;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      setState(() => _isLoading = false);
      return;
    }
    try {
      final res = await widget.backendApiService.fetchDailyRewardStatus(
        identityToken: token,
        localDate: _todayLocalDate(),
      );
      if (!mounted) return;
      setState(() {
        _status = res;
        _isLoading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorToast(context, 'Failed to load daily reward.');
    }
  }

  Future<void> _claim() async {
    if (_isClaiming) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    setState(() => _isClaiming = true);
    try {
      final res = await widget.backendApiService.claimDailyReward(
        identityToken: token,
        localDate: _todayLocalDate(),
      );
      final coins = res['coins'];
      if (coins is num) {
        widget.authService.updateCoins(coins.toInt());
      }
      if (!mounted) return;
      setState(() {
        _claimedReward = res;
        _isClaiming = false;
      });
      widget.onClaimed?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClaiming = false);
      showErrorToast(context, 'Claim failed. Try again.');
    }
  }

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: Stack(
        children: [
          Positioned.fill(
            child: BackdropFilter(
              filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
              child: ColoredBox(
                color: AppColors.roofDark.withValues(alpha: 0.54),
              ),
            ),
          ),
          SafeArea(
            child: Center(
              child: SingleChildScrollView(
                padding: const EdgeInsets.fromLTRB(14, 18, 14, 24),
                child: ConstrainedBox(
                  constraints: const BoxConstraints(maxWidth: 460),
                  child: _isLoading
                      ? _buildLoading()
                      : _claimedReward != null
                      ? _RewardReveal(
                          reward: _claimedReward!,
                          onClose: () => Navigator.of(context).pop(true),
                        )
                      : _buildLadder(),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.all(48),
      child: Center(
        child: CircularProgressIndicator(color: AppColors.accent),
      ),
    );
  }

  Widget _buildLadder() {
    final status = _status;
    if (status == null) {
      return GameContainer(
        padding: const EdgeInsets.all(20),
        frameColor: AppColors.accent,
        surfaceColor: AppColors.parchmentLight,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              'Daily reward unavailable.',
              style: PixelText.body(size: 14, color: AppColors.textMid),
            ),
            const SizedBox(height: 12),
            PillButton(
              label: 'CLOSE',
              fullWidth: true,
              onPressed: () => Navigator.of(context).pop(false),
            ),
          ],
        ),
      );
    }

    final ladder = (status['ladder'] as List? ?? [])
        .cast<Map<String, dynamic>>();
    final claimedToday = status['claimedToday'] == true;
    final currentDay = (status['currentDay'] as num?)?.toInt() ?? 1;

    return GameContainer(
      padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
      frameColor: AppColors.accent,
      surfaceColor: AppColors.parchmentLight,
      glowColor: AppColors.coinMid,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  'DAILY REWARD',
                  style: HomeText.display(size: 26, color: HomeColors.ink),
                ),
              ),
              _CloseButton(onTap: () => Navigator.of(context).pop(false)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            claimedToday
                ? 'You\'ve claimed today. Come back tomorrow!'
                : 'Day $currentDay of 6 — claim to keep your streak.',
            style: HomeText.body(
              size: 13,
              color: HomeColors.muted,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          GridView.count(
            crossAxisCount: 3,
            shrinkWrap: true,
            physics: const NeverScrollableScrollPhysics(),
            childAspectRatio: 0.82,
            mainAxisSpacing: 10,
            crossAxisSpacing: 10,
            children: [
              for (final tile in ladder) _LadderTile(tile: tile),
            ],
          ),
          const SizedBox(height: 18),
          PillButton(
            label: claimedToday
                ? 'COME BACK TOMORROW'
                : _isClaiming
                ? 'CLAIMING...'
                : currentDay == 6
                ? 'SPIN FOR ACCESSORY'
                : 'CLAIM TODAY',
            variant: PillButtonVariant.primary,
            fullWidth: true,
            onPressed: (claimedToday || _isClaiming) ? null : _claim,
          ),
        ],
      ),
    );
  }
}

class _LadderTile extends StatelessWidget {
  const _LadderTile({required this.tile});
  final Map<String, dynamic> tile;

  @override
  Widget build(BuildContext context) {
    final day = (tile['day'] as num?)?.toInt() ?? 0;
    final reward = tile['reward'] as Map<String, dynamic>? ?? const {};
    final claimed = tile['claimed'] == true;
    final isToday = tile['isToday'] == true;
    final rewardType = reward['type'] as String? ?? 'COINS';
    final coinAmount = (reward['coinAmount'] as num?)?.toInt() ?? 0;

    final borderColor = claimed
        ? AppColors.parchmentBorder
        : isToday
        ? AppColors.coinDark
        : AppColors.parchmentBorder;
    final bgColor = isToday
        ? AppColors.coinLight.withValues(alpha: 0.35)
        : AppColors.parchmentDark;

    return Container(
      decoration: BoxDecoration(
        color: bgColor,
        border: Border.all(color: borderColor, width: isToday ? 3 : 2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: isToday
            ? [
                BoxShadow(
                  color: AppColors.coinDark.withValues(alpha: 0.4),
                  blurRadius: 12,
                  spreadRadius: 1,
                ),
              ]
            : null,
      ),
      padding: const EdgeInsets.all(6),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Text(
            'DAY $day',
            style: PixelText.title(
              size: 11,
              color: isToday ? AppColors.textDark : AppColors.textMid,
            ),
          ),
          if (rewardType == 'ACCESSORY')
            const Icon(
              Icons.checkroom_rounded,
              size: 36,
              color: AppColors.accent,
            )
          else
            const SpinningCoin(size: 32),
          Text(
            rewardType == 'ACCESSORY' ? 'ITEM' : '+$coinAmount',
            style: PixelText.number(size: 14, color: AppColors.coinDark),
          ),
          if (claimed)
            const Icon(Icons.check_circle, size: 16, color: AppColors.accent)
          else
            const SizedBox(height: 16),
        ],
      ),
    );
  }
}

class _RewardReveal extends StatefulWidget {
  const _RewardReveal({required this.reward, required this.onClose});
  final Map<String, dynamic> reward;
  final VoidCallback onClose;

  @override
  State<_RewardReveal> createState() => _RewardRevealState();
}

class _RewardRevealState extends State<_RewardReveal> {
  bool _spinDone = false;

  @override
  void initState() {
    super.initState();
    final type = widget.reward['rewardType'] as String? ?? 'COINS';
    if (type != 'ACCESSORY') {
      _spinDone = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.reward['rewardType'] as String? ?? 'COINS';
    final coinAmount = (widget.reward['coinAmount'] as num?)?.toInt() ?? 0;
    final shopItem = widget.reward['shopItem'] as Map<String, dynamic>?;

    if (type == 'ACCESSORY' && shopItem != null && !_spinDone) {
      return _AccessorySpinner(
        targetItem: shopItem,
        onComplete: () => setState(() => _spinDone = true),
      );
    }

    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0.0, end: 1.0),
      duration: const Duration(milliseconds: 500),
      curve: Curves.easeOutBack,
      builder: (context, value, child) {
        return Transform.scale(
          scale: value,
          child: Opacity(opacity: value.clamp(0.0, 1.0), child: child),
        );
      },
      child: GameContainer(
        padding: const EdgeInsets.all(20),
        frameColor: AppColors.coinDark,
        surfaceColor: AppColors.parchmentLight,
        glowColor: AppColors.coinMid,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'CLAIMED!',
              textAlign: TextAlign.center,
              style: HomeText.display(size: 32, color: HomeColors.ink),
            ),
            const SizedBox(height: 16),
            if (type == 'ACCESSORY' && shopItem != null) ...[
              Center(
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: AppColors.parchmentDark,
                    border: Border.all(color: AppColors.coinDark, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(10),
                  child: Image.asset(
                    'assets/images/accessories/${shopItem['assetKey']}.png',
                    fit: BoxFit.contain,
                    filterQuality: FilterQuality.none,
                    errorBuilder: (_, _, _) => const Icon(
                      Icons.checkroom_rounded,
                      size: 80,
                      color: AppColors.accent,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                shopItem['name'] as String? ?? 'Accessory',
                textAlign: TextAlign.center,
                style: PixelText.title(size: 22, color: AppColors.textDark),
              ),
            ] else ...[
              const Center(child: SpinningCoin(size: 96)),
              const SizedBox(height: 12),
              Text(
                '+$coinAmount COINS',
                textAlign: TextAlign.center,
                style: PixelText.title(size: 26, color: AppColors.coinDark),
              ),
              if (type == 'COINS_FALLBACK') ...[
                const SizedBox(height: 6),
                Text(
                  'You own every accessory! Bonus coins instead.',
                  textAlign: TextAlign.center,
                  style: PixelText.body(size: 12, color: AppColors.textMid),
                ),
              ],
            ],
            const SizedBox(height: 22),
            PillButton(
              label: 'CONTINUE',
              fullWidth: true,
              onPressed: widget.onClose,
            ),
          ],
        ),
      ),
    );
  }
}

// CSGO-style accessory strip — variant of CaseOpeningStrip but renders
// accessory PNGs from assetKey instead of powerup icons.
class _AccessorySpinner extends StatefulWidget {
  const _AccessorySpinner({required this.targetItem, required this.onComplete});
  final Map<String, dynamic> targetItem;
  final VoidCallback onComplete;

  @override
  State<_AccessorySpinner> createState() => _AccessorySpinnerState();
}

class _AccessorySpinnerState extends State<_AccessorySpinner>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _animation;
  late final List<Map<String, dynamic>> _strip;
  bool _waiting = true;

  static const double _itemWidth = 96.0;
  static const double _itemSpacing = 8.0;
  static const double _totalItemWidth = _itemWidth + _itemSpacing;
  static const int _itemCount = 45;
  static const int _resultPosition = 38;

  // Fallback decoys when we don't have many accessories yet.
  static const _fallbackKeys = ['cowboy_hat', 'baseball_cap'];

  @override
  void initState() {
    super.initState();
    _strip = _generateStrip();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 4000),
    );
    _animation = CurvedAnimation(parent: _controller, curve: Curves.easeOutQuart);
    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        Future.delayed(const Duration(milliseconds: 600), widget.onComplete);
      }
    });
  }

  List<Map<String, dynamic>> _generateStrip() {
    final rng = Random();
    return [
      for (int i = 0; i < _itemCount; i++)
        if (i == _resultPosition)
          widget.targetItem
        else
          {
            'assetKey': _fallbackKeys[rng.nextInt(_fallbackKeys.length)],
            'name': '???',
          },
    ];
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _start() {
    if (!_waiting) return;
    setState(() => _waiting = false);
    _controller.forward();
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onTap: _waiting ? _start : null,
      onHorizontalDragEnd: _waiting ? (_) => _start() : null,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final viewportWidth = constraints.maxWidth;
          final centerX = viewportWidth / 2;
          final resultCenter = _resultPosition * _totalItemWidth + _itemWidth / 2;
          final totalScroll = resultCenter - centerX;

          return GameContainer(
            padding: const EdgeInsets.fromLTRB(10, 14, 10, 16),
            frameColor: AppColors.coinDark,
            surfaceColor: AppColors.parchmentLight,
            glowColor: AppColors.coinMid,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  _waiting ? 'TAP OR SWIPE TO SPIN' : 'SPINNING...',
                  style: PixelText.title(size: 14, color: AppColors.textMid),
                ),
                const SizedBox(height: 12),
                SizedBox(
                  height: 130,
                  width: viewportWidth,
                  child: Stack(
                    alignment: Alignment.center,
                    children: [
                      ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: ColoredBox(
                          color: AppColors.parchmentDark,
                          child: ClipRect(
                            child: OverflowBox(
                              maxWidth: double.infinity,
                              alignment: Alignment.centerLeft,
                              child: AnimatedBuilder(
                                animation: _animation,
                                builder: (context, child) {
                                  return Transform.translate(
                                    offset: Offset(
                                      -_animation.value * totalScroll,
                                      0,
                                    ),
                                    child: child,
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.symmetric(
                                    vertical: 8,
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      for (int i = 0; i < _strip.length; i++) ...[
                                        if (i > 0)
                                          const SizedBox(width: _itemSpacing),
                                        _SpinTile(item: _strip[i]),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),
                      ),
                      IgnorePointer(
                        child: Container(
                          width: 3,
                          height: 130,
                          color: AppColors.coinDark.withValues(alpha: 0.75),
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          );
        },
      ),
    );
  }
}

class _SpinTile extends StatelessWidget {
  const _SpinTile({required this.item});
  final Map<String, dynamic> item;

  @override
  Widget build(BuildContext context) {
    final assetKey = item['assetKey'] as String? ?? '';
    return Container(
      width: _AccessorySpinnerState._itemWidth,
      height: 110,
      decoration: BoxDecoration(
        color: AppColors.parchment,
        border: Border.all(color: AppColors.coinDark, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      padding: const EdgeInsets.all(6),
      child: Image.asset(
        'assets/images/accessories/$assetKey.png',
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.checkroom_rounded, color: AppColors.accent),
      ),
    );
  }
}

class _CloseButton extends StatelessWidget {
  const _CloseButton({required this.onTap});
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(8),
        child: Ink(
          width: 36,
          height: 36,
          decoration: BoxDecoration(
            color: AppColors.errorLight,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.error, width: 2),
          ),
          child: const Center(
            child: Icon(Icons.close_rounded, size: 18, color: AppColors.textDark),
          ),
        ),
      ),
    );
  }
}
