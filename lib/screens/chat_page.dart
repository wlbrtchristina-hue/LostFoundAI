import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

import '../models/match_model.dart';
import '../services/supabase_service.dart';
import '../utils/time_ago.dart';

/// 聊天页：匹配双方直接沟通。
///
/// 消息存 Supabase `messages` 表（match_id 即会话，见 backend/chat_schema.sql），
/// Realtime 实时收发；RLS 保证只有匹配双方能读写。
class ChatPage extends StatefulWidget {
  const ChatPage({super.key, required this.match});

  final MatchModel match;

  @override
  State<ChatPage> createState() => _ChatPageState();
}

class _ChatMessage {
  const _ChatMessage({
    required this.id,
    required this.senderId,
    required this.content,
    required this.createdAt,
  });

  final String id;
  final String senderId;
  final String content;
  final DateTime createdAt;

  factory _ChatMessage.fromRow(Map<String, dynamic> row) => _ChatMessage(
        id: row['id']?.toString() ?? '',
        senderId: row['sender_id']?.toString() ?? '',
        content: row['content']?.toString() ?? '',
        createdAt:
            DateTime.tryParse(row['created_at']?.toString() ?? '') ??
                DateTime.now(),
      );
}

class _ChatPageState extends State<ChatPage> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();
  final List<_ChatMessage> _messages = [];
  bool _loading = true;
  bool _sending = false;
  RealtimeChannel? _channel;

  String? get _myId => SupabaseService.instance.currentUserId;

  @override
  void initState() {
    super.initState();
    _loadHistory();
    _subscribe();
  }

  @override
  void dispose() {
    if (_channel != null) {
      SupabaseService.instance.client.removeChannel(_channel!);
    }
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  Future<void> _loadHistory() async {
    try {
      final rows = await SupabaseService.instance.client
          .from('messages')
          .select('id, sender_id, content, created_at')
          .eq('match_id', widget.match.id)
          .order('created_at');
      if (!mounted) return;
      setState(() {
        _messages
          ..clear()
          ..addAll(rows.map(_ChatMessage.fromRow));
        _loading = false;
      });
      _scrollToBottom();
    } catch (_) {
      if (mounted) setState(() => _loading = false);
    }
  }

  /// 订阅该会话的新消息（RLS 下只有双方能收到）。
  void _subscribe() {
    _channel = SupabaseService.instance.client
        .channel('chat-${widget.match.id}')
        .onPostgresChanges(
          event: PostgresChangeEvent.insert,
          schema: 'public',
          table: 'messages',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'match_id',
            value: widget.match.id,
          ),
          callback: (payload) {
            final msg = _ChatMessage.fromRow(payload.newRecord);
            // 去重：自己发的消息也会经 Realtime 回来
            if (_messages.any((m) => m.id == msg.id)) return;
            if (!mounted) return;
            setState(() => _messages.add(msg));
            _scrollToBottom();
          },
        )
        .subscribe();
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty || _sending || _myId == null) return;
    setState(() => _sending = true);
    try {
      // RLS 校验 sender_id = 当前用户 且是匹配参与者
      await SupabaseService.instance.client.from('messages').insert({
        'match_id': widget.match.id,
        'sender_id': _myId,
        'content': text,
      });
      _inputController.clear();
      // 新消息会经 Realtime 回调进入列表
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('发送失败：$e'),
            backgroundColor: Colors.red.shade400,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _sending = false);
    }
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 200),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final counterpart = widget.match.counterpartOf(_myId);
    return Scaffold(
      appBar: AppBar(title: Text('联系对方 · ${counterpart.category}')),
      body: Column(
        children: [
          // 会话背景：关于什么物品
          Container(
            width: double.infinity,
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            color: theme.colorScheme.surfaceContainerHighest
                .withValues(alpha: 0.5),
            child: Text(
              '关于：${widget.match.lostItem.category} · ${widget.match.lostItem.color}（${widget.match.lostItem.typeLabel}）↔ '
              '${widget.match.foundItem.category} · ${widget.match.foundItem.color}（${widget.match.foundItem.typeLabel}）',
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.outline),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Expanded(
            child: _loading
                ? const Center(child: CircularProgressIndicator())
                : _messages.isEmpty
                    ? const Center(child: Text('还没有消息，打个招呼吧 👋'))
                    : ListView.builder(
                        controller: _scrollController,
                        padding: const EdgeInsets.all(12),
                        itemCount: _messages.length,
                        itemBuilder: (context, index) =>
                            _buildBubble(_messages[index]),
                      ),
          ),
          _buildInputBar(),
        ],
      ),
    );
  }

  Widget _buildBubble(_ChatMessage msg) {
    final theme = Theme.of(context);
    final mine = msg.senderId == _myId;
    return Align(
      alignment: mine ? Alignment.centerRight : Alignment.centerLeft,
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          if (!mine)
            Padding(
              padding: const EdgeInsets.only(left: 4, bottom: 2),
              child: Text(
                _senderLabel(msg.senderId),
                style: theme.textTheme.labelSmall
                    ?.copyWith(color: theme.colorScheme.outline),
              ),
            ),
          Container(
            margin: const EdgeInsets.only(bottom: 6),
            padding:
                const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.72,
            ),
            decoration: BoxDecoration(
              color: mine
                  ? theme.colorScheme.primary
                  : theme.colorScheme.surfaceContainerHighest,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(12),
                topRight: const Radius.circular(12),
                bottomLeft: Radius.circular(mine ? 12 : 2),
                bottomRight: Radius.circular(mine ? 2 : 12),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  msg.content,
                  style: TextStyle(
                    color: mine
                        ? theme.colorScheme.onPrimary
                        : theme.colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  timeAgo(msg.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: mine
                        ? theme.colorScheme.onPrimary.withValues(alpha: 0.7)
                        : theme.colorScheme.outline,
                    fontSize: 10,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// 对方消息显示身份（失物方 / 招领方）
  String _senderLabel(String senderId) {
    if (senderId == widget.match.lostItem.userId) return '失物方';
    if (senderId == widget.match.foundItem.userId) return '招领方';
    return '未知';
  }

  Widget _buildInputBar() {
    return SafeArea(
      top: false,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 4, 12, 8),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _inputController,
                minLines: 1,
                maxLines: 4,
                textInputAction: TextInputAction.send,
                onSubmitted: (_) => _send(),
                decoration: InputDecoration(
                  hintText: '输入消息…',
                  isDense: true,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 10,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 8),
            IconButton.filled(
              onPressed: _sending ? null : _send,
              icon: const Icon(Icons.send),
            ),
          ],
        ),
      ),
    );
  }
}
