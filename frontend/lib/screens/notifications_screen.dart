import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../providers/notifications_provider.dart';
import '../models/notification_model.dart';
import '../models/job.dart';
import '../providers/auth_provider.dart';
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
      appBar: AppBar(
        title: const Text('Notifications'),
        actions: [
          if (filtered.any((n) => !n.isRead))
            TextButton(
              onPressed: () => provider.markAllAsRead(),
              child: Text(
                'Mark all read',
                style: TextStyle(color: colorScheme.onPrimary),
              ),
            ),
          IconButton(
            icon: const Icon(Icons.delete_sweep),
            tooltip: 'Clear All',
            onPressed: () {
              showDialog(
                context: context,
                builder: (context) => AlertDialog(
                  title: const Text('Clear Notifications'),
                  content: const Text(
                      'Are you sure you want to clear all notifications?'),
                  actions: [
                    TextButton(
                      onPressed: () => Navigator.of(context).pop(),
                      child: const Text('Cancel'),
                    ),
                    ElevatedButton(
                      onPressed: () {
                        provider.clearAll();
                        Navigator.of(context).pop();
                      },
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
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            color: provider.isConnected
                ? colorScheme.secondaryContainer.withValues(alpha: 0.4)
                : colorScheme.errorContainer.withValues(alpha: 0.4),
            child: Row(
              children: [
                Icon(
                  provider.isConnected ? Icons.check_circle : Icons.error,
                  color: provider.isConnected ? Colors.green : Colors.red,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    provider.isConnected
                        ? 'System Status: Operational. Real-time alert stream active.'
                        : 'System Status: Disconnected. Reconnecting...',
                    style: TextStyle(
                      fontSize: 13,
                      fontWeight: FontWeight.w500,
                      color: provider.isConnected
                          ? colorScheme.onSecondaryContainer
                          : colorScheme.onErrorContainer,
                    ),
                  ),
                ),
              ],
            ),
          ),

          // Categories Filter Tabs
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            child: Row(
              children: _categories.map((cat) {
                final isSelected = _selectedCategory == cat;
                return Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: ChoiceChip(
                    label: Text(cat),
                    selected: isSelected,
                    selectedColor: colorScheme.secondary,
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
                ? const Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.notifications_none,
                            size: 64, color: Colors.grey),
                        SizedBox(height: 16),
                        Text(
                          'No notifications found',
                          style: TextStyle(color: Colors.grey, fontSize: 16),
                        ),
                      ],
                    ),
                  )
                : ListView(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
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
                      const SizedBox(height: 24),
                    ],
                  ),
          ),
        ],
      ),
    );
  }

  Widget _buildSectionHeader(String title, ColorScheme colorScheme) {
    return Padding(
      padding: const EdgeInsets.only(top: 16, bottom: 8),
      child: Text(
        title.toUpperCase(),
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: colorScheme.primary.withValues(alpha: 0.7),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: notif.isRead ? 0 : 2,
      color: notif.isRead
          ? colorScheme.surface
          : colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: notif.isRead
              ? Colors.transparent
              : colorScheme.secondary.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () {
          provider.markAsRead(notif.id);
        },
        child: Padding(
          padding: const EdgeInsets.all(16.0),
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
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight:
                            notif.isRead ? FontWeight.w500 : FontWeight.bold,
                      ),
                    ),
                  ),
                  Text(
                    _formatTime(notif.timestamp),
                    style: const TextStyle(fontSize: 12, color: Colors.grey),
                  ),
                ],
              ),
              const SizedBox(height: 8),

              // Body content
              Text(
                notif.body,
                style: const TextStyle(fontSize: 14, height: 1.3),
              ),
              const SizedBox(height: 12),

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
                        foregroundColor: colorScheme.secondary,
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
                    const SizedBox(width: 8),
                  ],
                  TextButton.icon(
                    icon: const Icon(Icons.reply, size: 16),
                    label: const Text('Reply'),
                    style: TextButton.styleFrom(
                      foregroundColor: colorScheme.primary,
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
                  const SizedBox(width: 8),
                  IconButton(
                    icon: const Icon(Icons.delete_outline, size: 18),
                    tooltip: 'Dismiss',
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
