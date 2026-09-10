import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/rewarded_coins_controller.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/billing_scope.dart';
import '../widgets/coin_pack_offers.dart';
// Bara+ on hold; restore with its entry below.
// import '../widgets/bara_plus_card.dart';
import '../widgets/coin_balance_badge.dart';
import '../widgets/error_toast.dart';
import '../widgets/info_toast.dart';
import '../widgets/pill_button.dart';
import 'daily_reward_screen.dart';
import 'referral_screen.dart';

/// The "Get Coins" hub — where the "+" next to the coin balance lands. One
/// page listing every way to earn coins: watch-ad-for-coins (SSV-verified,
/// capped per day), invite friends (pushes the full [ReferralScreen]), and
/// the daily box spin. Styled after [ReferralScreen] (checker roof header,
/// parchment body) so it reads as part of the same family of pages.
///
/// The watch-ad section exists only when the /daily-reward/status response
/// carries the additive `adCoinReward` block ({available, pendingGrant,
/// remainingToday, coinAmount}) AND an ad controller is supported — old
/// backends omit the field and the section never renders. All fields are read
/// defensively: the backend may be newer or older than this build.
class GetCoinsScreen extends StatefulWidget {
  final AuthService authService;
  final BackendApiService? backendApiService;
  // Rewarded-ad controller. Null (or an unsupported platform) hides the
  // watch-ad section entirely.
  final ExtraSpinAdController? adController;
  final DateTime Function()? now;
  final RewardedCoinsController? rewardedCoinsController;

  const GetCoinsScreen({
    super.key,
    required this.authService,
    this.backendApiService,
    this.adController,
    this.now,
    this.rewardedCoinsController,
  });

  @override
  State<GetCoinsScreen> createState() => _GetCoinsScreenState();
}

class _GetCoinsScreenState extends State<GetCoinsScreen>
    with WidgetsBindingObserver {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  late final BackendApiService _api;
  late final RewardedCoinsController _rewards;
  late final bool _ownsRewards;
  int? _referrerCoins;
  int? _refereeCoins;
  String? _referralToken;
  Map<String, dynamic>? get _status => _rewards.status;
  ExtraSpinAdController get _adController => _rewards.ads;
  bool get _adReady => _rewards.ready;
  bool get _adLoading => _rewards.loading;
  bool get _adFlowBusy => _rewards.busy;

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
    _ownsRewards = widget.rewardedCoinsController == null;
    _rewards =
        widget.rewardedCoinsController ??
        RewardedCoinsController(
          auth: widget.authService,
          api: _api,
          ads: widget.adController ?? AdService(),
          ownsAds: widget.adController == null,
          now: widget.now,
        );
    _rewards.addListener(_changed);
    unawaited(_load());
  }

  void _changed() {
    if (!mounted) return;
    final rewards = _status?['referralRewards'];
    final referrer = rewards is Map
        ? RewardedCoinsController.integer(rewards['referrerCoins'])
        : null;
    final referee = rewards is Map
        ? RewardedCoinsController.integer(rewards['refereeCoins'])
        : null;
    final token = widget.authService.authToken;
    if (_referralToken != token) {
      _referrerCoins = null;
      _refereeCoins = null;
    }
    if (referrer != null && referee != null) {
      _referrerCoins = referrer;
      _refereeCoins = referee;
    } else if (_status != null && token != null && _referralToken != token) {
      unawaited(_loadReferralRewards(token));
    }
    if (_status != null) _referralToken = token;
    setState(() {});
  }

  @override
  void dispose() {
    _rewards.removeListener(_changed);
    if (_ownsRewards) _rewards.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    await _rewards.refresh();
    _changed();
  }

  /// Best-effort lookup of the configured referral rewards so the invite row
  /// can state a figure. Entirely optional: a 404 from an older backend, a
  /// dropped connection, or a response without the fields all leave both null
  /// and the row keeps its number-free wording. Never blocks the hub's paint.
  Future<void> _loadReferralRewards(String token) async {
    try {
      final res = await _api.fetchReferralStatus(identityToken: token);
      if (!mounted || widget.authService.authToken != token) return;
      setState(() {
        _referrerCoins = RewardedCoinsController.integer(res['referrerCoins']);
        _refereeCoins = RewardedCoinsController.integer(res['refereeCoins']);
      });
    } catch (_) {
      // Number-free copy is the correct outcome here, not an error state.
    }
  }

  /// Watch-ad-for-coins offer — read defensively (see class doc).
  Map<String, dynamic>? get _adCoinReward {
    final block = _status?['adCoinReward'];
    return block is Map<String, dynamic> ? block : null;
  }

  int get _remainingToday => _rewards.remaining;
  int get _coinAmount {
    final value = RewardedCoinsController.integer(_adCoinReward?['coinAmount']);
    return value != null && value >= 25 && value <= 50 ? value : 25;
  }

  int get _coinRewardMin {
    final value = _adCoinReward?['coinRewardMin'];
    return value is num && value >= 1 && value <= 100 ? value.toInt() : 25;
  }

  int get _coinRewardMax {
    final value = _adCoinReward?['coinRewardMax'];
    final parsed = value is num ? value.toInt() : 50;
    return parsed >= _coinRewardMin && parsed <= 100 ? parsed : 50;
  }

  /// Watches allowed per day. Server-driven so a retuned cap reaches this build
  /// without an App Store cycle; the fallback matches the backend default for a
  /// backend too old to send it.
  int get _dailyCap {
    final value = RewardedCoinsController.integer(_adCoinReward?['dailyCap']);
    return value != null && value > 0 ? value : 5;
  }

  bool get _pendingGrant => _adCoinReward?['pendingGrant'] == true;
  Future<void> _maybePrepareAd() => _rewards.prepare();

  Future<void> _startWatchAd() async {
    final token = widget.authService.authToken;
    try {
      final amount = await _rewards.claim();
      if (!mounted || widget.authService.authToken != token || amount == null) {
        return;
      }
      showInfoToast(context, '+$amount coins earned!');
    } catch (_) {
      if (mounted && widget.authService.authToken == token) {
        showErrorToast(context, 'Reward failed. Try again later.');
      }
    }
  }

  bool _previewUnavailable() {
    if (BillingScope.read(context)?.isPreview != true) return false;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'This earn method is unavailable in the offline preview.',
        ),
      ),
    );
    return true;
  }

  void _openReferral() {
    if (_previewUnavailable()) return;
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => ReferralScreen(
          authService: widget.authService,
          backendApiService: _api,
        ),
      ),
    );
  }

  void _openDailyReward() {
    if (_previewUnavailable()) return;
    // Same blurred-overlay push the StreakChip uses.
    Navigator.of(context)
        .push(
          PageRouteBuilder(
            opaque: false,
            transitionDuration: const Duration(milliseconds: 250),
            reverseTransitionDuration: const Duration(milliseconds: 200),
            pageBuilder: (_, _, _) => DailyRewardScreen(
              authService: widget.authService,
              backendApiService: _api,
              // Deliberately NOT _adController: ours is armed with the
              // `coins:<date>` SSV custom_data, and the extra-spin flow showing
              // it would mint coins instead of a spin. Null lets that screen
              // create its own correctly-armed controller.
              adController: null,
            ),
            transitionsBuilder: (_, animation, _, child) =>
                FadeTransition(opacity: animation, child: child),
          ),
        )
        .then((_) => _load());
  }

  @override
  Widget build(BuildContext context) {
    final topInset = MediaQuery.of(context).padding.top;

    return Scaffold(
      backgroundColor: AppColors.of(context).parchment,
      body: Stack(
        children: [
          Positioned.fill(
            child: ColoredBox(
              color: AppColors.of(context).roofLight,
              child: CustomPaint(
                painter: ArcadeCheckerPainter(drawBottomStripe: false),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.only(top: topInset),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                _buildHeader(),
                Expanded(
                  child: ListView(
                    key: const Key('get-coins-earn-list'),
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                    children: [
                      if (BillingScope.maybeOf(context)?.isAvailable ==
                          true) ...[
                        const CoinPackOffers(onGreenSurface: true),
                        const SizedBox(height: 20),
                      ],
                      // Bara+ on hold.
                      /*
                      if (BillingScope.maybeOf(context)?.canShowMembership ==
                          true) ...[
                        const BaraPlusCard(),
                        const SizedBox(height: 24),
                      ],
                      */
                      if (_adCoinReward != null &&
                          _adController.isSupported) ...[
                        _buildWatchAdCard(),
                        const SizedBox(height: 12),
                      ],
                      _buildReferralCard(),
                      const SizedBox(height: 12),
                      _buildDailySpinCard(),
                    ],
                  ),
                ),
                AdBannerSlot(
                  withBottomSafeArea: true,
                  hidden: BillingScope.maybeOf(context)?.isPreview == true,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return DecoratedBox(
      decoration: BoxDecoration(color: AppColors.of(context).roofLight),
      child: CustomPaint(
        painter: const ArcadeCheckerPainter(drawBottomStripe: false),
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  IconButton(
                    padding: EdgeInsets.zero,
                    constraints: const BoxConstraints(),
                    icon: Icon(
                      Icons.arrow_back,
                      color: AppColors.of(context).textLight,
                    ),
                    onPressed: () => Navigator.of(context).maybePop(),
                  ),
                  const Spacer(),
                  CoinBalanceBadge(coins: widget.authService.coins),
                ],
              ),
              const SizedBox(height: 4),
              Text(
                'GET COINS',
                style: PixelText.title(
                  size: 28,
                  color: AppColors.of(context).textLight,
                ).copyWith(shadows: _textShadows),
              ),
              const SizedBox(height: 5),
              Text(
                'Watch ads, invite friends, and open your daily box.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.of(
                    context,
                  ).textLight.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required Key key,
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    return Container(
      key: key,
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchment,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(
          color: AppColors.of(context).roofDark.withValues(alpha: 0.55),
          width: 2,
        ),
        boxShadow: const [
          BoxShadow(
            color: Color(0x66000000),
            offset: Offset(0, 4),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.of(context).textDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: PixelText.title(
                    size: 16,
                    color: AppColors.of(context).textDark,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: PixelText.body(
              size: 13,
              color: AppColors.of(context).textMid,
            ),
          ),
          const SizedBox(height: 12),
          action,
        ],
      ),
    );
  }

  Widget _buildWatchAdCard() {
    final exhausted = _remainingToday <= 0 && !_pendingGrant;

    final String label;
    final VoidCallback? onPressed;
    if (exhausted) {
      label = 'COME BACK TOMORROW';
      onPressed = null;
    } else if (_pendingGrant) {
      label = 'CLAIM +$_coinAmount COINS';
      onPressed = _adFlowBusy ? null : _startWatchAd;
    } else if (_adReady) {
      label = 'WATCH AD · RANDOM COINS';
      onPressed = _adFlowBusy ? null : _startWatchAd;
    } else if (_adLoading || _adFlowBusy) {
      label = 'LOADING AD...';
      onPressed = null;
    } else {
      // Load finished without an ad (no fill / network) — offer a manual
      // retry rather than stranding the button on a loading state.
      label = 'TRY AGAIN';
      onPressed = _maybePrepareAd;
    }

    return _buildCard(
      key: const Key('get-coins-watch-ad-card'),
      icon: Icons.play_circle_outline_rounded,
      title: 'WATCH AN AD',
      subtitle: exhausted
          ? 'You earned all your ad coins for today.'
          : 'Earn a random $_coinRewardMin–$_coinRewardMax coins per ad · $_remainingToday of $_dailyCap left today',
      action: PillButton(
        label: label,
        variant: PillButtonVariant.rewardedAd,
        fullWidth: true,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildReferralCard() {
    return _buildCard(
      key: const Key('get-coins-referral-card'),
      icon: Icons.group_add_rounded,
      title: 'INVITE FRIENDS',
      subtitle: referralInviteRowCopy(
        referrerCoins: _referrerCoins,
        refereeCoins: _refereeCoins,
      ),
      action: PillButton(
        label: 'SHARE INVITE LINK',
        variant: PillButtonVariant.primary,
        fullWidth: true,
        onPressed: _openReferral,
      ),
    );
  }

  Widget _buildDailySpinCard() {
    final claimed = _status?['claimedToday'] == true;
    return _buildCard(
      key: const Key('get-coins-daily-card'),
      icon: Icons.card_giftcard_rounded,
      title: 'DAILY BOX',
      subtitle: claimed
          ? 'Claimed today. Come back tomorrow for the next one.'
          : 'Open your free daily box for coins and gear.',
      action: PillButton(
        label: claimed ? 'CLAIMED TODAY' : 'OPEN DAILY BOX',
        variant: PillButtonVariant.primary,
        fullWidth: true,
        onPressed: claimed ? null : _openDailyReward,
      ),
    );
  }
}
