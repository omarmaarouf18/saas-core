import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/feature_flags.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/marketplace_provider.dart';
import '../../screens/customer_home_screen.dart';
import '../../ui/qd_ui.dart';
import '../account/account_page.dart';
import 'customer_jobs_controller.dart';
import 'customer_theme.dart';
import 'home_page.dart';
import 'market_page.dart';
import 'orders_page.dart';

/// The customer's root screen: the redesigned [CustomerShell] when
/// [redesign] (default: the `QD_REDESIGN_CUSTOMER` flag) is on, otherwise the
/// existing CustomerHomeScreen.
Widget customerRootScreen({bool redesign = kRedesignCustomer}) =>
    redesign ? const CustomerShell() : const CustomerHomeScreen();

/// Redesigned customer shell (FE-CUST-1): Home / My orders / Account with a
/// [QdBottomNav], all under the redesign theme. Account is the
/// FE-AUTH-ACCOUNT [AccountPage].
class CustomerShell extends StatefulWidget {
  const CustomerShell({super.key, this.initialIndex = 0, this.now});

  final int initialIndex;

  /// Clock for date labels (tests).
  final DateTime Function()? now;

  @override
  State<CustomerShell> createState() => _CustomerShellState();
}

class _CustomerShellState extends State<CustomerShell> {
  late int _index = widget.initialIndex;
  late final Set<int> _visited = {_index};
  late final CustomerJobsController _jobs;

  @override
  void initState() {
    super.initState();
    final auth = context.read<AuthProvider>();
    _jobs = CustomerJobsController(
      context.read<MarketplaceProvider>(),
      () => auth.token,
    );
    WidgetsBinding.instance.addPostFrameCallback((_) => _jobs.refresh());
  }

  @override
  void dispose() {
    _jobs.dispose();
    super.dispose();
  }

  void _select(int i) {
    if (i == _index) return;
    setState(() {
      _index = i;
      _visited.add(i);
    });
    // Coming back to the order lists: pick up status changes.
    if (i != 2) _jobs.refresh();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    Widget lazy(int i, Widget Function() build) =>
        _visited.contains(i) ? build() : const SizedBox.shrink();

    return ChangeNotifierProvider<CustomerJobsController>.value(
      value: _jobs,
      child: CustomerTheme(
        child: Scaffold(
          key: const Key('customer_shell'),
          body: IndexedStack(
            index: _index,
            children: [
              lazy(0, () => const CustomerHomePage()),
              lazy(
                1,
                () => CustomerOrdersPage(
                  now: widget.now,
                  onBrowseServices: () => CustomerMarketPage.open(context),
                ),
              ),
              lazy(2, () => const AccountPage()),
            ],
          ),
          bottomNavigationBar: QdBottomNav(
            key: const Key('customer_shell_nav'),
            currentIndex: _index,
            onTap: _select,
            items: [
              QdNavItem(
                  icon: Icons.home_outlined,
                  activeIcon: Icons.home,
                  label: l10n.custNavHome),
              QdNavItem(
                  icon: Icons.receipt_long_outlined,
                  activeIcon: Icons.receipt_long,
                  label: l10n.custNavOrders),
              QdNavItem(
                  icon: Icons.person_outline,
                  activeIcon: Icons.person,
                  label: l10n.custNavAccount),
            ],
          ),
        ),
      ),
    );
  }
}
