import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../models/notification_model.dart';
import '../providers/auth_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/confirm_action_dialog.dart';
import '../widgets/pill_filter_bar.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _selectedCategory = 'All';
  DateTime? _lastCardTapTime;

  final List<String> _categories = ['All', 'Jobs', 'System', 'Alerts'];

  bool _isToday(DateTime dateTime) {
    final now = DateTime.now();
    return dateTime.year == now.year &&
        dateTime.month == now.month &&
        dateTime.day == now.day;
  }

  bool _isYesterday(DateTime dateTime) {
    final yesterday = DateTime.now().subtract(const Duration(days: 1));
    return yesterday.year == dateTime.year &&
        yesterday.month == dateTime.month &&
        yesterday.day == dateTime.day;
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

    // Grouping
    final todayNotifs = filtered.where((n) => _isToday(n.timestamp)).toList();
    final yesterdayNotifs =
        filtered.where((n) => _isYesterday(n.timestamp)).toList();
    final earlierNotifs = filtered
        .where((n) => !_isToday(n.timestamp) && !_isYesterday(n.timestamp))
        .toList();

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: Text(
          l10n.notificationsTitle,
          style: AppTypography.titleMd.copyWith(color: AppColors.onPrimary),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
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
      ),
      body: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // System Status Banner
          Container(
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md, vertical: AppSpacing.sm),
            color: provider.isConnected
                ? AppColors.success.withValues(alpha: 0.15)
                : AppColors.error.withValues(alpha: 0.15),
            child: Row(
              children: [
                Icon(
                  provider.isConnected ? Icons.check_circle : Icons.error,
                  color: provider.isConnected
                      ? AppColors.success
                      : AppColors.error,
                  size: AppIconSize.sm,
                ),
                const SizedBox(width: AppSpacing.base),
                Expanded(
                  child: Text(
                    provider.isConnected
                        ? 'System Status: Operational.'
                        : 'System Status: Disconnected.',
                    style: AppTypography.labelMd.copyWith(
                      color: provider.isConnected
                          ? AppColors.onSurface
                          : AppColors.error,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Categories Filter Tabs
          PillFilterBar<String>(
            items: _categories
                .map((cat) => PillFilterItem<String>(
                      label: cat,
                      value: cat,
                    ))
                .toList(),
            selectedValue: _selectedCategory,
            onSelected: (val) {
              setState(() {
                _selectedCategory = val;
              });
            },
            padding: const EdgeInsets.symmetric(
              horizontal: AppSpacing.md,
              vertical: AppSpacing.sm,
            ),
          ),

          // List of Notifications
          Expanded(
            child: filtered.isEmpty
                ? ThemedEmptyState(
                    icon: Icons.notifications_none,
                    title: l10n.notificationsTitle,
                    description: l10n.notificationsTitle,
                    actionText: "Back to Home",
                    onActionPressed: () => Navigator.pop(context),
                  )
                : ListView(
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    children: [
                      if (todayNotifs.isNotEmpty) ...[
                        _buildSectionHeader('Today', colorScheme),
                        ...todayNotifs.map((n) => _buildNotificationCard(
                            n, provider, auth.token, colorScheme)),
                      ],
                      if (yesterdayNotifs.isNotEmpty) ...[
                        _buildSectionHeader('Yesterday', colorScheme),
                        ...yesterdayNotifs.map((n) => _buildNotificationCard(
                            n, provider, auth.token, colorScheme)),
                      ],
                      if (earlierNotifs.isNotEmpty) ...[
                        _buildSectionHeader('Earlier', colorScheme),
                        ...earlierNotifs.map((n) => _buildNotificationCard(
                            n, provider, auth.token, colorScheme)),
                      ],
                      const SizedBox(height: AppSpacing.lg),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding:
          const EdgeInsets.only(top: AppSpacing.md, bottom: AppSpacing.base),
      child: Text(
        title.toUpperCase(),
        style: AppTypography.labelMd.copyWith(
          color: AppColors.primary.withValues(alpha: 0.7),
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }

  Widget _buildNotificationCard(
    NotificationModel notif,
    NotificationsProvider provider,
    String? userToken,
    ColorScheme colorScheme,
  ) {
    IconData typeIcon = Icons.notifications_outlined;
    Color iconBgColor = AppColors.surfaceContainerHigh;
    Color iconColor = AppColors.primary;
    String tagLabel = 'NOTIFICATION';

    if (notif.type == 'job_alert' || notif.id.startsWith('job-')) {
      typeIcon = Icons.local_shipping_outlined;
      iconBgColor = AppColors.primaryContainer;
      iconColor = AppColors.onPrimary;
      tagLabel = 'JOB ALERT';
    } else if (notif.type == 'status_update' || notif.type == 'popup') {
      typeIcon = Icons.warning_amber_rounded;
      iconBgColor = AppColors.errorContainer;
      iconColor = AppColors.error;
      tagLabel = 'ALERT';
    } else if (notif.type == 'system') {
      typeIcon = Icons.system_update_alt_rounded;
      iconBgColor = AppColors.surfaceContainerHigh;
      iconColor = AppColors.onSurfaceVariant;
      tagLabel = 'SYSTEM';
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: ThemedCard(
        padding: 0,
        color:
            notif.isRead ? AppColors.surface : AppColors.surfaceContainerLowest,
        borderRadius: AppRadius.md,
        child: InkWell(
          borderRadius: AppRadius.mdBorder,
          onTap: () => _handleCardTap(notif.id, provider),
          child: IntrinsicHeight(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Unread indicator bar on left
                if (!notif.isRead)
                  Container(
                    width: 4,
                    decoration: const BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(AppRadius.md),
                        bottomLeft: Radius.circular(AppRadius.md),
                      ),
                    ),
                  ),
                Expanded(
                  child: Padding(
                    padding: const EdgeInsets.all(AppSpacing.md),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Header line: icon badge + tag + timestamp + dismiss button
                        Row(
                          children: [
                            Container(
                              width: 32,
                              height: 32,
                              decoration: BoxDecoration(
                                color: iconBgColor,
                                shape: BoxShape.circle,
                              ),
                              child: Icon(
                                typeIcon,
                                size: 16,
                                color: iconColor,
                              ),
                            ),
                            const SizedBox(width: AppSpacing.sm),
                            Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: AppSpacing.xs,
                                vertical: 2,
                              ),
                              decoration: BoxDecoration(
                                color: AppColors.surfaceContainerHigh,
                                borderRadius: AppRadius.xsBorder,
                              ),
                              child: Text(
                                tagLabel,
                                style: AppTypography.labelSm.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: AppColors.onSurfaceVariant,
                                ),
                              ),
                            ),
                            const Spacer(),
                            Text(
                              _formatTime(notif.timestamp),
                              style: AppTypography.labelMd
                                  .copyWith(color: AppColors.outline),
                            ),
                            const SizedBox(width: AppSpacing.xs),
                            IconButton(
                              icon: const Icon(Icons.delete_outline,
                                  size: AppIconSize.sm),
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
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xs),

                        // Body content
                        Text(
                          notif.body,
                          style: AppTypography.bodyMd.copyWith(
                            color: AppColors.onSurfaceVariant,
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
