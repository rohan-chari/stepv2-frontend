import 'dart:async';

import 'package:flutter/widgets.dart';

import 'ad_service.dart';
import 'auth_service.dart';
import 'backend_api_service.dart';

/// Session-owned entitlement and serialized SSV claim flow shared by every
/// Get Coins entry point. Screens only attach listeners; they never own an ad
/// supplied by the shell.
class RewardedCoinsController extends ChangeNotifier
    with WidgetsBindingObserver {
  RewardedCoinsController({
    required this.auth,
    required this.api,
    required ExtraSpinAdController ads,
    this.now,
    this.ownsAds = false,
  }) : _ads = ads {
    auth.addListener(_authChanged);
    WidgetsBinding.instance.addObserver(this);
    _syncIdentity();
  }

  final AuthService auth;
  final BackendApiService api;
  ExtraSpinAdController _ads;
  ExtraSpinAdController get ads => _ads;
  Timer? _midnightTimer;
  final DateTime Function()? now;
  final bool ownsAds;
  Map<String, dynamic>? status;
  bool loading = false;
  bool busy = false;
  bool ready = false;
  bool _disposed = false;
  int _generation = 0;
  int _statusRevision = 0;
  String? _token;
  RewardedAdContext? _context;
  Future<void>? _refreshFuture;

  /// The shell replaces SDK caches at auth boundaries; mounted routes retain
  /// this business-state owner and its listeners throughout that transition.
  void replaceAds(ExtraSpinAdController next) {
    if (_disposed || identical(next, _ads)) return;
    _ads = next;
    _generation++;
    _statusRevision++;
    _refreshFuture = null;
    status = null;
    ready = false;
    loading = false;
    _syncIdentity();
    _emit();
    unawaited(refresh());
  }

  @override
  void addListener(VoidCallback listener) {
    final first = !hasListeners;
    super.addListener(listener);
    if (first) _scheduleMidnight();
  }

  @override
  void removeListener(VoidCallback listener) {
    super.removeListener(listener);
    if (!hasListeners) _midnightTimer?.cancel();
  }

  void _scheduleMidnight() {
    _midnightTimer?.cancel();
    if (_disposed || !hasListeners) return;
    final date = now?.call() ?? DateTime.now();
    final next = DateTime(date.year, date.month, date.day + 1);
    _midnightTimer = Timer(next.difference(date), () {
      if (_disposed) return;
      unawaited(refresh());
      _scheduleMidnight();
    });
  }

  static int? integer(Object? value) =>
      value is num &&
          value.isFinite &&
          value == value.truncateToDouble() &&
          value >= 0
      ? value.toInt()
      : null;

  Map<String, dynamic>? get offer {
    final value = status?['adCoinReward'];
    return value is Map<String, dynamic> ? value : null;
  }

  int get remaining => integer(offer?['remainingToday']) ?? 0;
  bool get pending => offer?['pendingGrant'] == true;
  bool get live =>
      offer != null &&
      (pending || (offer?['available'] == true && remaining > 0));
  bool get supported => ads.isSupported;
  int? get rewardMin => integer(offer?['coinRewardMin']);
  int? get rewardMax => integer(offer?['coinRewardMax']);
  String get homeRewardCopy {
    final min = rewardMin;
    final max = rewardMax;
    return min != null && max != null && min > 0 && max >= min
        ? 'Random $min–$max coins'
        : 'Random coins';
  }

  RewardedAdContext? get _currentContext {
    final user = auth.userId;
    if (user == null || user.isEmpty) return null;
    final date = now?.call() ?? DateTime.now();
    String two(int n) => n.toString().padLeft(2, '0');
    return RewardedAdContext.getCoins(
      userId: user,
      localDate: '${date.year}-${two(date.month)}-${two(date.day)}',
    );
  }

  void _emit() {
    if (!_disposed) notifyListeners();
  }

  bool _valid(int generation) =>
      !_disposed &&
      generation == _generation &&
      _token == auth.authToken &&
      _context == _currentContext;

  bool _syncIdentity() {
    final next = _currentContext;
    final token = auth.authToken;
    if (_context == next && _token == token) return false;
    final previous = _context;
    if (previous != null) ads.disposeContext(previous);
    _generation++;
    _statusRevision++;
    _context = next;
    _token = token;
    status = null;
    ready = false;
    loading = false;
    _refreshFuture = null;
    _emit();
    return true;
  }

  void _authChanged() {
    if (_syncIdentity()) unawaited(refresh());
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _scheduleMidnight();
      unawaited(refresh());
    }
  }

  Future<void> refresh() {
    if (_disposed) return Future.value();
    _syncIdentity();
    if (busy) return Future.value();
    final existing = _refreshFuture;
    if (existing != null) return existing;
    final generation = _generation;
    final revision = _statusRevision;
    final future = _load(generation, revision);
    _refreshFuture = future;
    return future.whenComplete(() {
      if (identical(_refreshFuture, future)) _refreshFuture = null;
    });
  }

  Future<void> _load(int generation, int revision) async {
    final token = _token;
    final context = _context;
    final date = context?.localDate;
    if (token == null || token.isEmpty || date == null) return;
    try {
      final result = await api.fetchGetCoinsStatus(
        identityToken: token,
        localDate: date,
      );
      if (!_valid(generation) || revision != _statusRevision) return;
      status = result;
      if (!live && context != null) {
        ads.disposeContext(context);
        ready = false;
      }
      _emit();
      await prepare();
    } catch (_) {
      if (!_valid(generation) || revision != _statusRevision) return;
      status = const {};
      ready = false;
      if (context != null) ads.disposeContext(context);
      _emit();
    }
  }

  Future<void> prepare() async {
    if (_disposed || !supported || !live || pending || loading) return;
    final context = _context;
    if (context == null) return;
    final generation = _generation;
    if (!ads.isReadyFor(context)) {
      loading = true;
      _emit();
      try {
        await ads.warm(context);
      } catch (_) {
        // No fill/network failures leave an explicit retry affordance.
      } finally {
        if (_valid(generation)) loading = false;
      }
    }
    if (_valid(generation)) {
      ready = ads.isReadyFor(context);
      _emit();
    }
  }

  /// Null means canceled/stale; a successful response supplies the toast amount.
  /// Errors are surfaced by the initiating mounted screen only.
  Future<int?> claim() async {
    if (_disposed || busy) return null;
    if (_syncIdentity()) {
      await refresh();
      return null;
    }
    final token = _token;
    final context = _context;
    final date = context?.localDate;
    if (!supported ||
        !live ||
        token == null ||
        date == null ||
        context == null) {
      return null;
    }
    final generation = _generation;
    busy = true;
    _statusRevision++;
    _emit();
    var failed = false;
    try {
      if (!pending) {
        if (!ads.isReadyFor(context)) return null;
        ready = false;
        _emit();
        final earned = await ads.showAndAwaitRewardFor(context);
        if (!_valid(generation)) return null;
        if (!earned) return null;
      }
      Map<String, dynamic> result;
      for (var attempt = 0; ; attempt++) {
        if (!_valid(generation)) return null;
        try {
          result = await api.claimAdCoinReward(
            identityToken: token,
            localDate: date,
          );
          break;
        } on ApiException catch (e) {
          if (e.statusCode != 409 ||
              !e.message.toLowerCase().contains('no verified ad reward') ||
              attempt >= 4) {
            rethrow;
          }
          await Future<void>.delayed(const Duration(seconds: 2));
        }
      }
      if (!_valid(generation)) return null;
      final coins = integer(result['coins']);
      if (coins != null) auth.updateCoins(coins);
      final left = integer(result['remainingToday']);
      status = {
        ...?status,
        'adCoinReward': {
          ...?offer,
          'available': left != null && left > 0,
          'pendingGrant': false,
          'remainingToday': left ?? 0,
        },
      };
      if (!live) ads.disposeContext(context);
      _emit();
      return integer(result['coinAmount']);
    } catch (_) {
      if (!_valid(generation)) return null;
      failed = true;
      rethrow;
    } finally {
      busy = false;
      _emit();
      if (!_disposed) {
        if (!_valid(generation) || failed) {
          // Invalidate an older status request before fetching recovery state.
          _refreshFuture = null;
          await refresh();
        } else {
          await prepare();
        }
      }
    }
  }

  @override
  void dispose() {
    _disposed = true;
    _midnightTimer?.cancel();
    _generation++;
    auth.removeListener(_authChanged);
    WidgetsBinding.instance.removeObserver(this);
    if (ownsAds) ads.dispose();
    super.dispose();
  }
}
