import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:firebase_database/firebase_database.dart';
import '../services/firebase_service.dart';
import '../services/local_storage_service.dart';
import '../services/foreground_screen_service.dart';
import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../theme/app_typography.dart';
import '../widgets/app_bottom_nav.dart';
import 'map_screen.dart';
import 'settings_screen.dart';
import 'blacklist_screen.dart';

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
    ForegroundScreenService().set(ForegroundScreen.chat);
    _loadIcon();
    _listenToMessages();
  }

  Future<void> _loadIcon() async {
    final icon = await _localStorage.getUserIcon();
    if (mounted) setState(() => _myIcon = icon ?? '🧑');
  }

  void _listenToMessages() {
    _messagesSubscription = _firebaseService
        .watchMessages(widget.groupCode)
        .listen((event) {
          if (!mounted) return;
          final snap = event.snapshot;
          if (!snap.exists) {
            if (mounted) setState(() => _messages.clear());
            return;
          }
          final data = snap.value is Map
              ? snap.value as Map<dynamic, dynamic>
              : null;
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
          list.sort(
            (a, b) => (a['timestamp'] as int).compareTo(b['timestamp'] as int),
          );
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

  Future<void> _deleteMessage(String messageId) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => Directionality(
        textDirection: TextDirection.rtl,
        child: AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          title: const Text('حذف الرسالة'),
          content: const Text('هل أنت متأكد من حذف هذه الرسالة؟'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: Colors.red),
              onPressed: () => Navigator.pop(ctx, true),
              child: const Text('حذف'),
            ),
          ],
        ),
      ),
    );
    if (confirmed == true) {
      await _firebaseService.deleteMessage(
        groupCode: widget.groupCode,
        messageId: messageId,
      );
    }
  }

  @override
  void dispose() {
    ForegroundScreenService().clear(ForegroundScreen.chat);
    _messagesSubscription?.cancel();
    _msgController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: AppColors.background,
      body: Column(
        children: [
          _buildChatHeader(),
          Expanded(
            child: _messages.isEmpty
                ? _buildEmptyState()
                : ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: AppSpacing.lg,
                      vertical: AppSpacing.md,
                    ),
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
                        messageId: msg['id'] as String,
                        onDelete: isMe
                            ? () => _deleteMessage(msg['id'] as String)
                            : null,
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

  Widget _buildChatHeader() {
    // Count online members from the messages' sender data for the status pill
    final onlineCount = _messages
        .map((m) => m['userId'] as String)
        .toSet()
        .length;
    return Container(
      decoration: const BoxDecoration(
        color: AppColors.surface,
        border: Border(
          bottom: BorderSide(color: AppColors.ink100, width: 1),
        ),
      ),
      child: SafeArea(
        bottom: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.lg,
            AppSpacing.md,
            AppSpacing.lg,
            AppSpacing.md,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  gradient: AppColors.primaryGradient,
                  borderRadius: const BorderRadius.all(Radius.circular(12)),
                ),
                child: const Center(
                  child: Text('💬', style: TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'المجموعة',
                      style: AppTypography.titleMd,
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          width: 6,
                          height: 6,
                          decoration: BoxDecoration(
                            color: AppColors.mint500,
                            shape: BoxShape.circle,
                            boxShadow: [
                              BoxShadow(
                                color: AppColors.mint500.withValues(alpha: 0.4),
                                blurRadius: 6,
                                spreadRadius: 1,
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(width: 6),
                        Text(
                          '${onlineCount > 0 ? onlineCount : 1} متصلين الآن',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.mint500,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // Search icon button (matches mockup)
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.ink50,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.search_rounded,
                  size: 18,
                  color: AppColors.ink700,
                ),
              ),
              const SizedBox(width: AppSpacing.xs),
              // More menu icon button
              Container(
                width: 38,
                height: 38,
                decoration: BoxDecoration(
                  color: AppColors.ink50,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                ),
                child: const Icon(
                  Icons.more_vert_rounded,
                  size: 18,
                  color: AppColors.ink700,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState() {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 88,
              height: 88,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    AppColors.indigo100,
                    AppColors.indigo50,
                  ],
                ),
                borderRadius: BorderRadius.circular(AppRadius.xl),
              ),
              child: const Icon(
                Icons.chat_bubble_outline_rounded,
                size: 40,
                color: AppColors.indigo500,
              ),
            ),
            const SizedBox(height: AppSpacing.xl),
            Text(
              'لا توجد رسائل بعد...',
              style: AppTypography.titleLg,
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              'أرسل أول رسالة في المجموعة!',
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.ink500,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildInputBar() {
    return Container(
      decoration: BoxDecoration(
        color: AppColors.surface,
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.06),
            blurRadius: 12,
            offset: const Offset(0, -4),
          ),
        ],
        border: Border(
          top: BorderSide(color: AppColors.ink100, width: 1),
        ),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(
            AppSpacing.md,
            AppSpacing.sm,
            AppSpacing.md,
            AppSpacing.sm,
          ),
          child: Row(
            children: [
              Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: AppColors.ink50,
                  borderRadius: BorderRadius.circular(AppRadius.md),
                ),
                child: Center(
                  child: Text(_myIcon, style: const TextStyle(fontSize: 18)),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Container(
                  decoration: BoxDecoration(
                    color: AppColors.ink50,
                    borderRadius: BorderRadius.circular(22),
                  ),
                  child: TextField(
                    controller: _msgController,
                    textDirection: TextDirection.rtl,
                    maxLines: 4,
                    minLines: 1,
                    style: AppTypography.bodyLg,
                    decoration: InputDecoration(
                      hintText: 'اكتب رسالة...',
                      hintStyle: AppTypography.bodyLg.copyWith(
                        color: AppColors.ink300,
                        fontWeight: FontWeight.w500,
                      ),
                      filled: false,
                      border: InputBorder.none,
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: AppSpacing.lg,
                        vertical: AppSpacing.md,
                      ),
                    ),
                    onSubmitted: (_) => _sendMessage(),
                  ),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              _SendButton(
                isLoading: _isSending,
                onPressed: _isSending ? null : _sendMessage,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildBottomNav() {
    return AppBottomNav(
      selectedIndex: 1,
      onDestinationSelected: (index) {
        if (index == 0) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => MapScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        } else if (index == 2) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => BlacklistScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        } else if (index == 3) {
          Navigator.pushReplacement(
            context,
            MaterialPageRoute(
              builder: (_) => SettingsScreen(
                groupCode: widget.groupCode,
                userName: widget.userName,
              ),
            ),
          );
        }
      },
    );
  }
}

class _SendButton extends StatelessWidget {
  final bool isLoading;
  final VoidCallback? onPressed;
  const _SendButton({required this.isLoading, required this.onPressed});

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        gradient: AppColors.primaryGradient,
        borderRadius: BorderRadius.circular(AppRadius.md),
        boxShadow: AppColors.shadowGlowPrimary,
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: Container(
            width: 44,
            height: 44,
            alignment: Alignment.center,
            child: isLoading
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Colors.white,
                    ),
                  )
                : const Icon(
                    Icons.send_rounded,
                    size: 20,
                    color: Colors.white,
                  ),
          ),
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  final String message;
  final String name;
  final String icon;
  final bool isMe;
  final int timestamp;
  final String messageId;
  final VoidCallback? onDelete;

  const _MessageBubble({
    required this.message,
    required this.name,
    required this.icon,
    required this.isMe,
    required this.timestamp,
    required this.messageId,
    this.onDelete,
  });

  String _formatTime(int epochMs) {
    if (epochMs <= 0) return '';
    final t = DateTime.fromMillisecondsSinceEpoch(epochMs);
    return '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
  }

  @override
  Widget build(BuildContext context) {
    final bubble = Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (!isMe) ...[
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.indigo50,
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    child: Text(
                      icon.isNotEmpty ? icon : '🧑',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
              ],
              Text(
                isMe ? 'أنت' : name,
                style: AppTypography.labelSm.copyWith(
                  color: isMe
                      ? AppColors.indigo600
                      : AppColors.ink500,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (isMe) ...[
                const SizedBox(width: AppSpacing.sm),
                Container(
                  width: 28,
                  height: 28,
                  decoration: BoxDecoration(
                    color: AppColors.orange500.withValues(alpha: 0.14),
                    borderRadius: BorderRadius.circular(AppRadius.sm),
                  ),
                  child: Center(
                    child: Text(
                      icon.isNotEmpty ? icon : '🧑',
                      style: const TextStyle(fontSize: 16),
                    ),
                  ),
                ),
              ],
            ],
          ),
          const SizedBox(height: AppSpacing.xs),
          Container(
            constraints: BoxConstraints(
              maxWidth: MediaQuery.of(context).size.width * 0.75,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.lg,
              vertical: AppSpacing.md,
            ),
            decoration: BoxDecoration(
              gradient: isMe ? AppColors.primaryGradient : null,
              color: isMe ? null : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(18),
                topRight: const Radius.circular(18),
                bottomLeft: isMe ? const Radius.circular(18) : Radius.zero,
                bottomRight: isMe ? Radius.zero : const Radius.circular(18),
              ),
              boxShadow: isMe
                  ? AppColors.shadowGlowPrimary
                  : [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.05),
                        blurRadius: 8,
                        offset: const Offset(0, 2),
                      ),
                    ],
              border: isMe ? null : Border.all(color: AppColors.ink100),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  message,
                  textDirection: TextDirection.rtl,
                  style: AppTypography.bodyMd.copyWith(
                    color: isMe ? Colors.white : AppColors.ink900,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(height: AppSpacing.xxs),
                Text(
                  _formatTime(timestamp),
                  style: AppTypography.caption.copyWith(
                    color: isMe
                        ? Colors.white.withValues(alpha: 0.65)
                        : AppColors.ink400,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );

    if (onDelete != null) {
      return GestureDetector(
        onLongPress: () {
          HapticFeedback.mediumImpact();
          onDelete!();
        },
        child: bubble,
      );
    }
    return bubble;
  }
}
