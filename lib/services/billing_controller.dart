import 'package:flutter/foundation.dart';
import '../models/billing.dart';

/// Injected purchase boundary. Presentation never grants wallet balances or
/// member benefits; the live implementation reconciles verified server state.
class PendingBillingFeedback {
  const PendingBillingFeedback(this.sequence, this.userId, this.result);
  final int sequence;
  final String userId;
  final BillingResult result;
}

abstract class BillingController extends ChangeNotifier {
  int _feedbackSequence = 0;
  PendingBillingFeedback? _pendingFeedback;
  PendingBillingFeedback? get pendingFeedback => _pendingFeedback;

  /// Terminal reconciliation of an earlier pending checkout. Widgets only
  /// consume this after originating that pending operation in the same session.
  @protected
  void publishPendingFeedback(BillingResult result) {
    _pendingFeedback = PendingBillingFeedback(
      ++_feedbackSequence,
      userId,
      result,
    );
    notifyListeners();
  }

  String get userId;
  bool get isPreview;
  bool get isAvailable => isPreview;
  bool get canShowMembership =>
      isAvailable || snapshot.isMember || canManageSubscription;
  int get rerollCoinCost => 50;
  List<StorePlanOffer> get plans =>
      isPreview ? StorePlanOffer.previewOffers : const [];
  BillingCosmetic? get cosmetic => null;
  String? get termsUrl => null;
  String? get privacyUrl => null;
  Future<void> refresh() async {}
  Future<BillingResult> openLegal(String url) async =>
      const BillingResult(success: false, message: 'Link unavailable.');
  BillingSnapshot get snapshot;
  bool supportsRace(String raceId) => false;
  List<CoinPackOffer> get coinPacks =>
      isPreview ? CoinPackOffer.previewOffers : const [];
  Future<BillingResult> buyCoins(CoinPackOffer pack);
  Future<BillingResult> startTrial(BillingPlan plan);
  Future<BillingResult> subscribe(BillingPlan plan);
  Future<BillingResult> buyPermanent() async => const BillingResult(
    success: false,
    message: 'Permanent Bara+ is unavailable.',
  );
  bool get canManageSubscription => snapshot.hasSubscription;
  bool get canChangePlan => false;
  Future<BillingResult> changePlan(BillingPlan plan) async =>
      const BillingResult(
        success: false,
        message: 'Plan changes are unavailable.',
      );
  Future<BillingResult> restore();
  Future<BillingResult> cancelRenewal();
  Future<RerollFunding?> pendingReroll({
    required String raceId,
    required List<String> ids,
  }) async => null;
  Future<BillingRerollResult> reroll({
    required String raceId,
    required List<String> ids,
    required RerollFunding funding,
  });
}
