import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/chat_message.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/app_shell.dart';
import '../widgets/themed_empty_state.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
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
    final shortJobId =
        widget.jobId.length > 8 ? widget.jobId.substring(0, 8) : widget.jobId;

    WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToBottom());

    Widget statusIndicator;
    if (chat.subscriptionError != null) {
      statusIndicator =
          const Icon(Icons.gpp_bad, color: AppColors.error, size: 14);
    } else if (chat.isConnected) {
      statusIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ThemedPanel(
              color: AppColors.success,
              shape: BoxShape.circle,
              width: 7,
              height: 7),
          const SizedBox(width: AppSpacing.xs),
          Text(
            "Live",
            style: AppTypography.labelSm.copyWith(
              color: AppColors.success,
              fontWeight: FontWeight.bold,
            ),
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
              color: AppColors.secondary,
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          Text(
            l10n.loading,
            style: AppTypography.labelSm.copyWith(
              color: AppColors.onSurfaceVariant,
            ),
          ),
        ],
      );
    } else {
      statusIndicator = Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          const ThemedPanel(
              color: AppColors.outline,
              shape: BoxShape.circle,
              width: 7,
              height: 7),
          const SizedBox(width: AppSpacing.xs),
          Text(
            "Disconnected",
            style: AppTypography.labelSm.copyWith(
              color: AppColors.outline,
            ),
          ),
        ],
      );
    }

    return AppShell(
      backgroundColor: AppColors.scaffoldBackground,
      appBarBackgroundColor: AppColors.primary,
      appBarForegroundColor: AppColors.onPrimary,
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            "${l10n.chatTitle} #$shortJobId",
            style: AppTypography.titleMd.copyWith(
              color: AppColors.onPrimary,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 2),
          statusIndicator,
        ],
      ),
      body: Column(
        children: [
          // Context Job Header Strip (Stitch DOM)
          ThemedPanel(
              color: AppColors.surface,
              border: Border(
                bottom: BorderSide(
                  color: AppColors.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              child: Row(
                children: [
                  ThemedPanel(
                      color: AppColors.primary.withValues(alpha: 0.1),
                      shape: BoxShape.circle,
                      width: 36,
                      height: 36,
                      child: const Icon(
                        Icons.local_shipping,
                        color: AppColors.primary,
                        size: 18,
                      )),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          "Job #$shortJobId",
                          style: AppTypography.labelLg.copyWith(
                            fontWeight: FontWeight.bold,
                            color: AppColors.onSurface,
                          ),
                        ),
                        Text(
                          "Direct Real-time Channel",
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              )),

          if (chat.error != null && chat.subscriptionError == null)
            ThemedErrorBanner(
              message: chat.error!,
              onRetry: _initChat,
            ),

          // Message List Area
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
                            padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.md,
                              vertical: AppSpacing.md,
                            ),
                            itemCount: chat.messages.length,
                            itemBuilder: (context, index) {
                              final msg = chat.messages[index];
                              final isMe = msg.senderId == currentUserId;
                              return _buildMessageBubble(msg, isMe);
                            },
                          ),
          ),

          // Sticky Input Row (Stitch DOM)
          if (chat.subscriptionError == null)
            ThemedPanel(
                color: AppColors.surface,
                border: Border(
                  top: BorderSide(
                    color: AppColors.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.04),
                    offset: const Offset(0, -2),
                    blurRadius: 6,
                  ),
                ],
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: SafeArea(
                  top: false,
                  child: Row(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Expanded(
                        child: ThemedPanel(
                            color: AppColors.surfaceContainerLowest,
                            borderRadius: AppRadius.defaultBorder,
                            border: Border.all(
                              color: AppColors.outlineVariant,
                              width: 1,
                            ),
                            child: TextField(
                              controller: _messageController,
                              minLines: 1,
                              maxLines: 4,
                              textInputAction: TextInputAction.send,
                              onSubmitted: (_) => _sendMessage(),
                              style: AppTypography.bodyMd.copyWith(
                                color: AppColors.onSurface,
                              ),
                              decoration: InputDecoration(
                                hintText: l10n.chatTypeHint,
                                hintStyle: AppTypography.bodyMd.copyWith(
                                  color: AppColors.onSurfaceVariant,
                                ),
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.md,
                                  vertical: AppSpacing.sm,
                                ),
                                border: InputBorder.none,
                                isDense: true,
                              ),
                            )),
                      ),
                      const SizedBox(width: AppSpacing.sm),
                      Material(
                        color: AppColors.secondary,
                        shape: const CircleBorder(),
                        elevation: 1,
                        child: InkWell(
                          onTap: _sendMessage,
                          customBorder: const CircleBorder(),
                          child: const Padding(
                            padding: EdgeInsets.all(AppSpacing.sm),
                            child: Icon(
                              Icons.send_rounded,
                              color: AppColors.onSecondary,
                              size: 20,
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                )),
        ],
      ),
    );
  }

  Widget _buildMessageBubble(ChatMessage msg, bool isMe) {
    final senderLabel = isMe
        ? "You"
        : (msg.senderUsername.isNotEmpty
            ? msg.senderUsername
            : "User #${msg.senderId.substring(0, msg.senderId.length > 6 ? 6 : msg.senderId.length)}");

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: Column(
        crossAxisAlignment:
            isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          // Bubble Container
          ThemedPanel(
              color: isMe ? AppColors.primaryContainer : AppColors.surface,
              borderRadius: BorderRadius.only(
                topLeft: const Radius.circular(AppRadius.md),
                topRight: const Radius.circular(AppRadius.md),
                bottomLeft: isMe
                    ? const Radius.circular(AppRadius.md)
                    : const Radius.circular(AppRadius.xs),
                bottomRight: isMe
                    ? const Radius.circular(AppRadius.xs)
                    : const Radius.circular(AppRadius.md),
              ),
              border: isMe
                  ? null
                  : Border.all(
                      color: AppColors.outlineVariant.withValues(alpha: 0.5),
                      width: 1,
                    ),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: 0.04),
                  blurRadius: 3,
                  offset: const Offset(0, 1),
                ),
              ],
              constraints: BoxConstraints(
                maxWidth: MediaQuery.of(context).size.width * 0.78,
              ),
              padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm + 2,
              ),
              child: Text(
                msg.content,
                style: AppTypography.bodyMd.copyWith(
                  color: isMe ? AppColors.onPrimary : AppColors.onSurface,
                  height: 1.35,
                ),
              )),
          const SizedBox(height: AppSpacing.xxs),
          // Metadata Row: Username + Status icon
          Padding(
            padding: EdgeInsets.only(
              left: isMe ? 0 : AppSpacing.xs,
              right: isMe ? AppSpacing.xs : 0,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Text(
                  senderLabel,
                  style: AppTypography.labelSm.copyWith(
                    color: AppColors.onSurfaceVariant,
                    fontWeight: isMe ? FontWeight.normal : FontWeight.w600,
                  ),
                ),
                if (isMe) ...[
                  const SizedBox(width: AppSpacing.xs),
                  const Icon(
                    Icons.done_all,
                    size: 14,
                    color: AppColors.secondary,
                  ),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
