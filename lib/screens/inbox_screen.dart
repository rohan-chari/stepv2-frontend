import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/retro_card.dart';
import '../widgets/arcade_page.dart';

enum InboxDestinationRoute {
  home,
  races,
  dailyReward,
  friends,
  inbox,
  profile,
  raceDetail,
  tournamentDetail,
  supportThread,
}

/// Parses only the server's allowlisted Inbox destination shape. This model is
/// deliberately not a generic URI router: alerts must not become a route
/// injection path when an old/new backend sends malformed JSON.
class InboxDestination {
  const InboxDestination._(
    this.route, {
    this.raceId,
    this.tournamentId,
    this.threadId,
  });

  final InboxDestinationRoute route;
  final String? raceId;
  final String? tournamentId;
  final String? threadId;

  static InboxDestination? tryParse(Object? raw) {
    if (raw is! Map) return null;
    final route = raw['route'];
    if (route is! String) return null;
    final keys = raw.keys;
    if (keys.any((key) => key is! String)) return null;
    switch (route) {
      case 'home':
        return const InboxDestination._(InboxDestinationRoute.home);
      case 'races':
        return const InboxDestination._(InboxDestinationRoute.races);
      case 'dailyReward':
        return const InboxDestination._(InboxDestinationRoute.dailyReward);
      case 'friends':
        return const InboxDestination._(InboxDestinationRoute.friends);
      case 'inbox':
        return const InboxDestination._(InboxDestinationRoute.inbox);
      case 'profile':
        return const InboxDestination._(InboxDestinationRoute.profile);
      case 'raceDetail':
        final id = raw['raceId'];
        return id is String && id.isNotEmpty
            ? InboxDestination._(InboxDestinationRoute.raceDetail, raceId: id)
            : null;
      case 'tournamentDetail':
        final id = raw['tournamentId'];
        return id is String && id.isNotEmpty
            ? InboxDestination._(
                InboxDestinationRoute.tournamentDetail,
                tournamentId: id,
              )
            : null;
      case 'supportThread':
        final id = raw['threadId'];
        return id is String && id.isNotEmpty
            ? InboxDestination._(
                InboxDestinationRoute.supportThread,
                threadId: id,
              )
            : null;
    }
    return null;
  }
}

enum InboxHostMode { standalone, embedded }

/// Recipient-private Inbox v1. It intentionally offers only system alerts and
/// staff-owned feedback threads—there is no user search, profile lookup, or
/// player-to-player composer in this surface.
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.authService,
    required this.backendApiService,
    this.onOpenDestination,
    this.onUnreadCountChanged,
    this.onUnreadCountDecremented,
    this.hostMode = InboxHostMode.standalone,
    this.clearOnOpen = false,
  });

  final AuthService authService;
  final BackendApiService backendApiService;
  final ValueChanged<Map<String, dynamic>>? onOpenDestination;
  final ValueChanged<int>? onUnreadCountChanged;
  final VoidCallback? onUnreadCountDecremented;
  final InboxHostMode hostMode;
  final bool clearOnOpen;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen>
    with AutomaticKeepAliveClientMixin {
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  String? _alertsCursor;
  String? _threadsCursor;
  bool _loadingMore = false;
  String? _userId;
  String? _authToken;
  int _loadGeneration = 0;
  int _unreadFetchGeneration = 0;
  int _lastAppliedUnreadFetchGeneration = 0;
  int _unreadMutationGeneration = 0;
  int _nextAlertReadGeneration = 0;
  int? _lastKnownUnreadCount;
  final Map<String, int> _readingAlertGenerations = <String, int>{};
  int _readBatchGeneration = 0;
  int _pendingAlertReads = 0;
  bool _readBatchConcurrent = false;
  bool _readBatchSawAuthoritativeCount = false;

  @override
  bool get wantKeepAlive => widget.hostMode == InboxHostMode.embedded;

  @override
  void initState() {
    super.initState();
    _userId = widget.authService.userId;
    _authToken = widget.authService.authToken;
    widget.authService.addListener(_handleAuthChanged);
    _load();
  }

  @override
  void didUpdateWidget(covariant InboxScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.authService == widget.authService) return;
    oldWidget.authService.removeListener(_handleAuthChanged);
    widget.authService.addListener(_handleAuthChanged);
    _handleAuthChanged();
  }

  @override
  void dispose() {
    widget.authService.removeListener(_handleAuthChanged);
    super.dispose();
  }

  void _handleAuthChanged() {
    final nextUserId = widget.authService.userId;
    final nextAuthToken = widget.authService.authToken;
    if (nextUserId == _userId && nextAuthToken == _authToken) return;
    _userId = nextUserId;
    _authToken = nextAuthToken;
    _loadGeneration++;
    _lastAppliedUnreadFetchGeneration = ++_unreadFetchGeneration;
    _unreadMutationGeneration++;
    _readingAlertGenerations.clear();
    _readBatchGeneration++;
    _pendingAlertReads = 0;
    _readBatchConcurrent = false;
    _readBatchSawAuthoritativeCount = false;
    _lastKnownUnreadCount = null;
    if (!mounted) return;
    setState(() {
      _rows = const [];
      _alertsCursor = null;
      _threadsCursor = null;
    });
    _load();
  }

  static int? _nonnegativeInt(Object? value) {
    if (value is int && value >= 0) return value;
    if (value is num &&
        value.isFinite &&
        value >= 0 &&
        value == value.round()) {
      return value.toInt();
    }
    return null;
  }

  void _applyFetchedUnreadResult(
    Object? rawUnreadCount,
    int fetchGeneration,
    int mutationGeneration,
  ) {
    if (fetchGeneration < _lastAppliedUnreadFetchGeneration ||
        mutationGeneration != _unreadMutationGeneration) {
      return;
    }
    final unread = _nonnegativeInt(rawUnreadCount);
    if (unread != null) {
      _lastAppliedUnreadFetchGeneration = fetchGeneration;
      _lastKnownUnreadCount = unread;
      widget.onUnreadCountChanged?.call(unread);
    }
  }

  void _applySingleReadAuthoritativeCount(int unread) {
    _lastKnownUnreadCount = unread;
    widget.onUnreadCountChanged?.call(unread);
  }

  void _applyLegacyReadDecrement() {
    final previous = _lastKnownUnreadCount;
    if (previous != null && previous > 0) {
      _lastKnownUnreadCount = previous - 1;
    }
    widget.onUnreadCountDecremented?.call();
  }

  Future<void> _load() async {
    final generation = ++_loadGeneration;
    final token = widget.authService.authToken;
    final unreadFetchGeneration = ++_unreadFetchGeneration;
    final unreadMutationGeneration = _unreadMutationGeneration;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _loadingMore = false;
      _error = null;
    });
    try {
      final payloads = await Future.wait([
        widget.backendApiService.fetchInboxAlerts(identityToken: token),
        widget.backendApiService.fetchFeedbackThreads(identityToken: token),
      ]);
      final alertPayload = payloads[0];
      final threadPayload = payloads[1];
      if (!mounted ||
          generation != _loadGeneration ||
          token != widget.authService.authToken) {
        return;
      }
      final rows = [
        ..._normalizeRows(alertPayload['alerts'], 'alert'),
        ..._normalizeRows(threadPayload['threads'], 'support'),
      ]..sort(_compareRows);
      if (mounted) {
        setState(() {
          _rows = rows;
          _alertsCursor = alertPayload['nextCursor'] is String
              ? alertPayload['nextCursor'] as String
              : null;
          _threadsCursor = threadPayload['nextCursor'] is String
              ? threadPayload['nextCursor'] as String
              : null;
          _loading = false;
        });
        _applyFetchedUnreadResult(
          _combinedUnreadCount(alertPayload),
          unreadFetchGeneration,
          unreadMutationGeneration,
        );
        // The Home entry opens the standalone page and clears the inbox on
        // entry. Embedded Inbox is also used by existing shell/tutorial flows
        // where opening the tab must preserve per-item read semantics.
        if (widget.clearOnOpen) {
          unawaited(_markVisibleAlertsRead(rows, generation));
        }
      }
    } catch (_) {
      if (mounted &&
          generation == _loadGeneration &&
          token == widget.authService.authToken) {
        setState(() {
          _loading = false;
          _error = 'Couldn’t load your Inbox.';
        });
      }
    }
  }

  Future<void> _markVisibleAlertsRead(
    List<Map<String, dynamic>> rows,
    int loadGeneration,
  ) async {
    final token = widget.authService.authToken;
    final userId = widget.authService.userId;
    if (token == null || token.isEmpty) return;
    final unread = rows
        .where(
          (row) =>
              row['_inboxKind'] == 'alert' &&
              row['readAt'] == null &&
              row['id'] is String,
        )
        .toList(growable: false);
    final allAlertIds = <String>{for (final row in unread) row['id'] as String};
    var cursor = _alertsCursor;
    while (cursor != null && cursor.isNotEmpty) {
      try {
        final payload = await widget.backendApiService.fetchInboxAlerts(
          identityToken: token,
          cursor: cursor,
          limit: 50,
        );
        final raw = payload['alerts'];
        if (raw is List) {
          for (final rawRow in raw.whereType<Map>()) {
            final id = rawRow['id'];
            final readAt = rawRow['readAt'];
            if (id is String && id.isNotEmpty && readAt == null) {
              allAlertIds.add(id);
            }
          }
        }
        cursor = payload['nextCursor'] is String
            ? payload['nextCursor'] as String
            : null;
      } catch (_) {
        cursor = null;
      }
    }
    final succeeded = <String>{};
    for (final row in unread) {
      row['readAt'] = DateTime.now().toIso8601String();
    }
    await Future.wait(
      allAlertIds.map((id) async {
        try {
          await widget.backendApiService.markInboxAlertRead(
            identityToken: token,
            alertId: id,
          );
          succeeded.add(id);
        } catch (_) {}
      }),
    );
    if (mounted &&
        token == widget.authService.authToken &&
        userId == widget.authService.userId &&
        loadGeneration == _loadGeneration) {
      for (final row in unread) {
        if (!succeeded.contains(row['id'])) row['readAt'] = null;
      }
      if (succeeded.length == allAlertIds.length) {
        _lastKnownUnreadCount = 0;
        widget.onUnreadCountChanged?.call(0);
      } else {
        unawaited(_refreshUnreadCount());
      }
      setState(() {});
    }
  }

  Future<void> _loadMore() async {
    final token = widget.authService.authToken;
    if (_loadingMore ||
        (_alertsCursor == null && _threadsCursor == null) ||
        token == null ||
        token.isEmpty) {
      return;
    }
    final alertsCursor = _alertsCursor;
    final threadsCursor = _threadsCursor;
    final unreadFetchGeneration = ++_unreadFetchGeneration;
    final unreadMutationGeneration = _unreadMutationGeneration;
    setState(() => _loadingMore = true);
    try {
      final payloads = await Future.wait([
        if (alertsCursor != null)
          widget.backendApiService.fetchInboxAlerts(
            identityToken: token,
            cursor: alertsCursor,
          )
        else
          Future.value(const <String, dynamic>{'alerts': <dynamic>[]}),
        if (threadsCursor != null)
          widget.backendApiService.fetchFeedbackThreads(
            identityToken: token,
            cursor: threadsCursor,
          )
        else
          Future.value(const <String, dynamic>{'threads': <dynamic>[]}),
      ]);
      final alertPayload = payloads[0];
      final threadPayload = payloads[1];
      if (!mounted ||
          token != widget.authService.authToken ||
          alertsCursor != _alertsCursor ||
          threadsCursor != _threadsCursor) {
        return;
      }
      final incoming = [
        ..._normalizeRows(alertPayload['alerts'], 'alert'),
        ..._normalizeRows(threadPayload['threads'], 'support'),
      ]..sort(_compareRows);
      if (mounted) {
        setState(() {
          _rows = [..._rows, ...incoming]..sort(_compareRows);
          _alertsCursor = alertPayload['nextCursor'] is String
              ? alertPayload['nextCursor'] as String
              : null;
          _threadsCursor = threadPayload['nextCursor'] is String
              ? threadPayload['nextCursor'] as String
              : null;
          _loadingMore = false;
        });
        _applyFetchedUnreadResult(
          _combinedUnreadCount(alertPayload),
          unreadFetchGeneration,
          unreadMutationGeneration,
        );
      }
    } catch (_) {
      if (mounted &&
          token == widget.authService.authToken &&
          alertsCursor == _alertsCursor &&
          threadsCursor == _threadsCursor) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _openAlert(Map<String, dynamic> alert) async {
    final token = widget.authService.authToken;
    final id = alert['id'];
    final locallyUnread = alert['readAt'] == null;
    if (alert['_inboxKind'] != 'alert') {
      final threadId = alert['id'];
      if (threadId is! String || threadId.isEmpty) return;
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (_) => SupportThreadScreen(
            authService: widget.authService,
            backendApiService: widget.backendApiService,
            threadId: threadId,
            onThreadRead: _refreshUnreadCount,
          ),
        ),
      );
      if (mounted) _load();
      return;
    }
    if (!locallyUnread) {
      _openDestination(alert['destination']);
      return;
    }
    if (token == null ||
        token.isEmpty ||
        id is! String ||
        id.isEmpty ||
        _readingAlertGenerations.containsKey(id)) {
      return;
    }
    final userId = widget.authService.userId;
    if (_pendingAlertReads == 0) {
      _readBatchGeneration++;
      _readBatchConcurrent = false;
      _readBatchSawAuthoritativeCount = false;
    } else {
      _readBatchConcurrent = true;
    }
    final readBatchGeneration = _readBatchGeneration;
    _pendingAlertReads++;
    final readGeneration = ++_nextAlertReadGeneration;
    // A GET begun before this mutation cannot describe the post-read total.
    _unreadMutationGeneration++;
    _readingAlertGenerations[id] = readGeneration;
    var readSucceeded = false;
    Map<String, dynamic>? readPayload;
    try {
      readPayload = await widget.backendApiService.markInboxAlertRead(
        identityToken: token,
        alertId: id,
      );
      readSucceeded = readPayload['read'] == true;
    } catch (_) {}
    final ownsRead =
        _readingAlertGenerations[id] == readGeneration &&
        readBatchGeneration == _readBatchGeneration;
    if (!ownsRead ||
        !mounted ||
        token != widget.authService.authToken ||
        userId != widget.authService.userId) {
      return;
    }
    _readingAlertGenerations.remove(id);
    _pendingAlertReads--;
    if (readSucceeded) {
      final hasAuthoritativeUnreadCount =
          readPayload?.containsKey('totalUnreadCount') == true ||
          readPayload?.containsKey('unreadCount') == true;
      final authoritativeUnread = readPayload == null
          ? null
          : _combinedUnreadCount(readPayload);
      if (!hasAuthoritativeUnreadCount) {
        _applyLegacyReadDecrement();
      } else {
        _readBatchSawAuthoritativeCount = true;
        if (authoritativeUnread != null &&
            !_readBatchConcurrent &&
            _pendingAlertReads == 0) {
          _applySingleReadAuthoritativeCount(authoritativeUnread);
        }
      }
      setState(() => alert['readAt'] = DateTime.now().toIso8601String());
    }
    final reconcileConcurrentAuthoritativeReads =
        _pendingAlertReads == 0 &&
        _readBatchConcurrent &&
        _readBatchSawAuthoritativeCount;
    if (_pendingAlertReads == 0) {
      _readBatchConcurrent = false;
      _readBatchSawAuthoritativeCount = false;
    }
    if (reconcileConcurrentAuthoritativeReads) {
      unawaited(_refreshUnreadCount());
    }
    _openDestination(alert['destination']);
  }

  void _openDestination(Object? rawDestination) {
    if (!mounted ||
        rawDestination is! Map ||
        InboxDestination.tryParse(rawDestination) == null) {
      return;
    }
    widget.onOpenDestination?.call(_stringKeyedMap(rawDestination));
  }

  Future<void> _refreshUnreadCount() async {
    final token = widget.authService.authToken;
    final userId = widget.authService.userId;
    if (token == null || token.isEmpty) return;
    final fetchGeneration = ++_unreadFetchGeneration;
    final mutationGeneration = _unreadMutationGeneration;
    try {
      final payload = await widget.backendApiService.fetchInboxAlerts(
        identityToken: token,
        limit: 1,
      );
      if (!mounted ||
          token != widget.authService.authToken ||
          userId != widget.authService.userId) {
        return;
      }
      _applyFetchedUnreadResult(
        _combinedUnreadCount(payload),
        fetchGeneration,
        mutationGeneration,
      );
    } catch (_) {
      // Keep the last shell badge when an older backend/network cannot refresh.
    }
  }

  static Map<String, dynamic> _stringKeyedMap(Map raw) => {
    for (final entry in raw.entries)
      if (entry.key is String) entry.key as String: entry.value,
  };

  static List<Map<String, dynamic>> _normalizeRows(Object? raw, String kind) {
    if (raw is! List) return const [];
    return raw
        .whereType<Map>()
        .map((row) {
          final normalized = _stringKeyedMap(row);
          normalized['_inboxKind'] = kind;
          if (kind == 'support' && normalized['createdAt'] == null) {
            normalized['createdAt'] = normalized['lastMessageAt'];
          }
          return normalized;
        })
        .where((row) {
          if (row['id'] is! String || (row['id'] as String).isEmpty) {
            return false;
          }
          if (kind != 'alert') return true;
          return _visibleAlertTypes.contains(row['type']) &&
              InboxDestination.tryParse(row['destination']) != null;
        })
        .toList();
  }

  static const _visibleAlertTypes = <String>{
    'FRIEND_REQUEST_SENT',
    'FRIEND_REQUEST_ACCEPTED',
    'RACE_INVITE_SENT',
    'RACE_INVITE_ACCEPTED',
    'RACE_BUYIN_CHANGED',
    'TEAM_RACE_SCHEDULED_UNEVEN',
    'RACE_STARTED',
    'RACE_COMPLETED',
    'TEAM_LEAD_CHANGE',
    'RACE_CANCELLED',
    'REFERRAL_REWARDED',
    'GLOBAL_EVENT_STARTED',
    'TOURNAMENT_INVITE_SENT',
    'TOURNAMENT_STARTED',
    'TOURNAMENT_ROUND_STARTED',
    'TOURNAMENT_MATCHUP_WON',
    'TOURNAMENT_ELIMINATED',
    'TOURNAMENT_CHAMPION',
    'TOURNAMENT_COMPLETED',
    'TOURNAMENT_CANCELLED',
    'HIGH_MULTIPLIER_ALERT',
  };

  static String _categoryLabel(Object? type) {
    final value = type is String ? type : '';
    if (value.startsWith('TOURNAMENT_')) return 'TOURNAMENT';
    if (value.startsWith('RACE_') || value.startsWith('TEAM_')) return 'RACE';
    if (value.startsWith('FRIEND_')) return 'FRIENDS';
    if (value == 'REFERRAL_REWARDED' || value == 'GLOBAL_EVENT_STARTED') {
      return 'REWARD';
    }
    return 'IMPORTANT';
  }

  static int _compareRows(Map<String, dynamic> a, Map<String, dynamic> b) {
    final aDate = DateTime.tryParse('${a['createdAt'] ?? ''}');
    final bDate = DateTime.tryParse('${b['createdAt'] ?? ''}');
    if (aDate == null && bDate == null) return 0;
    if (aDate == null) return 1;
    if (bDate == null) return -1;
    return bDate.compareTo(aDate);
  }

  // New backends preserve alert-only `unreadCount` for frozen clients and add
  // the combined alerts+support badge as `totalUnreadCount`. Older backends
  // expose only `unreadCount`, so fall back defensively when the additive key
  // is absent or malformed.
  static int? _combinedUnreadCount(Map<String, dynamic> payload) =>
      _nonnegativeInt(payload['totalUnreadCount']) ??
      _nonnegativeInt(payload['unreadCount']);

  @override
  Widget build(BuildContext context) {
    super.build(context);
    final embedded = widget.hostMode == InboxHostMode.embedded;
    final bottomPadding = embedded
        ? 77.5 + MediaQuery.of(context).padding.bottom
        : 0.0;
    return Scaffold(
      backgroundColor: AppColors.of(context).parchment,
      body: ArcadePageBackground(
        headerHeight: 56,
        headerColor: AppColors.of(context).roofLight,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomPadding),
          child: Column(
            children: [
              if (embedded)
                _embeddedHeader(context)
              else
                _standaloneHeader(context),
              Expanded(
                child: ColoredBox(
                  color: AppColors.of(context).parchment,
                  child: _body(context),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _standaloneHeader(BuildContext context) => Padding(
    padding: EdgeInsets.fromLTRB(
      16,
      MediaQuery.of(context).padding.top + 10,
      16,
      10,
    ),
    child: Row(
      children: [
        GestureDetector(
          onTap: () => Navigator.of(context).pop(),
          child: const Padding(
            padding: EdgeInsets.all(8),
            child: Icon(Icons.arrow_back, color: Colors.white),
          ),
        ),
        const SizedBox(width: 8),
        Text(
          'NOTIFICATIONS',
          style: PixelText.title(
            size: 22,
            color: AppColors.of(context).textLight,
          ),
        ),
      ],
    ),
  );

  Widget _embeddedHeader(BuildContext context) => Container(
    width: double.infinity,
    color: AppColors.of(context).roofDark,
    padding: EdgeInsets.fromLTRB(
      16,
      MediaQuery.of(context).padding.top + 14,
      16,
      12,
    ),
    child: Text(
      'INBOX',
      style: PixelText.title(size: 28, color: AppColors.of(context).textLight),
    ),
  );

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: _InboxActionButton(label: 'TRY AGAIN', onPressed: _load),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          'YOU’RE CAUGHT UP',
          style: PixelText.title(
            size: 14,
            color: AppColors.of(context).textMid,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount:
          _rows.length +
          (_alertsCursor == null && _threadsCursor == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == _rows.length) {
          return Center(
            child: _InboxActionButton(
              label: _loadingMore ? 'LOADING…' : 'LOAD MORE',
              onPressed: _loadingMore ? null : _loadMore,
            ),
          );
        }
        final row = _rows[index];
        final isSupport = row['_inboxKind'] == 'support';
        final title = isSupport
            ? 'BARA SUPPORT'
            : row['title'] is String
            ? row['title'] as String
            : 'BARA ALERT';
        final body = isSupport
            ? row['preview'] is String
                  ? row['preview'] as String
                  : 'Support conversation'
            : row['body'] is String
            ? row['body'] as String
            : '';
        final category = isSupport ? 'SUPPORT' : _categoryLabel(row['type']);
        final unread = isSupport
            ? row.containsKey('unreadByUser')
                  ? row['unreadByUser'] == true
                  : row.containsKey('unread')
                  ? row['unread'] == true
                  : row['readAt'] == null
            : row['readAt'] == null;
        return InkWell(
          onTap: () => _openAlert(row),
          child: RetroCard(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(14, 12, 14, 13),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Text(
                        category,
                        style: PixelText.title(
                          size: 10,
                          color: unread
                              ? AppColors.of(context).coinDark
                              : AppColors.of(context).textMid,
                        ),
                      ),
                      const Spacer(),
                      if (unread)
                        Text(
                          'NEW',
                          style: PixelText.title(
                            size: 10,
                            color: AppColors.of(context).coinDark,
                          ),
                        ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Text(
                    title,
                    style: PixelText.title(
                      size: 14,
                      color: AppColors.of(context).textDark,
                    ),
                  ),
                  const SizedBox(height: 4),
                  Text(
                    body,
                    maxLines: 2,
                    overflow: TextOverflow.ellipsis,
                    style: PixelText.body(
                      size: 13,
                      color: AppColors.of(context).textMid,
                    ),
                  ),
                  const SizedBox(height: 9),
                  Text(
                    isSupport ? 'REPLY' : 'OPEN',
                    style: PixelText.title(
                      size: 10,
                      color: AppColors.of(context).textAccent,
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }
}

class _InboxActionButton extends StatelessWidget {
  const _InboxActionButton({required this.label, required this.onPressed});

  final String label;
  final VoidCallback? onPressed;

  @override
  Widget build(BuildContext context) {
    final colors = AppColors.of(context);
    final enabled = onPressed != null;
    return Semantics(
      excludeSemantics: true,
      button: true,
      enabled: enabled,
      label: label,
      onTap: onPressed,
      child: Material(
        color: enabled ? colors.roofDark : colors.parchmentDark,
        borderRadius: BorderRadius.circular(9),
        child: InkWell(
          onTap: onPressed,
          excludeFromSemantics: true,
          borderRadius: BorderRadius.circular(9),
          focusColor: colors.coinLight.withValues(alpha: 0.28),
          highlightColor: colors.accent,
          child: Container(
            constraints: const BoxConstraints(minHeight: 48, minWidth: 112),
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
            alignment: Alignment.center,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(9),
              border: Border.all(
                color: enabled ? colors.coinLight : colors.parchmentBorder,
                width: 2,
              ),
            ),
            child: Text(
              label,
              maxLines: 1,
              style: PixelText.title(
                size: 12,
                color: enabled ? colors.textLight : colors.textMid,
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The user side of a staff-only support conversation. All sender identity is
/// fixed by the endpoint; the UI never transmits a role or recipient id.
class SupportThreadScreen extends StatefulWidget {
  const SupportThreadScreen({
    super.key,
    required this.authService,
    required this.backendApiService,
    required this.threadId,
    this.admin = false,
    this.onThreadRead,
  });

  final AuthService authService;
  final BackendApiService backendApiService;
  final String threadId;
  final bool admin;
  final VoidCallback? onThreadRead;

  @override
  State<SupportThreadScreen> createState() => _SupportThreadScreenState();
}

class _SupportThreadScreenState extends State<SupportThreadScreen> {
  final _composer = TextEditingController();
  List<Map<String, dynamic>> _messages = const [];
  String? _nextBefore;
  bool _loading = true;
  bool _sending = false;
  String? _error;
  bool _reportedThreadRead = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void dispose() {
    _composer.dispose();
    super.dispose();
  }

  Future<void> _load({bool older = false}) async {
    final token = widget.authService.authToken;
    final userId = widget.authService.userId;
    if (token == null || token.isEmpty) {
      return;
    }
    if (!older) {
      setState(() {
        _loading = true;
        _error = null;
      });
    }
    try {
      final payload = widget.admin
          ? await widget.backendApiService.fetchAdminFeedbackThread(
              identityToken: token,
              threadId: widget.threadId,
              before: older ? _nextBefore : null,
            )
          : await widget.backendApiService.fetchFeedbackThread(
              identityToken: token,
              threadId: widget.threadId,
              before: older ? _nextBefore : null,
            );
      final raw = payload['messages'];
      final parsed = raw is List
          ? raw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : <Map<String, dynamic>>[];
      if (mounted &&
          token == widget.authService.authToken &&
          userId == widget.authService.userId) {
        setState(() {
          _messages = older ? [...parsed, ..._messages] : parsed;
          _nextBefore = payload['nextBefore'] is String
              ? payload['nextBefore'] as String
              : null;
          _loading = false;
        });
        if (!older &&
            !widget.admin &&
            !_reportedThreadRead &&
            token == widget.authService.authToken) {
          _reportedThreadRead = true;
          widget.onThreadRead?.call();
        }
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = 'Couldn’t load this conversation.';
        });
      }
    }
  }

  Future<void> _send() async {
    final text = _composer.text.trim();
    final token = widget.authService.authToken;
    if (_sending ||
        text.isEmpty ||
        text.length > 2000 ||
        token == null ||
        token.isEmpty) {
      return;
    }
    setState(() => _sending = true);
    try {
      final key = BackendApiService.generateIdempotencyKey();
      final payload = widget.admin
          ? await widget.backendApiService.sendAdminFeedbackThreadMessage(
              identityToken: token,
              threadId: widget.threadId,
              text: text,
              idempotencyKey: key,
            )
          : await widget.backendApiService.sendFeedbackThreadMessage(
              identityToken: token,
              threadId: widget.threadId,
              text: text,
              idempotencyKey: key,
            );
      final message = payload['message'];
      if (mounted) {
        setState(() {
          _composer.clear();
          if (message is Map) {
            _messages = [..._messages, Map<String, dynamic>.from(message)];
          }
          _sending = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _sending = false;
          _error = 'Couldn’t send your message. Try again.';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => Scaffold(
    backgroundColor: AppColors.of(context).parchment,
    appBar: AppBar(
      title: Text(
        widget.admin ? 'SUPPORT REPLY' : 'BARA SUPPORT',
        style: PixelText.title(
          size: 17,
          color: AppColors.of(context).textLight,
        ),
      ),
    ),
    body: Column(
      children: [
        if (_nextBefore != null)
          Padding(
            padding: const EdgeInsets.all(8),
            child: _InboxActionButton(
              label: 'LOAD OLDER',
              onPressed: () => _load(older: true),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _messages.isEmpty
              ? Center(
                  child: _InboxActionButton(
                    label: 'TRY AGAIN',
                    onPressed: _load,
                  ),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _messages.length,
                  itemBuilder: (context, index) {
                    final message = _messages[index];
                    final staff = message['senderKind'] == 'STAFF';
                    final text = message['text'] is String
                        ? message['text'] as String
                        : '';
                    return Align(
                      alignment: staff
                          ? Alignment.centerLeft
                          : Alignment.centerRight,
                      child: Container(
                        margin: const EdgeInsets.only(bottom: 8),
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: staff
                              ? AppColors.of(context).parchmentDark
                              : AppColors.of(
                                  context,
                                ).pillGreenDark.withValues(alpha: 0.22),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          '${staff ? 'BARA SUPPORT\n' : ''}$text',
                          style: PixelText.body(
                            size: 13,
                            color: AppColors.of(context).textDark,
                          ),
                        ),
                      ),
                    );
                  },
                ),
        ),
        SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _composer,
                    maxLength: 2000,
                    minLines: 1,
                    maxLines: 4,
                    decoration: const InputDecoration(
                      hintText: 'Write a message',
                      counterText: '',
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                _InboxActionButton(
                  label: _sending ? 'SENDING…' : 'SEND',
                  onPressed: _sending ? null : _send,
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
