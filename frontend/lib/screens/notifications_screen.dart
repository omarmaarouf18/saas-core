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

    final todayNotifs = filtered.where((n) => _isToday(n.timestamp)).toList();
    final yesterdayNotifs =
        filtered.where((n) => _isYesterday(n.timestamp)).toList();
    final earlierNotifs = filtered
        .where((n) => !_isToday(n.timestamp) && !_isYesterday(n.timestamp))
        .toList();

    return Scaffold(
      backgroundColor: AppColors.background,
      appBar: AppBar(
        title: Text(
          l10n.notificationsTitle,
          style: AppTypography.titleMd.copyWith(
            color: AppColors.onPrimary,
            fontWeight: FontWeight.bold,
          ),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        elevation: 0,
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
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 1000),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              // 1. Connectivity Status Banner
              Container(
                margin: const EdgeInsets.fromLTRB(
                  AppSpacing.marginMobile,
                  AppSpacing.sm,
                  AppSpacing.marginMobile,
                  AppSpacing.xs,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                decoration: BoxDecoration(
                  color: provider.isConnected
                      ? AppColors.success.withValues(alpha: 0.12)
                      : AppColors.errorContainer.withValues(alpha: 0.3),
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  border: Border.all(
                    color: provider.isConnected
                        ? AppColors.success.withValues(alpha: 0.25)
                        : AppColors.error.withValues(alpha: 0.25),
                  ),
                ),
                child: Row(
                  children: [
                    Icon(
                      provider.isConnected
                          ? Icons.check_circle_outline
                          : Icons.wifi_off,
                      color: provider.isConnected
                          ? AppColors.success
                          : AppColors.error,
                      size: AppIconSize.sm,
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      child: Text(
                        provider.isConnected
                            ? 'System Status: Operational.'
                            : 'Sync paused. Showing offline notifications.',
                        style: AppTypography.labelMd.copyWith(
                          color: provider.isConnected
                              ? AppColors.onSurface
                              : AppColors.error,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                    ),
                  ],
                ),
              ),

              // 2. Horizontal Filter Bar
              Padding(
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.marginMobile,
                  vertical: AppSpacing.xs,
                ),
                child: PillFilterBar<String>(
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
                ),
              ),

              // 3. Notification List Canvas
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
                        padding: const EdgeInsets.symmetric(
                          horizontal: AppSpacing.marginMobile,
                          vertical: AppSpacing.sm,
                        ),
                        children: [
                          if (todayNotifs.isNotEmpty) ...[
                            _buildDateSection(
                              title: 'Today',
                              items: todayNotifs,
                              provider: provider,
                              userToken: auth.token,
                            ),
                          ],
                          if (yesterdayNotifs.isNotEmpty) ...[
                            _buildDateSection(
                              title: 'Yesterday',
                              items: yesterdayNotifs,
                              provider: provider,
                              userToken: auth.token,
                            ),
                          ],
                          if (earlierNotifs.isNotEmpty) ...[
                            _buildDateSection(
                              title: 'Earlier',
                              items: earlierNotifs,
                              provider: provider,
                              userToken: auth.token,
                            ),
                          ],
                          const SizedBox(height: AppSpacing.xl),
                        ],
                      ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildDateSection({
    required String title,
    required List<NotificationModel> items,
    required NotificationsProvider provider,
    required String? userToken,
  }) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.only(
            top: AppSpacing.md,
            bottom: AppSpacing.xs,
          ),
          child: Text(
            title.toUpperCase(),
            style: AppTypography.labelMd.copyWith(
              color: AppColors.primary.withValues(alpha: 0.7),
              fontWeight: FontWeight.bold,
              letterSpacing: 0.8,
            ),
          ),
        ),
        ...items.map(
          (notif) => _buildStitchNotificationCard(
            notif: notif,
            provider: provider,
            userToken: userToken,
          ),
        ),
      ],
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
            ? AppColors.errorContainer
            : (isSystem
                ? AppColors.surfaceContainerHigh
                : AppColors.surfaceContainerHigh));

    final Color iconColor = isJob
        ? AppColors.secondary
        : (isAlert
            ? AppColors.error
            : (isSystem ? AppColors.onSurfaceVariant : AppColors.primary));

    final String tagLabel = isJob
        ? 'JOB ALERT'
        : (isAlert ? 'ALERT' : (isSystem ? 'SYSTEM' : 'NOTIFICATION'));

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: ThemedCard(
        padding: 0,
        color:
            notif.isRead ? AppColors.surface : AppColors.surfaceContainerLowest,
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
                  Container(
                    width: 4,
                    decoration: const BoxDecoration(
                      color: AppColors.secondary,
                      borderRadius: BorderRadius.only(
                        topLeft: Radius.circular(AppRadius.lg),
                        bottomLeft: Radius.circular(AppRadius.lg),
                      ),
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
                                color: isAlert
                                    ? AppColors.errorContainer
                                        .withValues(alpha: 0.5)
                                    : AppColors.surfaceContainerHigh,
                                borderRadius:
                                    BorderRadius.circular(AppRadius.xs),
                              ),
                              child: Text(
                                tagLabel,
                                style: AppTypography.labelSm.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: isAlert
                                      ? AppColors.error
                                      : AppColors.onSurfaceVariant,
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
                            color: AppColors.onSurface,
                          ),
                        ),
                        const SizedBox(height: AppSpacing.xxs),

                        // Body description
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
