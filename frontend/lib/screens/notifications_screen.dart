import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/theme.dart';
import '../providers/notifications_provider.dart';
import '../models/notification_model.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import 'job_status_screen.dart';

class NotificationsScreen extends StatefulWidget {
  const NotificationsScreen({super.key});

  @override
  State<NotificationsScreen> createState() => _NotificationsScreenState();
}

class _NotificationsScreenState extends State<NotificationsScreen> {
  String _selectedCategory = 'All';

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

  @override
  Widget build(BuildContext context) {
    final provider = Provider.of<NotificationsProvider>(context);
    final auth = Provider.of<AuthProvider>(context, listen: false);
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
          'Notifications',
          style: AppTypography.titleMd.copyWith(color: AppColors.onPrimary),
        ),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        actions: [
          if (filtered.any((n) => !n.isRead))
            TextButton(
              onPressed: () => provider.markAllAsRead(),
              child: Text(
                'Mark all read',
                style:
                    AppTypography.labelMd.copyWith(color: AppColors.onPrimary),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear All',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  backgroundColor: AppColors.surface,
                  title: Text(
                    'Clear Notifications',
                    style: AppTypography.titleMd
                        .copyWith(color: AppColors.onSurface),
                  ),
                  content: Text(
                    'Are you sure you want to clear all notifications?',
                    style: AppTypography.bodyMd
                        .copyWith(color: AppColors.onSurfaceVariant),
                  ),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text(
                        'Cancel',
                        style: TextStyle(color: AppColors.primary),
                      ),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        provider.clearAll();
                        Navigator.of(context).pop();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                      ),
                      child: const Text('Clear'),
                    ),
                  ],
                ),
              );
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
                  size: 20,
                ),
                const SizedBox(width: AppSpacing.base),
                Expanded(
                  child: Text(
                    provider.isConnected
                        ? 'System Status: Operational. Real-time alert stream active.'
                        : 'System Status: Disconnected. Reconnecting...',
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
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.sm, vertical: AppSpacing.base),
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding:
                      const EdgeInsets.symmetric(horizontal: AppSpacing.xs),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: AppColors.secondary,
                    labelStyle: AppTypography.labelMd.copyWith(
                      color: isSelected
                          ? AppColors.onSecondary
                          : AppColors.onSurface,
                    ),
                    onSelected: (val) {
                      if (val) {
                        setState(() {
                          _selectedCategory = cat;
                        });
                      }
                    },
                  ),
                );
              }).toList(),
            ),
          ),

          // List of Notifications
          Expanded(
            child: filtered.isEmpty
                ? const ThemedEmptyState(
                    icon: Icons.notifications_none,
                    title: 'No notifications found',
                    description: 'No new notifications to display.',
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
    final bool isJobAlert =
        notif.type == 'job_alert' || notif.id.startsWith('job-');
    final String bodyText = notif.body;

    // Extract Job ID from body if possible
    String? extractedJobId;
    if (isJobAlert) {
      final reg = RegExp(r'(?:job-alert-|job\s)(notif-\d+|job:\w+|\w{24})');
      final match = reg.firstMatch(bodyText);
      if (match != null) {
        extractedJobId = match.group(1);
      }
    }

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.base),
      child: ThemedCard(
        padding: AppSpacing.md,
        color: notif.isRead
            ? AppColors.surface
            : AppColors.surfaceContainerHighest.withValues(alpha: 0.3),
        borderSide: BorderSide(
          color: notif.isRead
              ? Colors.transparent
              : AppColors.secondary.withValues(alpha: 0.3),
          width: 1,
        ),
        borderRadius: AppRadius.md,
        child: InkWell(
          borderRadius: AppRadius.mdBorder,
          onTap: () {
            provider.markAsRead(notif.id);
          },
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header line: title + timestamp
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      notif.title,
                      style: AppTypography.bodyLg.copyWith(
                        fontWeight:
                            notif.isRead ? FontWeight.w500 : FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    _formatTime(notif.timestamp),
                    style: AppTypography.labelMd
                        .copyWith(color: AppColors.outline),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.base),

              // Body content
              Text(
                notif.body,
                style: AppTypography.bodyMd.copyWith(height: 1.3),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Action buttons
              Row(
                mainAxisAlignment: MainAxisAlignment.end,
                children: [
                  if (isJobAlert &&
                      extractedJobId != null &&
                      userToken != null) ...[
                    TextButton.icon(
                      icon: const Icon(Icons.gps_fixed, size: 16),
                      label: const Text('Track Shipment'),
                      style: TextButton.styleFrom(
                        foregroundColor: AppColors.secondary,
                        textStyle: AppTypography.labelLg,
                      ),
                      onPressed: () {
                        provider.markAsRead(notif.id);
                        final placeholderJob = Job(
                          id: extractedJobId!,
                          ownerId: '',
                          userId: '',
                          serviceId: '',
                          status: 'pending',
                          location: JobLocation(latitude: 0, longitude: 0),
                          paymentMethod: 'cod',
                        );
                        Navigator.of(context).push(
                          MaterialPageRoute(
                            builder: (context) => JobStatusScreen(
                              job: placeholderJob,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(width: AppSpacing.base),
                  ],
                  TextButton.icon(
                    icon: const Icon(Icons.reply, size: 16),
                    label: const Text('Reply'),
                    style: TextButton.styleFrom(
                      foregroundColor: AppColors.primary,
                      textStyle: AppTypography.labelLg,
                    ),
                    onPressed: () {
                      provider.markAsRead(notif.id);
                      ScaffoldMessenger.of(context).showSnackBar(
                        const SnackBar(
                          content:
                              Text('Reply feature is in beta and local-only.'),
                        ),
                      );
                    },
                  ),
                  const SizedBox(width: AppSpacing.base),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Dismiss',
                    color: AppColors.onSurfaceVariant,
                    onPressed: () => provider.dismiss(notif.id),
                  ),
                ],
              ),
            ],
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
