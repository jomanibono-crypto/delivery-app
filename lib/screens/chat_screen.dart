import 'dart:async';
import 'package:flutter/material.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/firebase_service.dart';
import '../services/local_storage_service.dart';
import 'home_screen.dart';
import 'map_screen.dart';
import 'settings_screen.dart';

/// Group chat screen — all members can send & read messages in real time.
class ChatScreen extends StatefulWidget {
  final String groupCode;
  final String userName;

  const ChatScreen({
    super.key,
    required this.groupCode,
    required this.userName,
  });

  @override
  State<ChatScreen> createState() => ChatScreenState();
}

class ChatScreenState extends State<ChatScreen> {
  final FirebaseService _firebaseService = FirebaseService();
  final LocalStorageService _localStorage = LocalStorageService();
  final TextEditingController _msgController = TextEditingController();
  final ScrollController _scrollController = ScrollController();

  StreamSubscription<DatabaseEvent>? _messagesSubscription;
  List<Map<String, dynamic>> _messages = [];
  bool _isSending = false;
  String _myIcon = '🧑';

  @override
  void initState() {
    super.initState();
    _loadIcon();
    _listenToMessages();
  }

  Future<void> _loadIcon() async {
    final icon = await _localStorage.getUserIcon();
    if (mounted) setState(() => _myIcon = icon ?? '🧑');
  }

  void _listenToMessages() {
    _messagesSubscription =
        _firebaseService.watchMessages(widget.groupCode).listen((event) {
      if (!mounted) return;
      final snap = event.snapshot;
      if (!snap.exists) {
        if (mounted) setState(() => _messages.clear());
        return;
      }
      final data = snap.value as Map<dynamic, dynamic>?;
      if (data == null) {
        if (mounted) setState(() => _messages.clear());
        return;
      }
      final list = <Map<String, dynamic>>[];
      data.forEach((key, value) {
        if (value is! Map) return;
        list.add({
          'id': key.toString(),
          'userId': (value['userId'] as String?) ?? '',
          'name': (value['name'] as String?) ?? 'عضو',
          'message': (value['message'] as String?) ?? '',
          'timestamp': (value['timestamp'] as num?)?.toInt() ?? 0,
          'icon': (value['icon'] as String?) ?? '',
        });
      });
      list.sort((a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int));
      if (mounted) {
        setState(() => _messages = list);
        _scrollToBottom();
      }
    });
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

  Future<void> _sendMessage() async {
    final text = _msgController.text.trim();
    if (text.isEmpty) return;
    setState(() => _isSending = true);
    _msgController.clear();
    await _firebaseService.sendMessage(
      groupCode: widget.groupCode,
      message: text,
      icon: _myIcon,
    );
    if (mounted) setState(() => _isSending = false);
  }

  @override
  void dispose() {
    _messagesSubscription?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('الدردشة'),
        actions: [
          Padding(
            padding: const EdgeInsets.only(left: 16),
            child: Center(
              child: Chip(
                avatar: const Icon(Icons.chat, size: 16),
                label: Text('${_messages.length} رسالة'),
                visualDensity: VisualDensity.compact,
              ),
            ),
          ),
        ],
      ),
      body: Column(
        children: [
          Expanded(
            child: _messages.isEmpty
                ? Center(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.chat_bubble_outline, size: 64, color: Colors.grey.shade300),
                        const SizedBox(height: 12),
                        Text(
                          'لا توجد رسائل بعد...\nأرسل أول رسالة في المجموعة!',
                          textAlign: TextAlign.center,
                          style: TextStyle(color: Colors.grey.shade500, fontSize: 14),
                        ),
                      ],
                    ),
                  )
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                    itemCount: _messages.length,
                    itemBuilder: (context, index) {
                      final msg = _messages[index];
                      final isMe = msg['userId'] == _firebaseService.userId;
                      return _MessageBubble(
                        message: msg['message'] as String,
                        name: msg['name'] as String,
                        icon: msg['icon'] as String,
                        isMe: isMe,
                        timestamp: msg['timestamp'] as int,
                      );
                    },
                  ),
          ),
          _buildInputBar(),
        ],
      ),
      bottomNavigationBar: _buildBottomNav(),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: Theme.of(context).scaffoldBackgroundColor,
        boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 4, offset: const Offset(0, -2))],
      ),
      child: SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(12, 8, 12, 8),
          child: Row(
            children: [
              CircleAvatar(
                radius: 18,
                backgroundColor: Colors.grey.shade100,
                child: Text(_myIcon, style: const TextStyle(fontSize: 18)),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: TextField(
                  controller: _msgController,
                  textDirection: TextDirection.rtl,
                  maxLines: 4,
                  minLines: 1,
                  decoration: InputDecoration(
                    hintText: 'اكتب رسالة...',
                    filled: true,
                    fillColor: Colors.grey.shade100,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(24),
                      borderSide: BorderSide.none,
                    ),
                    contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                  ),
                  onSubmitted: (_) => _sendMessage(),
                ),
              ),
              const SizedBox(width: 8),
              IconButton.filled(
                onPressed: _isSending ? null : _sendMessage,
                icon: _isSending
                    ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white))
                    : const Icon(Icons.send_rounded),
                style: IconButton.styleFrom(
                  backgroundColor: const Color(0xFF1565C0),
                  foregroundColor: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return NavigationBar(
      selectedIndex: 1,
      destinations: const [
        NavigationDestination(icon: Icon(Icons.map_outlined), selectedIcon: Icon(Icons.map), label: 'الخريطة'),
        NavigationDestination(icon: Icon(Icons.chat_bubble_outline), selectedIcon: Icon(Icons.chat_bubble), label: 'الدردشة'),
        NavigationDestination(icon: Icon(Icons.settings_outlined), selectedIcon: Icon(Icons.settings), label: 'الإعدادات'),
      ],
      onDestinationSelected: (index) {
        if (index == 0) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => MapScreen(groupCode: widget.groupCode, userName: widget.userName)));
        } else if (index == 2) {
          Navigator.pushReplacement(context, MaterialPageRoute(builder: (_) => SettingsScreen(groupCode: widget.groupCode, userName: widget.userName)));
        }
      },
    );
  }
}

/// A single chat message bubble.
class _MessageBubble extends StatelessWidget {
  final String message;
  final String name;
  final String icon;
  final bool isMe;
  final int timestamp;

  const _MessageBubble({
    required this.message,
    required this.name,
    required this.icon,
    required this.isMe,
    required this.timestamp,
  });

  String _formatTime(int epochMs) {
    if (epochMs <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMe) ...[
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.grey.shade100,
                  child: Text(icon.isNotEmpty ? icon : '🧑', style: const TextStyle(fontSize: 14)),
                ),
                const SizedBox(width: 6),
              ],
              Text(
                isMe ? 'أنت' : name,
                style: TextStyle(fontSize: 11, fontWeight: FontWeight.w600, color: isMe ? const Color(0xFF1565C0) : Colors.grey.shade700),
              ),
              if (isMe) ...[
                const SizedBox(width: 6),
                CircleAvatar(
                  radius: 12,
                  backgroundColor: Colors.grey.shade100,
                  child: Text(icon.isNotEmpty ? icon : '🧑', style: const TextStyle(fontSize: 14)),
                ),
              ],
            ],
          ),
          const SizedBox(height: 4),
          Container(
            constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            decoration: BoxDecoration(
              color: isMe ? const Color(0xFF1565C0) : Colors.grey.shade100,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(16),
                topRight: const Radius.circular(16),
                bottomLeft: isMe ? const Radius.circular(16) : Radius.zero,
                bottomRight: isMe ? Radius.zero : const Radius.circular(16),
              ),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  textDirection: TextDirection.rtl,
                  style: TextStyle(fontSize: 14, color: isMe ? Colors.white : Colors.black87),
                ),
                const SizedBox(height: 2),
                Text(
                  _formatTime(timestamp),
                  style: TextStyle(fontSize: 10, color: isMe ? Colors.white60 : Colors.grey.shade500),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
