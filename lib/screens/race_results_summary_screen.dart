import 'dart:ui';

import 'package:flutter/material.dart';

import '../models/race_payouts.dart';
import '../models/race_payout_double_offer.dart';
import '../services/ad_service.dart';
import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../utils/at_name.dart';
import '../utils/race_participant_display.dart';
import '../utils/team_race.dart';
import '../widgets/ad_banner_slot.dart';
import '../widgets/celebration_confetti.dart';
import '../widgets/game_container.dart';
import '../widgets/home_chrome.dart';
import '../widgets/pill_button.dart';
import '../widgets/race_podium.dart';
import '../widgets/spinning_coin.dart';

/// Blurred-backdrop popup summarizing races that finished since the user last
/// opened the app. Reuses the daily-reward modal pattern (transparent Material
/// + [BackdropFilter] blur), pushed via a `PageRouteBuilder(opaque: false)`
/// with a ~250ms fade by the caller.
///
/// [races] are the completed-bucket race maps the user participated in. Reads
/// every field defensively: a race may come from a backend version newer or
/// older than this build.
class RaceResultsSummaryScreen extends StatefulWidget {
  const RaceResultsSummaryScreen({
    super.key,
    required this.races,
    this.canStartNextRace = false,
    this.payoutDoubleOffer,
    this.authService,
    this.backendApiService,
    this.adController,
    this.claimRetryDelay = const Duration(seconds: 2),
    this.onBeforeDismiss,
  });

  final List<Map<String, dynamic>> races;
  final bool canStartNextRace;
  final RacePayoutDoubleOffer? payoutDoubleOffer;
  final AuthService? authService;
  final BackendApiService? backendApiService;
  final RacePayoutDoubleAdController? adController;
  final Duration claimRetryDelay;
  final Future<void> Function()? onBeforeDismiss;

  @override
  State<RaceResultsSummaryScreen> createState() =>
      _RaceResultsSummaryScreenState();
}

enum _PayoutDoubleFlowState { ready, loading, verifying, earned }

class _RaceResultsSummaryScreenState extends State<RaceResultsSummaryScreen> {
  RacePayoutDoubleOffer? _offer;
  _PayoutDoubleFlowState _flowState = _PayoutDoubleFlowState.ready;
  String? _message;
  bool _offerHidden = false;
  bool _earnedCallbackReceived = false;
  bool _dismissStarted = false;
  int? _earnedBaseCoins;
  int? _earnedBonusCoins;

  bool get _flowBusy =>
      _flowState == _PayoutDoubleFlowState.loading ||
      _flowState == _PayoutDoubleFlowState.verifying;

  @override
  void initState() {
    super.initState();
    _offer = widget.payoutDoubleOffer;
    if (_offer?.offerId != null && _dependenciesAvailable) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) _recoverPendingOffer();
      });
    }
  }

  bool get _dependenciesAvailable {
    final auth = widget.authService;
    final api = widget.backendApiService;
    final ads = widget.adController;
    return auth != null &&
        api != null &&
        ads != null &&
        ads.isSupported &&
        (auth.authToken?.isNotEmpty ?? false) &&
        (auth.userId?.isNotEmpty ?? false);
  }

  @override
  void dispose() {
    widget.adController?.dispose();
    super.dispose();
  }

  Future<void> _dismiss([bool? result]) async {
    if (_dismissStarted) return;
    _dismissStarted = true;
    try {
      await widget.onBeforeDismiss?.call();
    } catch (_) {
      // Queue persistence has its own memory fallback. Dismissal must remain
      // available even if local storage is unavailable.
    }
    if (mounted) Navigator.of(context).pop(result);
  }

  Future<void> _recoverPendingOffer() async {
    final offerId = _offer?.offerId;
    if (offerId == null || _flowBusy || _offerHidden) return;
    await _claimPreparedOffer(offerId, recovery: true);
  }

  Future<void> _startPayoutDouble() async {
    if (_flowBusy ||
        _offerHidden ||
        _flowState == _PayoutDoubleFlowState.earned) {
      return;
    }
    final api = widget.backendApiService;
    final auth = widget.authService;
    final ads = widget.adController;
    final token = auth?.authToken;
    final userId = auth?.userId;
    var current = _offer;
    if (api == null ||
        auth == null ||
        ads == null ||
        !ads.isSupported ||
        token == null ||
        token.isEmpty ||
        userId == null ||
        userId.isEmpty ||
        current == null) {
      _hideOffer();
      return;
    }

    if (_earnedCallbackReceived && current.offerId != null) {
      await _claimPreparedOffer(current.offerId!);
      return;
    }

    setState(() {
      _flowState = _PayoutDoubleFlowState.loading;
      _message = null;
    });
    try {
      if (current.offerId == null) {
        current = await api.createRacePayoutDoubleOffer(
          identityToken: token,
          raceIds: current.raceIds,
          popupRaceIds: _popupRaceIds,
        );
        if (!mounted) return;
        setState(() => _offer = current);
      }
      final offerId = current.offerId;
      if (offerId == null) {
        _hideOffer();
        return;
      }
      if (!ads.isReady) {
        await ads.loadForRacePayoutDouble(userId: userId, offerId: offerId);
      }
      if (!mounted) return;
      if (!ads.isReady) {
        setState(() {
          _flowState = _PayoutDoubleFlowState.ready;
          _message = "Ad didn't load. Your coins are unchanged.";
        });
        return;
      }
      final earned = await ads.showAndAwaitReward();
      if (!mounted) return;
      if (!earned) {
        setState(() {
          _flowState = _PayoutDoubleFlowState.ready;
          _message = current!.isFlat50
              ? 'Finish the ad to earn +${current.bonusCoins} flat bonus coins.'
              : 'Finish the ad to earn +${current.bonusCoins} bonus coins.';
        });
        return;
      }
      _earnedCallbackReceived = true;
      await _claimPreparedOffer(offerId);
    } on ApiException catch (error) {
      if (!mounted) return;
      _handleFlowError(error, preparing: current?.offerId == null);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _flowState = _PayoutDoubleFlowState.ready;
        _message = 'Bonus unavailable right now. Your coins are unchanged.';
      });
    }
  }

  Future<void> _claimPreparedOffer(
    String offerId, {
    bool recovery = false,
  }) async {
    final api = widget.backendApiService;
    final auth = widget.authService;
    final token = auth?.authToken;
    if (api == null || auth == null || token == null || token.isEmpty) {
      _hideOffer();
      return;
    }
    setState(() {
      _flowState = _PayoutDoubleFlowState.verifying;
      _message = null;
    });
    try {
      RacePayoutDoubleClaimResult? result;
      const maxAttempts = 5;
      for (var attempt = 0; attempt < maxAttempts; attempt++) {
        try {
          result = await api.claimRacePayoutDouble(
            identityToken: token,
            offerId: offerId,
            popupRaceIds: _popupRaceIds,
          );
          break;
        } on ApiException catch (error) {
          if (error.code != 'AD_NOT_VERIFIED' || attempt == maxAttempts - 1) {
            rethrow;
          }
          await Future<void>.delayed(widget.claimRetryDelay);
        }
      }
      if (!mounted || result == null) return;
      var coins = result.coins;
      if (coins == null) {
        final me = await api.fetchMe(identityToken: token);
        final refreshed = me['coins'];
        if (refreshed is int && refreshed >= 0) coins = refreshed;
      }
      if (coins == null) {
        throw const ApiException(
          'Could not refresh your balance.',
          code: 'BALANCE_UNAVAILABLE',
        );
      }
      await auth.updateCoins(coins);
      if (!mounted) return;
      setState(() {
        _earnedBaseCoins = result!.baseCoins;
        _earnedBonusCoins = result.bonusCoins;
        _flowState = _PayoutDoubleFlowState.earned;
        _message = null;
      });
    } on ApiException catch (error) {
      if (!mounted) return;
      if (recovery) {
        // A recovered pending offer represents an interrupted entitlement.
        // Retry its claim directly after transient/claim-switch failures. Only
        // AD_NOT_VERIFIED means this device should offer the same immutable
        // ad context again because no signed grant has arrived yet.
        _earnedCallbackReceived = error.code != 'AD_NOT_VERIFIED';
      }
      _handleFlowError(error, preparing: false);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _flowState = _PayoutDoubleFlowState.ready;
        _message = 'Verification is taking longer. Try again.';
      });
    }
  }

  void _handleFlowError(ApiException error, {required bool preparing}) {
    const terminalCodes = {
      'INVALID_REQUEST',
      'ENDPOINT_UNSUPPORTED',
      'OFFER_NOT_FOUND',
      'OFFER_CHANGED',
      'OFFER_PENDING',
      'OFFER_FORFEITED',
      'RESULTS_ALREADY_SEEN',
    };
    if (terminalCodes.contains(error.code) ||
        (preparing && error.code == 'PREPARATION_DISABLED')) {
      _hideOffer();
      return;
    }
    final bonus = _offer?.bonusCoins ?? 0;
    final flat = _offer?.isFlat50 ?? false;
    setState(() {
      _flowState = _PayoutDoubleFlowState.ready;
      if (error.code == 'CLAIMS_DISABLED') {
        _earnedCallbackReceived = true;
        _message = flat
            ? 'Flat bonus verification is temporarily unavailable. Try again.'
            : 'Bonus verification is temporarily unavailable. Try again.';
      } else if (error.code == 'AD_NOT_VERIFIED') {
        _message = flat
            ? _earnedCallbackReceived
                  ? 'Still verifying +$bonus flat bonus coins. Try again.'
                  : 'Finish an ad to earn +$bonus flat bonus coins.'
            : _earnedCallbackReceived
            ? 'Still verifying +$bonus bonus coins. Try again.'
            : 'Finish an ad to earn +$bonus bonus coins.';
      } else {
        _message = flat
            ? 'Flat bonus unavailable right now. Your coins are unchanged.'
            : 'Bonus unavailable right now. Your coins are unchanged.';
      }
    });
  }

  void _hideOffer() {
    if (!mounted) return;
    setState(() {
      _offerHidden = true;
      _flowState = _PayoutDoubleFlowState.ready;
      _message = null;
    });
  }

  List<String> get _popupRaceIds => widget.races
      .map((race) => race['id'])
      .whereType<String>()
      .where((id) => id.isNotEmpty)
      .toList(growable: false);

  int get _displayedPayoutCoins => widget.races.fold<int>(0, (sum, race) {
    final raw = race['myPayoutCoins'];
    return sum + (raw is num && raw > 0 ? raw.toInt() : 0);
  });

  @override
  Widget build(BuildContext context) {
    final races = widget.races;
    final single = races.length == 1;
    // Celebrate a top-3 finish — or, for team races, a real team WIN
    // (TR-807: ties and losses never confetti; race finishes are the one
    // approved confetti moment).
    final placedTop3 = races.any(raceCountsAsReviewHappyMoment);
    return PopScope(
      canPop: false,
      onPopInvokedWithResult: (didPop, _) {
        if (!didPop) _dismiss();
      },
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            Positioned.fill(
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 2.5, sigmaY: 2.5),
                child: ColoredBox(
                  color: AppColors.of(context).roofDark.withValues(alpha: 0.54),
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
                          child: GameContainer(
                            padding: const EdgeInsets.fromLTRB(18, 18, 18, 18),
                            frameColor: AppColors.of(context).accent,
                            surfaceColor: AppColors.of(context).parchmentLight,
                            glowColor: AppColors.of(context).coinMid,
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  single ? 'RACE FINISHED' : 'RACES FINISHED',
                                  textAlign: TextAlign.center,
                                  style: HomeText.display(
                                    size: 28,
                                    color: AppColors.of(context).ink,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  single
                                      ? 'Here\'s how you did.'
                                      : '${races.length} of your races wrapped up.',
                                  textAlign: TextAlign.center,
                                  style: HomeText.body(
                                    size: 13,
                                    color: AppColors.of(context).muted,
                                    weight: FontWeight.w700,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                for (var i = 0; i < races.length; i++) ...[
                                  if (i > 0) const SizedBox(height: 10),
                                  _ResultCard(race: races[i]),
                                ],
                                if (_shouldShowRewardPanel) ...[
                                  const SizedBox(height: 14),
                                  _buildRewardPanel(context),
                                ],
                                const SizedBox(height: 18),
                                PillButton(
                                  key: widget.canStartNextRace
                                      ? const Key('results-start-next-race')
                                      : null,
                                  label: widget.canStartNextRace
                                      ? 'START YOUR NEXT RACE'
                                      : 'CONTINUE',
                                  variant: PillButtonVariant.primary,
                                  fullWidth: true,
                                  // TODO(ads-interstitial): frequency-capped
                                  // interstitial fires after this pop (see ADS_TODO.md)
                                  onPressed: () => _dismiss(
                                    widget.canStartNextRace ? true : null,
                                  ),
                                ),
                                if (widget.canStartNextRace) ...[
                                  const SizedBox(height: 8),
                                  TextButton(
                                    key: const Key('results-nice-secondary'),
                                    onPressed: () => _dismiss(false),
                                    child: Text(
                                      'NICE',
                                      style: PixelText.body(
                                        size: 13,
                                        color: AppColors.of(context).textMid,
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
                // Screen-bottom trackside footer (same treatment as the
                // leaderboard/shop tabs) instead of a banner nested in the card;
                // collapses to zero size when adless.
                const AdBannerSlot(withBottomSafeArea: true),
              ],
            ),
            if (placedTop3) const Positioned.fill(child: CelebrationConfetti()),
          ],
        ),
      ),
    );
  }

  bool get _shouldShowRewardPanel =>
      !_offerHidden && _offer != null && _dependenciesAvailable;

  Widget _buildRewardPanel(BuildContext context) {
    final offer = _offer!;
    final earned = _flowState == _PayoutDoubleFlowState.earned;
    final flat = offer.isFlat50;
    final bonus = earned
        ? _earnedBonusCoins ?? offer.bonusCoins
        : offer.bonusCoins;
    final base = earned ? _earnedBaseCoins ?? offer.baseCoins : offer.baseCoins;
    final qualifyingDiffers = _displayedPayoutCoins != offer.baseCoins;
    final String title;
    final String body;
    if (flat) {
      if (earned) {
        title = '+$bonus COINS EARNED';
        body = 'Your verified flat bonus is in your coin balance.';
      } else {
        final perRace = offer.raceIds.length > 1;
        title = perRace ? 'FLAT +50 COINS PER RACE' : 'FLAT +50 COINS';
        body = perRace
            ? 'Watch one ad to earn a flat 50-coin bonus for each race.'
            : 'Watch one ad to earn a flat 50-coin bonus.';
      }
    } else if (earned) {
      title = qualifyingDiffers
          ? '$base QUALIFYING PRIZES + $bonus AD BONUS'
          : '$base PAYOUT + $bonus AD BONUS';
      body = 'Your verified race bonus is in your coin balance.';
    } else if (offer.isFullDouble) {
      title = 'DOUBLE +$bonus COINS';
      body = qualifyingDiffers
          ? 'Watch one ad to get another $bonus on qualifying race prizes.'
          : 'Watch one ad to get another $bonus.';
    } else if (offer.isMaximumPartial) {
      title = 'GET THE MAX +$bonus BONUS';
      body = 'Your qualifying race prizes earn the maximum ad bonus.';
    } else {
      title = 'GET +$bonus BONUS COINS';
      body =
          'Watch one ad to earn $bonus bonus coins on your qualifying race prizes.';
    }

    final palette = AppColors.of(context);
    final reduceMotion =
        MediaQuery.maybeOf(context)?.disableAnimations ?? false;
    final actionSemanticsLabel = switch (_flowState) {
      _PayoutDoubleFlowState.loading =>
        flat
            ? 'Loading ad for $bonus flat bonus coins.'
            : 'Loading ad for $bonus bonus coins.',
      _PayoutDoubleFlowState.verifying =>
        flat
            ? 'Verifying $bonus flat bonus coins.'
            : 'Verifying $bonus bonus coins.',
      _PayoutDoubleFlowState.ready when _earnedCallbackReceived =>
        flat
            ? 'Retry verification for $bonus flat bonus coins.'
            : 'Retry verification for $bonus bonus coins.',
      _ =>
        flat
            ? 'Watch an ad to earn $bonus flat bonus coins.'
            : 'Watch an ad to earn $bonus bonus coins on your qualifying race prizes.',
    };
    final announceActionState =
        _flowState == _PayoutDoubleFlowState.loading ||
        _flowState == _PayoutDoubleFlowState.verifying ||
        _earnedCallbackReceived;
    final panel = Container(
      key: const Key('race-payout-double-panel'),
      padding: const EdgeInsets.fromLTRB(14, 12, 14, 14),
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            palette.coinLight.withValues(alpha: 0.28),
            palette.parchmentDark,
          ],
          begin: Alignment.topCenter,
          end: Alignment.bottomCenter,
        ),
        border: Border.all(color: palette.coinEdge, width: 2),
        borderRadius: BorderRadius.circular(10),
        boxShadow: [
          BoxShadow(
            color: palette.coinEdge.withValues(alpha: 0.2),
            offset: const Offset(0, 3),
            blurRadius: 0,
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              if (earned) ...[
                SpinningCoin(size: 20, animate: !reduceMotion),
                const SizedBox(width: 7),
              ],
              Flexible(
                child: AnimatedSwitcher(
                  duration: reduceMotion
                      ? Duration.zero
                      : const Duration(milliseconds: 240),
                  child: Text(
                    title,
                    key: ValueKey<String>(title),
                    textAlign: TextAlign.center,
                    // Keep the offer headline in the same readable display
                    // family as the rest of the results surface. Pixel
                    // number lettering was too thin/low-contrast here,
                    // especially against the gold gradient.
                    style: HomeText.title(size: 16, color: palette.textDark),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 5),
          Text(
            body,
            textAlign: TextAlign.center,
            style: HomeText.body(
              size: 13,
              color: palette.textDark,
              weight: FontWeight.w700,
            ),
          ),
          if (!earned) ...[
            const SizedBox(height: 12),
            Semantics(
              key: const Key('race-payout-double-semantics'),
              container: true,
              button: true,
              enabled: !_flowBusy,
              liveRegion: announceActionState,
              excludeSemantics: true,
              label: actionSemanticsLabel,
              child: PillButton(
                key: const Key('race-payout-double-action'),
                label: _flowState == _PayoutDoubleFlowState.loading
                    ? 'LOADING AD…'
                    : _flowState == _PayoutDoubleFlowState.verifying
                    ? 'VERIFYING…'
                    : _earnedCallbackReceived
                    ? 'RETRY +$bonus BONUS'
                    : flat && offer.raceIds.length > 1
                    ? 'WATCH AD · +50 COINS PER RACE'
                    : 'WATCH AD · +$bonus COINS',
                icon: Icons.play_circle_fill_rounded,
                // This is the primary action on the results screen. The
                // gold decision treatment made the label difficult to read
                // and did not match the app-wide action hierarchy.
                variant: PillButtonVariant.primary,
                fullWidth: true,
                onPressed: _flowBusy ? null : _startPayoutDouble,
              ),
            ),
          ],
          if (_message != null) ...[
            const SizedBox(height: 10),
            Semantics(
              liveRegion: true,
              label: _message,
              child: Text(
                _message!,
                key: const Key('race-payout-double-message'),
                textAlign: TextAlign.center,
                style: HomeText.body(
                  size: 13,
                  color: palette.textDark,
                  weight: FontWeight.w800,
                ),
              ),
            ),
          ],
        ],
      ),
    );
    return Semantics(
      key: const Key('race-payout-double-panel-semantics'),
      container: true,
      liveRegion: earned,
      excludeSemantics: earned,
      label: earned
          ? flat
                ? '+$bonus flat bonus coins awarded.'
                : '$base qualifying race prize coins plus $bonus ad bonus coins awarded.'
          : null,
      child: panel,
    );
  }
}

/// One finished race: name, the user's place, winner, and payout coins.
class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.race});

  final Map<String, dynamic> race;

  /// Top-3 finishers for the podium, or null when this payload can't feed one
  /// (no `podium` array, or fewer than two actual finishers). Never throws on
  /// a shape it doesn't recognise.
  List<PodiumFinisher>? _podiumFinishers() {
    final raw = race['podium'];
    if (raw is! List) return null;
    final rows = raw
        .whereType<Map>()
        .map((e) => e.cast<String, dynamic>())
        .toList();
    if (!RacePodium.canRender(RacePodium.occupantCount(rows))) return null;
    return RacePodium.finishersFromParticipants(
      orderRaceParticipantsForDisplay(rows),
      payoutTiers: parsePayoutTiers(race),
    );
  }

  @override
  Widget build(BuildContext context) {
    final name = race['name'] as String? ?? 'Race';
    final participantCount = (race['participantCount'] as num?)?.toInt() ?? 0;
    final myPlacement = (race['myPlacement'] as num?)?.toInt();
    final payoutCoins = (race['myPayoutCoins'] as num?)?.toInt() ?? 0;
    final winner = race['winner'] as Map<String, dynamic>?;
    final winnerName = winner?['displayName'] as String?;

    // TR-807: team-framed result. Tie = winnerTeam null on a completed team
    // race (TR-404). All reads defensive — old payloads have none of this.
    if (TeamRace.isTeamRace(race)) {
      return _buildTeamResult(
        context: context,
        payoutCoins: payoutCoins,
        raceName: name,
      );
    }

    final placeText = myPlacement == null
        ? 'Did not finish'
        : participantCount > 0
        ? '${formatOrdinal(myPlacement)} of $participantCount'
        : formatOrdinal(myPlacement);

    // Item 4 — the podium, when this payload can feed one.
    //
    // The completed-bucket race map served by `GET /races` is gaining a
    // `podium` array (top finishers with displayName/totalSteps/accessories);
    // it previously carried only `winner`, `myPlacement`, `participantCount`
    // and `payoutTiers`. Read defensively: against a backend that predates the
    // field this stays null and the card renders exactly as it always has, so
    // there is no ordering dependency between the two deploys.
    final podiumFinishers = _podiumFinishers();

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentDark,
        border: Border.all(color: AppColors.of(context).coinDark, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            name,
            style: PixelText.title(
              size: 15,
              color: AppColors.of(context).textDark,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          if (podiumFinishers != null) ...[
            const SizedBox(height: 10),
            // The screen already fires the shared confetti for a top-3 finish,
            // so the podium must not fire a second burst on top of it.
            RacePodium(finishers: podiumFinishers),
          ],
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                myPlacement == 1
                    ? Icons.emoji_events_rounded
                    : Icons.flag_rounded,
                size: 18,
                color: myPlacement == 1
                    ? AppColors.of(context).coinDark
                    : AppColors.of(context).textMid,
              ),
              const SizedBox(width: 6),
              Text(
                'YOU PLACED',
                style: PixelText.body(
                  size: 11,
                  color: AppColors.of(context).textMid,
                ),
              ),
              const Spacer(),
              Text(
                placeText.toUpperCase(),
                style: PixelText.number(
                  size: 14,
                  color: AppColors.of(context).textDark,
                ),
              ),
            ],
          ),
          if (winnerName != null && winnerName.isNotEmpty) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                Icon(
                  Icons.military_tech_rounded,
                  size: 18,
                  color: AppColors.of(context).textMid,
                ),
                const SizedBox(width: 6),
                Text(
                  'WINNER',
                  style: PixelText.body(
                    size: 11,
                    color: AppColors.of(context).textMid,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    atName(winnerName),
                    textAlign: TextAlign.right,
                    style: PixelText.title(
                      size: 13,
                      color: AppColors.of(context).textDark,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (payoutCoins > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SpinningCoin(size: 18),
                const SizedBox(width: 6),
                Text(
                  'PAYOUT',
                  style: PixelText.body(
                    size: 11,
                    color: AppColors.of(context).textMid,
                  ),
                ),
                const Spacer(),
                Text(
                  '+$payoutCoins',
                  style: PixelText.number(
                    size: 14,
                    color: AppColors.of(context).coinDark,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// TR-807: team-framed variant — outcome banner (VICTORY / DEFEAT / tie
  /// refund copy), winning team plaque + members, and the user's payout.
  Widget _buildTeamResult({
    required BuildContext context,
    required int payoutCoins,
    required String raceName,
  }) {
    final winnerTeam = TeamRace.winnerTeam(race);
    final myTeam = parseRaceTeam(race['myTeam']);
    final isTie = winnerTeam == null;
    final won = !isTie && myTeam != null && myTeam == winnerTeam;

    final participants =
        (race['participants'] as List?)?.cast<Map<String, dynamic>>() ??
        const <Map<String, dynamic>>[];
    final winnerMembers = winnerTeam == null
        ? const <Map<String, dynamic>>[]
        : TeamRace.membersOf(participants, winnerTeam);

    final outcomeColor = isTie
        ? AppColors.of(context).textMid
        : won
        ? AppColors.of(context).successText
        : AppColors.of(context).error;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: AppColors.of(context).parchmentDark,
        border: Border.all(color: AppColors.of(context).coinDark, width: 2),
        borderRadius: BorderRadius.circular(10),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(
            raceName,
            style: PixelText.title(
              size: 15,
              color: AppColors.of(context).textDark,
            ),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Icon(
                isTie
                    ? Icons.handshake_rounded
                    : won
                    ? Icons.emoji_events_rounded
                    : Icons.flag_rounded,
                size: 18,
                color: isTie ? AppColors.of(context).textMid : outcomeColor,
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  isTie ? 'It’s a tie. Buy-ins refunded' : 'YOUR TEAM',
                  style: PixelText.body(
                    size: 11,
                    color: AppColors.of(context).textMid,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isTie)
                Text(
                  won ? 'VICTORY' : 'DEFEAT',
                  style: PixelText.number(size: 14, color: outcomeColor),
                ),
            ],
          ),
          if (winnerTeam != null) ...[
            const SizedBox(height: 6),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Icons.military_tech_rounded,
                  size: 18,
                  color: TeamRace.textColorOn(winnerTeam, context),
                ),
                const SizedBox(width: 6),
                Text(
                  'WINNERS',
                  style: PixelText.body(
                    size: 11,
                    color: AppColors.of(context).textMid,
                  ),
                ),
                const SizedBox(width: 6),
                Expanded(
                  child: Text(
                    [
                      TeamRace.teamName(race, winnerTeam).toUpperCase(),
                      if (winnerMembers.isNotEmpty)
                        winnerMembers
                            .map(
                              (m) =>
                                  atName(m['displayName'] as String? ?? '???'),
                            )
                            .join(', '),
                    ].join(': '),
                    textAlign: TextAlign.right,
                    style: PixelText.title(
                      size: 12,
                      // P3 (item 3): team chrome colour used as text.
                      color: TeamRace.textColorOn(winnerTeam, context),
                    ),
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                  ),
                ),
              ],
            ),
          ],
          if (payoutCoins > 0) ...[
            const SizedBox(height: 6),
            Row(
              children: [
                const SpinningCoin(size: 18),
                const SizedBox(width: 6),
                Text(
                  'PAYOUT',
                  style: PixelText.body(
                    size: 11,
                    color: AppColors.of(context).textMid,
                  ),
                ),
                const Spacer(),
                Text(
                  '+$payoutCoins',
                  style: PixelText.number(
                    size: 14,
                    color: AppColors.of(context).coinDark,
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }
}
