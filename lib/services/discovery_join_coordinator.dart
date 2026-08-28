import 'package:flutter/material.dart';

import '../styles.dart';
import '../utils/funded_exposure_error_copy.dart';
import '../utils/team_race.dart';
import '../utils/tournament.dart';
import '../widgets/error_toast.dart';
import '../widgets/pill_button.dart';
import '../widgets/team_side_picker.dart';
import '../widgets/trail_sign.dart';
import 'auth_service.dart';
import 'backend_api_service.dart';

enum DiscoveryJoinTarget { race, tournament }

class DiscoveryJoinResult {
  const DiscoveryJoinResult({
    required this.id,
    required this.status,
    required this.target,
  });

  final String id;
  final String status;
  final DiscoveryJoinTarget target;
}

/// Shared public-discovery join flow used by PublicRacesScreen and Home.
/// Paid/funded, team-side, wallet refresh, and coded-error behavior lives in
/// one place so the compact Home card cannot accidentally bypass a safeguard.
class DiscoveryJoinCoordinator {
  const DiscoveryJoinCoordinator({
    required this.authService,
    required this.backendApiService,
  });

  final AuthService authService;
  final BackendApiService backendApiService;

  Future<DiscoveryJoinResult?> joinRace(
    BuildContext context,
    Map<String, dynamic> race,
  ) async {
    final token = authService.authToken;
    final id = _string(race['id']);
    if (token == null || token.isEmpty || id == null) return null;

    final funded = _hasCanonicalFundedPrizePool(race['prizePool']);
    final buyIn = funded ? 0 : _nonnegativeInt(race['buyInAmount']);
    if (buyIn > authService.coins) {
      showErrorToast(context, 'Not enough gold for this buy-in');
      return null;
    }
    if (buyIn > 0) {
      final confirmed = await _confirmBuyIn(
        context,
        buyIn: buyIn,
        tournament: false,
      );
      if (confirmed != true || !context.mounted) return null;
    }

    String? team;
    if (TeamRace.isTeamRace(race)) {
      team = await showTeamSidePicker(context: context, race: race);
      if (team == null || !context.mounted) return null;
    }

    try {
      final response = team == null
          ? await backendApiService.joinPublicRace(
              identityToken: token,
              raceId: id,
            )
          : await backendApiService.joinPublicRaceOnTeam(
              identityToken: token,
              raceId: id,
              team: team,
            );
      await _refreshWallet(token);
      final raceResult = response['race'];
      final status = raceResult is Map ? _string(raceResult['status']) : null;
      return DiscoveryJoinResult(
        id: id,
        status: status ?? _string(race['status']) ?? 'PENDING',
        target: DiscoveryJoinTarget.race,
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        showErrorToast(
          context,
          isActiveCompetitionLimitError(error)
              ? fundedExposureErrorCopy(error)
              : error.code != null
              ? teamRaceErrorCopy(error.code)
              : error.message,
        );
      }
    } catch (error) {
      if (context.mounted) showErrorToast(context, error.toString());
    }
    return null;
  }

  Future<DiscoveryJoinResult?> joinTournament(
    BuildContext context,
    Map<String, dynamic> tournament, {
    // Retained for call-site/API compatibility. Funding validity alone decides
    // whether a buy-in safeguard is suppressed; discovery category never does.
    required bool featured,
  }) async {
    final token = authService.authToken;
    final id = Tournament.id(tournament);
    if (token == null || token.isEmpty || id == null || id.isEmpty) return null;

    final buyIn = _hasCanonicalFundedPrizePool(tournament['prizePool'])
        ? 0
        : Tournament.buyInAmount(tournament);
    if (buyIn > authService.coins) {
      showErrorToast(context, 'Not enough gold for this buy-in');
      return null;
    }
    if (buyIn > 0) {
      final confirmed = await _confirmBuyIn(
        context,
        buyIn: buyIn,
        tournament: true,
      );
      if (confirmed != true || !context.mounted) return null;
    }

    try {
      final response = await backendApiService.joinTournament(
        identityToken: token,
        tournamentId: id,
      );
      if (!await _applyWallet(response)) await _refreshWallet(token);
      final payload = response['tournament'];
      final status = payload is Map ? _string(payload['status']) : null;
      return DiscoveryJoinResult(
        id: id,
        status: status ?? _string(tournament['status']) ?? 'PENDING',
        target: DiscoveryJoinTarget.tournament,
      );
    } on ApiException catch (error) {
      if (context.mounted) {
        showErrorToast(
          context,
          isActiveCompetitionLimitError(error)
              ? fundedExposureErrorCopy(error)
              : error.code != null
              ? tournamentErrorCopy(error.code)
              : error.message,
        );
      }
    } catch (error) {
      if (context.mounted) showErrorToast(context, error.toString());
    }
    return null;
  }

  Future<void> _refreshWallet(String token) async {
    try {
      final user = await backendApiService.fetchMe(identityToken: token);
      final coins = user['coins'];
      final held = user['heldCoins'];
      await authService.updateCoins(
        coins is num ? coins.toInt() : authService.coins,
      );
      await authService.updateHeldCoins(
        held is num ? held.toInt() : authService.heldCoins,
      );
    } catch (_) {
      // Joining already succeeded. Wallet refresh remains best effort exactly
      // as it was on the existing discovery screen.
    }
  }

  Future<bool> _applyWallet(Map<String, dynamic> response) async {
    final wallet = response['wallet'];
    if (wallet is! Map ||
        wallet['coins'] is! num ||
        wallet['heldCoins'] is! num) {
      return false;
    }
    await authService.updateCoins((wallet['coins'] as num).toInt());
    await authService.updateHeldCoins((wallet['heldCoins'] as num).toInt());
    return true;
  }

  Future<bool?> _confirmBuyIn(
    BuildContext context, {
    required int buyIn,
    required bool tournament,
  }) {
    return showDialog<bool>(
      context: context,
      builder: (dialogContext) => Dialog(
        backgroundColor: Colors.transparent,
        child: TrailSign(
          width: 320,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                '$buyIn GOLD BUY-IN',
                style: PixelText.title(
                  size: 18,
                  color: AppColors.of(dialogContext).textDark,
                ),
              ),
              const SizedBox(height: 12),
              Text(
                tournament
                    ? 'Your $buyIn gold is held until the bracket starts. You only get it back if the tournament is cancelled.'
                    : 'Your $buyIn gold is held until the race starts, then moves into the live pot. It returns only if the race is cancelled.',
                textAlign: TextAlign.center,
                style: PixelText.body(
                  size: 13.5,
                  color: AppColors.of(dialogContext).textMid,
                ),
              ),
              const SizedBox(height: 18),
              PillButton(
                label: 'NEVER MIND',
                variant: tournament
                    ? PillButtonVariant.primary
                    : PillButtonVariant.secondary,
                fullWidth: true,
                padding: tournament
                    ? const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                    : PillButton.defaultPadding,
                onPressed: () => Navigator.of(dialogContext).pop(false),
              ),
              const SizedBox(height: 10),
              PillButton(
                label: 'LOCK IT IN',
                variant: PillButtonVariant.accent,
                fullWidth: true,
                padding: tournament
                    ? const EdgeInsets.symmetric(horizontal: 24, vertical: 12)
                    : PillButton.defaultPadding,
                onPressed: () => Navigator.of(dialogContext).pop(true),
              ),
            ],
          ),
        ),
      ),
    );
  }

  String? _string(dynamic value) =>
      value is String && value.isNotEmpty ? value : null;
  int _nonnegativeInt(dynamic value) =>
      value is num && value >= 0 ? value.toInt() : 0;

  bool _hasCanonicalFundedPrizePool(dynamic raw) {
    if (raw is! Map || raw['funded'] != true) return false;
    return _nonnegativeWhole(raw['coins']) &&
        raw['projected'] is bool &&
        raw['atMax'] is bool &&
        _nonnegativeWhole(raw['playerCount']) &&
        _positiveWhole(raw['durationDays']) &&
        _positiveWhole(raw['durationPoints']) &&
        _positiveWhole(raw['coinUnit']) &&
        _positiveWhole(raw['maxCoins']);
  }

  bool _nonnegativeWhole(dynamic value) => value is int && value >= 0;
  bool _positiveWhole(dynamic value) => value is int && value > 0;
}
