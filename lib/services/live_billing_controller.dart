import 'dart:async';
import 'dart:convert';
import 'dart:math';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
import '../models/billing.dart';
import 'auth_service.dart';
import 'backend_api_service.dart';
import 'billing_controller.dart';
import 'store_billing_client.dart';

Map<String, dynamic> _map(Object? value) => value is Map
    ? value.map((key, value) => MapEntry(key.toString(), value))
    : {};
int _int(Object? value, [int fallback = 0]) =>
    value is num && value.isFinite && value >= 0 ? value.toInt() : fallback;
String? _string(Object? value) =>
    value is String && value.isNotEmpty ? value : null;

/// Account-bound native checkout and durable reconciliation. Never grants value.
class LiveBillingController extends BillingController {
  final AuthService auth;
  final BackendApiService api;
  final StoreBillingClient store;
  final String platform;
  LiveBillingController({
    required this.auth,
    required this.api,
    required this.store,
    required this.platform,
  }) {
    _user = auth.userId ?? '';
    _token = auth.authToken;
    auth.addListener(_authChanged);
    store.setOnCustomerInfoChanged(() => unawaited(refresh()));
  }
  String _user = '';
  String? _token;
  String? _identity;
  int _generation = 0;
  bool _disposed = false;
  bool _storeAvailable = false;
  bool _rerollSupported = false;
  int _cost = 50;
  bool _working = false;
  bool _loadingCatalog = false;
  Timer? _retry;
  Map<String, dynamic> _data = {};
  final Map<String, String> _productIds = {};
  List<CoinPackOffer> _packs = [];
  List<StorePlanOffer> _plans = [];
  BillingOperationStatus _operation = BillingOperationStatus.idle;
  String? _message;
  @override
  String get userId => _user;
  @override
  bool get isPreview => false;
  @override
  bool get isAvailable =>
      _storeAvailable &&
      store.configured &&
      (_packs.isNotEmpty || _plans.isNotEmpty);
  @override
  bool supportsRace(String raceId) =>
      _rerollSupported && _user.isNotEmpty && raceId.isNotEmpty;
  @override
  int get rerollCoinCost => _cost;
  @override
  List<CoinPackOffer> get coinPacks => _packs;
  @override
  List<StorePlanOffer> get plans => snapshot.isPermanent ? const [] : _plans;
  @override
  BillingCosmetic? get cosmetic {
    final row = _map(_data['cosmetic']),
        item = _map(_map(_data['cosmetic'])['item']);
    final month = _string(row['month']),
        name = _string(item['name']),
        key = _string(item['assetKey']),
        slot = _string(item['slot']);
    if (row['owned'] != true ||
        month == null ||
        name == null ||
        key == null ||
        slot == null) {
      return null;
    }
    return BillingCosmetic(
      month: month,
      name: name,
      assetKey: key,
      slot: slot,
      animationFrames: _int(
        _map(item['renderMetadata'])['animationFrames'],
        1,
      ).clamp(1, 120),
    );
  }

  @override
  String? get termsUrl => _https(_data['termsUrl']);
  @override
  String? get privacyUrl => _https(_data['privacyUrl']);
  String? _https(Object? raw) {
    final value = _string(raw);
    final uri = value == null ? null : Uri.tryParse(value);
    return uri?.scheme == 'https' && uri!.host.isNotEmpty ? value : null;
  }

  @override
  BillingSnapshot get snapshot {
    final member = _map(_data['membership']);
    final credits = _map(_data['credits']);
    final subscription = _map(member['subscription']);
    var status =
        BillingStatus.values
            .where((e) => e.name == member['status'])
            .firstOrNull ??
        BillingStatus.free;
    final expiry = DateTime.tryParse(_string(credits['trialExpiresAt']) ?? '');
    final accessUntil = DateTime.tryParse(_string(member['accessUntil']) ?? '');
    final givesAccess = switch (member['givesAccess']) {
      bool value => value,
      _ => null,
    };
    if ((status == BillingStatus.active || status == BillingStatus.trial) &&
        (givesAccess == false ||
            (givesAccess != true &&
                (accessUntil == null ||
                    !accessUntil.isAfter(DateTime.now()))))) {
      status = BillingStatus.expired;
    }
    return BillingSnapshot(
      status: status,
      plan: BillingPlan.values
          .where((e) => e.name == member['plan'])
          .firstOrNull,
      coins: auth.coins,
      paidCredits: _int(credits['paid']),
      trialCredits: expiry == null || !expiry.isAfter(DateTime.now())
          ? 0
          : _int(credits['trial']),
      accessUntil: accessUntil,
      nextRewardAt: DateTime.tryParse(_string(member['nextRewardAt']) ?? ''),
      subscription: subscription.isEmpty
          ? null
          : BillingSubscription(
              givesAccess: subscription['givesAccess'] == true,
              status:
                  BillingStatus.values
                      .where((e) => e.name == subscription['status'])
                      .firstOrNull ??
                  BillingStatus.free,
              plan: [
                BillingPlan.monthly,
                BillingPlan.annual,
              ].where((e) => e.name == subscription['plan']).firstOrNull,
              accessUntil: DateTime.tryParse(
                _string(subscription['accessUntil']) ?? '',
              ),
              renews: subscription['renews'] == true,
            ),
      renews: member['renews'] == true,
      givesAccess: givesAccess,
      discountPercent:
          (givesAccess ??
              (status == BillingStatus.active || status == BillingStatus.trial))
          ? _int(member['discountPercent']).clamp(0, 100)
          : 0,
      operationStatus:
          _loadingCatalog && _operation != BillingOperationStatus.pending
          ? BillingOperationStatus.loading
          : _operation,
      message: _message,
    );
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  bool _current(int generation) =>
      !_disposed &&
      generation == _generation &&
      auth.userId == _user &&
      auth.authToken == _token;
  void _authChanged() {
    if (auth.userId == _user && auth.authToken == _token) {
      _notify();
      return;
    }
    _generation++;
    _retry?.cancel();
    _working = false;
    _loadingCatalog = false;
    _user = auth.userId ?? '';
    _token = auth.authToken;
    _identity = null;
    _data = {};
    _packs = [];
    _plans = [];
    _productIds.clear();
    _storeAvailable = false;
    _rerollSupported = false;
    _operation = BillingOperationStatus.idle;
    _message = null;
    _notify();
    unawaited(refresh());
  }

  String _syncKey(String user) => 'billing.sync.v1.$platform.$user';
  Future<void> _apply(Map<String, dynamic> data, int generation) async {
    if (!_current(generation)) return;
    _data = data;
    final reroll = _map(data['reroll']);
    _rerollSupported =
        data['contract'] == 'bara-billing-v1' &&
        reroll['supported'] == true &&
        _int(reroll['coinCost']) > 0;
    _cost = _int(reroll['coinCost'], 50);
    if (data['coins'] is num) await auth.updateCoins(_int(data['coins']));
    if (_current(generation)) _notify();
  }

  @override
  Future<void> refresh() async {
    final generation = _generation, token = _token;
    if (_working ||
        token == null ||
        token.isEmpty ||
        _user.isEmpty ||
        (platform != 'ios' && platform != 'android')) {
      return;
    }
    _working = true;
    _loadingCatalog = true;
    _notify();
    try {
      final data = await api.fetchBillingBootstrap(
        identityToken: token,
        platform: platform,
      );
      if (!_current(generation)) return;
      if (data['contract'] != 'bara-billing-v1') {
        _data = {};
        _rerollSupported = false;
        _storeAvailable = false;
        _packs = [];
        _plans = [];
        return;
      }
      await _apply(data, generation);
      if (!_current(generation)) return;
      _identity = _string(_map(data['identity'])['appUserId']);
      _storeAvailable =
          data['available'] == true && _identity != null && store.configured;
      _packs = [];
      _plans = [];
      _productIds.clear();
      if (_storeAvailable) {
        await store.identify(_identity!);
        if (!_current(generation)) return;
        final catalog = data['products'] is List
            ? (data['products'] as List).map(_map).toList()
            : <Map<String, dynamic>>[];
        final coins = catalog
            .where(
              (p) =>
                  p['kind'] == 'coins' ||
                  (p['kind'] == 'non_consumable' &&
                      p['plan'] == 'permanent' &&
                      p['id'] == 'plus_permanent'),
            )
            .map((p) => _string(p['storeProductId']))
            .whereType<String>()
            .toList();
        final subscriptions = catalog
            .where((p) => p['kind'] == 'subscription')
            .map((p) => _string(p['storeProductId']))
            .whereType<String>()
            .toList();
        final products = await store.products(coins, subscriptions);
        if (!_current(generation)) return;
        for (final item in catalog) {
          final id = _string(item['id']),
              storeId = _string(item['storeProductId']);
          final product = products.where((p) => p.id == storeId).firstOrNull;
          if (id == null || product == null || product.price.isEmpty) continue;
          _productIds[id] = product.id;
          if (item['kind'] == 'coins' && _int(item['coins']) > 0) {
            _packs.add(
              CoinPackOffer(
                id: id,
                coins: _int(item['coins']),
                price: product.price,
              ),
            );
          }
          final plan = BillingPlan.values
              .where((p) => p.name == item['plan'])
              .firstOrNull;
          if (((item['kind'] == 'subscription' &&
                      plan == BillingPlan.monthly &&
                      id == 'plus_monthly') ||
                  (item['kind'] == 'non_consumable' &&
                      plan == BillingPlan.permanent &&
                      id == 'plus_permanent')) &&
              plan != null &&
              termsUrl != null &&
              privacyUrl != null) {
            _plans.add(
              StorePlanOffer(
                plan: plan,
                price: product.price,
                trialDays: plan == BillingPlan.monthly ? product.trialDays : 0,
              ),
            );
          }
        }
        final prefs = await SharedPreferences.getInstance();
        if (!_current(generation)) return;
        final rawPending = prefs.getString(_syncKey(_user));
        final pending = _pendingRecord(rawPending);
        var hint = _string(pending['transactionId']);
        final nativeIntent = pending['kind'] == 'purchase';
        if (nativeIntent && hint == null) {
          final productId = _string(pending['productId']);
          final baseline = pending['baseline'];
          if (pending['identity'] == _identity &&
              productId != null &&
              baseline is List &&
              baseline.every((id) => id is String && id.isNotEmpty)) {
            try {
              final ids = await store.transactionIds(productId);
              if (!_current(generation)) return;
              hint = ids
                  .where((id) => id.isNotEmpty && !baseline.contains(id))
                  .firstOrNull;
              if (hint != null) {
                await prefs.setString(
                  _syncKey(_user),
                  jsonEncode({...pending, 'transactionId': hint}),
                );
              }
            } catch (_) {
              /* Unavailable native history never resolves an intent. */
            }
          }
        }
        if (!_current(generation)) return;
        // Native evidence selects an exact transaction; only the backend may
        // verify it. Empty history reconciliation cannot complete native pending.
        await _sync(
          generation,
          hint,
          rawPending != null,
          unresolvedNative: nativeIntent && hint == null,
        );
      }
    } catch (error) {
      if (_current(generation)) {
        if (error is ApiException && error.statusCode == 404) {
          _data = {};
          _rerollSupported = false;
          _identity = null;
        }
        _storeAvailable = false;
        _packs = [];
        _plans = [];
      }
    } finally {
      if (_current(generation)) {
        _working = false;
        _loadingCatalog = false;
        _notify();
      }
    }
  }

  Map<String, dynamic> _pendingRecord(String? raw) {
    if (raw == null) return {};
    try {
      return _map(jsonDecode(raw));
    } catch (_) {
      return {'kind': 'purchase'};
    }
  }

  Future<BillingResult> _sync(
    int generation,
    String? hint,
    bool pending, {
    bool unresolvedNative = false,
  }) async {
    final user = _user, token = _token;
    if (!_current(generation) || token == null) {
      return const BillingResult(success: false, message: 'Account changed.');
    }
    try {
      final data = await api.syncBilling(
        identityToken: token,
        platform: platform,
        transactionId: hint,
      );
      if (!_current(generation)) {
        return const BillingResult(success: false, message: 'Account changed.');
      }
      await _apply(data, generation);
      if (!_current(generation)) {
        return const BillingResult(success: false, message: 'Account changed.');
      }
      if (data['status'] == 'complete' && !unresolvedNative) {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(_syncKey(user));
        if (!_current(generation)) {
          return const BillingResult(
            success: false,
            message: 'Account changed.',
          );
        }
        _operation = BillingOperationStatus.success;
        _message = pending
            ? hint != null
                  ? 'Purchase reconciled. Your balance and benefits are up to date.'
                  : 'Purchases refreshed. Payments awaiting store approval will appear once approved.'
            : null;
        _retry?.cancel();
        _notify();
        final result = BillingResult(
          success: true,
          message: _message ?? 'Purchases are up to date.',
        );
        if (_current(generation) && pending) publishPendingFeedback(result);
        return result;
      }
    } on ApiException catch (error) {
      if (error.code == 'PURCHASE_ACCOUNT_MISMATCH' ||
          error.code == 'BILLING_REALM_MISMATCH') {
        if (_current(generation)) {
          _operation = BillingOperationStatus.failed;
          _message = error.code == 'PURCHASE_ACCOUNT_MISMATCH'
              ? 'This purchase belongs to another Bara account. Sign in to the original account to restore it.'
              : 'This store purchase cannot be used with this Bara account.';
          _notify();
        }
        final result = BillingResult(
          success: false,
          message: _message ?? 'Purchase account mismatch.',
        );
        if (_current(generation) && pending) publishPendingFeedback(result);
        return result;
      }
    } catch (_) {
      /* Durable marker survives transport failure. */
    }
    if (_current(generation) && pending) {
      _operation = BillingOperationStatus.pending;
      _message =
          'Payment is still being confirmed. Your purchase will appear automatically when it is ready.';
      _retry?.cancel();
      _retry = Timer(const Duration(seconds: 10), () {
        if (_current(generation)) unawaited(refresh());
      });
      _notify();
    }
    return BillingResult(
      success: false,
      message: _message ?? 'Purchases could not be refreshed.',
      disposition: pending
          ? BillingDisposition.pending
          : BillingDisposition.error,
    );
  }

  void _scheduleRetry(int generation) {
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 10), () {
      if (_current(generation)) unawaited(refresh());
    });
  }

  Future<BillingResult> _purchase(String id) async {
    final product = _productIds[id],
        identity = _identity,
        generation = _generation,
        user = _user;
    if (!isAvailable ||
        product == null ||
        identity == null ||
        snapshot.busy ||
        _working) {
      return const BillingResult(
        success: false,
        message: 'This purchase is not available yet.',
      );
    }
    _working = true;
    _operation = BillingOperationStatus.loading;
    _message = null;
    _notify();
    final prefs = await SharedPreferences.getInstance();
    var nativeStarted = false;
    Map<String, dynamic>? intent;
    try {
      await store.identify(identity);
      if (!_current(generation)) {
        return const BillingResult(success: false, message: 'Account changed.');
      }
      final baseline = await store.transactionIds(product);
      if (!_current(generation)) {
        return const BillingResult(success: false, message: 'Account changed.');
      }
      if (baseline.any((id) => id.isEmpty)) {
        throw const FormatException('Invalid native baseline');
      }
      intent = {
        'kind': 'purchase',
        'identity': identity,
        'productId': product,
        'baseline': baseline,
      };
      await prefs.setString(_syncKey(user), jsonEncode(intent));
      if (!_current(generation)) {
        return const BillingResult(success: false, message: 'Account changed.');
      }
      nativeStarted = true;
      final hint = await store.purchase(product);
      // Retain the old account's marker even when the user signs out during checkout.
      if (hint != null) {
        await prefs.setString(
          _syncKey(user),
          jsonEncode({...intent, 'transactionId': hint}),
        );
      }
      if (!_current(generation)) {
        return const BillingResult(
          success: false,
          message: 'Sign in to the purchasing account to see this purchase.',
        );
      }
      return await _sync(
        generation,
        hint,
        true,
        unresolvedNative: hint == null,
      );
    } on StoreBillingException catch (error) {
      if (error.cancelled ||
          !nativeStarted ||
          (!error.pending && !error.uncertain)) {
        await prefs.remove(_syncKey(user));
      }
      if (_current(generation)) {
        _operation = error.cancelled
            ? BillingOperationStatus.idle
            : error.pending || error.uncertain
            ? BillingOperationStatus.pending
            : BillingOperationStatus.failed;
        _message = error.message;
        if (error.pending || error.uncertain) _scheduleRetry(generation);
        _notify();
      }
      return BillingResult(
        success: false,
        message: error.message,
        disposition: error.cancelled
            ? BillingDisposition.cancelled
            : error.pending || error.uncertain
            ? BillingDisposition.pending
            : BillingDisposition.error,
      );
    } catch (_) {
      if (!nativeStarted) {
        if (_current(generation)) {
          _operation = BillingOperationStatus.failed;
          _message = 'Could not load store purchase history. Please try again.';
        }
        return const BillingResult(
          success: false,
          message: 'Could not load store purchase history. Please try again.',
        );
      }
      if (_current(generation)) {
        _operation = BillingOperationStatus.pending;
        _message =
            'Checking the purchase. Please reopen this screen or return to the app to retry.';
        _scheduleRetry(generation);
        _notify();
      }
      return const BillingResult(
        success: false,
        message: 'Checking the purchase.',
        disposition: BillingDisposition.pending,
      );
    } finally {
      if (_current(generation)) {
        _working = false;
        _notify();
      }
    }
  }

  @override
  Future<BillingResult> buyCoins(CoinPackOffer pack) => _purchase(pack.id);
  @override
  Future<BillingResult> startTrial(BillingPlan plan) => subscribe(plan);
  @override
  Future<BillingResult> subscribe(BillingPlan plan) {
    if (plan != BillingPlan.monthly ||
        snapshot.isMember ||
        !plans.any((p) => p.plan == plan)) {
      return Future.value(
        const BillingResult(
          success: false,
          message: 'Manage your current membership in the store.',
        ),
      );
    }
    return _purchase('plus_monthly');
  }

  @override
  Future<BillingResult> buyPermanent() {
    if (snapshot.isPermanent ||
        !plans.any((p) => p.plan == BillingPlan.permanent)) {
      return Future.value(
        const BillingResult(
          success: false,
          message: 'Permanent Bara+ is unavailable or already owned.',
        ),
      );
    }
    return _purchase('plus_permanent');
  }

  @override
  bool get canManageSubscription =>
      snapshot.hasSubscription || _https(_data['managementUrl']) != null;
  @override
  bool get canChangePlan =>
      isAvailable &&
      snapshot.isMember &&
      snapshot.plan == BillingPlan.annual &&
      _productIds.containsKey('plus_annual') &&
      plans.any((p) => p.plan == BillingPlan.monthly);
  @override
  Future<BillingResult> changePlan(BillingPlan plan) async {
    final generation = _generation,
        identity = _identity,
        oldPlan = snapshot.plan;
    final oldId =
        _productIds[oldPlan == BillingPlan.monthly
            ? 'plus_monthly'
            : 'plus_annual'];
    final newId =
        _productIds[plan == BillingPlan.monthly
            ? 'plus_monthly'
            : 'plus_annual'];
    if (plan != BillingPlan.monthly ||
        !canChangePlan ||
        _working ||
        snapshot.busy ||
        oldPlan == plan ||
        identity == null ||
        oldId == null ||
        newId == null) {
      return const BillingResult(
        success: false,
        message: 'This plan change is unavailable.',
      );
    }
    _working = true;
    _operation = BillingOperationStatus.loading;
    _message = null;
    _notify();
    try {
      await store.identify(identity);
      if (!_current(generation)) {
        return const BillingResult(success: false, message: 'Account changed.');
      }
      await store.changePlan(oldProductId: oldId, newProductId: newId);
      if (!_current(generation)) {
        return const BillingResult(success: false, message: 'Account changed.');
      }
      // No purchase intent or transaction hint: a deferred change has not yet
      // charged. The provider worker reconciles the real future paid renewal.
      await _sync(generation, null, false);
      if (!_current(generation)) {
        return const BillingResult(success: false, message: 'Account changed.');
      }
      _operation = BillingOperationStatus.success;
      _message =
          'Plan change requested. Your current plan continues until the next renewal. Confirm the scheduled change in your store settings.';
      return BillingResult(success: true, message: _message!);
    } on StoreBillingException catch (error) {
      if (_current(generation)) {
        _operation = BillingOperationStatus.failed;
        _message = error.message;
      }
      return BillingResult(
        success: false,
        message: error.message,
        disposition: error.cancelled
            ? BillingDisposition.notice
            : BillingDisposition.error,
      );
    } catch (_) {
      const message =
          'The plan change could not be confirmed. Check your store subscription settings before trying again.';
      if (_current(generation)) {
        _operation = BillingOperationStatus.failed;
        _message = message;
      }
      return const BillingResult(success: false, message: message);
    } finally {
      if (_current(generation)) {
        _working = false;
        _notify();
      }
    }
  }

  @override
  Future<BillingResult> restore() async {
    final identity = _identity, generation = _generation, user = _user;
    if (!isAvailable || identity == null || _working || snapshot.busy) {
      return const BillingResult(
        success: false,
        message: 'Restore is unavailable.',
      );
    }
    _working = true;
    _operation = BillingOperationStatus.loading;
    _notify();
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_syncKey(user), jsonEncode({'kind': 'restore'}));
      if (!_current(generation)) {
        return const BillingResult(success: false, message: 'Account changed.');
      }
      await store.identify(identity);
      if (!_current(generation)) {
        return const BillingResult(success: false, message: 'Account changed.');
      }
      await store.restore();
      return await _sync(generation, null, true);
    } on StoreBillingException catch (error) {
      final prefs = await SharedPreferences.getInstance();
      if (error.accountMismatch || error.cancelled) {
        await prefs.remove(_syncKey(user));
      }
      if (_current(generation)) {
        _operation = error.cancelled
            ? BillingOperationStatus.idle
            : error.accountMismatch
            ? BillingOperationStatus.failed
            : BillingOperationStatus.pending;
        _message = error.message;
        if (!error.accountMismatch && !error.cancelled) {
          _scheduleRetry(generation);
        }
      }
      return BillingResult(
        success: false,
        message: error.message,
        disposition: error.cancelled
            ? BillingDisposition.cancelled
            : error.accountMismatch
            ? BillingDisposition.error
            : BillingDisposition.pending,
      );
    } catch (_) {
      if (_current(generation)) {
        _operation = BillingOperationStatus.pending;
        _message = 'Restore is being confirmed. Return to the app to retry.';
        _scheduleRetry(generation);
      }
      return const BillingResult(
        success: false,
        message: 'Restore is being confirmed.',
        disposition: BillingDisposition.pending,
      );
    } finally {
      if (_current(generation)) {
        _working = false;
        _notify();
      }
    }
  }

  @override
  Future<BillingResult> cancelRenewal() async {
    try {
      await store.manage();
      unawaited(refresh());
      return const BillingResult(
        success: true,
        message: 'Manage renewal in your store subscription settings.',
        disposition: BillingDisposition.notice,
      );
    } catch (_) {
      return const BillingResult(
        success: false,
        message: 'Could not open subscription settings.',
      );
    }
  }

  @override
  Future<BillingResult> openLegal(String url) async {
    if (url != termsUrl && url != privacyUrl) {
      return const BillingResult(success: false, message: 'Link unavailable.');
    }
    try {
      final opened = await launchUrl(
        Uri.parse(url),
        mode: LaunchMode.externalApplication,
      );
      return BillingResult(
        success: opened,
        message: opened ? '' : 'Could not open this link.',
      );
    } catch (_) {
      return const BillingResult(
        success: false,
        message: 'Could not open this link.',
      );
    }
  }

  String _uuid() {
    final bytes = List.generate(16, (_) => Random.secure().nextInt(256));
    bytes[6] = (bytes[6] & 15) | 64;
    bytes[8] = (bytes[8] & 63) | 128;
    final hex = bytes.map((b) => b.toRadixString(16).padLeft(2, '0')).join();
    return '${hex.substring(0, 8)}-${hex.substring(8, 12)}-${hex.substring(12, 16)}-${hex.substring(16, 20)}-${hex.substring(20)}';
  }

  String _rerollStorageKey(String raceId, List<String> ids) {
    final sorted = [...ids]..sort();
    return 'billing.reroll.v1.$platform.$_user.${Uri.encodeComponent(jsonEncode([raceId, sorted]))}';
  }

  @override
  Future<RerollFunding?> pendingReroll({
    required String raceId,
    required List<String> ids,
  }) async {
    final generation = _generation;
    final key = _rerollStorageKey(raceId, ids);
    try {
      final prefs = await SharedPreferences.getInstance();
      if (!_current(generation)) return null;
      final saved = prefs.getString(key);
      if (saved == null) return null;
      final operation = _map(jsonDecode(saved));
      if (operation['complete'] == true) return null;
      return RerollFunding.values
          .where((e) => e.name == operation['funding'])
          .firstOrNull;
    } catch (_) {
      return null;
    }
  }

  @override
  Future<BillingRerollResult> reroll({
    required String raceId,
    required List<String> ids,
    required RerollFunding funding,
  }) async {
    final token = _token, generation = _generation;
    if (!supportsRace(raceId) ||
        token == null ||
        _working ||
        funding == RerollFunding.ad ||
        ids.isEmpty ||
        ids.length > 8 ||
        ids.toSet().length != ids.length) {
      return const BillingRerollResult(
        success: false,
        message: 'Reroll unavailable.',
      );
    }
    _working = true;
    final sorted = [...ids]..sort();
    // One unresolved operation per exact item set. Changing funding cannot turn
    // a timed-out debit into a new debit with a different UUID.
    final storageKey = _rerollStorageKey(raceId, sorted);
    try {
      final prefs = await SharedPreferences.getInstance();
      final saved = prefs.getString(storageKey);
      final operation = saved == null
          ? {'key': _uuid(), 'funding': funding.name, 'cost': _cost}
          : _map(jsonDecode(saved));
      await prefs.setString(storageKey, jsonEncode(operation));
      if (!_current(generation)) {
        return const BillingRerollResult(
          success: false,
          message: 'Account changed.',
        );
      }
      final savedFunding = _string(operation['funding']) ?? funding.name;
      if (savedFunding != funding.name) {
        return BillingRerollResult(
          success: false,
          message:
              'A previous $savedFunding reroll is still being checked. Choose $savedFunding again to recover that action.',
        );
      }
      final result = await api.purchaseBoxReroll(
        identityToken: token,
        raceId: raceId,
        powerupIds: sorted,
        funding: savedFunding,
        idempotencyKey: _string(operation['key']) ?? '',
        expectedCoinCost: savedFunding == 'coins'
            ? _int(operation['cost'], _cost)
            : null,
      );
      if (!_current(generation)) {
        return const BillingRerollResult(
          success: false,
          message: 'Account changed.',
        );
      }
      final rawRows = result['results'];
      if (rawRows is! List || rawRows.length != ids.length) {
        throw const FormatException('Incomplete reroll response');
      }
      final rows = rawRows.map(_map).toList();
      if (rows.any(
        (row) => !sorted.contains(row['powerupId']) || row['type'] is! String,
      )) {
        throw const FormatException('Invalid reroll response');
      }
      if (saved == null) {
        await _apply({
          ..._data,
          'coins': result['coins'],
          'credits': result['credits'],
        }, generation);
      } else {
        // A durable replay deliberately returns its original receipt. Its old
        // wallet/credit balances must not overwrite more recent spending.
        try {
          final current = await api.fetchBillingBootstrap(
            identityToken: token,
            platform: platform,
          );
          if (current['contract'] == 'bara-billing-v1') {
            await _apply(current, generation);
          }
        } catch (_) {
          /* Keep the current cached wallet; resume refreshes it. */
        }
      }
      await prefs.setString(
        storageKey,
        jsonEncode({...operation, 'complete': true}),
      );
      if (!_current(generation)) {
        return const BillingRerollResult(
          success: false,
          message: 'Account changed.',
        );
      }
      // Keep successful UUID forever so a lost reveal or process death replays
      // the original result. The server owns item eligibility and replay.
      return BillingRerollResult(
        success: true,
        message: 'Reroll complete.',
        rows: rows,
      );
    } on ApiException catch (error) {
      if (_current(generation) && error.code == 'PRICE_CHANGED') {
        _cost = _int(error.details?['coinCost'], _cost);
      }
      if (error.statusCode != null &&
          error.statusCode! >= 400 &&
          error.statusCode! < 500 &&
          error.code != 'IDEMPOTENCY_CONFLICT') {
        final prefs = await SharedPreferences.getInstance();
        await prefs.remove(storageKey);
      }
      return BillingRerollResult(
        success: false,
        message: error.code == 'PRICE_CHANGED'
            ? 'The reroll price changed. Refresh and confirm the new price.'
            : error.message,
      );
    } catch (_) {
      return const BillingRerollResult(
        success: false,
        message:
            'The reroll is still being checked. Retry to recover the same action without a second charge.',
      );
    } finally {
      if (_current(generation)) {
        _working = false;
        _notify();
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _generation++;
    _retry?.cancel();
    auth.removeListener(_authChanged);
    store.setOnCustomerInfoChanged(null);
    super.dispose();
  }
}
