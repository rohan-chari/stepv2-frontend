import 'dart:math';
import 'dart:ui';

import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/accessory_thumbnail.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/case_opening_strip.dart';
import '../widgets/error_toast.dart';
import '../widgets/game_container.dart';
import '../widgets/home_chrome.dart';
import '../widgets/odds_sheet.dart';
import '../widgets/pill_button.dart';
import '../widgets/powerup_icon.dart';
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
  // Rewarded-ad extra spin. Null (or an unsupported platform) hides the offer
  // entirely — the screen works exactly as before ads existed.
  final ExtraSpinAdController? adController;

  const DailyRewardScreen({
    super.key,
    required this.authService,
    required this.backendApiService,
    this.onClaimed,
    this.adController,
  });

  @override
  State<DailyRewardScreen> createState() => _DailyRewardScreenState();
}

class _DailyRewardScreenState extends State<DailyRewardScreen> {
  Map<String, dynamic>? _status;
  bool _isLoading = true;
  bool _isClaiming = false;
  Map<String, dynamic>? _claimedReward;
  // Box mode (v2): the reel screen opens UNclaimed — the claim fires from the
  // reel's swipe gate, so closing with the X before swiping consumes nothing.
  // The reveal shows once the spin lands.
  bool _opening = false;
  Map<String, dynamic>? _boxResult;
  List<_DailyStripItem>? _stripItems;
  // Rewarded-ad extra spin state.
  bool _adReady = false;
  bool _adFlowBusy = false;
  bool _extraSpinDone = false;

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
      // Box mode goes straight to the reel, still unclaimed — the claim only
      // fires when the user swipes, same as opening a race mystery box.
      if (_box != null && res['claimedToday'] != true) {
        _openBox();
      }
      _maybePrepareExtraSpin();
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

  /// Exact box odds (spec §5.3 `box.itemOdds`). Null when the backend omits it
  /// OR sends something incoherent — both hide the ODDS affordance entirely,
  /// because a wrong odds display is worse than none (§6.3.B.10).
  OddsBreakdown? get _itemOdds => OddsBreakdown.parseItemOdds(_box?['itemOdds']);

  /// Rewarded-ad extra spin offer — present only when the backend has the
  /// feature enabled AND this build declared the `ads` capability. Older
  /// backends simply omit it. Read defensively.
  Map<String, dynamic>? get _adExtraSpin {
    final extra = _status?['adExtraSpin'];
    return extra is Map<String, dynamic> ? extra : null;
  }

  // Preload the rewarded ad as soon as the offer is live, so the button is
  // tappable by the time the free box's reveal settles. Skipped when a
  // verified-but-unredeemed watch already exists (claim needs no new ad).
  Future<void> _maybePrepareExtraSpin() async {
    final extra = _adExtraSpin;
    final ctrl = widget.adController;
    if (extra == null || ctrl == null || !ctrl.isSupported) return;
    if (extra['used'] == true || extra['pendingGrant'] == true) return;
    final userId = widget.authService.userId;
    if (userId == null || userId.isEmpty) return;
    if (!ctrl.isReady) {
      await ctrl.load(userId: userId, localDate: _todayLocalDate());
    }
    if (mounted) setState(() => _adReady = ctrl.isReady);
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
      if (!mounted) return;
      // Don't apply coins / refresh yet — the accessory reveal still spins (and
      // the coin reveal hasn't shown). Stash the result and apply it only when
      // the reveal settles (_applyReward, via _RewardReveal.onSettled), so the
      // wallet/inventory doesn't jump before the roll lands.
      setState(() {
        _claimedReward = res;
        _isClaiming = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _isClaiming = false);
      showErrorToast(context, 'Claim failed. Try again.');
    }
  }

  // Box mode: show the reel WITHOUT claiming. The strip is decoys-only (null
  // result) until the swipe-gated claim lands and replants the result tile.
  void _openBox() {
    setState(() {
      _opening = true;
      _stripItems = _generateStrip(null);
    });
  }

  // Swipe gate for the free daily box (CaseOpeningReel.onSpinRequested): claim
  // now, plant the result, then let the reel spin. Returning false on failure
  // re-arms the reel so the user can retry — nothing was consumed server-side.
  Future<bool> _claimBoxOnSpin() async {
    // Extra-spin path arrives here with the roll already claimed (the ad grant
    // forced an eager claim) — nothing to do but spin.
    if (_boxResult != null) return true;
    if (_isClaiming) return false;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return false;
    setState(() => _isClaiming = true);
    try {
      final res = await widget.backendApiService.claimDailyRewardBox(
        identityToken: token,
        localDate: _todayLocalDate(),
      );
      if (!mounted) return false;
      // Don't apply the coin balance yet — the reel hasn't spun. Stash the
      // result and credit coins only when the spin lands (_onStripComplete),
      // so the wallet doesn't jump before the roll is revealed. Replant just
      // the result tile so the visible decoys don't reshuffle mid-swipe.
      setState(() {
        _boxResult = res;
        final items = List<_DailyStripItem>.of(
          _stripItems ?? _generateStrip(null),
        );
        items[_DailyStripItem.resultPosition] = _DailyStripItem.fromResult(res);
        _stripItems = items;
        _isClaiming = false;
      });
      return true;
    } catch (e) {
      if (!mounted) return false;
      setState(() => _isClaiming = false);
      showErrorToast(context, 'Claim failed. Try again.');
      return false;
    }
  }

  // Extra spin: (optionally) run the rewarded ad, then claim and re-run the
  // reel with the extra roll. The server only honors the claim if AdMob's SSV
  // callback minted a grant — the client never asserts "I watched an ad".
  Future<void> _startExtraSpin() async {
    if (_adFlowBusy || _isClaiming) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final ctrl = widget.adController;
    final pending = _adExtraSpin?['pendingGrant'] == true;

    setState(() => _adFlowBusy = true);
    // Snapshot for restore if the flow dies before the new roll lands.
    final priorClaimed = _claimedReward;
    final priorBoxResult = _boxResult;
    final priorStrip = _stripItems;
    final priorOpening = _opening;
    try {
      if (!pending) {
        if (ctrl == null || !ctrl.isReady) return;
        setState(() => _adReady = false);
        final earned = await ctrl.showAndAwaitReward();
        if (!earned || !mounted) return;
      }
      setState(() {
        // Back to the reel screen; the reveal-once guard resets so the extra
        // roll credits coins when ITS spin lands.
        _opening = true;
        _claimedReward = null;
        _boxResult = null;
        _stripItems = null;
        _rewardApplied = false;
        _extraSpinDone = true;
      });
      final res = await _claimExtraWithRetry(token);
      if (!mounted) return;
      setState(() {
        _boxResult = res;
        _stripItems = _generateStrip(res);
      });
    } catch (e) {
      if (!mounted) return;
      // The grant (if any) is still unconsumed server-side — next visit shows
      // pendingGrant and redeems it without another ad.
      setState(() {
        _claimedReward = priorClaimed;
        _boxResult = priorBoxResult;
        _stripItems = priorStrip;
        _opening = priorOpening;
        _rewardApplied = true;
        _extraSpinDone = false;
      });
      showErrorToast(context, 'Extra spin failed. Try again later.');
    } finally {
      if (mounted) setState(() => _adFlowBusy = false);
    }
  }

  // AdMob's server-side verification can land a few seconds after the ad
  // closes on-device; the backend answers 409 ("no verified ad reward") until
  // it does. Retry briefly before giving up.
  Future<Map<String, dynamic>> _claimExtraWithRetry(String token) async {
    const maxAttempts = 5;
    for (var attempt = 0; ; attempt++) {
      try {
        return await widget.backendApiService.claimExtraDailyRewardBox(
          identityToken: token,
          localDate: _todayLocalDate(),
        );
      } on ApiException catch (e) {
        final ssvLag =
            e.statusCode == 409 &&
            e.message.toLowerCase().contains('no verified ad reward');
        if (!ssvLag || attempt >= maxAttempts - 1) rethrow;
        await Future<void>.delayed(const Duration(seconds: 2));
      }
    }
  }

  void _onStripComplete() {
    if (_claimedReward != null || _boxResult == null) return;
    // Spin landed: credit the coins and reveal the reward.
    _applyReward(_boxResult!);
    setState(() => _claimedReward = _boxResult);
  }

  // Applies a claimed reward's side effects — credit coins + trigger the parent
  // refresh. Guarded so it runs exactly once: box mode calls it from
  // _onStripComplete (when the reel lands), legacy mode from the reveal's
  // onSettled (when the coin card shows / the accessory spinner lands).
  bool _rewardApplied = false;
  void _applyReward(Map<String, dynamic> reward) {
    if (_rewardApplied) return;
    _rewardApplied = true;
    final coins = reward['coins'];
    if (coins is num) {
      widget.authService.updateCoins(coins.toInt());
    }
    widget.onClaimed?.call();
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
                color: AppColors.roofDark.withValues(alpha: 0.78),
                child: const CustomPaint(
                  painter: ArcadeCheckerPainter(
                    tileColor: Color(0x0AFFFFFF),
                    stripeColor: Color(0x14000000),
                    drawBottomStripe: false,
                  ),
                ),
              ),
            ),
          ),
          Column(
            children: [
              Expanded(
                child: SafeArea(
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
                                onSettled: () => _applyReward(_claimedReward!),
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
              ),
              // Screen-bottom trackside footer (same treatment as the
              // leaderboard/shop tabs); collapses to zero size when adless.
              const AdBannerSlot(withBottomSafeArea: true),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLoading() {
    return const Padding(
      padding: EdgeInsets.all(48),
      child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
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
            children: [for (final tile in ladder) _LadderTile(tile: tile)],
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
              _OddsEntry(odds: _itemOdds),
              _InfoButton(onTap: _showOddsInfo),
              const SizedBox(width: 8),
              _CloseButton(onTap: () => Navigator.of(context).pop(false)),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            !claimedToday
                ? 'Open today\'s mystery box to keep your streak going.'
                : _extraSpinOffered
                ? 'You\'ve opened today\'s box — grab your bonus spin!'
                : 'You\'ve opened today\'s box. Come back tomorrow!',
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
                    '$streak-DAY STREAK',
                    style: PixelText.title(size: 14, color: AppColors.textDark),
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 18),
          if (!claimedToday)
            PillButton(
              label: _isClaiming ? 'OPENING...' : 'OPEN BOX',
              variant: PillButtonVariant.primary,
              fullWidth: true,
              onPressed: _isClaiming ? null : _openBox,
            )
          else if (_extraSpinOffered)
            // The extra spin IS the primary action once today's box is open —
            // this view is reached from the home button's EXTRA SPIN state.
            PillButton(
              label: _adFlowBusy
                  ? 'PLEASE WAIT...'
                  : _adExtraSpin?['pendingGrant'] == true
                  ? 'CLAIM EXTRA SPIN'
                  : _adReady
                  ? 'WATCH AD · +1 SPIN'
                  : 'LOADING AD...',
              variant: PillButtonVariant.primary,
              fullWidth: true,
              onPressed:
                  (_adFlowBusy ||
                      !(_adExtraSpin?['pendingGrant'] == true || _adReady))
                  ? null
                  : _startExtraSpin,
            )
          else
            const PillButton(
              label: 'COME BACK TOMORROW',
              variant: PillButtonVariant.primary,
              fullWidth: true,
              onPressed: null,
            ),
        ],
      ),
    );
  }

  /// The rewarded-ad extra spin is on offer: the backend advertised it, it
  /// hasn't been used or already run this session, and this platform can show
  /// ads.
  bool get _extraSpinOffered {
    final extra = _adExtraSpin;
    final ctrl = widget.adController;
    return extra != null &&
        extra['used'] != true &&
        !_extraSpinDone &&
        ctrl != null &&
        ctrl.isSupported;
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
              _OddsEntry(odds: _itemOdds),
              _InfoButton(onTap: _showOddsInfo),
              const SizedBox(width: 8),
              // Before the swipe nothing is claimed — closing keeps today's
              // box available. After the swipe-gated claim it just skips the
              // reveal. Either way refresh the caller (pop true).
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
                    '$streak-DAY STREAK',
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
              onSpinRequested: _claimBoxOnSpin,
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
  // a longer streak visibly fills the reel with rarer tiles. A null [result]
  // (deferred-roll: claim hasn't fired yet) fills the result slot with a decoy
  // too; _claimBoxOnSpin replants it once the claim lands.
  List<_DailyStripItem> _generateStrip(Map<String, dynamic>? result) {
    final box = _box ?? const <String, dynamic>{};
    final odds = box['odds'] is Map<String, dynamic>
        ? box['odds'] as Map<String, dynamic>
        : const <String, dynamic>{};
    // Audit register #8: the old 0.50 / 0.35 fallbacks matched NO backend row
    // (every real row is 0.70/0.25/0.05 at streak 1 or 0.20/0.35/0.45 at cap),
    // so an old backend that omits `odds` used to fill the reel with decoys the
    // box could never actually pay at that rate. Fall back to the real
    // streak-1 row instead — the conservative end of the curve.
    final commonOdds =
        (odds['COMMON'] as num?)?.toDouble() ?? dailyBoxFallbackOdds['COMMON']!;
    final uncommonOdds =
        (odds['UNCOMMON'] as num?)?.toDouble() ??
        dailyBoxFallbackOdds['UNCOMMON']!;

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
    // Powerup prizes (spinPowerups feature). Absent on old backends → empty, so
    // the reel keeps showing accessory-only RARE tiles exactly as before.
    final powerupPool = (box['powerupPool'] as List? ?? const [])
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
      if (i == _DailyStripItem.resultPosition && result != null) {
        items.add(_DailyStripItem.fromResult(result));
        continue;
      }
      final roll = rng.nextDouble();
      if (roll < commonOdds) {
        items.add(
          _DailyStripItem.coins(randomCoins(commonMin, commonMax), 'COMMON'),
        );
      } else if (roll < commonOdds + uncommonOdds) {
        items.add(
          _DailyStripItem.coins(
            randomCoins(uncommonMin, uncommonMax),
            'UNCOMMON',
          ),
        );
      } else if (accessoryPool.isNotEmpty || powerupPool.isNotEmpty) {
        // RARE decoy: mix accessories and powerups from whatever's winnable.
        // When both pools have stock, roughly half-and-half (mirrors the
        // backend's 50/50 RARE sub-roll); otherwise draw from the non-empty one.
        final usePowerup = powerupPool.isNotEmpty &&
            (accessoryPool.isEmpty || rng.nextBool());
        if (usePowerup) {
          items.add(
            _DailyStripItem.powerup(
              powerupPool[rng.nextInt(powerupPool.length)],
            ),
          );
        } else {
          items.add(
            _DailyStripItem.accessory(
              accessoryPool[rng.nextInt(accessoryPool.length)],
            ),
          );
        }
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

    // RARE can now pay an accessory OR a shop powerup (spinPowerups feature).
    // Describe whichever the backend says is in play; fall back to the legacy
    // "new accessory" copy when the mix field is absent (old backend).
    final mix = box?['rarePrizeMix'] is Map<String, dynamic>
        ? box!['rarePrizeMix'] as Map<String, dynamic>
        : const <String, dynamic>{};
    final accessoryShare = (mix['ACCESSORY'] as num?)?.toDouble() ?? 1.0;
    final powerupShare = (mix['POWERUP'] as num?)?.toDouble() ?? 0.0;
    final rareDetail = powerupShare > 0 && accessoryShare > 0
        ? 'new accessory or powerup'
        : powerupShare > 0
        ? 'a shop powerup'
        : 'new accessory';

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
                detail: rareDetail,
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

/// Daily-box decoy odds used ONLY when the backend omits `box.odds` (older
/// backend). This is the real streak-1 row from the balance config — not an
/// invented curve. Audit register #8.
const dailyBoxFallbackOdds = <String, double>{
  'COMMON': 0.70,
  'UNCOMMON': 0.25,
  'RARE': 0.05,
};

/// One tile on the daily-box reel: a coin stack or an accessory.
class _DailyStripItem {
  static const stripLength = 45;
  // Same as the race reel: result near the end for a long scroll.
  static const resultPosition = 38;

  final String rarity;
  final int? coinAmount;
  final String? assetKey;
  final String? name;
  final int animationFrames;
  // Set when this tile is a shop powerup (spinPowerups feature): drives the
  // PowerupIcon face. Null for coin/accessory tiles.
  final String? powerupType;

  const _DailyStripItem._({
    required this.rarity,
    this.coinAmount,
    this.assetKey,
    this.name,
    this.animationFrames = 1,
    this.powerupType,
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
      animationFrames: AccessoryThumbnail.framesOf(shopItem),
    );
  }

  factory _DailyStripItem.powerup(Map<String, dynamic> powerup) {
    return _DailyStripItem._(
      rarity: 'RARE',
      powerupType: powerup['powerupType'] as String?,
      name: powerup['name'] as String? ?? 'Powerup',
    );
  }

  factory _DailyStripItem.fromResult(Map<String, dynamic> result) {
    final rarity = (result['rarity'] as String? ?? 'COMMON').toUpperCase();
    // Shop powerup prize (additive field; absent on old backends / other
    // reward types). Read defensively so a partial payload never crashes.
    final powerup = result['powerup'] as Map<String, dynamic>?;
    if (result['rewardType'] == 'POWERUP' && powerup != null) {
      return _DailyStripItem.powerup(powerup);
    }
    final shopItem = result['shopItem'] as Map<String, dynamic>?;
    if (shopItem != null) {
      return _DailyStripItem._(
        rarity: rarity,
        assetKey: shopItem['assetKey'] as String?,
        name: shopItem['name'] as String? ?? 'Accessory',
        animationFrames: AccessoryThumbnail.framesOf(shopItem),
      );
    }
    return _DailyStripItem._(
      rarity: rarity,
      coinAmount: (result['coinAmount'] as num?)?.toInt() ?? 0,
    );
  }

  bool get isPowerup => powerupType != null;
  bool get isCoins => coinAmount != null;
  bool get isAccessory => coinAmount == null && powerupType == null;
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
            item.isCoins ? '+${item.coinAmount}' : (item.name ?? '???'),
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
    if (item.isCoins) {
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
    if (item.isPowerup) {
      return PowerupIcon(type: item.powerupType!, size: 46);
    }
    if (item.assetKey != null) {
      return SizedBox(
        width: 46,
        height: 46,
        child: AccessoryThumbnail(
          assetKey: item.assetKey!,
          animationFrames: item.animationFrames,
          errorBuilder: (_, _, _) => const Icon(
            Icons.checkroom_rounded,
            size: 38,
            color: AppColors.accent,
          ),
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

/// The exact-odds entry point plus its trailing gap, collapsed to nothing
/// when the backend didn't send usable odds so the header doesn't gain a
/// stray 8px gutter on older backends.
class _OddsEntry extends StatelessWidget {
  const _OddsEntry({required this.odds});
  final OddsBreakdown? odds;

  @override
  Widget build(BuildContext context) {
    if (odds == null) return const SizedBox.shrink();
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        OddsAffordance(
          odds: odds,
          title: 'BOX ODDS',
          subtitle: 'Exactly what today\'s box can pay at your streak.',
        ),
        const SizedBox(width: 8),
      ],
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
  const _RewardReveal({
    required this.reward,
    required this.onClose,
    this.onSettled,
  });
  final Map<String, dynamic> reward;
  final VoidCallback onClose;

  /// Fired once when the reveal settles — the coin card is shown, or the
  /// accessory spinner has landed. The parent uses this to apply the reward
  /// (credit coins + refresh) so nothing is granted before the roll lands.
  final VoidCallback? onSettled;

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
      // No spinner to wait on — the card shows now, so settle on the next frame.
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) widget.onSettled?.call();
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final type = widget.reward['rewardType'] as String? ?? 'COINS';
    final coinAmount = (widget.reward['coinAmount'] as num?)?.toInt() ?? 0;
    final shopItem = widget.reward['shopItem'] as Map<String, dynamic>?;
    // Shop powerup prize (spinPowerups feature). Read defensively — a POWERUP
    // rewardType with a missing payload falls through to the coin card rather
    // than crashing.
    final powerup = widget.reward['powerup'] as Map<String, dynamic>?;
    final isPowerup = type == 'POWERUP' && powerup != null;
    // Present only on daily-box claims; legacy ladder claims have no rarity.
    final rarity = widget.reward['rarity'] as String?;
    final rarityColor = rarity != null ? _rarityColor(rarity) : null;

    if (type == 'ACCESSORY' && shopItem != null && !_spinDone) {
      return _AccessorySpinner(
        targetItem: shopItem,
        onComplete: () {
          // Spinner landed: apply the reward, then show the claimed card.
          widget.onSettled?.call();
          setState(() => _spinDone = true);
        },
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
            if (isPowerup) ...[
              Center(
                child: Container(
                  width: 130,
                  height: 130,
                  decoration: BoxDecoration(
                    color: AppColors.parchmentDark,
                    border: Border.all(color: AppColors.coinDark, width: 3),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  padding: const EdgeInsets.all(14),
                  child: Center(
                    child: PowerupIcon(
                      type: powerup['powerupType'] as String? ?? '',
                      size: 96,
                    ),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Text(
                powerup['name'] as String? ?? 'Powerup',
                textAlign: TextAlign.center,
                style: PixelText.title(size: 22, color: AppColors.textDark),
              ),
              const SizedBox(height: 6),
              Text(
                'Added to your powerups',
                textAlign: TextAlign.center,
                style: PixelText.body(size: 12, color: AppColors.textMid),
              ),
            ] else if (type == 'ACCESSORY' && shopItem != null) ...[
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
                  child: AccessoryThumbnail(
                    assetKey: shopItem['assetKey'] as String? ?? '',
                    animationFrames: AccessoryThumbnail.framesOf(shopItem),
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
    _animation = CurvedAnimation(
      parent: _controller,
      curve: Curves.easeOutQuart,
    );
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
          final resultCenter =
              _resultPosition * _totalItemWidth + _itemWidth / 2;
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
                                      for (
                                        int i = 0;
                                        i < _strip.length;
                                        i++
                                      ) ...[
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
      child: AccessoryThumbnail(
        assetKey: assetKey,
        animationFrames: AccessoryThumbnail.framesOf(item),
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
            child: Icon(
              Icons.close_rounded,
              size: 18,
              color: AppColors.textDark,
            ),
          ),
        ),
      ),
    );
  }
}
