import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../models/chat_message.dart';
import '../widgets/themed_text_field.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_success_banner.dart';

class ChatScreen extends StatefulWidget {
  final String jobId;

  const ChatScreen({super.key, required this.jobId});

  @override
  State<ChatScreen> createState() => _ChatScreenState();
}

class _ChatScreenState extends State<ChatScreen> {
  final _messageController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initChat();
    });
  }

  void _initChat() {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final chat = Provider.of<ChatProvider>(context, listen: false);
    if (auth.token != null) {
      chat.fetchHistory(widget.jobId, auth.token!).then((_) {
        if (mounted && chat.subscriptionError == null) {
          chat.connectAndSubscribe(widget.jobId, auth.token!);
        }
      });
    }
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    // We disconnect chat when leaving the screen to clean up WebSocket resources
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        Provider.of<ChatProvider>(context, listen: false).disconnect();
      }
    });
    super.dispose();
  }

  void _scrollToBottom() {
    if (_scrollController.hasClients) {
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: AppMotion.durationMedium,
        curve: AppMotion.curveEntrance,
      );
    }
  }

  void _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty) return;

    final chat = Provider.of<ChatProvider>(context, listen: false);
    try {
      await chat.sendMessage(text);
      _messageController.clear();
      Timer(AppMotion.durationFast, _scrollToBottom);
    } catch (e) {
      if (mounted) {
        final l10n = AppLocalizations.of(context)!;
        ThemedSnackBar.showError(
          context,
          l10n.chatFailedSend(e.toString()),
          onRetry: _sendMessage,
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final chat = Provider.of<ChatProvider>(context);
    final l10n = context.l10n;
    final currentUserId = auth.user?.id ?? '';

    // Auto scroll to bottom when new messages arrive
    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    // Connection status label
    Widget statusIndicator;
    if (chat.subscriptionError != null) {
      statusIndicator =
          const Icon(Icons.gpp_bad, color: AppColors.error, size: 16);
    } else if (chat.isConnected) {
      statusIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: AppColors.success, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            "Live",
            style: AppTypography.labelMd.copyWith(color: AppColors.success),
          ),
        ],
      );
    } else if (chat.isConnecting) {
      statusIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const SizedBox(
            width: 8,
            height: 8,
            child: CircularProgressIndicator(
              strokeWidth: 1.5,
              color: AppColors.warning,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            l10n.loading,
            style: AppTypography.labelMd.copyWith(color: AppColors.warning),
          ),
        ],
      );
    } else {
      statusIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            width: 8,
            height: 8,
            decoration: const BoxDecoration(
                color: AppColors.outline, shape: BoxShape.circle),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            "Disconnected",
            style: AppTypography.labelMd.copyWith(color: AppColors.outline),
          ),
        ],
      );
    }

    return Scaffold(
      backgroundColor: AppColors.surfaceDim,
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              "${l10n.chatTitle} #${widget.jobId.substring(0, widget.jobId.length > 8 ? 8 : widget.jobId.length)}",
              style: AppTypography.titleMd.copyWith(color: AppColors.onPrimary),
            ),
            const SizedBox(height: 2),
            statusIndicator,
          ],
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
      ),
      body: Column(
        children: [
          // Error banners
          if (chat.error != null && chat.subscriptionError == null)
            ThemedErrorBanner(
              message: chat.error!,
              onRetry: _initChat,
            ),
          // Main Body
          Expanded(
            child: chat.subscriptionError != null
                ? Center(
                    child: Padding(
                      padding: const EdgeInsets.all(AppSpacing.lg),
                      child: ThemedErrorBanner(
                        message:
                            "Access Denied: You are not authorized to view or join the chat for Job #${widget.jobId}.",
                        onRetry: _initChat,
                      ),
                    ),
                  )
                : chat.messages.isEmpty && chat.isConnecting
                    ? const Center(child: ThemedLoadingIndicator())
                    : chat.messages.isEmpty
                        ? ThemedEmptyState(
                            icon: Icons.chat_bubble_outline,
                            title: l10n.chatTitle,
                            description: l10n.chatTypeHint,
                          )
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            itemCount: chat.messages.length,
                            itemBuilder: (context, index) {
                              final msg = chat.messages[index];
                              final isMe = msg.senderId == currentUserId;
                              return _buildMessageBubble(msg, isMe);
                            },
                          ),
          ),
          // Input Row (only if authorized)
          if (chat.subscriptionError == null)
            Container(
              padding: const EdgeInsets.all(AppSpacing.md),
              decoration: BoxDecoration(
                color: Theme.of(context).colorScheme.surface,
                boxShadow: [
                  BoxShadow(
                    color: Theme.of(context).shadowColor.withValues(alpha: 0.1),
                    offset: const Offset(0, -2),
                    blurRadius: 4,
                  ),
                ],
              ),
              child: SafeArea(
                child: Row(
                  children: [
                    Expanded(
                      child: ThemedTextField(
                        controller: _messageController,
                        hintText: l10n.chatTypeHint,
                        textInputAction: TextInputAction.send,
                        onFieldSubmitted: (_) => _sendMessage(),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    IconButton(
                      onPressed: _sendMessage,
                      icon: const Icon(Icons.send),
                      color: AppColors.primary,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    const primaryColor = AppColors.primary;
    const secondaryColor = AppColors.secondary;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Bubble
          Container(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.75),
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            decoration: BoxDecoration(
              color:
                  isMe ? primaryColor : secondaryColor.withValues(alpha: 0.2),
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppRadius.lg),
                topRight: const Radius.circular(AppRadius.lg),
                bottomLeft: isMe
                    ? const Radius.circular(AppRadius.lg)
                    : const Radius.circular(0),
                bottomRight: isMe
                    ? const Radius.circular(0)
                    : const Radius.circular(AppRadius.lg),
              ),
            ),
            child: Text(
              msg.content,
              style: AppTypography.bodyMd.copyWith(
                color: isMe ? AppColors.onPrimary : AppColors.primary,
              ),
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          // Sender Username / ID tag
          Text(
            isMe
                ? "You"
                : (msg.senderUsername.isNotEmpty
                    ? msg.senderUsername
                    : "User #${msg.senderId.substring(0, msg.senderId.length > 6 ? 6 : msg.senderId.length)}"),
            style: AppTypography.labelMd
                .copyWith(color: AppColors.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
