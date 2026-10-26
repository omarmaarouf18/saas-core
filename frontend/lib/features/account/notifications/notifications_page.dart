import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:intl/intl.dart';
import 'package:provider/provider.dart';

import '../../../l10n/l10n.dart';
import '../../../models/notification_model.dart';
import '../../../providers/auth_provider.dart';
import '../../../providers/notifications_provider.dart';
import '../../../ui/qd_ui.dart';
import '../account_nav.dart';
import 'notification_rules.dart';

/// Notifications (A-Notifs): grouped by day, newest first.
///
/// Behaviour kept from NotificationsScreen: history fetched on open when
/// the list is empty, pull to refresh (full reload), load more (older
/// pages), tap marks read, dismiss one, clear all after a confirmation,
/// the live-stream state with a reconnect when the stream failed, and a
/// loader instead of the empty state during the first fetch. Changed: tap
/// links check the role (customers only, customer screens only, see
/// [notificationTarget]); "mark all read" is wired (it existed in the
/// provider only); the category filter is dropped (the mockup has none).
class NotificationsPage extends StatefulWidget {
  const NotificationsPage({super.key, this.links, this.now});

  /// Where taps lead; default [NotificationLinks.of] the opening context.
  final NotificationLinks? links;

  /// Clock for day groups and relative times (tests).
  final DateTime Function()? now;

  /// Opens the page from [context] (inside a role shell, so links can
  /// switch to its tabs, see [NotificationShellScope]).
  static Future<void> open(BuildContext context) {
    final links = NotificationLinks.of(context);
    return Navigator.of(context).push<void>(
        MaterialPageRoute(builder: (_) => NotificationsPage(links: links)));
  }

  @override
  State<NotificationsPage> createState() => _NotificationsPageState();
}

class _NotificationsPageState extends State<NotificationsPage> {
  Timer? _tapGuard;
  late NotificationLinks _links;

  DateTime _now() => widget.now?.call() ?? DateTime.now();

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      final provider = context.read<NotificationsProvider>();
      if (provider.notifications.isEmpty) provider.fetchHistory();
    });
  }

  @override
  void dispose() {
    _tapGuard?.cancel();
    super.dispose();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _links = widget.links ?? NotificationLinks.of(context);
  }

  void _tap(NotificationModel n) {
    // Same 500 ms guard as the old screen: a double tap opens one page.
    if (_tapGuard?.isActive ?? false) return;
    _tapGuard = Timer(const Duration(milliseconds: 500), () {});
    final provider = context.read<NotificationsProvider>();
    if (!n.isRead) provider.markAsRead(n.id);
    final role = context.read<AuthProvider>().user?.role;
    _links.follow(context, notificationTarget(n, role),
        resolved: n.type == 'ticket_resolved');
  }

  Future<void> _clearAll() async {
    final l10n = context.l10n;
    final provider = context.read<NotificationsProvider>();
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => Builder(builder: (ctx) {
        final c = QdColors.of(ctx);
        return AlertDialog(
          backgroundColor: c.surface,
          title: Text(l10n.ntfClearTitle,
              style: QdText.header.copyWith(color: c.textPrimary)),
          content: Text(l10n.ntfClearBody,
              style: QdText.body.copyWith(color: c.textSecondary)),
          actions: [
            QdButton.text(
              key: const Key('ntf_clear_cancel'),
              label: l10n.acctCancel,
              small: true,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            QdButton.destructive(
              key: const Key('ntf_clear_confirm'),
              label: l10n.ntfClear,
              small: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      }),
    );
    if (ok == true && mounted) await provider.clearAll();
  }

  void _reconnect() {
    final token = context.read<AuthProvider>().token;
    if (token != null) context.read<NotificationsProvider>().initSse(token);
  }

  String _dayLabel(BuildContext context, DateTime day) {
    final l10n = context.l10n;
    final n = _now();
    final today = DateTime(n.year, n.month, n.day);
    if (day == today) return l10n.ntfToday;
    if (day == today.subtract(const Duration(days: 1))) {
      return l10n.ntfYesterday;
    }
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat.yMMMd(locale).format(day);
  }

  String _timeLabel(BuildContext context, DateTime t) {
    final l10n = context.l10n;
    final local = t.toLocal();
    final diff = _now().difference(local);
    if (!diff.isNegative && diff.inHours < 12) {
      if (diff.inMinutes < 1) return l10n.ntfJustNow;
      if (diff.inMinutes < 60) return l10n.ntfMinutesAgo(diff.inMinutes);
      return l10n.ntfHoursAgo(diff.inHours);
    }
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat.jm(locale).format(local);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final provider = context.watch<NotificationsProvider>();
    final list = provider.notifications;

    final Widget body;
    if (list.isEmpty && provider.isLoadingHistory) {
      body = const Center(
          key: Key('ntf_loading'), child: CircularProgressIndicator());
    } else if (list.isEmpty &&
        provider.error != null &&
        !provider.isConnected) {
      body = Center(
        child: SingleChildScrollView(
          child: QdErrorState(
            key: const Key('ntf_error'),
            body: l10n.ntfLoadError,
            onRetry: () => provider.fetchHistory(refresh: true),
          ),
        ),
      );
    } else if (list.isEmpty) {
      body = RefreshIndicator(
        onRefresh: () => provider.fetchHistory(refresh: true),
        child: ListView(children: [
          const SizedBox(height: 80),
          QdEmptyState(
            key: const Key('ntf_empty'),
            icon: Icons.notifications_none,
            title: l10n.ntfEmptyTitle,
            body: l10n.ntfEmptyBody,
          ),
        ]),
      );
    } else {
      final groups = groupByDay(list);
      body = RefreshIndicator(
        onRefresh: () => provider.fetchHistory(refresh: true),
        child: ListView(
          key: const Key('ntf_list'),
          padding: const EdgeInsetsDirectional.fromSTEB(
              QdSpace.gutter, QdSpace.x1, QdSpace.gutter, QdSpace.x4),
          children: [
            for (final (day, items) in groups) ...[
              Padding(
                padding: const EdgeInsets.only(top: QdSpace.x3, bottom: 4),
                child: Semantics(
                  header: true,
                  child: Text(_dayLabel(context, day),
                      style: QdText.secondary.copyWith(
                          color: c.textSecondary, fontWeight: FontWeight.w600)),
                ),
              ),
              for (final n in items)
                Padding(
                  padding: const EdgeInsets.only(bottom: QdSpace.x2),
                  child: _NotificationTile(
                    key: Key('ntf_${n.id}'),
                    notification: n,
                    time: _timeLabel(context, n.timestamp),
                    onTap: () => _tap(n),
                    onDismiss: () => provider.dismiss(n.id),
                  ),
                ),
            ],
            if (provider.hasMore) ...[
              const SizedBox(height: QdSpace.x2),
              QdButton.secondary(
                key: const Key('ntf_more'),
                label: l10n.ntfShowOlder,
                loading: provider.isLoadingMore,
                fullWidth: true,
                onPressed: provider.loadMore,
              ),
            ],
          ],
        ),
      );
    }

    return Scaffold(
      backgroundColor: c.surface,
      appBar: accountAppBar(context, l10n.ntfTitle, actions: [
        if (provider.unreadCount > 0)
          QdButton.text(
            key: const Key('ntf_mark_all'),
            label: l10n.ntfMarkAllRead,
            small: true,
            onPressed: provider.markAllAsRead,
          ),
        if (list.isNotEmpty)
          IconButton(
            key: const Key('ntf_clear_all'),
            tooltip: l10n.ntfClearAll,
            onPressed: _clearAll,
            icon: Icon(Icons.delete_sweep_outlined, color: c.textPrimary),
          ),
        const SizedBox(width: QdSpace.x1),
      ]),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: QdSpace.gutter),
            child: provider.error != null && !provider.isConnected
                ? QdBanner(
                    key: const Key('ntf_connection_error'),
                    tone: QdBannerTone.warning,
                    message: l10n.ntfConnectError,
                    actionLabel: l10n.ntfReconnect,
                    onAction: _reconnect,
                  )
                : _ConnectionLine(connected: provider.isConnected),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

class _ConnectionLine extends StatelessWidget {
  const _ConnectionLine({required this.connected});

  final bool connected;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Row(
        key: const Key('ntf_connection'),
        children: [
          ExcludeSemantics(
            child: Container(
              width: 8,
              height: 8,
              decoration: BoxDecoration(
                color: connected ? c.success : c.decorative,
                shape: BoxShape.circle,
              ),
            ),
          ),
          const SizedBox(width: 6),
          Expanded(
            child: Text(
              connected ? l10n.ntfLive : l10n.ntfOffline,
              style: QdText.caption.copyWith(color: c.textSecondary),
            ),
          ),
        ],
      ),
    );
  }
}

class _NotificationTile extends StatelessWidget {
  const _NotificationTile({
    super.key,
    required this.notification,
    required this.time,
    required this.onTap,
    required this.onDismiss,
  });

  final NotificationModel notification;
  final String time;
  final VoidCallback onTap;
  final VoidCallback onDismiss;

  /// Icon, tile fill and icon color per type (A-Notifs: gold for an
  /// accepted order or a new job, green for delivered or approved, red for
  /// cancelled or rejected, amber for cancellation requests, muted
  /// otherwise).
  (IconData, Color, Color) _icon(QdColors c, String type) => switch (type) {
        'job_accepted' || 'job_offer' || 'job_alert' => (
            Icons.inventory_2_outlined,
            c.gold,
            c.onGold
          ),
        'job_completed' || 'kyc_approved' => (
            Icons.check,
            c.successBg,
            c.success
          ),
        'job_cancelled' || 'job_unavailable' || 'kyc_rejected' => (
            Icons.block,
            c.dangerBg,
            c.danger
          ),
        'cancellation_requested' ||
        'cancellation_request_expired' ||
        'cancellation_resolved' =>
          (Icons.schedule, c.warningBg, c.warning),
        'ticket_resolved' || 'ticket_assigned' => (
            Icons.chat_bubble_outline,
            c.fillMuted,
            c.textPrimary
          ),
        _ => (Icons.notifications_none, c.fillMuted, c.textPrimary),
      };

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final n = notification;
    final (title, body) = notificationCopy(l10n, n);
    final (icon, tileBg, tileFg) = _icon(c, n.type);
    final radius = BorderRadius.circular(QdRadius.card);

    return Dismissible(
      key: ValueKey('dismiss_${n.id}'),
      onDismissed: (_) => onDismiss(),
      background: Container(
        alignment: AlignmentDirectional.centerStart,
        padding: const EdgeInsets.symmetric(horizontal: QdSpace.x5),
        decoration: BoxDecoration(color: c.dangerBg, borderRadius: radius),
        child: Icon(Icons.delete_outline, color: c.danger),
      ),
      child: Semantics(
        customSemanticsActions: {
          CustomSemanticsAction(label: l10n.ntfDismiss): onDismiss,
        },
        child: Material(
          color: n.isRead ? c.surface : c.goldTint,
          borderRadius: radius,
          child: InkWell(
            onTap: onTap,
            borderRadius: radius,
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  ExcludeSemantics(
                    child: Container(
                      width: QdSize.iconTile,
                      height: QdSize.iconTile,
                      decoration: BoxDecoration(
                        color: tileBg,
                        borderRadius: BorderRadius.circular(QdRadius.sm),
                      ),
                      child: Icon(icon, size: QdSize.icon, color: tileFg),
                    ),
                  ),
                  const SizedBox(width: QdSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(title,
                            style: QdText.rowTitleSm
                                .copyWith(color: c.textPrimary)),
                        if (body.isNotEmpty) ...[
                          const SizedBox(height: 2),
                          Text(body,
                              maxLines: 3,
                              overflow: TextOverflow.ellipsis,
                              style:
                                  QdText.secondary.copyWith(color: c.neutral)),
                        ],
                        const SizedBox(height: 2),
                        Text(time,
                            style: QdText.caption
                                .copyWith(color: c.textSecondary)),
                      ],
                    ),
                  ),
                  if (!n.isRead)
                    Semantics(
                      label: l10n.ntfUnread,
                      child: Container(
                        key: const Key('ntf_unread_dot'),
                        width: 8,
                        height: 8,
                        margin: const EdgeInsetsDirectional.only(
                            start: QdSpace.x2, top: 6),
                        decoration: BoxDecoration(
                            color: c.navy, shape: BoxShape.circle),
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
}
