import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/notification_model.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/list_screen_template.dart';
import '../widgets/pill_filter_bar.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_empty_state.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key, this.clock});

  /// Injectable clock for deterministic date-group rendering (tests/goldens).
  /// Defaults to the real system time when null.
  final DateTime Function()? clock;

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _selectedCategory = 'All';
  DateTime? _lastCardTapTime;

  // A8: filter chip LABELS localize (keys existed unused); VALUES stay
  // canonical English so filtering logic remains stable across locales.
  List<PillFilterItem<String>> _categoryItems(AppLocalizations l10n) => [
        PillFilterItem(label: l10n.notificationsAll, value: 'All'),
        PillFilterItem(label: l10n.notificationsJobs, value: 'Jobs'),
        PillFilterItem(label: l10n.notificationsSystem, value: 'System'),
        PillFilterItem(label: l10n.notificationsAlerts, value: 'Alerts'),
      ];

  DateTime _now() => widget.clock?.call() ?? DateTime.now();

  bool _isToday(DateTime dateTime) {
    final now = _now();
    return dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;
  }

  bool _isYesterday(DateTime dateTime) {
    final yesterday = _now().subtract(const Duration(days: 1));
    return yesterday.year == dateTime.year &&
        yesterday.month == dateTime.month &&
        yesterday.day == dateTime.day;
  }

  String _getSectionTitle(DateTime timestamp) {
    if (_isToday(timestamp)) return 'TODAY';
    if (_isYesterday(timestamp)) return 'YESTERDAY';
    return 'EARLIER';
  }

  List<NotificationModel> _filterNotifications(List<NotificationModel> list) {
    if (_selectedCategory == 'All') return list;
    if (_selectedCategory == 'Jobs') {
      return list
          .where((n) => n.type == 'job_alert' || n.id.startsWith('job-'))
          .toList();
    }
    if (_selectedCategory == 'System') {
      return list.where((n) => n.type == 'system').toList();
    }
    if (_selectedCategory == 'Alerts') {
      return list
          .where((n) => n.type == 'status_update' || n.type == 'popup')
          .toList();
    }
    return list;
  }

  void _handleCardTap(String notifId, NotificationsProvider provider) {
    final now = DateTime.now();
    if (_lastCardTapTime != null &&
        now.difference(_lastCardTapTime!) < AppMotion.debounceGuard) {
      return;
    }
    _lastCardTapTime = now;
    provider.markAsRead(notifId);
  }

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<NotificationsProvider>(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);
    final l10n = context.l10n;
    final allNotifications = provider.notifications;
    final filtered = _filterNotifications(allNotifications);

    return ListScreenTemplate<NotificationModel>(
      title: l10n.notificationsTitle,
      actions: [
        IconButton(
          icon: const Icon(Icons.delete_sweep),
          tooltip: l10n.notificationsClear,
          onPressed: () async {
            final confirmed = await ConfirmActionDialog.show(
              context,
              title: l10n.notificationsClear,
              message: "${l10n.notificationsClear}?",
              confirmLabel: l10n.notificationsClear,
              cancelLabel: l10n.cancel,
              isDestructive: true,
            );
            if (confirmed == true && mounted) {
              provider.clearAll();
            }
          },
        ),
      ],
      header: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // A8/E2-F1: distinct retryable error state when the SSE stream
              // has errored — the connectivity banner alone reads as a neutral
              // "offline" state and offers no recovery affordance.
              if (provider.error != null)
                Padding(
                  padding: const EdgeInsets.fromLTRB(
                    AppSpacing.marginMobile,
                    AppSpacing.sm,
                    AppSpacing.marginMobile,
                    0,
                  ),
                  child: ThemedErrorBanner(
                    key: const Key('notifications_error_banner'),
                    message: provider.error!,
                    onRetry: () {
                      final auth =
                          Provider.of<AuthProvider>(context, listen: false);
                      if (auth.token != null) {
                        provider.initSse(auth.token!);
                      }
                    },
                  ),
                ),

              // 1. Connectivity Status Banner
              _buildConnectivityBanner(provider),

              // 2. Horizontal Filter Bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.marginMobile,
                  vertical: AppSpacing.xs,
                ),
                child: PillFilterBar<String>(
                  items: _categoryItems(context.l10n),
                  selectedValue: _selectedCategory,
                  onSelected: (val) {
                    setState(() {
                      _selectedCategory = val;
                    });
                  },
                ),
              ),
            ],
          ),
        ),
      ),
      items: filtered,
      emptyWidget: ThemedEmptyState(
        icon: Icons.notifications_none,
        title: l10n.notificationsTitle,
        description: l10n.notificationsTitle,
        actionText: l10n.backToHomeBtn,
        onActionPressed: () => Navigator.pop(context),
      ),
      itemSpacing: 0,
      itemBuilder: (context, notif, index) => _buildNotificationItem(
        context,
        notif,
        index,
        filtered,
        provider,
        auth.token,
      ),
    );
  }

  Widget _buildConnectivityBanner(NotificationsProvider provider) {
    final l10n = context.l10n;
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.marginMobile,
        AppSpacing.sm,
        AppSpacing.marginMobile,
        AppSpacing.xs,
      ),
      child: ThemedCard(
        padding: AppSpacing.sm,
        color: provider.isConnected
            ? context.semanticColors.success.withValues(alpha: 0.12)
            : Theme.of(context)
                .colorScheme
                .errorContainer
                .withValues(alpha: 0.3),
        borderRadius: AppRadius.md,
        borderSide: BorderSide(
          color: provider.isConnected
              ? context.semanticColors.success.withValues(alpha: 0.25)
              : AppColors.error.withValues(alpha: 0.25),
        ),
        child: Row(
          children: [
            Icon(
              provider.isConnected
                  ? Icons.check_circle_outline
                  : Icons.wifi_off,
              color: provider.isConnected
                  ? context.semanticColors.success
                  : AppColors.error,
              size: AppIconSize.sm,
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: Text(
                provider.isConnected
                    ? l10n.systemStatusOperationalMsg
                    : l10n.syncPausedOfflineMsg,
                style: AppTypography.labelMd.copyWith(
                  color: provider.isConnected
                      ? Theme.of(context).colorScheme.onSurface
                      : AppColors.error,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildNotificationItem(
    BuildContext context,
    NotificationModel notif,
    int index,
    List<NotificationModel> list,
    NotificationsProvider provider,
    String? userToken,
  ) {
    final currentSection = _getSectionTitle(notif.timestamp);
    final showSectionHeader = index == 0 ||
        _getSectionTitle(list[index - 1].timestamp) != currentSection;

    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 1000),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            if (showSectionHeader)
              Padding(
                padding: const EdgeInsets.only(
                  top: AppSpacing.md,
                  bottom: AppSpacing.xs,
                ),
                child: Text(
                  currentSection,
                  style: AppTypography.labelMd.copyWith(
                    color: Theme.of(context)
                        .colorScheme
                        .primary
                        .withValues(alpha: 0.7),
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.8,
                  ),
                ),
              ),
            _buildStitchNotificationCard(
              notif: notif,
              provider: provider,
              userToken: userToken,
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildStitchNotificationCard({
    required NotificationModel notif,
    required NotificationsProvider provider,
    required String? userToken,
  }) {
    final bool isJob = notif.type == 'job_alert' || notif.id.startsWith('job-');
    final bool isAlert = notif.type == 'status_update' || notif.type == 'popup';
    final bool isSystem = notif.type == 'system';

    final IconData typeIcon = isJob
        ? Icons.local_shipping_outlined
        : (isAlert
            ? Icons.warning_amber_rounded
            : (isSystem
                ? Icons.system_update_alt_rounded
                : Icons.notifications_outlined));

    final Color iconBgColor = isJob
        ? AppColors.primaryContainer
        : (isAlert
            ? Theme.of(context).colorScheme.errorContainer
            : (isSystem
                ? Theme.of(context).colorScheme.surfaceContainerHigh
                : Theme.of(context).colorScheme.surfaceContainerHigh));

    final Color iconColor = isJob
        ? AppColors.secondary
        : (isAlert
            ? AppColors.error
            : (isSystem
                ? Theme.of(context).colorScheme.onSurfaceVariant
                : Theme.of(context).colorScheme.primary));

    final String tagLabel = isJob
        ? 'JOB ALERT'
        : (isAlert ? 'ALERT' : (isSystem ? 'SYSTEM' : 'NOTIFICATION'));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ThemedCard(
        padding: 0,
        color: notif.isRead
            ? Theme.of(context).colorScheme.surface
            : Theme.of(context).colorScheme.surfaceContainerLowest,
        borderRadius: AppRadius.lg,
        child: InkWell(
          borderRadius: BorderRadius.circular(AppRadius.lg),
          onTap: () => _handleCardTap(notif.id, provider),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Left Amber Vertical Bar for Unread
                if (!notif.isRead)
                  ClipRRect(
                    borderRadius: const BorderRadius.only(
                      topLeft: Radius.circular(AppRadius.lg),
                      bottomLeft: Radius.circular(AppRadius.lg),
                    ),
                    child: Container(
                      width: 4,
                      color: AppColors.secondary,
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Top Meta Row: Icon + Tag + Timestamp + Dismiss
                        Row(
                          children: [
                            CircleAvatar(
                              radius: 16,
                              backgroundColor: iconBgColor,
                              child: Icon(
                                typeIcon,
                                size: 16,
                                color: iconColor,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            ClipRRect(
                              borderRadius: BorderRadius.circular(AppRadius.xs),
                              child: Container(
                                color: isAlert
                                    ? Theme.of(context)
                                        .colorScheme
                                        .errorContainer
                                        .withValues(alpha: 0.5)
                                    : Theme.of(context)
                                        .colorScheme
                                        .surfaceContainerHigh,
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.xs,
                                  vertical: 2,
                                ),
                                child: Text(
                                  tagLabel,
                                  style: AppTypography.labelSm.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: isAlert
                                        ? AppColors.error
                                        : Theme.of(context)
                                            .colorScheme
                                            .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(notif.timestamp),
                              style: AppTypography.caption.copyWith(
                                color: AppColors.outline,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            IconButton(
                              icon: const Icon(
                                Icons.delete_outline,
                                size: AppIconSize.sm,
                              ),
                              tooltip: context.l10n.tooltipDismiss,
                              color: AppColors.outline,
                              padding: EdgeInsets.zero,
                              constraints: const BoxConstraints(
                                minWidth: 24,
                                minHeight: 24,
                              ),
                              onPressed: () => provider.dismiss(notif.id),
                            ),
                          ],
                        ),
                        const SizedBox(height: AppSpacing.sm),

                        // Title
                        Text(
                          notif.title,
                          style: AppTypography.bodyLg.copyWith(
                            fontWeight: notif.isRead
                                ? FontWeight.w500
                                : FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),

                        // Body description
                        Text(
                          notif.body,
                          style: AppTypography.bodyMd.copyWith(
                            color:
                                Theme.of(context).colorScheme.onSurfaceVariant,
                            height: 1.4,
                          ),
                        ),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  String _formatTime(DateTime dt) {
    final local = dt.toLocal();
    final hour = local.hour.toString().padLeft(2, '0');
    final minute = local.minute.toString().padLeft(2, '0');
    return '$hour:$minute';
  }
}
