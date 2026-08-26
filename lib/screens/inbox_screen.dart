import 'dart:async';

import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
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
  raceJoinRequest,
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
    this.requestId,
  });

  final InboxDestinationRoute route;
  final String? raceId;
  final String? tournamentId;
  final String? threadId;
  final String? requestId;

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
      case 'raceJoinRequest':
        final raceId = raw['raceId'];
        final requestId = raw['requestId'];
        return raceId is String &&
                raceId.isNotEmpty &&
                requestId is String &&
                requestId.isNotEmpty
            ? InboxDestination._(
                InboxDestinationRoute.raceJoinRequest,
                raceId: raceId,
                requestId: requestId,
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
  bool _readAllAttempted = false;
  int? _lastSuccessfulReadAllMutationGeneration;
  final Map<String, String> _joinRequestStatuses = <String, String>{};
  final Set<String> _respondingJoinRequests = <String>{};
  final Map<String, String> _joinRequestErrors = <String, String>{};

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
    _readAllAttempted = false;
    _lastSuccessfulReadAllMutationGeneration = null;
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
      final changed = _lastKnownUnreadCount != unread;
      _lastAppliedUnreadFetchGeneration = fetchGeneration;
      _lastKnownUnreadCount = unread;
      if (changed) widget.onUnreadCountChanged?.call(unread);
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
        // Only the Home-launched standalone route opts into clear-on-open.
        // Embedded/tutorial Inbox retains its existing item-level semantics.
        if (widget.hostMode == InboxHostMode.standalone &&
            widget.clearOnOpen &&
            !_readAllAttempted) {
          _readAllAttempted = true;
          unawaited(_markInboxReadAll(generation));
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

  Future<void> _markInboxReadAll(int loadGeneration) async {
    final token = widget.authService.authToken;
    final userId = widget.authService.userId;
    if (token == null || token.isEmpty) return;
    final mutationGeneration = ++_unreadMutationGeneration;
    try {
      await widget.backendApiService.markInboxAlertsRead(identityToken: token);
      if (!mounted ||
          token != widget.authService.authToken ||
          userId != widget.authService.userId ||
          loadGeneration != _loadGeneration ||
          mutationGeneration != _unreadMutationGeneration) {
        return;
      }
      // Any fetch started before read-all must not overwrite its authoritative
      // combined count when it completes after this mutation.
      _unreadMutationGeneration++;
      _lastSuccessfulReadAllMutationGeneration = _unreadMutationGeneration;
      final readAt = DateTime.now().toIso8601String();
      var markedAlerts = 0;
      for (final row in _rows) {
        if (row['_inboxKind'] == 'alert' && row['readAt'] == null) {
          row['readAt'] = readAt;
          markedAlerts++;
        }
      }
      final previous = _lastKnownUnreadCount;
      if (previous != null) {
        final next = (previous - markedAlerts).clamp(0, previous);
        _lastKnownUnreadCount = next;
        widget.onUnreadCountChanged?.call(next);
      }
      setState(() {});
      // The alert-read endpoint intentionally does not clear staff replies.
      // Re-fetch the additive combined count so the shell badge reflects any
      // unread staff replies that remain on the authoritative backend.
      await _refreshUnreadCount();
    } catch (_) {
      // A missing endpoint, transport error, or malformed total is a
      // recoverable clear failure. Keep the existing badge and row state.
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
      // A read-all or per-item mutation may have completed while this page
      // was loading. Do not reintroduce stale NEW markers from that response.
      if (_lastSuccessfulReadAllMutationGeneration != null &&
          _lastSuccessfulReadAllMutationGeneration ==
              _unreadMutationGeneration &&
          _unreadMutationGeneration != unreadMutationGeneration) {
        final readAt = DateTime.now().toIso8601String();
        for (final row in incoming) {
          if (row['_inboxKind'] == 'alert') row['readAt'] = readAt;
        }
      }
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

  Future<void> _respondToJoinRequest(
    Map<String, dynamic> alert,
    String action,
  ) async {
    final token = widget.authService.authToken;
    final raceId = alert['raceId'];
    final requestId = alert['requestId'];
    if (token == null ||
        token.isEmpty ||
        raceId is! String ||
        raceId.isEmpty ||
        requestId is! String ||
        requestId.isEmpty ||
        _respondingJoinRequests.contains(requestId)) {
      return;
    }
    setState(() {
      _respondingJoinRequests.add(requestId);
      _joinRequestErrors.remove(requestId);
    });
    try {
      final payload = await widget.backendApiService
          .respondToPrivateRaceJoinRequest(
            identityToken: token,
            raceId: raceId,
            requestId: requestId,
            action: action,
          );
      final rawRequest = payload['joinRequest'];
      final status = rawRequest is Map ? rawRequest['status'] : null;
      if (!mounted || token != widget.authService.authToken) return;
      setState(() {
        _respondingJoinRequests.remove(requestId);
        _joinRequestStatuses[requestId] = status is String && status.isNotEmpty
            ? status
            : action == 'ACCEPT'
            ? 'ACCEPTED'
            : 'DECLINED';
      });
    } on ApiException catch (error) {
      if (!mounted || token != widget.authService.authToken) return;
      setState(() {
        _respondingJoinRequests.remove(requestId);
        _joinRequestErrors[requestId] = error.message;
      });
    } catch (_) {
      if (!mounted || token != widget.authService.authToken) return;
      setState(() {
        _respondingJoinRequests.remove(requestId);
        _joinRequestErrors[requestId] = 'Couldn’t update this request.';
      });
    }
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
            normalized['createdAt'] =
                normalized['lastStaffReplyAt'] ?? normalized['lastMessageAt'];
          }
          return normalized;
        })
        .where((row) {
          if (row['id'] is! String || (row['id'] as String).isEmpty) {
            return false;
          }
          if (kind != 'alert') return true;
          if (!_visibleAlertTypes.contains(row['type'])) return false;
          if (row['type'] == 'PRIVATE_RACE_JOIN_APPROVAL') {
            final rawDestination = row['destination'];
            if (rawDestination is Map) {
              final destination = _stringKeyedMap(rawDestination);
              final parsed = InboxDestination.tryParse(destination);
              if (parsed?.route != InboxDestinationRoute.raceJoinRequest) {
                return false;
              }
              row['destination'] = destination;
              row['raceId'] = parsed!.raceId;
              row['requestId'] = parsed.requestId;
              return true;
            }
            // Mixed-version fallback for the earlier additive flat shape.
            // It is accepted only when every required identifier is present,
            // then normalized into the same allowlisted nested destination.
            final raceId = row['raceId'];
            final requestId = row['requestId'];
            if (rawDestination == 'RACE_JOIN_REQUEST' &&
                raceId is String &&
                raceId.isNotEmpty &&
                requestId is String &&
                requestId.isNotEmpty) {
              row['destination'] = {
                'route': 'raceJoinRequest',
                'raceId': raceId,
                'requestId': requestId,
              };
              return true;
            }
            return false;
          }
          if (row['type'] == 'PRIVATE_RACE_JOIN_RESULT' &&
              row['destination'] == 'RACE' &&
              row['raceId'] is String) {
            row['destination'] = {
              'route': 'raceDetail',
              'raceId': row['raceId'],
            };
          }
          if (row['type'] == 'UNCLAIMED_REWARD') {
            if (row['destination'] == 'RACE' && row['raceId'] is String) {
              row['destination'] = {
                'route': 'raceDetail',
                'raceId': row['raceId'],
              };
            } else if (row['destination'] == 'DAILY_REWARD') {
              row['destination'] = const {'route': 'dailyReward'};
            }
          }
          return InboxDestination.tryParse(row['destination']) != null;
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
    'PRIVATE_RACE_JOIN_APPROVAL',
    'PRIVATE_RACE_JOIN_RESULT',
    'UNCLAIMED_REWARD',
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
    final aDate = DateTime.tryParse(
      '${a['sortAt'] ?? a['lastStaffReplyAt'] ?? a['lastMessageAt'] ?? a['createdAt'] ?? ''}',
    );
    final bDate = DateTime.tryParse(
      '${b['sortAt'] ?? b['lastStaffReplyAt'] ?? b['lastMessageAt'] ?? b['createdAt'] ?? ''}',
    );
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
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'INBOX',
                style: PixelText.title(
                  size: 28,
                  color: AppColors.of(context).textLight,
                ),
              ),
              Text(
                'The things that need your attention.',
                style: PixelText.body(
                  size: 10,
                  color: AppColors.of(context).textLight.withValues(alpha: .78),
                ),
              ),
            ],
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
    child: Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(
          'INBOX',
          style: PixelText.title(
            size: 28,
            color: AppColors.of(context).textLight,
          ),
        ),
        const SizedBox(height: 2),
        Text(
          'The things that need your attention.',
          style: PixelText.body(
            size: 10,
            color: AppColors.of(context).textLight.withValues(alpha: .78),
          ),
        ),
      ],
    ),
  );

  Widget _body(BuildContext context) {
    final colors = AppColors.of(context);
    final hasMore = _alertsCursor != null || _threadsCursor != null;
    final pinned = _rows
        .where(
          (row) =>
              row['_inboxKind'] == 'support' &&
              row['hasUnreadStaffReply'] == true,
        )
        .toList(growable: false);
    final pinnedIds = pinned.map((row) => row['id']).toSet();
    final visibleRows = <Map<String, dynamic>>[
      if (pinned.isNotEmpty) const {'_inboxHeading': 'REPLIES FROM BARA'},
      ...pinned,
      ..._rows.where(
        (row) =>
            row['_inboxKind'] != 'support' || !pinnedIds.contains(row['id']),
      ),
    ];
    return Container(
      key: const ValueKey('inbox-dispatch-board'),
      margin: const EdgeInsets.fromLTRB(12, 10, 12, 18),
      decoration: BoxDecoration(
        color: colors.parchmentLight,
        border: Border.all(color: colors.parchmentBorder, width: 2),
        boxShadow: [
          BoxShadow(color: colors.woodShadow, offset: const Offset(0, 4)),
        ],
      ),
      child: _loading
          ? const Center(
              key: ValueKey('inbox-loading'),
              child: CircularProgressIndicator(),
            )
          : _error != null
          ? Center(
              key: const ValueKey('inbox-error'),
              child: _InboxActionButton(label: 'TRY AGAIN', onPressed: _load),
            )
          : _rows.isEmpty
          ? Center(
              key: const ValueKey('inbox-empty'),
              child: Text(
                'YOU’RE CAUGHT UP',
                style: PixelText.title(size: 14, color: colors.textMid),
              ),
            )
          : ListView.separated(
              padding: const EdgeInsets.fromLTRB(10, 4, 10, 16),
              itemCount: visibleRows.length + (hasMore ? 1 : 0),
              separatorBuilder: (_, _) =>
                  Divider(height: 1, color: colors.parchmentBorder),
              itemBuilder: (context, index) {
                if (index == visibleRows.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 10),
                    child: Center(
                      key: const ValueKey('inbox-load-more'),
                      child: _InboxActionButton(
                        label: _loadingMore ? 'LOADING…' : 'LOAD MORE',
                        onPressed: _loadingMore ? null : _loadMore,
                      ),
                    ),
                  );
                }
                final row = visibleRows[index];
                final heading = row['_inboxHeading'];
                if (heading is String) {
                  return Padding(
                    key: const Key('inbox-staff-replies-heading'),
                    padding: const EdgeInsets.fromLTRB(4, 14, 4, 8),
                    child: Row(
                      children: [
                        Icon(
                          Icons.mark_email_unread_rounded,
                          size: 16,
                          color: colors.coinDark,
                        ),
                        const SizedBox(width: 7),
                        Text(
                          heading,
                          style: PixelText.title(
                            size: 11,
                            color: colors.coinDark,
                          ),
                        ),
                      ],
                    ),
                  );
                }
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
                final category = isSupport
                    ? 'SUPPORT'
                    : _categoryLabel(row['type']);
                final unread = isSupport
                    ? row.containsKey('unreadByUser')
                          ? row['unreadByUser'] == true
                          : row.containsKey('unread')
                          ? row['unread'] == true
                          : row['readAt'] == null
                    : row['readAt'] == null;
                final timestampRaw = isSupport
                    ? row['lastStaffReplyAt'] ??
                          row['lastMessageAt'] ??
                          row['createdAt']
                    : row['createdAt'];
                final timestamp = _compactTimestamp(context, timestampRaw);
                final fullTimestamp = _fullTimestamp(context, timestampRaw);
                final isJoinApproval =
                    row['type'] == 'PRIVATE_RACE_JOIN_APPROVAL';
                final requestId = row['requestId'] is String
                    ? row['requestId'] as String
                    : '';
                final requestStatus =
                    _joinRequestStatuses[requestId] ??
                    (row['status'] is String ? row['status'] as String : null);
                final responding = _respondingJoinRequests.contains(requestId);
                final responseError = _joinRequestErrors[requestId];
                return Semantics(
                  button: true,
                  label:
                      '$title${fullTimestamp == null ? '' : ', $fullTimestamp'}${unread ? ', unread' : ''}',
                  child: InkWell(
                    key: ValueKey(
                      'inbox-row-${isSupport ? 'support' : 'alert'}-${row['id']}',
                    ),
                    onTap: () => _openAlert(row),
                    child: ConstrainedBox(
                      constraints: const BoxConstraints(minHeight: 72),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 4,
                          vertical: 8,
                        ),
                        child: Row(
                          children: [
                            Container(
                              width: 38,
                              height: 38,
                              alignment: Alignment.center,
                              decoration: BoxDecoration(
                                color: unread
                                    ? colors.coinLight
                                    : colors.parchmentDark,
                                border: Border.all(
                                  color: colors.parchmentBorder,
                                ),
                              ),
                              child: Icon(
                                _categoryIcon(row['type'], isSupport),
                                size: 19,
                                color: colors.textDark,
                              ),
                            ),
                            const SizedBox(width: 10),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Text(
                                        category,
                                        style: PixelText.title(
                                          size: 9,
                                          color: unread
                                              ? colors.coinDark
                                              : colors.textMid,
                                        ),
                                      ),
                                      if (timestamp != null) ...[
                                        const SizedBox(width: 6),
                                        Text(
                                          timestamp,
                                          style: PixelText.body(
                                            size: 9,
                                            color: colors.textMid,
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    title,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PixelText.title(
                                      size: 13,
                                      color: colors.textDark,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    body,
                                    maxLines: isJoinApproval ? 2 : 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: PixelText.body(
                                      size: 11,
                                      color: colors.textMid,
                                    ),
                                  ),
                                  if (isJoinApproval) ...[
                                    const SizedBox(height: 8),
                                    if (requestStatus != null &&
                                        requestStatus != 'PENDING')
                                      Text(
                                        requestStatus,
                                        key: ValueKey(
                                          'join-request-status-$requestId',
                                        ),
                                        style: PixelText.title(
                                          size: 11,
                                          color: requestStatus == 'ACCEPTED'
                                              ? colors.success
                                              : colors.textMid,
                                        ),
                                      )
                                    else if (responding)
                                      Text(
                                        'UPDATING…',
                                        style: PixelText.title(
                                          size: 10,
                                          color: colors.coinDark,
                                        ),
                                      )
                                    else
                                      Row(
                                        children: [
                                          Expanded(
                                            child: KeyedSubtree(
                                              key: ValueKey(
                                                'join-request-accept-$requestId',
                                              ),
                                              child: _InboxActionButton(
                                                label: 'ACCEPT',
                                                compact: true,
                                                onPressed: () =>
                                                    _respondToJoinRequest(
                                                      row,
                                                      'ACCEPT',
                                                    ),
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: KeyedSubtree(
                                              key: ValueKey(
                                                'join-request-decline-$requestId',
                                              ),
                                              child: _InboxActionButton(
                                                label: 'DECLINE',
                                                compact: true,
                                                onPressed: () =>
                                                    _respondToJoinRequest(
                                                      row,
                                                      'DECLINE',
                                                    ),
                                              ),
                                            ),
                                          ),
                                        ],
                                      ),
                                    if (responseError != null) ...[
                                      const SizedBox(height: 5),
                                      Text(
                                        responseError,
                                        style: PixelText.body(
                                          size: 9,
                                          color: colors.error,
                                        ),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            ),
                            if (unread)
                              Container(
                                key: ValueKey('inbox-unread-${row['id']}'),
                                width: 6,
                                height: 6,
                                margin: const EdgeInsets.symmetric(
                                  horizontal: 7,
                                ),
                                decoration: BoxDecoration(
                                  color: colors.coinDark,
                                  shape: BoxShape.circle,
                                ),
                              ),
                            Icon(
                              Icons.chevron_right,
                              color: colors.textMid,
                              size: 20,
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                );
              },
            ),
    );
  }

  static IconData _categoryIcon(Object? raw, bool support) {
    if (support) return Icons.support_agent_rounded;
    final type = raw is String ? raw : '';
    if (type.startsWith('FRIEND_REQUEST') ||
        type.startsWith('FRIEND_ACCEPTED')) {
      return Icons.person_add_alt_1_rounded;
    }
    if (type.startsWith('RACE_') ||
        type.startsWith('TEAM_') ||
        type == 'RACE_COMPLETED') {
      return Icons.flag_rounded;
    }
    if (type.startsWith('TOURNAMENT') || type == 'TOURNAMENT') {
      return Icons.emoji_events_rounded;
    }
    if (type.startsWith('REWARD') || type == 'REFERRAL_REWARDED') {
      return Icons.card_giftcard_rounded;
    }
    return Icons.notifications_rounded;
  }

  static DateTime? _timestamp(Object? raw) {
    if (raw is! String) return null;
    final date = DateTime.tryParse(raw);
    return date?.toLocal();
  }

  static String? _compactTimestamp(BuildContext context, Object? raw) {
    final local = _timestamp(raw);
    if (local == null) return null;
    final now = DateTime.now();
    final age = now.difference(local);
    if (!age.isNegative && age < const Duration(hours: 24)) {
      if (age.inMinutes < 1) return 'NOW';
      if (age.inHours < 1) return '${age.inMinutes}M';
      return '${age.inHours}H';
    }
    final localizations = MaterialLocalizations.of(context);
    final date = local.year == now.year
        ? localizations.formatShortMonthDay(local)
        : localizations.formatMediumDate(local);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '$date · $time';
  }

  static String? _fullTimestamp(BuildContext context, Object? raw) {
    final local = _timestamp(raw);
    if (local == null) return null;
    final localizations = MaterialLocalizations.of(context);
    final time = localizations.formatTimeOfDay(
      TimeOfDay.fromDateTime(local),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context),
    );
    return '${localizations.formatFullDate(local)}, $time';
  }
}

class _InboxActionButton extends StatelessWidget {
  const _InboxActionButton({
    required this.label,
    required this.onPressed,
    this.compact = false,
  });

  final String label;
  final VoidCallback? onPressed;
  final bool compact;

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
            constraints: BoxConstraints(
              minHeight: compact ? 40 : 48,
              minWidth: compact ? 0 : 112,
            ),
            padding: EdgeInsets.symmetric(
              horizontal: compact ? 6 : 16,
              vertical: compact ? 7 : 10,
            ),
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
