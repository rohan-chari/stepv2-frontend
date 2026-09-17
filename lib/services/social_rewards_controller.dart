import 'dart:async';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';
import 'activation_analytics_service.dart';
import 'auth_service.dart';
import 'backend_api_service.dart';

class SocialRewardItem {
  SocialRewardItem.fromJson(Map<dynamic, dynamic> json)
    : platform = json['platform'] is String ? json['platform'] as String : '',
      label = json['label'] is String ? json['label'] as String : '',
      handle = json['handle'] is String ? json['handle'] as String : '',
      url = json['url'] is String ? json['url'] as String : '',
      amount = json['amount'] is num ? (json['amount'] as num).toInt() : 0,
      state = json['state'] is String ? json['state'] as String : 'not_started';
  final String platform, label, handle, url, state;
  final int amount;
  bool get isOpened => state == 'opened';
  bool get isClaimed => state == 'claimed';
}

class SocialRewardsController extends ChangeNotifier
    with WidgetsBindingObserver {
  SocialRewardsController({
    required this.auth,
    required this.api,
    ActivationAnalyticsService? analytics,
  }) : analytics =
           analytics ?? ActivationAnalyticsService(backendApiService: api) {
    WidgetsBinding.instance.addObserver(this);
  }
  final AuthService auth;
  final BackendApiService api;
  final ActivationAnalyticsService analytics;
  List<SocialRewardItem> rewards = const [];
  bool loading = false;
  final Set<String> busy = {};
  bool _impressionSent = false;

  SocialRewardItem? item(String platform) =>
      rewards.where((r) => r.platform == platform).firstOrNull;
  Future<void> refresh({bool impression = false}) async {
    final token = auth.authToken;
    if (token == null || token.isEmpty || loading) return;
    loading = true;
    notifyListeners();
    try {
      final result = await api.fetchSocialRewardsStatus(identityToken: token);
      final raw = result['rewards'];
      if (raw is List) {
        rewards = raw
            .whereType<Map>()
            .map(SocialRewardItem.fromJson)
            .where((r) => r.platform.isNotEmpty)
            .toList();
      }
      if (impression && !_impressionSent && rewards.any((r) => !r.isClaimed)) {
        _impressionSent = true;
        unawaited(
          analytics.record(
            'social_reward_impression',
            ownerUserId: auth.userId,
            context: const {'platform': 'instagram'},
          ),
        );
      }
    } catch (_) {
    } finally {
      loading = false;
      notifyListeners();
    }
  }

  Future<bool> launchAndOpen(SocialRewardItem reward) async {
    if (busy.contains(reward.platform) || reward.isClaimed) return false;
    final uri = Uri.tryParse(reward.url);
    if (uri == null) return false;
    busy.add(reward.platform);
    notifyListeners();
    try {
      final launched = await launchUrl(
        uri,
        mode: LaunchMode.externalApplication,
      );
      if (!launched) return false;
      final token = auth.authToken;
      if (token == null || token.isEmpty) return false;
      await api.openSocialReward(
        identityToken: token,
        platform: reward.platform,
      );
      unawaited(
        analytics.record(
          'social_reward_opened',
          ownerUserId: auth.userId,
          context: {'platform': reward.platform},
        ),
      );
      await refresh();
      return true;
    } finally {
      busy.remove(reward.platform);
      notifyListeners();
    }
  }

  Future<bool> claim(SocialRewardItem reward) async {
    if (busy.contains(reward.platform) ||
        !reward.isOpened ||
        reward.isClaimed) {
      return false;
    }
    final token = auth.authToken;
    if (token == null || token.isEmpty) return false;
    busy.add(reward.platform);
    notifyListeners();
    try {
      final result = await api.claimSocialReward(
        identityToken: token,
        platform: reward.platform,
      );
      final coins = result['coins'];
      if (coins is num) await auth.updateCoins(coins.toInt());
      unawaited(
        analytics.record(
          'social_reward_claimed',
          ownerUserId: auth.userId,
          context: {'platform': reward.platform},
        ),
      );
      await refresh();
      return true;
    } catch (_) {
      unawaited(
        analytics.record(
          'social_reward_claim_failed',
          ownerUserId: auth.userId,
          context: {'platform': reward.platform},
        ),
      );
      await refresh();
      return false;
    } finally {
      busy.remove(reward.platform);
      notifyListeners();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) unawaited(refresh());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }
}
