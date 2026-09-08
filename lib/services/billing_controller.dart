import 'package:flutter/foundation.dart';
import '../models/billing.dart';

/// Injected purchase boundary. Presentation never grants wallet balances or
/// member benefits; the live implementation reconciles verified server state.
abstract class BillingController extends ChangeNotifier {
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
