import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/case_opening_strip.dart';
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
  // Box mode (v2): claim fires when the reel screen opens; the reel waits for
  // the result before it can spin, and the reveal shows once the spin lands.
  bool _opening = false;
  Map<String, dynamic>? _boxResult;
  List<_DailyStripItem>? _stripItems;

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
      // Box mode goes straight to the reel — the claim fires immediately and
      // the reel waits for the swipe, same as opening a race mystery box.
      if (_box != null && res['claimedToday'] != true) {
        _openBox();
      }
    } catch (e) {
      if (!mounted) return;
      setState(() => _isLoading = false);
      showErrorToast(context, 'Failed to load daily reward.');
    }
  }

  /// Box mode is on only when the backend advertises it in the status
  /// response — older backends keep the legacy ladder flow.
  Map<String, dynamic>? get _box {
    final box = _status?['box'];
    return box is Map<String, dynamic> ? box : null;
  }

  // Legacy ladder claim (old backend without box support).
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

  // Box claim: switch to the reel screen immediately and roll in the
  // background — same flow as the race mystery box (CaseOpeningScreen).
  Future<void> _openBox() async {
    if (_isClaiming) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    setState(() {
      _isClaiming = true;
      _opening = true;
    });
    try {
      final res = await widget.backendApiService.claimDailyRewardBox(
        identityToken: token,
        localDate: _todayLocalDate(),
      );
      final coins = res['coins'];
      if (coins is num) {
        widget.authService.updateCoins(coins.toInt());
      }
      if (!mounted) return;
      setState(() {
        _boxResult = res;
        _stripItems = _generateStrip(res);
        _isClaiming = false;
      });
      widget.onClaimed?.call();
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isClaiming = false;
        _opening = false;
      });
      showErrorToast(context, 'Claim failed. Try again.');
    }
  }

  void _onStripComplete() {
    if (_claimedReward != null || _boxResult == null) return;
    setState(() => _claimedReward = _boxResult);
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
                      : _opening
                      ? _buildOpening()
                      : _box != null
                      ? _buildBox()
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

  // Daily reward v2: one mystery box per day; login streak drives the odds.
  Widget _buildBox() {
    final status = _status!;
    final box = _box!;
    final claimedToday = status['claimedToday'] == true;
    final streak = (box['streak'] as num?)?.toInt() ?? 1;

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
              _InfoButton(onTap: _showOddsInfo),
              const SizedBox(width: 8),
              _CloseButton(onTap: () => Navigator.of(context).pop(false)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            claimedToday
                ? 'You\'ve opened today\'s box. Come back tomorrow!'
                : 'Open today\'s mystery box to keep your streak going.',
            style: HomeText.body(
              size: 13,
              color: HomeColors.muted,
              weight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
              decoration: BoxDecoration(
                color: AppColors.coinLight.withValues(alpha: 0.35),
                border: Border.all(color: AppColors.coinDark, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    size: 20,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    streak == 1 ? 'DAY 1 STREAK' : '$streak-DAY STREAK',
                    style: PixelText.title(size: 14, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),
          Center(
            child: Container(
              width: 150,
              height: 150,
              decoration: BoxDecoration(
                color: AppColors.parchmentDark,
                border: Border.all(color: AppColors.coinDark, width: 3),
                borderRadius: BorderRadius.circular(14),
                boxShadow: [
                  BoxShadow(
                    color: AppColors.coinDark.withValues(alpha: 0.35),
                    blurRadius: 14,
                    spreadRadius: 1,
                  ),
                ],
              ),
              child: Center(
                child: Text(
                  '?',
                  style: HomeText.display(size: 72, color: AppColors.coinDark),
                ),
              ),
            ),
          ),
          const SizedBox(height: 10),
          Text(
            'Coins or a new accessory await...',
            textAlign: TextAlign.center,
            style: PixelText.body(size: 12, color: AppColors.textMid),
          ),
          const SizedBox(height: 18),
          PillButton(
            label: claimedToday
                ? 'COME BACK TOMORROW'
                : _isClaiming
                ? 'OPENING...'
                : 'OPEN BOX',
            variant: PillButtonVariant.primary,
            fullWidth: true,
            onPressed: (claimedToday || _isClaiming) ? null : _openBox,
          ),
        ],
      ),
    );
  }

  // Reel screen — same chrome as the race mystery box (CaseOpeningScreen):
  // "PREPARING..." until the claim lands, then swipe-to-spin reel.
  Widget _buildOpening() {
    final items = _stripItems;
    final streak = (_box?['streak'] as num?)?.toInt() ?? 1;
    return GameContainer(
      key: const ValueKey('opening'),
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 16),
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
                  style: HomeText.display(size: 28, color: HomeColors.ink),
                ),
              ),
              _InfoButton(onTap: _showOddsInfo),
              const SizedBox(width: 8),
              // Reward is already claimed once we're here; closing just skips
              // the animation, so refresh the caller (pop true).
              _CloseButton(onTap: () => Navigator.of(context).pop(true)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            'Swipe the reel to crack it open',
            style: HomeText.body(
              size: 14,
              color: HomeColors.muted,
              weight: FontWeight.w800,
            ),
          ),
          const SizedBox(height: 12),
          Center(
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 6),
              decoration: BoxDecoration(
                color: AppColors.coinLight.withValues(alpha: 0.35),
                border: Border.all(color: AppColors.coinDark, width: 2),
                borderRadius: BorderRadius.circular(20),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(
                    Icons.local_fire_department_rounded,
                    size: 18,
                    color: AppColors.error,
                  ),
                  const SizedBox(width: 6),
                  Text(
                    streak == 1 ? 'DAY 1 STREAK' : '$streak-DAY STREAK',
                    style: PixelText.title(size: 13, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 12),
          if (items != null)
            CaseOpeningReel(
              itemCount: items.length,
              resultIndex: _DailyStripItem.resultPosition,
              onComplete: _onStripComplete,
              itemBuilder: (context, index, isResult) =>
                  _DailyReelTile(item: items[index]),
            )
          else
            const SizedBox(
              height: 160,
              child: Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    CircularProgressIndicator(color: AppColors.accent),
                    SizedBox(height: 12),
                    Text(
                      'PREPARING...',
                      style: TextStyle(
                        color: AppColors.textMid,
                        fontWeight: FontWeight.w800,
                        letterSpacing: 1.5,
                      ),
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  // Decoy tiles show what the box can actually pay — coin stacks per tier and
  // the player's real unowned accessories — mixed at the live streak odds, so
  // a longer streak visibly fills the reel with rarer tiles.
  List<_DailyStripItem> _generateStrip(Map<String, dynamic> result) {
    final box = _box ?? const <String, dynamic>{};
    final odds = box['odds'] is Map<String, dynamic>
        ? box['odds'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final commonOdds = (odds['COMMON'] as num?)?.toDouble() ?? 0.50;
    final uncommonOdds = (odds['UNCOMMON'] as num?)?.toDouble() ?? 0.35;

    final ranges = box['coinRanges'] is Map<String, dynamic>
        ? box['coinRanges'] as Map<String, dynamic>
        : const <String, dynamic>{};
    (int, int) rangeFor(String tier, int defMin, int defMax) {
      final range = ranges[tier];
      if (range is List && range.length == 2) {
        final min = (range[0] as num?)?.toInt();
        final max = (range[1] as num?)?.toInt();
        if (min != null && max != null && max >= min) return (min, max);
      }
      return (defMin, defMax);
    }

    final (commonMin, commonMax) = rangeFor('COMMON', 10, 30);
    final (uncommonMin, uncommonMax) = rangeFor('UNCOMMON', 40, 80);
    final accessoryPool = (box['accessoryPool'] as List? ?? const [])
        .whereType<Map<String, dynamic>>()
        .toList();

    final rng = Random();
    // Coin payouts read better as round numbers, so pick a random multiple of
    // 5 within the tier's range instead of any integer (avoids 11, 17, …).
    int randomCoins(int min, int max) {
      final lo = (min + 4) ~/ 5; // smallest multiple of 5 >= min (divided by 5)
      final hi = max ~/ 5; // largest multiple of 5 <= max (divided by 5)
      if (hi < lo) return min + rng.nextInt(max - min + 1); // no multiple fits
      return (lo + rng.nextInt(hi - lo + 1)) * 5;
    }

    final items = <_DailyStripItem>[];
    for (int i = 0; i < _DailyStripItem.stripLength; i++) {
      if (i == _DailyStripItem.resultPosition) {
        items.add(_DailyStripItem.fromResult(result));
        continue;
      }
      final roll = rng.nextDouble();
      if (roll < commonOdds) {
        items.add(
          _DailyStripItem.coins(
            randomCoins(commonMin, commonMax),
            'COMMON',
          ),
        );
      } else if (roll < commonOdds + uncommonOdds) {
        items.add(
          _DailyStripItem.coins(
            randomCoins(uncommonMin, uncommonMax),
            'UNCOMMON',
          ),
        );
      } else if (accessoryPool.isNotEmpty) {
        items.add(
          _DailyStripItem.accessory(
            accessoryPool[rng.nextInt(accessoryPool.length)],
          ),
        );
      } else {
        items.add(const _DailyStripItem.mysteryAccessory());
      }
    }
    return items;
  }

  void _showOddsInfo() {
    final box = _box;
    final odds = box?['odds'] is Map<String, dynamic>
        ? box!['odds'] as Map<String, dynamic>
        : const <String, dynamic>{};
    String pct(String key) {
      final v = (odds[key] as num?)?.toDouble();
      if (v == null) return '—';
      return '${(v * 100).round()}%';
    }

    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        insetPadding: const EdgeInsets.symmetric(horizontal: 24),
        child: GameContainer(
          padding: const EdgeInsets.all(18),
          frameColor: AppColors.accent,
          surfaceColor: AppColors.parchmentLight,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'HOW IT WORKS',
                textAlign: TextAlign.center,
                style: HomeText.display(size: 22, color: HomeColors.ink),
              ),
              const SizedBox(height: 10),
              Text(
                'Open a mystery box every day to build your streak. '
                'The longer your streak, the better your odds of rare '
                'rewards — more coins and rarer accessories you don\'t '
                'own yet. Miss a day and your streak resets!',
                style: HomeText.body(
                  size: 13,
                  color: HomeColors.muted,
                  weight: FontWeight.w700,
                ),
              ),
              const SizedBox(height: 14),
              _OddsRow(
                label: 'COMMON',
                detail: 'a few coins',
                pct: pct('COMMON'),
                color: _rarityColor('COMMON'),
              ),
              const SizedBox(height: 6),
              _OddsRow(
                label: 'UNCOMMON',
                detail: 'more coins',
                pct: pct('UNCOMMON'),
                color: _rarityColor('UNCOMMON'),
              ),
              const SizedBox(height: 6),
              _OddsRow(
                label: 'RARE',
                detail: 'new accessory',
                pct: pct('RARE'),
                color: _rarityColor('RARE'),
              ),
              const SizedBox(height: 16),
              PillButton(
                label: 'GOT IT',
                fullWidth: true,
                onPressed: () => Navigator.of(dialogContext).pop(),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

Color _rarityColor(String rarity) => caseRarityColor(rarity);

/// One tile on the daily-box reel: a coin stack or an accessory.
class _DailyStripItem {
  static const stripLength = 45;
  // Same as the race reel: result near the end for a long scroll.
  static const resultPosition = 38;

  final String rarity;
  final int? coinAmount;
  final String? assetKey;
  final String? name;

  const _DailyStripItem._({
    required this.rarity,
    this.coinAmount,
    this.assetKey,
    this.name,
  });

  const _DailyStripItem.coins(int amount, String rarity)
    : this._(rarity: rarity, coinAmount: amount);

  const _DailyStripItem.mysteryAccessory()
    : this._(rarity: 'RARE', name: '???');

  factory _DailyStripItem.accessory(Map<String, dynamic> shopItem) {
    return _DailyStripItem._(
      rarity: 'RARE',
      assetKey: shopItem['assetKey'] as String?,
      name: shopItem['name'] as String? ?? 'Accessory',
    );
  }

  factory _DailyStripItem.fromResult(Map<String, dynamic> result) {
    final rarity = (result['rarity'] as String? ?? 'COMMON').toUpperCase();
    final shopItem = result['shopItem'] as Map<String, dynamic>?;
    if (shopItem != null) {
      return _DailyStripItem._(
        rarity: rarity,
        assetKey: shopItem['assetKey'] as String?,
        name: shopItem['name'] as String? ?? 'Accessory',
      );
    }
    return _DailyStripItem._(
      rarity: rarity,
      coinAmount: (result['coinAmount'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isAccessory => coinAmount == null;
}

class _DailyReelTile extends StatelessWidget {
  const _DailyReelTile({required this.item});
  final _DailyStripItem item;

  @override
  Widget build(BuildContext context) {
    return CaseReelTile(
      rarity: item.rarity,
      width: 86,
      height: 100,
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Expanded(child: Center(child: _buildFace())),
          const SizedBox(height: 3),
          Text(
            item.isAccessory ? (item.name ?? '???') : '+${item.coinAmount}',
            style: PixelText.body(size: 10, color: AppColors.textDark),
            textAlign: TextAlign.center,
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildFace() {
    if (!item.isAccessory) {
      // Static coin face — dozens of tiles scroll past, so no spin animation.
      return Image.asset(
        'assets/images/coin.png',
        width: 42,
        height: 42,
        fit: BoxFit.contain,
        errorBuilder: (_, _, _) =>
            const Icon(Icons.paid_rounded, size: 38, color: AppColors.coinDark),
      );
    }
    if (item.assetKey != null) {
      return Image.asset(
        'assets/images/accessories/${item.assetKey}.png',
        width: 46,
        height: 46,
        fit: BoxFit.contain,
        filterQuality: FilterQuality.none,
        errorBuilder: (_, _, _) => const Icon(
          Icons.checkroom_rounded,
          size: 38,
          color: AppColors.accent,
        ),
      );
    }
    return const Icon(
      Icons.checkroom_rounded,
      size: 38,
      color: AppColors.accent,
    );
  }
}

class _OddsRow extends StatelessWidget {
  const _OddsRow({
    required this.label,
    required this.detail,
    required this.pct,
    required this.color,
  });

  final String label;
  final String detail;
  final String pct;
  final Color color;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: AppColors.parchmentDark,
        border: Border.all(color: color, width: 2),
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        children: [
          Text(label, style: PixelText.title(size: 12, color: color)),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              detail,
              style: PixelText.body(size: 11, color: AppColors.textMid),
            ),
          ),
          Text(pct, style: PixelText.number(size: 13, color: color)),
        ],
      ),
    );
  }
}

class _InfoButton extends StatelessWidget {
  const _InfoButton({required this.onTap});
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
            color: AppColors.parchmentDark,
            borderRadius: BorderRadius.circular(8),
            border: Border.all(color: AppColors.coinDark, width: 2),
          ),
          child: Center(
            child: Text(
              '?',
              style: PixelText.title(size: 18, color: AppColors.coinDark),
            ),
          ),
        ),
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
    // Box claims (rarity present) already spun on the reel — go straight to
    // the reveal. The standalone accessory spinner is only for legacy day-6.
    if (type != 'ACCESSORY' || widget.reward['rarity'] != null) {
      _spinDone = true;
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.reward['rewardType'] as String? ?? 'COINS';
    final coinAmount = (widget.reward['coinAmount'] as num?)?.toInt() ?? 0;
    final shopItem = widget.reward['shopItem'] as Map<String, dynamic>?;
    // Present only on daily-box claims; legacy ladder claims have no rarity.
    final rarity = widget.reward['rarity'] as String?;
    final rarityColor = rarity != null ? _rarityColor(rarity) : null;

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
        frameColor: rarityColor ?? AppColors.coinDark,
        surfaceColor: AppColors.parchmentLight,
        glowColor: rarityColor ?? AppColors.coinMid,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              'CLAIMED!',
              textAlign: TextAlign.center,
              style: HomeText.display(size: 32, color: HomeColors.ink),
            ),
            if (rarity != null) ...[
              const SizedBox(height: 6),
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    border: Border.all(color: rarityColor!, width: 2),
                    borderRadius: BorderRadius.circular(14),
                  ),
                  child: Text(
                    rarity.toUpperCase(),
                    style: PixelText.title(size: 13, color: rarityColor),
                  ),
                ),
              ),
            ],
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
