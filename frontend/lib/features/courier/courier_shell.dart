import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/feature_flags.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/employee_jobs_provider.dart';
import '../../providers/employee_location_provider.dart';
import '../../providers/notifications_provider.dart';
import '../../ui/qd_ui.dart';
import '../account/account_page.dart';
import 'blocked_page.dart';
import 'courier_controller.dart';
import 'courier_rules.dart';
import 'courier_widgets.dart';
import 'task_page.dart';

/// The courier's root screen: the redesigned [CourierShell] when [redesign]
/// (default: the `QD_REDESIGN_COURIER` flag) is on, otherwise [legacy] (the
/// existing EmployeeHomeScreen). [initialIndex] keeps the old tab order:
/// 0 jobs, 1 history, 2 account.
Widget courierRootScreen({
  bool redesign = kRedesignCourier,
  int initialIndex = 0,
  required Widget Function() legacy,
}) =>
    redesign ? CourierShell(initialIndex: initialIndex.clamp(0, 2)) : legacy();

/// Redesigned courier shell (FE-COURIER): Task / My jobs / Account with a
/// [QdBottomNav] under the redesign theme, or the blocked screen while the
/// account is suspended or paused. A `job_alert` notification refreshes the
/// jobs and shows a notice, as the old home screen did.
class CourierShell extends StatefulWidget {
  const CourierShell({super.key, this.initialIndex = 0, this.now});

  final int initialIndex;

  /// Clock for countdowns and "today" (tests).
  final DateTime Function()? now;

  @override
  State<CourierShell> createState() => _CourierShellState();
}

class _CourierShellState extends State<CourierShell> {
  late int _index = widget.initialIndex;
  late final Set<int> _visited = {_index};
  late final CourierController _ctl;
  NotificationsProvider? _notifications;
  String? _lastAlertId;

  @override
  void initState() {
    super.initState();
    _ctl = CourierController(
      jobsProvider: context.read<EmployeeJobsProvider>(),
      location: context.read<EmployeeLocationProvider>(),
      auth: context.read<AuthProvider>(),
      now: widget.now,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _ctl.refresh();
      final n = context.read<NotificationsProvider>();
      // Only alerts that arrive from now on.
      _lastAlertId = _firstAlertId(n);
      n.addListener(_onNotifications);
      _notifications = n;
    });
  }

  @override
  void dispose() {
    _notifications?.removeListener(_onNotifications);
    _ctl.dispose();
    super.dispose();
  }

  String? _firstAlertId(NotificationsProvider n) {
    final list = n.notifications;
    if (list.isEmpty || list.first.type != 'job_alert') return null;
    return list.first.id;
  }

  void _onNotifications() {
    if (!mounted || _notifications == null) return;
    final id = _firstAlertId(_notifications!);
    if (id == null || id == _lastAlertId) return;
    _lastAlertId = id;
    _ctl.refresh();
    showCourierNotice(context, context.l10n.newDispatchAlertMessage,
        key: const Key('job_alert_dispatch_snackbar'));
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _visited.add(i);
    });
    // Back on a jobs tab: pick up changes (joins a refresh in flight).
    if (i != 2) _ctl.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final blocked = isBlocked(context.watch<AuthProvider>().user);
    Widget lazy(int i, Widget Function() build) =>
        _visited.contains(i) ? build() : const SizedBox.shrink();

    return ChangeNotifierProvider<CourierController>.value(
      value: _ctl,
      child: QdThemeScope(
        child: blocked
            ? const CourierBlockedPage()
            : Builder(
                builder: (context) => Scaffold(
                  key: const Key('courier_shell'),
                  backgroundColor: QdColors.of(context).surface,
                  body: IndexedStack(
                    index: _index,
                    children: [
                      lazy(0, () => const CourierTaskPage()),
                      lazy(1, () => const SizedBox.shrink()),
                      lazy(2, () => const AccountPage()),
                    ],
                  ),
                  bottomNavigationBar: QdBottomNav(
                    key: const Key('courier_shell_nav'),
                    currentIndex: _index,
                    onTap: _select,
                    items: [
                      QdNavItem(
                          icon: Icons.inventory_2_outlined,
                          activeIcon: Icons.inventory_2,
                          label: l10n.courNavTask),
                      QdNavItem(
                          icon: Icons.format_list_bulleted,
                          label: l10n.courNavJobs),
                      QdNavItem(
                          icon: Icons.person_outline,
                          activeIcon: Icons.person,
                          label: l10n.courNavAccount),
                    ],
                  ),
                ),
              ),
      ),
    );
  }
}
