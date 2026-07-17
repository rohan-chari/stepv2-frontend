import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/coin_balance_badge.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import 'daily_reward_screen.dart';
import 'referral_screen.dart';

String _todayLocalDate() {
  final now = DateTime.now();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${now.year}-${two(now.month)}-${two(now.day)}';
}

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

  const GetCoinsScreen({
    super.key,
    required this.authService,
    this.backendApiService,
    this.adController,
  });

  @override
  State<GetCoinsScreen> createState() => _GetCoinsScreenState();
}

class _GetCoinsScreenState extends State<GetCoinsScreen> {
  static const _textShadows = [
    Shadow(color: Color(0x40000000), blurRadius: 4, offset: Offset(0, 1)),
  ];

  late final BackendApiService _api;
  late final ExtraSpinAdController _adController;
  bool _ownsAdController = false;

  Map<String, dynamic>? _status;
  bool _adReady = false;
  bool _adLoading = false;
  bool _adFlowBusy = false;

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
    final provided = widget.adController;
    _ownsAdController = provided == null;
    _adController = provided ?? AdService();
    _load();
  }

  @override
  void dispose() {
    if (_ownsAdController) _adController.dispose();
    super.dispose();
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    try {
      final res = await _api.fetchDailyRewardStatus(
        identityToken: token,
        localDate: _todayLocalDate(),
      );
      if (!mounted) return;
      setState(() => _status = res);
      await _maybePrepareAd();
    } catch (_) {
      // Status is progressive enhancement here: without it the hub still
      // shows the referral and daily-spin entries.
      if (mounted) setState(() => _status = const {});
    }
  }

  /// Watch-ad-for-coins offer — read defensively (see class doc).
  Map<String, dynamic>? get _adCoinReward {
    final block = _status?['adCoinReward'];
    return block is Map<String, dynamic> ? block : null;
  }

  int get _remainingToday =>
      (_adCoinReward?['remainingToday'] as num?)?.toInt() ?? 0;
  int get _coinAmount => (_adCoinReward?['coinAmount'] as num?)?.toInt() ?? 25;

  /// Watches allowed per day. Server-driven so a retuned cap reaches this build
  /// without an App Store cycle; the fallback matches the backend default for a
  /// backend too old to send it.
  int get _dailyCap => (_adCoinReward?['dailyCap'] as num?)?.toInt() ?? 3;
  bool get _pendingGrant => _adCoinReward?['pendingGrant'] == true;
  bool get _offerLive =>
      _adCoinReward != null &&
      _adCoinReward?['available'] == true &&
      _remainingToday > 0;

  // Preload the rewarded ad whenever the offer is live and no ad is armed.
  // Called on load, after every watch (earned or not), and from the TRY AGAIN
  // button — the button must never dead-end on a loading state (that's what
  // stranded the first build of this screen). Skipped when a
  // verified-but-unredeemed watch already exists (claim needs no new ad).
  Future<void> _maybePrepareAd() async {
    if (!_offerLive || !_adController.isSupported || _pendingGrant) return;
    if (_adLoading) return;
    final userId = widget.authService.userId;
    if (userId == null || userId.isEmpty) return;
    if (!_adController.isReady) {
      setState(() => _adLoading = true);
      try {
        // The localDate parameter rides to AdMob as the SSV custom_data; the
        // "coins:" prefix tells the backend to mint a coin_reward grant
        // rather than an extra daily spin.
        await _adController.load(
          userId: userId,
          localDate: 'coins:${_todayLocalDate()}',
        );
      } finally {
        if (mounted) setState(() => _adLoading = false);
      }
    }
    if (mounted) setState(() => _adReady = _adController.isReady);
  }

  // (Optionally) run the rewarded ad, then claim. The server only honors the
  // claim if AdMob's SSV callback minted a grant — the client never asserts
  // "I watched an ad".
  Future<void> _startWatchAd() async {
    if (_adFlowBusy) return;
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final pending = _pendingGrant;

    setState(() => _adFlowBusy = true);
    try {
      if (!pending) {
        if (!_adController.isReady) return;
        setState(() => _adReady = false);
        final earned = await _adController.showAndAwaitReward();
        if (!mounted) return;
        if (!earned) {
          // Closed early: nothing to claim; re-arm so the offer stays live.
          await _maybePrepareAd();
          return;
        }
      }
      final res = await _claimWithRetry(token);
      if (!mounted) return;
      final coins = res['coins'];
      if (coins is num) widget.authService.updateCoins(coins.toInt());
      setState(() {
        // Fold the claim result back into the status so the section's counter
        // and button state stay honest without a refetch.
        final remaining =
            (res['remainingToday'] as num?)?.toInt() ?? (_remainingToday - 1);
        _status = {
          ...?_status,
          'adCoinReward': {
            ...?_adCoinReward,
            'available': remaining > 0,
            'pendingGrant': false,
            'remainingToday': remaining,
          },
        };
      });
      await _maybePrepareAd();
    } catch (_) {
      if (!mounted) return;
      showErrorToast(context, 'Reward failed. Try again later.');
      // The grant (if any) is still unconsumed server-side. Refetch: the
      // status flips to pendingGrant (claim without another ad) and the ad
      // re-arms — the button must recover, not strand on LOADING.
      await _load();
    } finally {
      if (mounted) setState(() => _adFlowBusy = false);
    }
  }

  // AdMob's server-side verification can land a few seconds after the ad
  // closes on-device; the backend answers 409 ("no verified ad reward") until
  // it does. Retry briefly before giving up.
  Future<Map<String, dynamic>> _claimWithRetry(String token) async {
    const maxAttempts = 5;
    for (var attempt = 0; ; attempt++) {
      try {
        return await _api.claimAdCoinReward(
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

  void _openReferral() {
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
              adController: widget.adController,
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
      backgroundColor: AppColors.parchment,
      body: Stack(
        children: [
          const Positioned.fill(
            child: ColoredBox(
              color: AppColors.roofLight,
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
                  child: ColoredBox(
                    color: AppColors.parchment,
                    child: ListView(
                      physics: const AlwaysScrollableScrollPhysics(),
                      padding: const EdgeInsets.fromLTRB(16, 16, 16, 40),
                      children: [
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
                ),
                const AdBannerSlot(withBottomSafeArea: true),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildHeader() {
    return DecoratedBox(
      decoration: const BoxDecoration(
        color: AppColors.roofLight,
        border: Border(bottom: BorderSide(color: AppColors.roofDark, width: 1)),
      ),
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
                    icon: const Icon(
                      Icons.arrow_back,
                      color: AppColors.parchment,
                    ),
                    onPressed: () => Navigator.of(context).pop(),
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
                  color: AppColors.parchment,
                ).copyWith(shadows: _textShadows),
              ),
              const SizedBox(height: 5),
              Text(
                'Watch ads, invite friends, and open your daily box.',
                style: PixelText.body(
                  size: 14,
                  color: AppColors.parchment.withValues(alpha: 0.92),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCard({
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.parchmentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: AppColors.parchmentBorder, width: 1.5),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: AppColors.textDark),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  style: PixelText.title(size: 16, color: AppColors.textDark),
                ),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            subtitle,
            style: PixelText.body(size: 13, color: AppColors.textMid),
          ),
          const SizedBox(height: 12),
          action,
        ],
      ),
    );
  }

  Widget _buildWatchAdCard() {
    final exhausted = _remainingToday <= 0;

    final String label;
    final VoidCallback? onPressed;
    if (exhausted) {
      label = 'COME BACK TOMORROW';
      onPressed = null;
    } else if (_pendingGrant) {
      label = 'CLAIM +$_coinAmount COINS';
      onPressed = _adFlowBusy ? null : _startWatchAd;
    } else if (_adReady) {
      label = 'WATCH AD · +$_coinAmount COINS';
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
      icon: Icons.play_circle_outline_rounded,
      title: 'WATCH AN AD',
      subtitle: exhausted
          ? 'You earned all your ad coins for today.'
          : 'Earn $_coinAmount coins per ad · $_remainingToday of $_dailyCap left today',
      action: PillButton(
        label: label,
        variant: PillButtonVariant.primary,
        fullWidth: true,
        onPressed: onPressed,
      ),
    );
  }

  Widget _buildReferralCard() {
    return _buildCard(
      icon: Icons.group_add_rounded,
      title: 'INVITE FRIENDS',
      subtitle: 'You both earn coins when a friend joins with your link.',
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
      icon: Icons.card_giftcard_rounded,
      title: 'DAILY BOX',
      subtitle: claimed
          ? 'Claimed today — come back tomorrow for the next one.'
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
