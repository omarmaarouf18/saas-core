import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/feature_flags.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/owner_provider.dart';
import '../../ui/qd_ui.dart';
import '../account/account_page.dart';
import '../account/notifications/notification_rules.dart';
import 'order_detail_page.dart';
import 'orders_page.dart';
import 'owner_nav.dart';
import 'plan_rules.dart';
import 'owner_controller.dart';
import 'team_page.dart';
import 'today_page.dart';

/// The owner's root screen: the redesigned [OwnerShell] when [redesign]
/// (default: the `QD_REDESIGN_OWNER` flag) is on, otherwise [legacy] (the
/// existing owner dashboard built by HomeScreen).
Widget ownerRootScreen(
        {bool redesign = kRedesignOwner, required Widget Function() legacy}) =>
    redesign ? const OwnerShell() : legacy();

/// Whether HomeScreen still runs the old owner dashboard fetch (wallet,
/// subscription, ledger and owner jobs) when it opens. With the redesign
/// on, the shell and its pages load what they show, so it is skipped.
bool runLegacyOwnerDashboardFetch({bool redesign = kRedesignOwner}) =>
    !redesign;

/// Redesigned owner shell (FE-OWNER-1): Today / Orders / Team / Account with
/// a [QdBottomNav] under the redesign theme. Account is the shared account
/// page with the owner rows (FE-OWNER-2b).
class OwnerShell extends StatefulWidget {
  const OwnerShell({super.key, this.initialIndex = 0, this.now});

  final int initialIndex;

  /// Clock for "today" and relative times (tests).
  final DateTime Function()? now;

  @override
  State<OwnerShell> createState() => _OwnerShellState();
}

class _OwnerShellState extends State<OwnerShell> {
  late int _index = widget.initialIndex;
  late final Set<int> _visited = {_index};
  late final OwnerDataController _data;

  @override
  void initState() {
    super.initState();
    _data = OwnerDataController(
      context.read<OwnerProvider>(),
      context.read<AuthProvider>(),
      now: widget.now,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _data.refresh();
      if (_index == 3) _loadPlan();
    });
  }

  /// The Account tab's plan row: the plan (with the wallet and ledger, one
  /// call) is loaded each time the tab opens (owner decision, FE-V2-CONSUME).
  void _loadPlan() {
    final token = context.read<AuthProvider>().token;
    if (token == null) return;
    context.read<OwnerProvider>().fetchDashboardData(token);
  }

  @override
  void dispose() {
    _data.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _visited.add(i);
    });
    // Back on a data tab: pick up changes (joins a refresh in flight).
    if (i != 3) {
      _data.refresh();
    } else {
      _loadPlan();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget lazy(int i, Widget Function() build) =>
        _visited.contains(i) ? build() : const SizedBox.shrink();

    return ChangeNotifierProvider<OwnerDataController>.value(
      value: _data,
      child: QdThemeScope(
        child: Builder(
          builder: (context) => NotificationShellScope(
            // Notification links: the Orders and Team tabs, an order's
            // detail, the plan page.
            links: NotificationShellLinks(
              showOrders: () => _select(1),
              openOrder: (id) => OwnerOrderDetailPage.open(context, id),
              showTeam: () => _select(2),
              openPlan: () =>
                  OwnerNavScope.of(context).openSubscription(context),
            ),
            child: Scaffold(
              key: const Key('owner_shell'),
              backgroundColor: QdColors.of(context).surface,
              body: IndexedStack(
                index: _index,
                children: [
                  lazy(
                    0,
                    () => OwnerTodayPage(
                      onShowTeam: () => _select(2),
                      onShowOrders: () => _select(1),
                    ),
                  ),
                  lazy(1, () => const OwnerOrdersPage()),
                  lazy(2, () => const OwnerTeamPage()),
                  lazy(3, () => const _OwnerAccount()),
                ],
              ),
              bottomNavigationBar: QdBottomNav(
                key: const Key('owner_shell_nav'),
                currentIndex: _index,
                onTap: _select,
                items: [
                  QdNavItem(
                      icon: Icons.today_outlined,
                      activeIcon: Icons.today,
                      label: l10n.ownNavToday),
                  QdNavItem(
                      icon: Icons.receipt_long_outlined,
                      activeIcon: Icons.receipt_long,
                      label: l10n.ownNavOrders),
                  QdNavItem(
                      icon: Icons.groups_outlined,
                      activeIcon: Icons.groups,
                      label: l10n.ownNavTeam),
                  QdNavItem(
                      icon: Icons.person_outline,
                      activeIcon: Icons.person,
                      label: l10n.ownNavAccount),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// The Account tab: the shared account page with the owner rows, which
/// open the owner pages through [OwnerNav] (they need the shell's data).
class _OwnerAccount extends StatelessWidget {
  const _OwnerAccount();

  @override
  Widget build(BuildContext context) {
    final nav = OwnerNavScope.of(context);
    final owner = context.watch<OwnerProvider>();
    return AccountPage(
      owner: OwnerAccountLinks(
        openServiceSetup: nav.openServiceSetup,
        openPlan: nav.openSubscription,
        openWallet: nav.openWallet,
        openActivity: nav.openHistory,
        // Loaded by the shell when this tab opens (and by the plan, wallet
        // and activity pages); empty until the first load finishes.
        planValue: owner.isDashboardHydrated
            ? planLabel(context.l10n, owner.subscriptionTier)
            : null,
      ),
    );
  }
}
