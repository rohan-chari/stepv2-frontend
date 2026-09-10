/// UI contracts only. Store adapters supply verified state and localized prices.
enum BillingStatus { free, trial, active, expired }

enum BillingPlan { monthly, annual, permanent }

enum BillingOperationStatus { idle, loading, pending, success, failed }

enum BillingDisposition { success, error, cancelled, pending, notice }

enum RerollFunding { credits, coins, ad }

class CoinPackOffer {
  final String id;
  final int coins;
  final String price;
  final String? highlight;
  const CoinPackOffer({
    required this.id,
    required this.coins,
    required this.price,
    this.highlight,
  });
  static const previewOffers = [
    CoinPackOffer(id: 'coins_500', coins: 500, price: r'$0.99'),
    CoinPackOffer(
      id: 'coins_2800',
      coins: 3000,
      price: r'$4.99',
      highlight: 'EXTRA COINS',
    ),
    CoinPackOffer(
      id: 'coins_6000',
      coins: 7500,
      price: r'$9.99',
      highlight: 'BEST VALUE',
    ),
  ];
}

class BillingSubscription {
  final bool givesAccess;
  final BillingStatus status;
  final BillingPlan? plan;
  final DateTime? accessUntil;
  final bool renews;
  const BillingSubscription({
    required this.givesAccess,
    required this.status,
    this.plan,
    this.accessUntil,
    this.renews = false,
  });
}

class BillingSnapshot {
  final BillingStatus status;
  final BillingPlan? plan;
  final int paidCredits;
  final int trialCredits;
  final int coins;
  final DateTime? accessUntil;
  final bool renews;
  final DateTime? nextRewardAt;
  final BillingSubscription? subscription;
  final int? discountPercent;

  /// Explicit verified backend access, including a store billing grace period.
  /// Null preserves the legacy status-based presentation contract.
  final bool? givesAccess;
  final BillingOperationStatus operationStatus;
  final String? message;
  const BillingSnapshot({
    this.status = BillingStatus.free,
    this.plan,
    this.paidCredits = 0,
    this.trialCredits = 0,
    this.coins = 0,
    this.accessUntil,
    this.renews = true,
    this.nextRewardAt,
    this.subscription,
    this.discountPercent,
    this.givesAccess,
    this.operationStatus = BillingOperationStatus.idle,
    this.message,
  });
  bool get isPermanent => isMember && plan == BillingPlan.permanent;
  bool get hasSubscription =>
      subscription != null ||
      (isMember && (plan == BillingPlan.monthly || plan == BillingPlan.annual));
  bool get isTrial => status == BillingStatus.trial;
  int get effectiveDiscountPercent => isMember ? (discountPercent ?? 15) : 0;
  bool get isMember =>
      givesAccess ??
      (status == BillingStatus.active || status == BillingStatus.trial);
  int get availableCredits =>
      paidCredits +
      (isMember && status == BillingStatus.trial ? trialCredits : 0);
  bool get busy =>
      operationStatus == BillingOperationStatus.loading ||
      operationStatus == BillingOperationStatus.pending;
}

class BillingResult {
  final bool success;
  final String message;
  final BillingDisposition? _disposition;
  BillingDisposition get disposition =>
      _disposition ??
      (success ? BillingDisposition.success : BillingDisposition.error);
  const BillingResult({
    required this.success,
    required this.message,
    BillingDisposition? disposition,
  }) : _disposition = disposition;
}

class BillingRerollResult extends BillingResult {
  final List<Map<String, dynamic>> rows;
  const BillingRerollResult({
    required super.success,
    required super.message,
    this.rows = const [],
  });
}

String billingCoinLabel(int coins) => coins.toString().replaceAllMapped(
  RegExp(r'(\d)(?=(\d{3})+(?!\d))'),
  (m) => '${m[1]},',
);

class StorePlanOffer {
  final BillingPlan plan;
  final String price;
  final int trialDays;
  const StorePlanOffer({
    required this.plan,
    required this.price,
    this.trialDays = 0,
  });
  static const previewOffers = [
    StorePlanOffer(plan: BillingPlan.monthly, price: r'$4.99', trialDays: 7),
    StorePlanOffer(plan: BillingPlan.permanent, price: r'$19.99'),
  ];
}

class BillingCosmetic {
  final String month;
  final String name;
  final String assetKey;
  final String slot;
  final int animationFrames;
  const BillingCosmetic({
    required this.month,
    required this.name,
    required this.assetKey,
    required this.slot,
    this.animationFrames = 1,
  });
}
