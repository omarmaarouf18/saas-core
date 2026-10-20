import 'dart:async';

import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../../core/error_messages.dart';
import '../../../core/provider_connection_cleanup.dart';
import '../../../l10n/l10n.dart';
import '../../../models/chat_message.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/chat_provider.dart';
import '../../../ui/qd_ui.dart';
import '../customer_theme.dart';

/// Chat (FE-CUST-2): one component for any chat-service channel. Job chat
/// uses `job:<id>`; ticket chat can reuse it with its own channel later.
///
/// Same behaviour as screens/chat_screen.dart: history first, then the
/// websocket (only when history was not refused), live / connecting /
/// offline state, an error banner with retry, an access-denied state that
/// hides the composer, a loader while history loads, an empty state, and a
/// send guard against double taps. The app-lifetime [ChatProvider]
/// connection is torn down when the page closes.
class CustomerChatPage extends StatefulWidget {
  const CustomerChatPage({
    super.key,
    required this.channel,
    required this.title,
    this.subtitle,
    this.emptyBody,
  });

  /// Chat-service channel, e.g. `job:<id>`.
  final String channel;
  final String title;
  final String? subtitle;

  /// Empty-state hint; defaults to the courier hint.
  final String? emptyBody;

  /// Job chat with the courier.
  static Future<void> openJob(BuildContext context,
      {required String jobId, required String title, String? subtitle}) {
    return Navigator.of(context).push<void>(customerRoute(
      (_) => CustomerChatPage(
          channel: 'job:$jobId', title: title, subtitle: subtitle),
    ));
  }

  @override
  State<CustomerChatPage> createState() => _CustomerChatPageState();
}

class _CustomerChatPageState extends State<CustomerChatPage>
    with ProviderConnectionCleanup<CustomerChatPage> {
  final _input = TextEditingController();
  final _scroll = ScrollController();
  Timer? _scrollTimer;
  bool _sending = false;
  int _lastCount = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      addConnectionTeardown(context.read<ChatProvider>().disconnect);
      _init();
    });
  }

  void _init() {
    final token = context.read<AuthProvider>().token;
    final chat = context.read<ChatProvider>();
    if (token == null) return;
    chat.fetchChannelHistory(widget.channel, token).then((_) {
      if (mounted && chat.subscriptionError == null) {
        chat.connectAndSubscribeChannel(widget.channel, token);
      }
    });
  }

  @override
  void dispose() {
    _scrollTimer?.cancel();
    _input.dispose();
    _scroll.dispose();
    super.dispose();
  }

  void _scrollToEnd() {
    if (!_scroll.hasClients) return;
    _scroll.animateTo(
      _scroll.position.maxScrollExtent,
      duration: const Duration(milliseconds: 250),
      curve: Curves.easeOut,
    );
  }

  Future<void> _send() async {
    // One send at a time: the field is cleared only after the await, so a
    // double tap would otherwise send the same text twice.
    if (_sending) return;
    final text = _input.text.trim();
    if (text.isEmpty) return;
    _sending = true;
    final chat = context.read<ChatProvider>();
    try {
      await chat.sendMessage(text);
      _input.clear();
      _scrollTimer?.cancel();
      _scrollTimer = Timer(const Duration(milliseconds: 150), _scrollToEnd);
    } catch (e) {
      if (mounted) {
        final messenger = ScaffoldMessenger.maybeOf(context);
        messenger?.showSnackBar(SnackBar(
          content: Text(context.l10n.chatSendFailed(friendlyErrorMessage(e))),
          action: SnackBarAction(label: context.l10n.retry, onPressed: _send),
        ));
      }
    } finally {
      _sending = false;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final chat = context.watch<ChatProvider>();
    final me = context.watch<AuthProvider>().user?.id ?? '';
    final denied = chat.subscriptionError != null;

    if (chat.messages.length != _lastCount) {
      _lastCount = chat.messages.length;
      WidgetsBinding.instance.addPostFrameCallback((_) => _scrollToEnd());
    }

    final Widget content;
    if (denied) {
      content = Center(
        child: SingleChildScrollView(
          padding: const EdgeInsets.all(QdSpace.gutter),
          child: QdBanner(
            key: const Key('chat_denied'),
            tone: QdBannerTone.danger,
            icon: Icons.lock_outline,
            message: l10n.chatDenied,
            actionLabel: l10n.retry,
            onAction: _init,
          ),
        ),
      );
    } else if (chat.messages.isEmpty &&
        (chat.isConnecting || chat.isLoadingHistory)) {
      content = const Center(
          key: Key('chat_loading'), child: CircularProgressIndicator());
    } else if (chat.messages.isEmpty) {
      content = Center(
        child: SingleChildScrollView(
          child: QdEmptyState(
            key: const Key('chat_empty'),
            icon: Icons.chat_bubble_outline,
            title: l10n.chatEmptyTitle,
            body: widget.emptyBody ?? l10n.chatEmptyBody,
          ),
        ),
      );
    } else {
      content = ListView.builder(
        key: const Key('chat_list'),
        controller: _scroll,
        padding: const EdgeInsets.symmetric(
            horizontal: QdSpace.x4, vertical: QdSpace.x4),
        itemCount: chat.messages.length,
        itemBuilder: (context, i) {
          final msg = chat.messages[i];
          return _Bubble(message: msg, mine: msg.senderId == me);
        },
      );
    }

    return Scaffold(
      appBar: AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(widget.title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: QdText.header.copyWith(color: c.textPrimary)),
            _ConnectionLine(chat: chat, subtitle: widget.subtitle),
          ],
        ),
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (chat.error != null && !denied)
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                  QdSpace.x4, QdSpace.x2, QdSpace.x4, 0),
              child: QdBanner(
                key: const Key('chat_error'),
                tone: QdBannerTone.danger,
                icon: Icons.error_outline,
                message: chat.error!,
                actionLabel: l10n.retry,
                onAction: _init,
              ),
            ),
          Expanded(child: content),
          if (!denied) _composer(context, chat),
        ],
      ),
    );
  }

  Widget _composer(BuildContext context, ChatProvider chat) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return QdFooterBar(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          Expanded(
            child: TextField(
              key: const Key('chat_input'),
              controller: _input,
              minLines: 1,
              maxLines: 4,
              textInputAction: TextInputAction.send,
              onSubmitted: (_) => _send(),
              style: QdText.body.copyWith(color: c.textPrimary),
              decoration: InputDecoration(
                hintText: l10n.chatHint,
                isDense: true,
              ),
            ),
          ),
          const SizedBox(width: QdSpace.x2),
          QdIconButton(
            key: const Key('chat_send'),
            icon: Icons.send,
            label: l10n.chatSend,
            round: true,
            onPressed: _send,
          ),
        ],
      ),
    );
  }
}

/// Subtitle + live / connecting / offline / denied line under the title.
class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({required this.chat, this.subtitle});

  final ChatProvider chat;
  final String? subtitle;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final (String label, Color dot) = chat.subscriptionError != null
        ? (l10n.chatDenied, c.danger)
        : chat.isConnected
            ? (l10n.chatLive, c.success)
            : chat.isConnecting
                ? (l10n.chatConnecting, c.warning)
                : (l10n.chatOffline, c.decorative);
    final text = subtitle == null ? label : '$subtitle · $label';
    return Row(
      key: const Key('chat_connection'),
      children: [
        ExcludeSemantics(
          child: Container(
            width: 8,
            height: 8,
            decoration: BoxDecoration(color: dot, shape: BoxShape.circle),
          ),
        ),
        const SizedBox(width: 6),
        Expanded(
          child: Text(
            text,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: QdText.caption.copyWith(color: c.textSecondary),
          ),
        ),
      ],
    );
  }
}

class _Bubble extends StatelessWidget {
  const _Bubble({required this.message, required this.mine});

  final ChatMessage message;
  final bool mine;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final id = message.senderId;
    final sender = mine
        ? l10n.chatYou
        : message.senderUsername.trim().isNotEmpty
            ? message.senderUsername.trim()
            : l10n.chatUserFallback(id.length > 6 ? id.substring(0, 6) : id);
    const r = Radius.circular(QdRadius.card);
    const tail = Radius.circular(4);
    return Padding(
      padding: const EdgeInsets.only(bottom: QdSpace.x3),
      child: Column(
        crossAxisAlignment:
            mine ? CrossAxisAlignment.end : CrossAxisAlignment.start,
        children: [
          ConstrainedBox(
            constraints: BoxConstraints(
                maxWidth: MediaQuery.sizeOf(context).width * 0.78),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: QdSpace.x4, vertical: 10),
              decoration: BoxDecoration(
                color: mine ? c.goldTint : c.surface,
                border: Border.all(color: mine ? c.gold : c.border),
                borderRadius: BorderRadiusDirectional.only(
                  topStart: r,
                  topEnd: r,
                  bottomStart: mine ? r : tail,
                  bottomEnd: mine ? tail : r,
                ),
              ),
              child: Text(message.content,
                  style: QdText.body.copyWith(color: c.textPrimary)),
            ),
          ),
          const SizedBox(height: 2),
          Text(sender, style: QdText.caption.copyWith(color: c.textSecondary)),
        ],
      ),
    );
  }
}
