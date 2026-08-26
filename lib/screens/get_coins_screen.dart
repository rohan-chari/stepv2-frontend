import 'dart:async';

import 'package:flutter/material.dart';

import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/ad_banner_slot.dart';
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

  const GetCoinsScreen({
    super.key,
    required this.authService,
    this.backendApiService,
    this.adController,
    this.now,
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
  late final ExtraSpinAdController _adController;
  bool _ownsAdController = false;

  Map<String, dynamic>? _status;
  // Configured referral rewards, off the wire (batch 2026-07-27 §4.3). Null
  // whenever the backend is older than the fields or the lookup failed — the
  // invite row then states no figure rather than a guess.
  int? _referrerCoins;
  int? _refereeCoins;
  bool _adReady = false;
  bool _adLoading = false;
  bool _adFlowBusy = false;
  RewardedAdContext? _activeAdContext;

  String _todayLocalDate() {
    final now = widget.now?.call() ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return '${now.year}-${two(now.month)}-${two(now.day)}';
  }

  @override
  void initState() {
    super.initState();
    _api = widget.backendApiService ?? BackendApiService();
    final provided = widget.adController;
    _ownsAdController = provided == null;
    _adController = provided ?? AdService();
    WidgetsBinding.instance.addObserver(this);
    widget.authService.addListener(_handleAuthChanged);
    _activeAdContext = _currentAdContext;
    _observeReadiness();
    _load();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    widget.authService.removeListener(_handleAuthChanged);
    if (_ownsAdController) _adController.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) _syncContextAndReload();
  }

  RewardedAdContext? get _currentAdContext {
    final userId = widget.authService.userId;
    if (userId == null || userId.isEmpty) return null;
    return RewardedAdContext.getCoins(
      userId: userId,
      localDate: _todayLocalDate(),
    );
  }

  void _handleAuthChanged() => _syncContextAndReload();

  void _syncContextAndReload() {
    if (!mounted) return;
    final next = _currentAdContext;
    final previous = _activeAdContext;
    if (previous == next) {
      _observeReadiness();
      return;
    }
    if (previous != null) _adController.disposeContext(previous);
    setState(() {
      _activeAdContext = next;
      _status = null;
      _adReady = false;
      _adLoading = false;
    });
    _observeReadiness();
    _load();
  }

  void _observeReadiness() {
    final context = _activeAdContext;
    if (!mounted || context == null) return;
    final ready = _adController.isReadyFor(context);
    if (_adReady != ready) setState(() => _adReady = ready);
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    final context = _activeAdContext;
    if (token == null || token.isEmpty || context?.localDate == null) return;
    try {
      final res = await _api.fetchGetCoinsStatus(
        identityToken: token,
        localDate: context!.localDate!,
      );
      if (!mounted || _activeAdContext != context) return;
      final referralRewards = res['referralRewards'];
      final referrer = referralRewards is Map
          ? referralRewards['referrerCoins']
          : null;
      final referee = referralRewards is Map
          ? referralRewards['refereeCoins']
          : null;
      if (referrer is num && referee is num) {
        setState(() {
          _status = res;
          _referrerCoins = referrer.toInt();
          _refereeCoins = referee.toInt();
        });
      } else {
        setState(() => _status = res);
        // Frozen/legacy backend: only the two referral numbers need the
        // dashboard fallback; claimed/ad status is already usable.
        unawaited(_loadReferralRewards(token));
      }
      if (!_offerLive) {
        _adController.disposeContext(context);
        if (mounted) setState(() => _adReady = false);
      } else {
        await _maybePrepareAd();
      }
    } catch (_) {
      // Status is progressive enhancement here: without it the hub still
      // shows the referral and daily-spin entries.
      if (mounted && context != null && _activeAdContext == context) {
        _adController.disposeContext(context);
        setState(() {
          _status = const {};
          _adReady = false;
        });
      }
    }
  }

  /// Best-effort lookup of the configured referral rewards so the invite row
  /// can state a figure. Entirely optional: a 404 from an older backend, a
  /// dropped connection, or a response without the fields all leave both null
  /// and the row keeps its number-free wording. Never blocks the hub's paint.
  Future<void> _loadReferralRewards(String token) async {
    try {
      final res = await _api.fetchReferralStatus(identityToken: token);
      if (!mounted) return;
      setState(() {
        _referrerCoins = (res['referrerCoins'] as num?)?.toInt();
        _refereeCoins = (res['refereeCoins'] as num?)?.toInt();
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

  int get _remainingToday =>
      (_adCoinReward?['remainingToday'] as num?)?.toInt() ?? 0;
  int get _coinAmount {
    final value = (_adCoinReward?['coinAmount'] as num?)?.toInt();
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
    final value = (_adCoinReward?['dailyCap'] as num?)?.toInt();
    return value != null && value > 0 ? value : 5;
  }

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
    final context = _activeAdContext;
    if (context == null) return;
    if (!_adController.isReadyFor(context)) {
      setState(() => _adLoading = true);
      try {
        await _adController.warm(context);
      } finally {
        if (mounted) setState(() => _adLoading = false);
      }
    }
    if (mounted && _activeAdContext == context) {
      setState(() => _adReady = _adController.isReadyFor(context));
    }
  }

  // (Optionally) run the rewarded ad, then claim. The server only honors the
  // claim if AdMob's SSV callback minted a grant — the client never asserts
  // "I watched an ad".
  Future<void> _startWatchAd() async {
    if (_adFlowBusy) return;
    if (_currentAdContext != _activeAdContext) {
      _syncContextAndReload();
      return;
    }
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) return;
    final pending = _pendingGrant;
    final adContext = _activeAdContext;

    setState(() => _adFlowBusy = true);
    try {
      if (!pending) {
        if (adContext == null || !_adController.isReadyFor(adContext)) return;
        setState(() => _adReady = false);
        final earned = await _adController.showAndAwaitRewardFor(adContext);
        if (!_flowStillCurrent(token, adContext)) return;
        if (!earned) {
          // Closed early: nothing to claim; re-arm so the offer stays live.
          await _maybePrepareAd();
          return;
        }
      }
      final claimDate = adContext?.localDate;
      if (claimDate == null) return;
      final res = await _claimWithRetry(token, claimDate, adContext);
      if (!_flowStillCurrent(token, adContext)) return;
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
      if (_remainingToday <= 0 && adContext != null) {
        _adController.disposeContext(adContext);
      }
      final rawEarnedAmount = res['coinAmount'];
      final earnedAmount = rawEarnedAmount is num
          ? rawEarnedAmount.toInt()
          : _coinAmount;
      if (!mounted) return;
      showInfoToast(context, '+$earnedAmount coins earned!');
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
  Future<Map<String, dynamic>> _claimWithRetry(
    String token,
    String localDate,
    RewardedAdContext? context,
  ) async {
    const maxAttempts = 5;
    for (var attempt = 0; ; attempt++) {
      try {
        if (!_flowStillCurrent(token, context)) {
          throw StateError('Rewarded-ad context changed');
        }
        return await _api.claimAdCoinReward(
          identityToken: token,
          localDate: localDate,
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

  bool _flowStillCurrent(String token, RewardedAdContext? context) =>
      mounted &&
      context != null &&
      widget.authService.authToken == token &&
      _activeAdContext == context &&
      _currentAdContext == context;

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
                  child: ColoredBox(
                    color: AppColors.of(context).parchment,
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
    required IconData icon,
    required String title,
    required String subtitle,
    required Widget action,
  }) {
    return Container(
      padding: const EdgeInsets.fromLTRB(14, 14, 14, 14),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentLight,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: AppColors.of(context).parchmentBorder,
          width: 1.5,
        ),
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
