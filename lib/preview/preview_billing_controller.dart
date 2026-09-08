import '../models/billing.dart';
import '../services/auth_service.dart';
import '../services/billing_controller.dart';

enum PreviewBillingScenario {
  free,
  trial,
  monthly,
  annual,
  permanent,
  permanentWithMonthly,
  expired,
  empty,
}

/// Standalone preview identity. It never loads credentials or writes preferences.
class PreviewBillingAuth extends AuthService {
  PreviewBillingAuth() {
    applyBackendUser({
      'id': 'billing-preview-user',
      'displayName': 'Rohan',
      'coins': 350,
      'shopTutorialCompletedAt': '2026-09-01T00:00:00Z',
    });
  }
  void announce() => notifyListeners();
  int balance = 350;
  int _previewHeldCoins = 0;
  @override
  int get heldCoins => _previewHeldCoins;
  @override
  Future<void> updateHeldCoins(int heldCoins) async {
    _previewHeldCoins = heldCoins;
    notifyListeners();
  }

  @override
  String get authToken => 'offline-billing-preview';
  @override
  String get userId => 'billing-preview-user';
  @override
  String get displayName => 'Rohan';
  @override
  String? get profilePhotoUrl => null;
  @override
  int get coins => balance;
  @override
  bool get hasShopTutorialServerState => true;
  @override
  String get shopTutorialCompletedAt => '2026-09-01T00:00:00Z';
  @override
  Future<void> updateCoins(int coins) async {
    if (balance == coins) return;
    balance = coins;
    notifyListeners();
  }
}

/// In-memory examples only. Never constructed by the ordinary app entrypoint.
class PreviewBillingController extends BillingController {
  PreviewBillingController() {
    auth.addListener(notifyListeners);
  }
  final PreviewBillingAuth auth = PreviewBillingAuth();
  BillingStatus _status = BillingStatus.free;
  BillingPlan? _plan;
  int _paid = 0;
  int _trial = 0;
  bool _renews = true;
  DateTime? _nextRewardAt;
  BillingSubscription? _subscription;
  BillingOperationStatus _operation = BillingOperationStatus.idle;
  String? _message;
  bool failNextPurchase = false;
  bool pendNextPurchase = false;
  void Function()? _pending;
  final Set<String> ownedCosmetics = {};
  final Map<String, int> powerupInventory = {};
  final Map<String, Map<String, dynamic>> raceItems = {};
  int _example = 0;
  int _generation = 0;

  @override
  String get userId => auth.userId;
  @override
  bool get isPreview => true;
  @override
  bool supportsRace(String raceId) => raceId == 'billing-preview-race';
  @override
  List<CoinPackOffer> get coinPacks => CoinPackOffer.previewOffers;
  @override
  BillingSnapshot get snapshot => BillingSnapshot(
    status: _status,
    plan: _plan,
    coins: auth.coins,
    paidCredits: _paid,
    trialCredits: _trial,
    renews: _renews,
    nextRewardAt: _nextRewardAt,
    subscription: _subscription,
    accessUntil: _status == BillingStatus.free || _plan == BillingPlan.permanent
        ? null
        : DateTime.now().add(
            Duration(
              days: _status == BillingStatus.expired
                  ? -1
                  : _status == BillingStatus.trial
                  ? 7
                  : _plan == BillingPlan.annual
                  ? 365
                  : 30,
            ),
          ),
    operationStatus: _operation,
    message: _message,
  );

  void setScenario(PreviewBillingScenario scenario) {
    _generation++;
    _pending = null;
    failNextPurchase = false;
    pendNextPurchase = false;
    _operation = BillingOperationStatus.idle;
    _message = null;
    _paid = 0;
    _trial = 0;
    _plan = null;
    _nextRewardAt = null;
    _subscription = null;
    _renews = true;
    _status = BillingStatus.free;
    auth.balance = 350;
    ownedCosmetics.clear();
    powerupInventory.clear();
    raceItems.clear();
    if (scenario == PreviewBillingScenario.trial) {
      _status = BillingStatus.trial;
      _trial = 3;
      _plan = BillingPlan.monthly;
    } else if (scenario == PreviewBillingScenario.monthly ||
        scenario == PreviewBillingScenario.annual) {
      _status = BillingStatus.active;
      _plan = scenario == PreviewBillingScenario.monthly
          ? BillingPlan.monthly
          : BillingPlan.annual;
      _paid = _plan == BillingPlan.monthly ? 10 : 120;
      auth.balance += _plan == BillingPlan.monthly ? 500 : 6000;
      ownedCosmetics.add('wizard_hat');
    } else if (scenario == PreviewBillingScenario.permanent ||
        scenario == PreviewBillingScenario.permanentWithMonthly) {
      _status = BillingStatus.active;
      _plan = BillingPlan.permanent;
      _renews = false;
      _paid = 10;
      auth.balance += 500;
      _nextRewardAt = _nextMonth(DateTime.now().toUtc());
      if (scenario == PreviewBillingScenario.permanentWithMonthly) {
        _subscription = BillingSubscription(
          givesAccess: true,
          status: BillingStatus.active,
          plan: BillingPlan.monthly,
          accessUntil: _nextRewardAt,
          renews: true,
        );
      }
      ownedCosmetics.add('wizard_hat');
    } else if (scenario == PreviewBillingScenario.expired) {
      _status = BillingStatus.expired;
      _paid = 12;
      _plan = BillingPlan.monthly;
      _renews = false;
      ownedCosmetics.add('wizard_hat');
    } else if (scenario == PreviewBillingScenario.empty) {
      auth.balance = 0;
    }
    auth.announce();
  }

  void simulateNextFailure() {
    failNextPurchase = true;
    notifyListeners();
  }

  void simulateNextPending() {
    pendNextPurchase = true;
    notifyListeners();
  }

  void finishPending() {
    final action = _pending;
    if (action == null) return;
    _pending = null;
    action();
    _operation = BillingOperationStatus.success;
    _message = 'Preview purchase completed. No payment was taken.';
    notifyListeners();
  }

  Future<BillingResult> _perform(void Function() apply, String message) async {
    if (snapshot.busy) {
      return const BillingResult(
        success: false,
        message: 'A purchase is already pending.',
      );
    }
    final generation = _generation;
    _operation = BillingOperationStatus.loading;
    _message = null;
    notifyListeners();
    await Future<void>.delayed(const Duration(milliseconds: 180));
    if (generation != _generation) {
      return const BillingResult(success: false, message: 'Preview reset.');
    }
    if (failNextPurchase) {
      failNextPurchase = false;
      _operation = BillingOperationStatus.failed;
      _message = 'Preview purchase failed. Nothing was charged. Try again.';
      notifyListeners();
      return BillingResult(
        success: false,
        message: _message ?? 'Purchase failed.',
      );
    }
    if (pendNextPurchase) {
      pendNextPurchase = false;
      _pending = apply;
      _operation = BillingOperationStatus.pending;
      _message = 'Purchase pending. Use Complete pending in preview controls.';
      notifyListeners();
      return BillingResult(
        success: false,
        message: _message ?? 'Purchase pending.',
      );
    }
    apply();
    _operation = BillingOperationStatus.success;
    _message = message;
    notifyListeners();
    return BillingResult(success: true, message: message);
  }

  @override
  Future<BillingResult> buyCoins(CoinPackOffer pack) => _perform(() {
    auth.balance += pack.coins;
    auth.announce();
  }, '${billingCoinLabel(pack.coins)} preview coins added.');
  @override
  Future<BillingResult> startTrial(BillingPlan plan) =>
      plan != BillingPlan.monthly || snapshot.isMember
      ? Future.value(
          const BillingResult(
            success: false,
            message: 'Monthly trial unavailable.',
          ),
        )
      : _perform(() {
          _status = BillingStatus.trial;
          _plan = plan;
          _trial = 3;
          _renews = true;
        }, 'Your seven-day preview trial has started.');
  @override
  Future<BillingResult> subscribe(BillingPlan plan) =>
      plan != BillingPlan.monthly || snapshot.isPermanent
      ? Future.value(
          const BillingResult(
            success: false,
            message: 'This subscription is unavailable.',
          ),
        )
      : _perform(() {
          _status = BillingStatus.active;
          _plan = plan;
          _trial = 0;
          _renews = true;
          _paid += 10;
          auth.balance += 500;
          ownedCosmetics.add('wizard_hat');
          auth.announce();
        }, 'Bara+ is active in this preview. Your gifts are ready.');
  DateTime _nextMonth(DateTime date) {
    final lastDay = DateTime.utc(date.year, date.month + 2, 0).day;
    return DateTime.utc(
      date.year,
      date.month + 1,
      date.day.clamp(1, lastDay),
      date.hour,
      date.minute,
      date.second,
    );
  }

  @override
  List<StorePlanOffer> get plans =>
      snapshot.isPermanent ? const [] : StorePlanOffer.previewOffers;
  @override
  Future<BillingResult> buyPermanent() {
    if (snapshot.isPermanent) {
      return Future.value(
        const BillingResult(
          success: false,
          message: 'Permanent Bara+ is already owned.',
        ),
      );
    }
    final previous = snapshot;
    return _perform(() {
      _subscription = previous.hasSubscription
          ? BillingSubscription(
              givesAccess: true,
              status: previous.status,
              plan: previous.plan,
              accessUntil: previous.accessUntil,
              renews: previous.renews,
            )
          : null;
      final paidEnd = previous.isMember && !previous.isTrial
          ? previous.accessUntil
          : null;
      final delayed = paidEnd != null && paidEnd.isAfter(DateTime.now());
      _nextRewardAt = delayed
          ? paidEnd.toUtc()
          : _nextMonth(DateTime.now().toUtc());
      if (!delayed) {
        _paid += 10;
        auth.balance += 500;
      }
      _status = BillingStatus.active;
      _plan = BillingPlan.permanent;
      _renews = false;
      _trial = 0;
      ownedCosmetics.add('wizard_hat');
      auth.announce();
    }, 'Permanent Bara+ is owned in this preview. No real payment was taken.');
  }

  @override
  Future<BillingResult> restore() => _perform(
    () {},
    'Preview membership checked. Your coins and credits are unchanged.',
  );
  @override
  Future<BillingResult> cancelRenewal() => _perform(() {
    _renews = false;
    final subscription = _subscription;
    if (subscription != null) {
      _subscription = BillingSubscription(
        givesAccess: subscription.givesAccess,
        status: subscription.status,
        plan: subscription.plan,
        accessUntil: subscription.accessUntil,
        renews: false,
      );
    }
  }, 'Renewal stopped in this preview. Paid credits stay yours.');

  List<String> createBoxes(int count, {bool held = false}) {
    final ids = <String>[];
    for (var i = 0; i < count; i++) {
      final id = 'billing-box-${_example++}';
      raceItems[id] = {
        'id': id,
        'powerupId': id,
        'type': held && i == 1 ? 'POCKET_WATCH' : 'PROTEIN_SHAKE',
        'rarity': 'COMMON',
        'status': 'HELD',
        'upgradeLevel': 0,
        'rerolledAt': null,
        'usedAt': null,
        'autoActivated': false,
      };
      ids.add(id);
    }
    return ids;
  }

  @override
  Future<BillingRerollResult> reroll({
    required String raceId,
    required List<String> ids,
    required RerollFunding funding,
  }) async {
    if (!supportsRace(raceId) ||
        ids.isEmpty ||
        ids.toSet().length != ids.length ||
        ids.any(
          (id) =>
              !raceItems.containsKey(id) ||
              raceItems[id]?['rerolledAt'] != null,
        )) {
      return const BillingRerollResult(
        success: false,
        message: 'These boxes cannot be rerolled again.',
      );
    }
    if ((funding == RerollFunding.coins && auth.coins < 50) ||
        (funding == RerollFunding.credits && snapshot.availableCredits == 0)) {
      return const BillingRerollResult(
        success: false,
        message: 'Not enough coins or reroll credits.',
      );
    }
    if (snapshot.busy) {
      return const BillingRerollResult(
        success: false,
        message: 'Finish the pending purchase first.',
      );
    }
    if (funding == RerollFunding.coins) auth.balance -= 50;
    if (funding == RerollFunding.credits) {
      if (_status == BillingStatus.trial && _trial > 0) {
        _trial--;
      } else {
        _paid--;
      }
    }
    final rows = <Map<String, dynamic>>[];
    for (final id in ids) {
      final result = <String, dynamic>{
        ...?raceItems[id],
        'type': 'GHOST_PEPPER',
        'rarity': 'EPIC',
        'rerolledAt': DateTime.now().toIso8601String(),
      };
      raceItems[id] = result;
      rows.add(Map<String, dynamic>.from(result));
    }
    auth.announce();
    return BillingRerollResult(
      success: true,
      message: 'Preview reroll complete.',
      rows: rows,
    );
  }

  @override
  void dispose() {
    _generation++;
    auth.removeListener(notifyListeners);
    auth.dispose();
    super.dispose();
  }
}
