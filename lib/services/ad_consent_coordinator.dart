import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:google_mobile_ads/google_mobile_ads.dart';

@immutable
class PartnerConsentSignals {
  const PartnerConsentSignals({this.gdprConsent, this.ccpaConsent});

  // Unity Technologies is vendor 1549 in IAB's Global Vendor List and
  // declares consent purposes 1, 3, and 4. Google lists Unity Ads as provider
  // 3234 in Additional Consent. Because Unity is also a TCF vendor, a present
  // TCF vendor bit is authoritative; Additional Consent is only the fallback
  // when the CMP did not publish the TCF vendor bitfield.
  static const int _unityTcfVendorId = 1549;
  static const int _unityAdditionalConsentProviderId = 3234;
  static const Set<int> _unityRequiredConsentPurposes = {1, 3, 4};

  /// Unity's GDPR setter uses `true` for opted in and `false` for opted out.
  /// Liftoff and Unity's CCPA setters use `true` for opted in (the user did not
  /// opt out) and `false` for opted out. Unknown and non-applicable values stay
  /// null so Bara never invents a privacy choice.
  final bool? gdprConsent;
  final bool? ccpaConsent;

  factory PartnerConsentSignals.fromIabValues(Map<Object?, Object?> values) {
    return PartnerConsentSignals(
      gdprConsent: _gdprConsent(values),
      ccpaConsent: _ccpaConsent(values),
    );
  }

  static bool? _gdprConsent(Map<Object?, Object?> values) {
    final applies = _intValue(
      values['IABTCF_gdprApplies'] ?? values['IABGPP_TCFEU2_gdprApplies'],
    );
    if (applies != 1) return null;
    final purposes =
        values['IABTCF_PurposeConsents'] ??
        values['IABGPP_TCFEU2_PurposesConsent'];
    final purposeConsent = _requiredBitConsent(
      purposes,
      _unityRequiredConsentPurposes,
    );

    final bool? vendorConsent;
    if (values.containsKey('IABTCF_VendorConsents')) {
      vendorConsent = _singleBitConsent(
        values['IABTCF_VendorConsents'],
        _unityTcfVendorId,
      );
    } else {
      vendorConsent = _additionalConsentChoice(
        values['IABTCF_AddtlConsent'],
        _unityAdditionalConsentProviderId,
      );
    }

    if (purposeConsent == null || vendorConsent == null) return null;
    return purposeConsent && vendorConsent;
  }

  static bool? _ccpaConsent(Map<Object?, Object?> values) {
    final sectionIds = _sectionIds(values['IABGPP_GppSID']);
    if (sectionIds == null) return null;

    final currentUsSectionIds = sectionIds
        .where(_gppUsSectionPrefixes.containsKey)
        .toSet();
    if (currentUsSectionIds.isNotEmpty) {
      var optedOut = false;
      for (final sectionId in currentUsSectionIds) {
        final sectionPrefix = _gppUsSectionPrefixes[sectionId];
        if (sectionPrefix == null) return null;
        final prefix = 'IABGPP_${sectionPrefix}_';
        for (final field in const [
          'SaleOptOut',
          'SharingOptOut',
          'TargetedAdvertisingOptOut',
        ]) {
          final choice = _intValue(values['$prefix$field']);
          if (choice != 1 && choice != 2) return null;
          if (choice == 1) optedOut = true;
        }
        final gpc = _gpcChoice(values['${prefix}Gpc']);
        if (gpc == null) return null;
        if (gpc) optedOut = true;
      }
      return !optedOut;
    }

    // The deprecated USP1 GPP section is authoritative when present. IAB
    // defines 1 as opted out and 2 as did not opt out.
    if (sectionIds.contains(6)) {
      return switch (_intValue(values['IABGPP_USP1_OptOut'])) {
        1 => false,
        2 => true,
        _ => null,
      };
    }

    // With no current US GPP section, the legacy US Privacy string remains
    // the applicable US signal. Its third character is the sale opt-out.
    final usPrivacy = values['IABUSPrivacy_String'];
    if (usPrivacy is String &&
        usPrivacy.length == 4 &&
        usPrivacy.startsWith('1')) {
      return switch (usPrivacy[2].toUpperCase()) {
        'Y' => false,
        'N' => true,
        _ => null,
      };
    }
    return null;
  }

  static bool? _requiredBitConsent(Object? value, Set<int> requiredIds) {
    if (value is! String || value.isEmpty || !_isBinaryString(value)) {
      return null;
    }
    if (requiredIds.isEmpty) return null;
    final highestId = requiredIds.reduce((a, b) => a > b ? a : b);
    if (value.length < highestId) return null;
    return requiredIds.every((id) => value[id - 1] == '1');
  }

  static bool? _singleBitConsent(Object? value, int id) {
    if (value is! String || value.length < id || !_isBinaryString(value)) {
      return null;
    }
    return value[id - 1] == '1';
  }

  static bool _isBinaryString(String value) =>
      RegExp(r'^[01]+$').hasMatch(value);

  static bool? _additionalConsentChoice(Object? value, int providerId) {
    if (value is! String || value.isEmpty) return null;
    final parts = value.split('~');
    if (parts.length != 2 && parts.length != 3) return null;

    final version = parts[0];
    if (version == '1') {
      if (parts.length != 2) return null;
    } else if (version == '2') {
      if (parts.length != 3 || !parts[2].startsWith('dv.')) return null;
      if (_dotSeparatedPositiveIds(parts[2].substring(3)) == null) return null;
    } else {
      return null;
    }

    final consentedIds = _dotSeparatedPositiveIds(parts[1]);
    if (consentedIds == null) return null;
    return consentedIds.contains(providerId);
  }

  static Set<int>? _dotSeparatedPositiveIds(String value) {
    if (value.isEmpty) return <int>{};
    if (!RegExp(r'^\d+(?:\.\d+)*$').hasMatch(value)) return null;
    final ids = value.split('.').map(int.parse).toSet();
    return ids.every((id) => id > 0) ? ids : null;
  }

  static bool? _gpcChoice(Object? value) {
    if (value is bool) return value;
    return switch (_intValue(value)) {
      0 => false,
      1 => true,
      _ => null,
    };
  }

  static int? _intValue(Object? value) {
    if (value is int) return value;
    if (value is String) return int.tryParse(value.trim());
    return null;
  }

  static Set<int>? _sectionIds(Object? value) {
    if (value == null) return const {};
    if (value is int) return value > 0 ? {value} : null;
    if (value is Iterable) {
      final parsed = value.map(_intValue).toList();
      if (parsed.any((id) => id == null || id <= 0)) return null;
      return parsed.whereType<int>().toSet();
    }
    if (value is! String || value.trim().isEmpty) return null;
    final tokens = value.trim().split(RegExp(r'[_\s,]+'));
    final parsed = tokens.map(int.tryParse).toList();
    if (parsed.any((id) => id == null || id <= 0)) return null;
    return parsed.whereType<int>().toSet();
  }

  // IAB GPP section IDs and API prefixes, current 2026-08-26. Bara reads the
  // CMP's standardized pre-parsed in-app fields rather than attempting to
  // decode the compact GPP string. Sections 7 (US National) and 8
  // (California) cover Liftoff's CCPA-specific requirement; the remaining US
  // state sections preserve the same opt-out behavior as UMP expands support.
  static const Map<int, String> _gppUsSectionPrefixes = {
    7: 'USNAT',
    8: 'USCA',
    9: 'USVA',
    10: 'USCO',
    11: 'USUT',
    12: 'USCT',
    13: 'USFL',
    14: 'USMT',
    15: 'USOR',
    16: 'USTX',
    17: 'USDE',
    18: 'USIA',
    19: 'USNE',
    20: 'USNH',
    21: 'USNJ',
    22: 'USTN',
    23: 'USMN',
    24: 'USMD',
    25: 'USIN',
    26: 'USKY',
    27: 'USRI',
  };

  @override
  bool operator ==(Object other) =>
      other is PartnerConsentSignals &&
      other.gdprConsent == gdprConsent &&
      other.ccpaConsent == ccpaConsent;

  @override
  int get hashCode => Object.hash(gdprConsent, ccpaConsent);
}

typedef InitializeAdsWithConsent =
    Future<bool> Function(PartnerConsentSignals signals);

class AdConsentCoordinator extends ChangeNotifier {
  AdConsentCoordinator({
    required Future<void> Function() requestConsentInfoUpdate,
    required Future<void> Function() loadAndShowConsentFormIfRequired,
    required Future<bool> Function() canRequestAds,
    required Future<bool> Function() getPrivacyOptionsRequired,
    required Future<void> Function() showPrivacyOptionsForm,
    required Future<PartnerConsentSignals> Function() readPartnerConsentSignals,
    required InitializeAdsWithConsent initializeAds,
    Future<void> Function(PartnerConsentSignals signals)? applyPartnerConsent,
    ValueChanged<bool>? onAdsPermissionChanged,
  }) : _requestConsentInfoUpdate = requestConsentInfoUpdate,
       _loadAndShowConsentFormIfRequired = loadAndShowConsentFormIfRequired,
       _canRequestAds = canRequestAds,
       _getPrivacyOptionsRequired = getPrivacyOptionsRequired,
       _showPrivacyOptionsForm = showPrivacyOptionsForm,
       _readPartnerConsentSignals = readPartnerConsentSignals,
       _initializeAds = initializeAds,
       _applyPartnerConsent = applyPartnerConsent,
       _onAdsPermissionChanged = onAdsPermissionChanged;

  factory AdConsentCoordinator.production({
    required InitializeAdsWithConsent initializeAds,
    required Future<void> Function(PartnerConsentSignals signals)
    applyPartnerConsent,
    required ValueChanged<bool> onAdsPermissionChanged,
  }) {
    return AdConsentCoordinator(
      requestConsentInfoUpdate: _requestProductionConsentInfoUpdate,
      loadAndShowConsentFormIfRequired:
          _loadAndShowProductionConsentFormIfRequired,
      canRequestAds: ConsentInformation.instance.canRequestAds,
      getPrivacyOptionsRequired: () async =>
          await ConsentInformation.instance
              .getPrivacyOptionsRequirementStatus() ==
          PrivacyOptionsRequirementStatus.required,
      showPrivacyOptionsForm: _showProductionPrivacyOptionsForm,
      readPartnerConsentSignals: _readProductionPartnerSignals,
      initializeAds: initializeAds,
      applyPartnerConsent: applyPartnerConsent,
      onAdsPermissionChanged: onAdsPermissionChanged,
    );
  }

  static const MethodChannel _privacySignalsChannel = MethodChannel(
    'com.steptracker/ad_privacy_signals',
  );

  final Future<void> Function() _requestConsentInfoUpdate;
  final Future<void> Function() _loadAndShowConsentFormIfRequired;
  final Future<bool> Function() _canRequestAds;
  final Future<bool> Function() _getPrivacyOptionsRequired;
  final Future<void> Function() _showPrivacyOptionsForm;
  final Future<PartnerConsentSignals> Function() _readPartnerConsentSignals;
  final InitializeAdsWithConsent _initializeAds;
  final Future<void> Function(PartnerConsentSignals signals)?
  _applyPartnerConsent;
  final ValueChanged<bool>? _onAdsPermissionChanged;

  Future<bool>? _bootstrapFlight;
  Future<void>? _privacyOptionsFlight;
  bool _launchSettled = false;
  bool _launchResult = false;
  bool _adsAllowed = false;
  bool _privacyOptionsRequired = false;

  bool get adsAllowed => _adsAllowed;
  bool get privacyOptionsRequired => _privacyOptionsRequired;
  bool get privacyOptionsFormOpen => _privacyOptionsFlight != null;

  Future<bool> bootstrap() {
    if (_launchSettled) return Future.value(_launchResult);
    final existing = _bootstrapFlight;
    if (existing != null) return existing;

    late final Future<bool> flight;
    flight = _bootstrapForLaunch().whenComplete(() {
      if (identical(_bootstrapFlight, flight)) _bootstrapFlight = null;
    });
    _bootstrapFlight = flight;
    return flight;
  }

  Future<bool> _bootstrapForLaunch() async {
    var result = false;
    try {
      await _requestConsentInfoUpdate();
      await _loadAndShowConsentFormIfRequired();
      await _refreshPrivacyRequirement();
      final allowed = await _canRequestAds();
      if (allowed) {
        final signals = await _readSignalsSafely();
        await _applySignalsSafely(signals);
        result = await _initializeAds(signals);
      }
    } catch (error) {
      debugPrint('Ad consent bootstrap failed closed: $error');
    }
    _setAdsAllowed(result);
    _launchResult = result;
    _launchSettled = true;
    notifyListeners();
    return result;
  }

  Future<void> showPrivacyOptions() {
    final existing = _privacyOptionsFlight;
    if (existing != null) return existing;
    if (!_privacyOptionsRequired) return Future.value();

    // A privacy edit may alter partner-specific signals even when UMP still
    // permits limited ads. Stop requests and dispose cached/in-flight ads for
    // the entire form lifetime; refreshed signals are propagated before ads
    // can be enabled again.
    _setAdsAllowed(false);

    late final Future<void> flight;
    flight = _showAndRefreshPrivacyOptions().whenComplete(() {
      if (identical(_privacyOptionsFlight, flight)) {
        _privacyOptionsFlight = null;
        notifyListeners();
      }
    });
    _privacyOptionsFlight = flight;
    notifyListeners();
    return flight;
  }

  Future<void> _showAndRefreshPrivacyOptions() async {
    try {
      await _showPrivacyOptionsForm();
    } catch (error) {
      debugPrint('UMP privacy options form failed: $error');
    }

    try {
      await _refreshPrivacyRequirement();
      final allowed = await _canRequestAds();
      final signals = await _readSignalsSafely();
      await _applySignalsSafely(signals);
      final operational = allowed ? await _initializeAds(signals) : false;
      _setAdsAllowed(allowed && operational);
    } catch (error) {
      debugPrint('Ad consent refresh failed closed: $error');
      _setAdsAllowed(false);
    }
    notifyListeners();
  }

  Future<void> _refreshPrivacyRequirement() async {
    try {
      _privacyOptionsRequired = await _getPrivacyOptionsRequired();
    } catch (error) {
      debugPrint('UMP privacy-options requirement query failed: $error');
      _privacyOptionsRequired = false;
    }
  }

  Future<PartnerConsentSignals> _readSignalsSafely() async {
    try {
      return await _readPartnerConsentSignals();
    } catch (error) {
      debugPrint('IAB partner consent signal read failed: $error');
      return const PartnerConsentSignals();
    }
  }

  Future<void> _applySignalsSafely(PartnerConsentSignals signals) async {
    final apply = _applyPartnerConsent;
    if (apply == null) return;
    try {
      await apply(signals);
    } catch (error) {
      debugPrint('Partner consent propagation failed: $error');
    }
  }

  void _setAdsAllowed(bool allowed) {
    if (_adsAllowed == allowed) return;
    _adsAllowed = allowed;
    _onAdsPermissionChanged?.call(allowed);
  }

  static Future<void> _requestProductionConsentInfoUpdate() {
    final completer = Completer<void>();
    ConsentInformation.instance.requestConsentInfoUpdate(
      ConsentRequestParameters(),
      completer.complete,
      completer.completeError,
    );
    return completer.future;
  }

  static Future<void> _loadAndShowProductionConsentFormIfRequired() {
    final completer = Completer<void>();
    ConsentForm.loadAndShowConsentFormIfRequired((error) {
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(error);
      }
    });
    return completer.future;
  }

  static Future<void> _showProductionPrivacyOptionsForm() {
    final completer = Completer<void>();
    ConsentForm.showPrivacyOptionsForm((error) {
      if (error == null) {
        completer.complete();
      } else {
        completer.completeError(error);
      }
    });
    return completer.future;
  }

  static Future<PartnerConsentSignals> _readProductionPartnerSignals() async {
    if (kIsWeb) return const PartnerConsentSignals();
    final raw = await _privacySignalsChannel.invokeMapMethod<Object?, Object?>(
      'getIabSignals',
    );
    return PartnerConsentSignals.fromIabValues(raw ?? const {});
  }
}

class AdConsentScope extends InheritedNotifier<AdConsentCoordinator> {
  const AdConsentScope({
    super.key,
    required AdConsentCoordinator coordinator,
    required super.child,
  }) : super(notifier: coordinator);

  static AdConsentCoordinator? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdConsentScope>()?.notifier;
}

class AdConsentBootstrap extends StatefulWidget {
  const AdConsentBootstrap({
    super.key,
    required this.coordinator,
    required this.child,
  });

  final AdConsentCoordinator coordinator;
  final Widget child;

  @override
  State<AdConsentBootstrap> createState() => _AdConsentBootstrapState();
}

class _AdConsentBootstrapState extends State<AdConsentBootstrap> {
  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) unawaited(widget.coordinator.bootstrap());
    });
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
