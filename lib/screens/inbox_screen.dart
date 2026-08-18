import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../styles.dart';
import '../widgets/pill_button.dart';
import '../widgets/retro_card.dart';

enum InboxDestinationRoute {
  home,
  dailyReward,
  friends,
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
    switch (route) {
      case 'home':
        return const InboxDestination._(InboxDestinationRoute.home);
      case 'dailyReward':
        return const InboxDestination._(InboxDestinationRoute.dailyReward);
      case 'friends':
        return const InboxDestination._(InboxDestinationRoute.friends);
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

/// Recipient-private Inbox v1. It intentionally offers only system alerts and
/// staff-owned feedback threads—there is no user search, profile lookup, or
/// player-to-player composer in this surface.
class InboxScreen extends StatefulWidget {
  const InboxScreen({
    super.key,
    required this.authService,
    required this.backendApiService,
    this.onOpenDestination,
  });

  final AuthService authService;
  final BackendApiService backendApiService;
  final ValueChanged<Map<String, dynamic>>? onOpenDestination;

  @override
  State<InboxScreen> createState() => _InboxScreenState();
}

class _InboxScreenState extends State<InboxScreen> {
  bool _support = false;
  bool _loading = true;
  String? _error;
  List<Map<String, dynamic>> _rows = const [];
  String? _nextCursor;
  bool _loadingMore = false;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final token = widget.authService.authToken;
    if (token == null || token.isEmpty) {
      setState(() {
        _loading = false;
        _error = 'Not signed in.';
      });
      return;
    }
    setState(() {
      _loading = true;
      _error = null;
    });
    try {
      final payload = _support
          ? await widget.backendApiService.fetchFeedbackThreads(
              identityToken: token,
            )
          : await widget.backendApiService.fetchInboxAlerts(
              identityToken: token,
            );
      final raw = payload[_support ? 'threads' : 'alerts'];
      final rows = raw is List
          ? raw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _rows = rows;
          _nextCursor = payload['nextCursor'] is String
              ? payload['nextCursor'] as String
              : null;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
          _error = _support
              ? 'Couldn’t load support messages.'
              : 'Couldn’t load alerts.';
        });
      }
    }
  }

  Future<void> _loadMore() async {
    final token = widget.authService.authToken;
    final cursor = _nextCursor;
    if (_loadingMore || cursor == null || token == null || token.isEmpty) {
      return;
    }
    setState(() => _loadingMore = true);
    try {
      final payload = _support
          ? await widget.backendApiService.fetchFeedbackThreads(
              identityToken: token,
              cursor: cursor,
            )
          : await widget.backendApiService.fetchInboxAlerts(
              identityToken: token,
              cursor: cursor,
            );
      final raw = payload[_support ? 'threads' : 'alerts'];
      final incoming = raw is List
          ? raw
                .whereType<Map>()
                .map((row) => Map<String, dynamic>.from(row))
                .toList()
          : <Map<String, dynamic>>[];
      if (mounted) {
        setState(() {
          _rows = [..._rows, ...incoming];
          _nextCursor = payload['nextCursor'] is String
              ? payload['nextCursor'] as String
              : null;
          _loadingMore = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() => _loadingMore = false);
      }
    }
  }

  Future<void> _openAlert(Map<String, dynamic> alert) async {
    final token = widget.authService.authToken;
    final id = alert['id'];
    if (token != null && token.isNotEmpty && id is String && id.isNotEmpty) {
      try {
        await widget.backendApiService.markInboxAlertRead(
          identityToken: token,
          alertId: id,
        );
      } catch (_) {}
    }
    final destination = alert['destination'];
    if (!mounted || destination is! Map) return;
    widget.onOpenDestination?.call(Map<String, dynamic>.from(destination));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.of(context).roofLight,
      appBar: AppBar(
        title: Text(
          'INBOX',
          style: PixelText.title(
            size: 18,
            color: AppColors.of(context).textLight,
          ),
        ),
        backgroundColor: AppColors.of(context).roofLight,
        foregroundColor: AppColors.of(context).textLight,
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(12),
            child: Row(
              children: [
                Expanded(
                  child: PillButton(
                    label: 'ALERTS',
                    variant: !_support
                        ? PillButtonVariant.primary
                        : PillButtonVariant.secondary,
                    onPressed: _support
                        ? () {
                            setState(() => _support = false);
                            _load();
                          }
                        : null,
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: PillButton(
                    label: 'SUPPORT',
                    variant: _support
                        ? PillButtonVariant.primary
                        : PillButtonVariant.secondary,
                    onPressed: !_support
                        ? () {
                            setState(() => _support = true);
                            _load();
                          }
                        : null,
                  ),
                ),
              ],
            ),
          ),
          Expanded(child: _body(context)),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    if (_error != null) {
      return Center(
        child: PillButton(label: 'TRY AGAIN', onPressed: _load),
      );
    }
    if (_rows.isEmpty) {
      return Center(
        child: Text(
          _support ? 'NO SUPPORT MESSAGES YET' : 'NO ALERTS YET',
          style: PixelText.title(
            size: 14,
            color: AppColors.of(context).textMid,
          ),
        ),
      );
    }
    return ListView.separated(
      padding: const EdgeInsets.fromLTRB(12, 4, 12, 24),
      itemCount: _rows.length + (_nextCursor == null ? 0 : 1),
      separatorBuilder: (_, _) => const SizedBox(height: 8),
      itemBuilder: (context, index) {
        if (index == _rows.length) {
          return Center(
            child: PillButton(
              label: _loadingMore ? 'LOADING…' : 'LOAD MORE',
              onPressed: _loadingMore ? null : _loadMore,
            ),
          );
        }
        final row = _rows[index];
        final title = _support
            ? 'BARA SUPPORT'
            : row['title'] is String
            ? row['title'] as String
            : 'BARA ALERT';
        final body = _support
            ? row['preview'] is String
                  ? row['preview'] as String
                  : 'Support conversation'
            : row['body'] is String
            ? row['body'] as String
            : '';
        return InkWell(
          onTap: _support
              ? () async {
                  final id = row['id'];
                  if (id is! String || id.isEmpty) return;
                  await Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SupportThreadScreen(
                        authService: widget.authService,
                        backendApiService: widget.backendApiService,
                        threadId: id,
                      ),
                    ),
                  );
                  if (mounted) _load();
                }
              : () => _openAlert(row),
          child: RetroCard(
            child: ListTile(
              title: Text(
                title,
                style: PixelText.title(
                  size: 14,
                  color: AppColors.of(context).textDark,
                ),
              ),
              subtitle: Text(
                body,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: PixelText.body(
                  size: 13,
                  color: AppColors.of(context).textMid,
                ),
              ),
              trailing: !_support && row['readAt'] == null
                  ? Icon(
                      Icons.mark_email_unread_rounded,
                      color: AppColors.of(context).coinDark,
                    )
                  : null,
            ),
          ),
        );
      },
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
  });

  final AuthService authService;
  final BackendApiService backendApiService;
  final String threadId;
  final bool admin;

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
      if (mounted) {
        setState(() {
          _messages = older ? [...parsed, ..._messages] : parsed;
          _nextBefore = payload['nextBefore'] is String
              ? payload['nextBefore'] as String
              : null;
          _loading = false;
        });
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
            child: PillButton(
              label: 'LOAD OLDER',
              onPressed: () => _load(older: true),
            ),
          ),
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null && _messages.isEmpty
              ? Center(
                  child: PillButton(label: 'TRY AGAIN', onPressed: _load),
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
                IconButton(
                  onPressed: _sending ? null : _send,
                  icon: _sending
                      ? const CircularProgressIndicator()
                      : const Icon(Icons.send_rounded),
                ),
              ],
            ),
          ),
        ),
      ],
    ),
  );
}
