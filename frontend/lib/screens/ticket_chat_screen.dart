import 'dart:async';
import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../models/chat_message.dart';
import '../models/support_ticket.dart';
import '../providers/auth_provider.dart';
import '../providers/chat_provider.dart';
import '../widgets/app_shell.dart';
import '../widgets/status_badge.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import 'package:file_picker/file_picker.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_panel.dart';
import '../widgets/themed_success_banner.dart';

class PickedAttachment {
  final String filename;
  final List<int> bytes;

  const PickedAttachment({
    required this.filename,
    required this.bytes,
  });
}

typedef TicketAttachmentPicker = Future<PickedAttachment?> Function(
    BuildContext context);

class TicketChatScreen extends StatefulWidget {
  final SupportTicket ticket;
  final TicketAttachmentPicker? onPickAttachment;

  const TicketChatScreen({
    super.key,
    required this.ticket,
    this.onPickAttachment,
  });

  @override
  State<TicketChatScreen> createState() => _TicketChatScreenState();
}

class _TicketChatScreenState extends State<TicketChatScreen> {
  final TextEditingController _messageController = TextEditingController();
  final ScrollController _scrollController = ScrollController();
  bool _isSending = false;
  bool _isUploadingAttachment = false;
  late bool _isResolved;
  String? _resolutionNote;

  Future<PickedAttachment?> _defaultPickAttachment(BuildContext context) async {
    try {
      final result = await FilePicker.platform.pickFiles(
        type: FileType.custom,
        allowedExtensions: ['jpg', 'jpeg', 'png', 'pdf'],
        withData: true,
      );
      if (result != null && result.files.isNotEmpty) {
        final file = result.files.first;
        if (file.bytes != null) {
          return PickedAttachment(
            filename: file.name,
            bytes: file.bytes!,
          );
        }
      }
    } catch (e) {
      debugPrint('Error picking file: $e');
    }
    return null;
  }

  Future<void> _pickAndUploadAttachment() async {
    if (_isSending || _isUploadingAttachment || _isResolved) return;
    final picker = widget.onPickAttachment ?? _defaultPickAttachment;
    final picked = await picker(context);
    if (!mounted || picked == null) return;

    if (picked.bytes.isEmpty) {
      ThemedSnackBar.showError(context, 'File cannot be empty');
      return;
    }
    if (picked.bytes.length > 10 * 1024 * 1024) {
      ThemedSnackBar.showError(
        context,
        'File exceeds maximum allowed size of 10MB',
      );
      return;
    }

    setState(() {
      _isUploadingAttachment = true;
    });

    final chat = Provider.of<ChatProvider>(context, listen: false);
    try {
      await chat.uploadTicketAttachment(
        ticketId: widget.ticket.id,
        fileBytes: picked.bytes,
        filename: picked.filename,
      );
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error uploading attachment: $e');
      if (mounted) {
        ThemedSnackBar.showError(
          context,
          context.l10n.chatFailedSend(friendlyErrorMessage(e)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isUploadingAttachment = false;
        });
      }
    }
  }

  @override
  void initState() {
    super.initState();
    _isResolved = widget.ticket.isResolved;
    _resolutionNote = widget.ticket.resolutionNote;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        _connectAndLoad();
      }
    });
  }

  Future<void> _connectAndLoad() async {
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final chat = Provider.of<ChatProvider>(context, listen: false);
    final token = auth.token;
    if (token != null && token.isNotEmpty) {
      final channel = 'ticket:${widget.ticket.id}';
      await chat.fetchChannelHistory(channel, token);
      if (mounted) {
        chat.connectAndSubscribeChannel(channel, token);
      }
    }
  }

  ChatProvider? _chatProvider;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _chatProvider = Provider.of<ChatProvider>(context, listen: false);
  }

  @override
  void dispose() {
    _messageController.dispose();
    _scrollController.dispose();
    // Teardown chat connection cleanly before unmounting
    _chatProvider?.disconnect();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollController.hasClients) {
        _scrollController.animateTo(
          _scrollController.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  Future<void> _sendMessage() async {
    final text = _messageController.text.trim();
    if (text.isEmpty || _isSending || _isResolved) return;

    setState(() {
      _isSending = true;
    });

    final chat = Provider.of<ChatProvider>(context, listen: false);
    try {
      await chat.sendMessage(text);
      _messageController.clear();
      _scrollToBottom();
    } catch (e) {
      debugPrint('Error sending ticket message: $e');
      if (mounted) {
        ThemedSnackBar.showError(
          context,
          context.l10n.chatFailedSend(friendlyErrorMessage(e)),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSending = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final chat = Provider.of<ChatProvider>(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final currentUserId = auth.user?.id ?? '';
    final displayId = widget.ticket.id.length > 8
        ? widget.ticket.id.substring(0, 8)
        : widget.ticket.id;

    // Check if any incoming message marked ticket resolved in real-time
    for (final m in chat.messages) {
      if (m.type == 'ticket_resolution') {
        _isResolved = true;
        if (m.content.isNotEmpty) {
          _resolutionNote = m.content;
        }
      }
    }

    return AppShell(
      titleWidget: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            l10n.ticketChatTitle(displayId),
            style: AppTypography.titleMd.copyWith(
              fontWeight: FontWeight.bold,
            ),
          ),
          Text(
            l10n.ticketChatSubtitle,
            style: AppTypography.bodySm.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
      actions: [
        Padding(
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.sm,
            vertical: AppSpacing.xs,
          ),
          child: Center(
            child: StatusBadge(
              status: _isResolved ? 'resolved' : widget.ticket.status,
              compact: true,
            ),
          ),
        ),
      ],
      showBackButton: true,
      padding: EdgeInsets.zero,
      body: Column(
        children: [
          // Top ticket context header
          _buildTicketMetadataHeader(context),

          // Resolved Banner (if ticket is resolved)
          if (_isResolved) _buildResolvedBanner(context),

          // Subscription/Connection Error Banner
          if (chat.subscriptionError != null)
            Padding(
              padding: const EdgeInsets.all(AppSpacing.sm),
              child: ThemedErrorBanner(
                message: chat.subscriptionError!,
              ),
            ),

          // Messages Stream
          Expanded(
            child: chat.isLoading
                ? const Center(child: ThemedLoadingIndicator())
                : RefreshIndicator(
                    onRefresh: () async {
                      final token = auth.token;
                      if (token != null) {
                        await chat.fetchChannelHistory(
                          'ticket:${widget.ticket.id}',
                          token,
                        );
                      }
                    },
                    child: chat.messages.isEmpty
                        ? _buildEmptyConversation(context)
                        : ListView.builder(
                            controller: _scrollController,
                            padding: const EdgeInsets.all(AppSpacing.md),
                            itemCount: chat.messages.length,
                            itemBuilder: (context, index) {
                              final message = chat.messages[index];
                              final isMe = message.senderId == currentUserId;
                              return _buildMessageItem(
                                context,
                                message,
                                isMe,
                              );
                            },
                          ),
                  ),
          ),

          // Bottom Input Area (or closed notice if resolved)
          _buildInputArea(context),
        ],
      ),
    );
  }

  Widget _buildTicketMetadataHeader(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);
    final subject = widget.ticket.subject ?? '';
    final contextId = widget.ticket.contextId ?? '';
    final agent = widget.ticket.assignedAgentId;

    return ThemedPanel(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      color: theme.colorScheme.surfaceContainerLow,
      border: Border(
        bottom: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (subject.isNotEmpty)
            Text(
              subject,
              style: AppTypography.bodyMd.copyWith(
                fontWeight: FontWeight.w600,
                color: theme.colorScheme.onSurface,
              ),
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
            ),
          const SizedBox(height: 2),
          Row(
            children: [
              if (contextId.isNotEmpty) ...[
                Icon(
                  Icons.receipt_long_outlined,
                  size: AppIconSize.xs,
                  color: theme.colorScheme.primary,
                ),
                const SizedBox(width: 4),
                Text(
                  l10n.ticketContextJob(contextId),
                  style: AppTypography.caption.copyWith(
                    color: theme.colorScheme.primary,
                    fontWeight: FontWeight.w500,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
              ],
              Icon(
                agent != null ? Icons.support_agent : Icons.hourglass_top,
                size: AppIconSize.xs,
                color: theme.colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  agent != null
                      ? l10n.ticketAssignedAgent(agent)
                      : l10n.ticketPendingAgent,
                  style: AppTypography.caption.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildResolvedBanner(BuildContext context) {
    final l10n = context.l10n;
    final semantic = context.semanticColors;

    return Padding(
      padding: const EdgeInsets.all(AppSpacing.sm),
      child: ThemedCard(
        color: semantic.success.withValues(alpha: 0.1),
        borderRadius: AppRadius.md,
        padding: AppSpacing.sm,
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.check_circle_outline,
              color: semantic.success,
              size: AppIconSize.md,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.ticketResolvedBannerTitle,
                    style: AppTypography.labelLg.copyWith(
                      color: semantic.success,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 2),
                  Text(
                    _resolutionNote != null && _resolutionNote!.isNotEmpty
                        ? "${l10n.ticketResolutionNote}: $_resolutionNote"
                        : l10n.ticketResolvedBannerMsg,
                    style: AppTypography.bodySm.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildEmptyConversation(BuildContext context) {
    final l10n = context.l10n;
    return ListView(
      children: [
        const SizedBox(height: AppSpacing.xxl),
        Icon(
          Icons.chat_bubble_outline,
          size: 48,
          color: Theme.of(context).colorScheme.outlineVariant,
        ),
        const SizedBox(height: AppSpacing.sm),
        Center(
          child: Text(
            l10n.ticketChatSubtitle,
            style: AppTypography.bodyLg.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xs),
        Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: Text(
              l10n.ticketPendingAgent,
              textAlign: TextAlign.center,
              style: AppTypography.bodySm.copyWith(
                color: Theme.of(context).colorScheme.outline,
              ),
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMessageItem(
    BuildContext context,
    ChatMessage message,
    bool isMe,
  ) {
    final theme = Theme.of(context);

    // System resolution message
    if (message.type == 'ticket_resolution') {
      return Center(
        child: ThemedPanel(
          margin: const EdgeInsets.symmetric(vertical: AppSpacing.xs),
          padding: const EdgeInsets.symmetric(
            horizontal: AppSpacing.md,
            vertical: AppSpacing.xs,
          ),
          color: context.semanticColors.success.withValues(alpha: 0.12),
          borderRadius: BorderRadius.circular(AppRadius.md),
          border: Border.all(
            color: context.semanticColors.success.withValues(alpha: 0.3),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline,
                size: AppIconSize.xs,
                color: context.semanticColors.success,
              ),
              const SizedBox(width: AppSpacing.xs),
              Flexible(
                child: Text(
                  message.content,
                  style: AppTypography.caption.copyWith(
                    color: context.semanticColors.success,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
        ),
      );
    }

    final bubbleBg = isMe
        ? theme.colorScheme.primary
        : theme.colorScheme.surfaceContainerHigh;
    final textColor =
        isMe ? theme.colorScheme.onPrimary : theme.colorScheme.onSurface;

    return Align(
      alignment: isMe ? Alignment.centerRight : Alignment.centerLeft,
      child: ThemedPanel(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.md,
          vertical: AppSpacing.sm,
        ),
        constraints: BoxConstraints(
          maxWidth: MediaQuery.of(context).size.width * 0.78,
        ),
        color: bubbleBg,
        borderRadius: BorderRadius.only(
          topLeft: const Radius.circular(AppRadius.md),
          topRight: const Radius.circular(AppRadius.md),
          bottomLeft: Radius.circular(isMe ? AppRadius.md : 2),
          bottomRight: Radius.circular(isMe ? 2 : AppRadius.md),
        ),
        child: Column(
          crossAxisAlignment:
              isMe ? CrossAxisAlignment.end : CrossAxisAlignment.start,
          children: [
            if (!isMe && message.senderUsername.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: 2),
                child: Text(
                  message.senderUsername,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: AppTypography.caption.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.primary,
                  ),
                ),
              ),
            if (message.attachmentUrl != null &&
                message.attachmentUrl!.isNotEmpty)
              _buildAttachmentPreview(context, message, isMe, textColor),
            if (message.content.isNotEmpty &&
                (message.attachmentUrl == null ||
                    message.attachmentUrl!.isEmpty ||
                    message.content != message.attachmentName))
              Text(
                message.content,
                style: AppTypography.bodyMd.copyWith(color: textColor),
              ),
          ],
        ),
      ),
    );
  }

  Widget _buildAttachmentPreview(
    BuildContext context,
    ChatMessage message,
    bool isMe,
    Color textColor,
  ) {
    final theme = Theme.of(context);
    final isImage = message.attachmentType?.startsWith('image/') == true ||
        (message.attachmentName != null &&
            (message.attachmentName!.toLowerCase().endsWith('.jpg') ||
                message.attachmentName!.toLowerCase().endsWith('.jpeg') ||
                message.attachmentName!.toLowerCase().endsWith('.png')));

    if (isImage && message.attachmentUrl != null) {
      return Padding(
        padding: const EdgeInsets.only(bottom: AppSpacing.xs),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.sm),
          child: ConstrainedBox(
            constraints: const BoxConstraints(
              maxHeight: 220,
              maxWidth: 280,
            ),
            child: Image.network(
              message.attachmentUrl!,
              fit: BoxFit.cover,
              errorBuilder: (context, error, stackTrace) => Container(
                padding: const EdgeInsets.all(AppSpacing.sm),
                color: isMe
                    ? theme.colorScheme.onPrimary.withValues(alpha: 0.15)
                    : theme.colorScheme.surfaceContainerHighest,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.broken_image_outlined,
                      size: 20,
                      color: isMe
                          ? theme.colorScheme.onPrimary
                          : theme.colorScheme.outline,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        message.attachmentName ?? 'Image',
                        style: AppTypography.caption.copyWith(color: textColor),
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      );
    }

    final isPdf = message.attachmentType == 'application/pdf' ||
        (message.attachmentName != null &&
            message.attachmentName!.toLowerCase().endsWith('.pdf'));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.xs),
      child: ThemedPanel(
        padding: const EdgeInsets.symmetric(
          horizontal: AppSpacing.sm,
          vertical: AppSpacing.xs,
        ),
        color: isMe
            ? theme.colorScheme.onPrimary.withValues(alpha: 0.15)
            : theme.colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.sm),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              isPdf ? Icons.picture_as_pdf : Icons.insert_drive_file_outlined,
              size: 28,
              color: isMe
                  ? theme.colorScheme.onPrimary
                  : theme.colorScheme.primary,
            ),
            const SizedBox(width: AppSpacing.sm),
            Flexible(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    message.attachmentName ?? 'Document',
                    style: AppTypography.bodySm.copyWith(
                      color: textColor,
                      fontWeight: FontWeight.w600,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (message.attachmentSize != null &&
                      message.attachmentSize! > 0)
                    Text(
                      _formatFileSize(message.attachmentSize!),
                      style: AppTypography.caption.copyWith(
                        color: textColor.withValues(alpha: 0.8),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  static String _formatFileSize(int bytes) {
    if (bytes < 1024) return '$bytes B';
    if (bytes < 1024 * 1024) return '${(bytes / 1024).toStringAsFixed(1)} KB';
    return '${(bytes / (1024 * 1024)).toStringAsFixed(1)} MB';
  }

  Widget _buildInputArea(BuildContext context) {
    final l10n = context.l10n;
    final theme = Theme.of(context);

    if (_isResolved) {
      return ThemedPanel(
        width: double.infinity,
        padding: const EdgeInsets.all(AppSpacing.md),
        color: theme.colorScheme.surfaceContainerLow,
        border: Border(
          top: BorderSide(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Row(
          children: [
            Icon(
              Icons.lock_outline,
              size: AppIconSize.sm,
              color: theme.colorScheme.outline,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                l10n.ticketInputClosed,
                style: AppTypography.bodySm.copyWith(
                  color: theme.colorScheme.outline,
                ),
              ),
            ),
          ],
        ),
      );
    }

    return ThemedPanel(
      padding: const EdgeInsets.all(AppSpacing.sm),
      color: theme.colorScheme.surface,
      border: Border(
        top: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Row(
        children: [
          IconButton(
            key: const Key('ticket_chat_attach_button'),
            icon: _isUploadingAttachment
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.attach_file_rounded,
                    color: theme.colorScheme.onSurfaceVariant,
                  ),
            tooltip: 'Attach file',
            onPressed: (_isSending || _isUploadingAttachment || _isResolved)
                ? null
                : _pickAndUploadAttachment,
          ),
          const SizedBox(width: AppSpacing.xs),
          Expanded(
            child: TextField(
              key: const Key('ticket_chat_input_field'),
              controller: _messageController,
              decoration: InputDecoration(
                hintText: l10n.chatTypeHint,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  borderSide: BorderSide(
                    color: theme.colorScheme.outlineVariant,
                  ),
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.xs,
                ),
              ),
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _sendMessage(),
            ),
          ),
          const SizedBox(width: AppSpacing.xs),
          IconButton(
            key: const Key('ticket_chat_send_button'),
            icon: _isSending
                ? const SizedBox(
                    width: 20,
                    height: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : Icon(
                    Icons.send_rounded,
                    color: theme.colorScheme.primary,
                  ),
            onPressed: _isSending ? null : _sendMessage,
          ),
        ],
      ),
    );
  }
}
