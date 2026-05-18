import 'package:flutter/material.dart';

import '../services/auth_service.dart';
import '../services/backend_api_service.dart';
import '../services/race_chat_service.dart';
import '../styles.dart';
import '../widgets/player_avatar.dart';

class RaceChatScreen extends StatefulWidget {
  final AuthService authService;
  final String raceId;
  final String raceName;
  final String raceStatus;
  final String myStatus;
  final String? myUserId;
  final bool initialMuted;
  final BackendApiService? backendApiService;

  const RaceChatScreen({
    super.key,
    required this.authService,
    required this.raceId,
    required this.raceName,
    required this.raceStatus,
    required this.myStatus,
    required this.myUserId,
    this.initialMuted = false,
    this.backendApiService,
  });

  @override
  State<RaceChatScreen> createState() => _RaceChatScreenState();
}

class _RaceChatScreenState extends State<RaceChatScreen>
    with WidgetsBindingObserver {
  late final RaceChatService _chat;
  final TextEditingController _input = TextEditingController();
  final ScrollController _scroll = ScrollController();
  bool _sending = false;

  bool get _canPost =>
      widget.myStatus == 'ACCEPTED' &&
      widget.raceStatus != 'COMPLETED' &&
      widget.raceStatus != 'CANCELLED';

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _chat = RaceChatService(
      authService: widget.authService,
      raceId: widget.raceId,
      api: widget.backendApiService ?? BackendApiService(),
    );
    _chat.setMutedFromServer(widget.initialMuted);
    _chat.loadInitial().then((_) {
      _chat.markRead();
    });
    _chat.startPolling();
    _scroll.addListener(_handleScroll);
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _chat.refreshTop();
      _chat.startPolling();
    } else if (state == AppLifecycleState.paused) {
      _chat.stopPolling();
    }
  }

  void _handleScroll() {
    if (!_scroll.hasClients) return;
    final pos = _scroll.position;
    // Reverse: maxScrollExtent == oldest. Load more as user nears the top of older messages.
    if (pos.pixels >= pos.maxScrollExtent - 200) {
      _chat.loadMore();
    }
  }

  Future<void> _send() async {
    final text = _input.text.trim();
    if (text.isEmpty || _sending) return;
    setState(() => _sending = true);
    _input.clear();
    await _chat.send(text);
    if (mounted) {
      setState(() => _sending = false);
      if (_scroll.hasClients) {
        _scroll.animateTo(
          0,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    }
  }

  Future<void> _toggleMute() async {
    await _chat.setMuted(!_chat.isMuted);
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _chat.markRead();
    _scroll.dispose();
    _input.dispose();
    _chat.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.parchmentLight,
      appBar: AppBar(
        backgroundColor: AppColors.accent,
        foregroundColor: AppColors.textDark,
        title: Text(
          widget.raceName,
          style: PixelText.title(size: 18, color: AppColors.textDark),
          overflow: TextOverflow.ellipsis,
        ),
        actions: [
          AnimatedBuilder(
            animation: _chat,
            builder: (context, _) {
              return IconButton(
                tooltip: _chat.isMuted ? 'Unmute' : 'Mute',
                icon: Icon(
                  _chat.isMuted
                      ? Icons.notifications_off
                      : Icons.notifications_active,
                ),
                onPressed: _toggleMute,
              );
            },
          ),
        ],
      ),
      body: SafeArea(
        child: Column(
          children: [
            Expanded(
              child: AnimatedBuilder(
                animation: _chat,
                builder: (context, _) {
                  final messages = _chat.messages;
                  if (messages.isEmpty && _chat.isLoading) {
                    return const Center(child: CircularProgressIndicator());
                  }
                  if (messages.isEmpty) {
                    return Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'No messages yet. Say hi!',
                          style: PixelText.body(
                            size: 16,
                            color: AppColors.textMid,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    );
                  }
                  return RefreshIndicator(
                    onRefresh: _chat.refreshTop,
                    child: ListView.builder(
                      controller: _scroll,
                      reverse: true,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 12,
                        vertical: 8,
                      ),
                      itemCount: messages.length + (_chat.hasMore ? 1 : 0),
                      itemBuilder: (context, index) {
                        if (index >= messages.length) {
                          return const Padding(
                            padding: EdgeInsets.all(12),
                            child: Center(
                              child: SizedBox(
                                width: 16,
                                height: 16,
                                child: CircularProgressIndicator(strokeWidth: 2),
                              ),
                            ),
                          );
                        }
                        final m = messages[index];
                        final mine =
                            m.kind == 'USER' &&
                            (m.senderId == null
                                ? m.pending || m.failed
                                : m.senderId == widget.myUserId);
                        return _ChatBubble(
                          message: m,
                          isMine: mine,
                          onLongPress: mine && !m.pending && !m.failed
                              ? () => _confirmDelete(m.id)
                              : null,
                        );
                      },
                    ),
                  );
                },
              ),
            ),
            _buildComposer(),
          ],
        ),
      ),
    );
  }

  Widget _buildComposer() {
    if (!_canPost) {
      final reason = widget.raceStatus == 'COMPLETED'
          ? 'This race is finished. Chat is read-only.'
          : widget.raceStatus == 'CANCELLED'
              ? 'This race was cancelled. Chat is read-only.'
              : widget.myStatus == 'INVITED'
                  ? 'Accept the invite to post in chat.'
                  : 'You can\'t post in this chat.';
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(12),
        color: AppColors.parchmentDark.withValues(alpha: 0.3),
        child: Text(
          reason,
          style: PixelText.body(size: 14, color: AppColors.textMid),
          textAlign: TextAlign.center,
        ),
      );
    }
    return SafeArea(
      top: false,
      child: Container(
        padding: const EdgeInsets.fromLTRB(8, 6, 8, 6),
        decoration: BoxDecoration(
          color: Colors.white,
          border: Border(
            top: BorderSide(color: AppColors.textMid.withValues(alpha: 0.2)),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.end,
          children: [
            Expanded(
              child: TextField(
                controller: _input,
                minLines: 1,
                maxLines: 4,
                maxLength: 500,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: 'Message…',
                  hintStyle: PixelText.body(size: 16, color: AppColors.textMid),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(20),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 14,
                    vertical: 10,
                  ),
                  counterText: '',
                ),
              ),
            ),
            const SizedBox(width: 6),
            IconButton(
              icon: _sending
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Icon(Icons.send),
              color: AppColors.accent,
              onPressed: _sending ? null : _send,
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _confirmDelete(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete message?'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await _chat.deleteMessage(messageId);
    }
  }
}

class _ChatBubble extends StatelessWidget {
  final RaceChatMessage message;
  final bool isMine;
  final VoidCallback? onLongPress;

  const _ChatBubble({
    required this.message,
    required this.isMine,
    this.onLongPress,
  });

  String _formatTime(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    final ampm = t.hour < 12 ? 'AM' : 'PM';
    return '$h:$m $ampm';
  }

  @override
  Widget build(BuildContext context) {
    if (message.kind == 'SYSTEM') {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 6),
        child: Center(
          child: Container(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.parchmentDark.withValues(alpha: 0.3),
              borderRadius: BorderRadius.circular(12),
            ),
            child: Text(
              message.body,
              textAlign: TextAlign.center,
              style: PixelText.body(size: 14, color: AppColors.textMid),
            ),
          ),
        ),
      );
    }

    final bubbleColor = isMine ? AppColors.accent : Colors.white;
    final textColor = AppColors.textDark;

    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment:
            isMine ? MainAxisAlignment.end : MainAxisAlignment.start,
        children: [
          if (!isMine) ...[
            PlayerAvatar(
              name: message.senderName ?? '?',
              size: 28,
            ),
            const SizedBox(width: 6),
          ],
          Flexible(
            child: GestureDetector(
              onLongPress: onLongPress,
              child: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 8,
                ),
                decoration: BoxDecoration(
                  color: bubbleColor,
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: AppColors.textMid.withValues(alpha: 0.2),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    if (!isMine && message.senderName != null)
                      Text(
                        message.senderName!,
                        style: PixelText.title(
                          size: 12,
                          color: AppColors.textMid,
                        ),
                      ),
                    Text(
                      message.body,
                      style: PixelText.body(size: 16, color: textColor),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          _formatTime(message.createdAt),
                          style: PixelText.body(
                            size: 11,
                            color: AppColors.textMid.withValues(alpha: 0.8),
                          ),
                        ),
                        if (message.pending) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.access_time,
                            size: 11,
                            color: AppColors.textMid.withValues(alpha: 0.8),
                          ),
                        ],
                        if (message.failed) ...[
                          const SizedBox(width: 4),
                          Icon(
                            Icons.error_outline,
                            size: 11,
                            color: AppColors.feedAttack,
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
