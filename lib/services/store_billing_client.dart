import 'dart:io';
import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:purchases_flutter/purchases_flutter.dart' as rc;
import 'package:url_launcher/url_launcher.dart';

class StoreBillingProduct {
  final String id;
  final String price;
  final int trialDays;
  const StoreBillingProduct({
    required this.id,
    required this.price,
    this.trialDays = 0,
  });
}

class StoreBillingException implements Exception {
  final String message;
  final bool cancelled;
  final bool pending;
  final bool uncertain;
  final bool accountMismatch;
  const StoreBillingException(
    this.message, {
    this.cancelled = false,
    this.pending = false,
    this.uncertain = false,
    this.accountMismatch = false,
  });
}

/// Injectable native boundary. Financial authority remains on the backend.
abstract class StoreBillingClient {
  bool get configured;
  void setOnCustomerInfoChanged(VoidCallback? callback) {}
  Future<void> identify(String identity);
  Future<List<StoreBillingProduct>> products(
    List<String> coins,
    List<String> subscriptions,
  );
  Future<List<String>> transactionIds(String productId);
  Future<String?> purchase(String productId);
  Future<void> changePlan({
    required String oldProductId,
    required String newProductId,
  });
  Future<void> restore();
  Future<void> manage();
}

class RevenueCatBillingClient extends StoreBillingClient {
  final String apiKey;
  final String platform;
  RevenueCatBillingClient({required this.apiKey, String? platform})
    : platform =
          platform ??
          (Platform.isIOS
              ? 'ios'
              : Platform.isAndroid
              ? 'android'
              : '');
  bool get _isIOS => platform == 'ios';
  bool get _isAndroid => platform == 'android';
  String? _identity;
  rc.CustomerInfoUpdateListener? _customerListener;
  @override
  void setOnCustomerInfoChanged(VoidCallback? callback) {
    final old = _customerListener;
    if (old != null) rc.Purchases.removeCustomerInfoUpdateListener(old);
    _customerListener = callback == null ? null : (_) => callback();
    final listener = _customerListener;
    if (listener != null && configured) {
      rc.Purchases.addCustomerInfoUpdateListener(listener);
    }
  }

  final _products = <String, rc.StoreProduct>{};
  Future<void> _tail = Future.value();
  Future<T> _serial<T>(Future<T> Function() action) {
    final result = _tail.then((_) => action());
    _tail = result.then<void>((_) {}, onError: (Object _) {});
    return result;
  }

  @override
  bool get configured => !kIsWeb && (_isIOS || _isAndroid) && apiKey.isNotEmpty;
  @override
  Future<void> identify(String identity) => _serial(() async {
    if (!configured) {
      throw const StoreBillingException('Purchases are unavailable.');
    }
    if (_identity == identity) return;
    if (await rc.Purchases.isConfigured) {
      await rc.Purchases.logIn(identity);
    } else {
      await rc.Purchases.configure(
        rc.PurchasesConfiguration(apiKey)..appUserID = identity,
      );
    }
    _identity = identity;
    _products.clear();
  });
  @override
  Future<List<StoreBillingProduct>> products(
    List<String> coins,
    List<String> subscriptions,
  ) => _serial(() async {
    final found = <rc.StoreProduct>[
      if (coins.isNotEmpty)
        ...await rc.Purchases.getProducts(
          coins,
          productCategory: rc.ProductCategory.nonSubscription,
        ),
      if (subscriptions.isNotEmpty)
        ...await rc.Purchases.getProducts(
          subscriptions,
          productCategory: rc.ProductCategory.subscription,
        ),
    ];
    final eligibility = _isIOS && subscriptions.isNotEmpty
        ? await rc.Purchases.checkTrialOrIntroductoryPriceEligibility(
            subscriptions,
          )
        : <String, rc.IntroEligibility>{};
    _products.clear();
    return found.map((product) {
      _products[product.identifier] = product;
      var days = 0;
      final intro = product.introductoryPrice;
      if (_isIOS &&
          eligibility[product.identifier]?.status ==
              rc.IntroEligibilityStatus.introEligibilityStatusEligible &&
          intro != null &&
          intro.price == 0) {
        if (intro.period == 'P1W' || intro.period == 'P7D') days = 7;
      }
      final freePeriod =
          product.defaultOption?.freePhase?.billingPeriod?.iso8601;
      if (_isAndroid && (freePeriod == 'P1W' || freePeriod == 'P7D')) {
        days = 7;
      }
      return StoreBillingProduct(
        id: product.identifier,
        price: product.priceString,
        trialDays: days,
      );
    }).toList();
  });
  @override
  Future<List<String>> transactionIds(String productId) => _serial(() async {
    await rc.Purchases.invalidateCustomerInfoCache();
    final info = await rc.Purchases.getCustomerInfo();
    final ids = <String>{};
    final parts = productId.split(':');
    bool matchesSubscription(rc.SubscriptionInfo subscription) =>
        subscription.productIdentifier == productId ||
        (parts.length == 2 &&
            subscription.productIdentifier == parts[0] &&
            subscription.productPlanIdentifier == parts[1]);
    for (final transaction in info.nonSubscriptionTransactions) {
      if (transaction.productIdentifier != productId) continue;
      if (transaction.transactionIdentifier.isEmpty) {
        throw const StoreBillingException(
          'Store purchase history is incomplete. Please try again.',
        );
      }
      ids.add(transaction.transactionIdentifier);
    }
    for (final subscription in info.subscriptionsByProductIdentifier.values) {
      if (!matchesSubscription(subscription)) continue;
      final id = subscription.storeTransactionId;
      if (id == null || id.isEmpty) {
        throw const StoreBillingException(
          'Store purchase history is incomplete. Please try again.',
        );
      }
      ids.add(id);
    }
    if (info.allPurchasedProductIdentifiers.contains(productId) &&
        ids.isEmpty) {
      throw const StoreBillingException(
        'Store purchase history is incomplete. Please try again.',
      );
    }
    return ids.toList();
  });
  @override
  Future<String?> purchase(String productId) => _serial(() async {
    final product = _products[productId];
    if (product == null) {
      throw const StoreBillingException('This store product is unavailable.');
    }
    try {
      final result = await rc.Purchases.purchase(
        rc.PurchaseParams.storeProduct(product),
      );
      return result.storeTransaction.transactionIdentifier;
    } on PlatformException catch (error) {
      final code = rc.PurchasesErrorHelper.getErrorCode(error);
      throw StoreBillingException(
        code == rc.PurchasesErrorCode.receiptAlreadyInUseError ||
                code == rc.PurchasesErrorCode.receiptInUseByOtherSubscriberError
            ? 'This purchase belongs to another Bara account. Sign in to the original account to restore it.'
            : code == rc.PurchasesErrorCode.purchaseCancelledError
            ? 'Purchase cancelled.'
            : code == rc.PurchasesErrorCode.paymentPendingError
            ? 'Waiting for store payment approval.'
            : 'The store could not complete this purchase. Please try again.',
        cancelled: code == rc.PurchasesErrorCode.purchaseCancelledError,
        pending: code == rc.PurchasesErrorCode.paymentPendingError,
        uncertain: !const {
          rc.PurchasesErrorCode.purchaseCancelledError,
          rc.PurchasesErrorCode.purchaseNotAllowedError,
          rc.PurchasesErrorCode.purchaseInvalidError,
          rc.PurchasesErrorCode.productNotAvailableForPurchaseError,
          rc.PurchasesErrorCode.receiptAlreadyInUseError,
          rc.PurchasesErrorCode.receiptInUseByOtherSubscriberError,
        }.contains(code),
      );
    }
  });
  @override
  Future<void> changePlan({
    required String oldProductId,
    required String newProductId,
  }) => _serial(() async {
    final product = _products[newProductId];
    if (product == null || oldProductId == newProductId) {
      throw const StoreBillingException('This plan is unavailable.');
    }
    await rc.Purchases.invalidateCustomerInfoCache();
    final info = await rc.Purchases.getCustomerInfo();
    final parts = oldProductId.split(':');
    final old = info.subscriptionsByProductIdentifier.values
        .where(
          (subscription) =>
              subscription.isActive &&
              subscription.store ==
                  (_isAndroid ? rc.Store.playStore : rc.Store.appStore) &&
              (subscription.productIdentifier == oldProductId ||
                  (parts.length == 2 &&
                      subscription.productIdentifier == parts[0] &&
                      subscription.productPlanIdentifier == parts[1])),
        )
        .firstOrNull;
    if (old == null) {
      throw const StoreBillingException(
        'Manage this membership in the store where you subscribed.',
      );
    }
    try {
      await rc.Purchases.purchase(
        rc.PurchaseParams.storeProduct(
          product,
          productChangeInfo: _isAndroid
              ? rc.StoreProductChangeInfo(
                  oldProductId,
                  replacementMode: rc.StoreReplacementMode.deferred,
                )
              : null,
        ),
      );
      // This is native scheduling acceptance, not a paid transaction grant.
      // Apple same-group/same-level products of different durations defer via
      // App Store configuration; Google receives explicit DEFERRED above.
    } on PlatformException catch (error) {
      final code = rc.PurchasesErrorHelper.getErrorCode(error);
      throw StoreBillingException(
        code == rc.PurchasesErrorCode.purchaseCancelledError
            ? 'Plan change cancelled.'
            : 'The plan change could not be confirmed. Check your store subscription settings before trying again.',
        cancelled: code == rc.PurchasesErrorCode.purchaseCancelledError,
      );
    }
  });
  @override
  Future<void> restore() => _serial(() async {
    try {
      await rc.Purchases.restorePurchases();
    } on PlatformException catch (error) {
      final code = rc.PurchasesErrorHelper.getErrorCode(error);
      if (code == rc.PurchasesErrorCode.receiptAlreadyInUseError ||
          code == rc.PurchasesErrorCode.receiptInUseByOtherSubscriberError) {
        throw const StoreBillingException(
          'This purchase belongs to another Bara account. Sign in to the original account to restore it.',
          accountMismatch: true,
        );
      }
      rethrow;
    }
  });
  @override
  Future<void> manage() => _serial(() async {
    Uri? management;
    try {
      final info = await rc.Purchases.getCustomerInfo();
      final candidate = Uri.tryParse(info.managementURL ?? '');
      if (candidate != null &&
          candidate.scheme == 'https' &&
          const {'apps.apple.com', 'play.google.com'}.contains(candidate.host)) {
        management = candidate;
      }
    } catch (_) {
      /* An offline store can still open its subscription center. */
    }
    final uri =
        management ??
        Uri.parse(
          _isIOS
              ? 'https://apps.apple.com/account/subscriptions'
              : 'https://play.google.com/store/account/subscriptions',
        );
    if (!await launchUrl(uri, mode: LaunchMode.externalApplication)) {
      throw const StoreBillingException(
        'Could not open subscription settings.',
      );
    }
  });
}
