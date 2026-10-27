import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/owner_provider.dart';
import '../../ui/qd_ui.dart';
import 'order_detail_page.dart';
import 'orders_page.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_nav.dart';
import 'owner_rules.dart';
import 'owner_sheets.dart';
import 'owner_widgets.dart';
import 'team_page.dart';
import 'team_sheets.dart';

/// One courier (O-Employee): who, their state, counts from the loaded
/// orders, current order, all their orders, the fleet map, and freeze /
/// unfreeze behind the owner's password (`POST /auth/employee/toggle`).
class OwnerEmployeePage extends StatefulWidget {
  const OwnerEmployeePage(
      {super.key, required this.employeeId, this.showIdCheck = false});

  final String employeeId;

  /// Opens the ID check sheet on arrival (the team row's KYE chip).
  final bool showIdCheck;

  static Future<void> open(BuildContext context, String employeeId,
          {bool showIdCheck = false}) =>
      OwnerNavScope.of(context).push<void>(
          context,
          (_) => OwnerEmployeePage(
              employeeId: employeeId, showIdCheck: showIdCheck));

  @override
  State<OwnerEmployeePage> createState() => _OwnerEmployeePageState();
}

class _OwnerEmployeePageState extends State<OwnerEmployeePage> {
  @override
  void initState() {
    super.initState();
    if (widget.showIdCheck) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        final e =
            context.read<OwnerDataController>().employeeById(widget.employeeId);
        if (e != null) showKyeSheet(context, e);
      });
    }
  }

  Future<void> _toggle(OwnerEmployee e) async {
    final l10n = context.l10n;
    final owner = context.read<OwnerProvider>();
    final data = context.read<OwnerDataController>();
    final ownerEmail = context.read<AuthProvider>().user?.email ?? '';
    final freeze = e.isActive;
    final done = await OwnerPasswordSheet.show(
      context,
      title: freeze
          ? l10n.ownFreezeTitle(e.displayName)
          : l10n.ownUnfreezeTitle(e.displayName),
      body: freeze ? l10n.ownFreezeBody : l10n.ownUnfreezeBody,
      confirmLabel: freeze ? l10n.ownFreeze : l10n.ownUnfreeze,
      destructive: freeze,
      onConfirm: (password) => owner.toggleEmployee(
        employeeEmail: e.email,
        ownerEmail: ownerEmail,
        ownerPassword: password,
        setActive: !freeze,
      ),
    );
    if (done != true || !mounted) return;
    showOwnerNotice(
        context,
        freeze
            ? l10n.ownFrozenDone(e.displayName)
            : l10n.ownUnfrozenDone(e.displayName));
    await data.refreshEmployees();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final data = context.watch<OwnerDataController>();
    final e = data.employeeById(widget.employeeId);

    if (e == null) {
      return Scaffold(
        backgroundColor: c.surface,
        appBar: ownerAppBar(context, title: l10n.ownTeamTitle),
        body: RefreshIndicator(
          onRefresh: data.refreshEmployees,
          child: OwnerScrollableCenter(
            child: QdEmptyState(
              key: const Key('own_employee_missing'),
              icon: Icons.badge_outlined,
              title: l10n.ownEmployeeMissing,
              actionLabel: l10n.ownRefresh,
              onAction: data.refreshEmployees,
            ),
          ),
        ),
      );
    }

    final state = courierStateOf(e, data.jobs);
    final current = currentJobOf(e.id, data.jobs);
    final mine = data.jobs.where((j) => j.employeeId == e.id);
    return Scaffold(
      key: const Key('own_employee_page'),
      backgroundColor: c.surface,
      appBar: ownerAppBar(context, title: ''),
      body: RefreshIndicator(
        onRefresh: data.refresh,
        child: ListView(
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsetsDirectional.fromSTEB(
              QdSpace.gutter, 0, QdSpace.gutter, QdSpace.x6),
          children: [
            Row(
              children: [
                QdAvatarInitial(
                    name: e.displayName, size: 56, dimmed: !e.isActive),
                const SizedBox(width: 14),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Semantics(
                        header: true,
                        child: Text(e.displayName,
                            style: QdText.sheetTitle
                                .copyWith(color: c.textPrimary)),
                      ),
                      if (e.email.isNotEmpty)
                        Text(e.email,
                            textDirection: TextDirection.ltr,
                            style: QdText.secondary
                                .copyWith(color: c.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: QdSpace.x2),
                courierStateChip(l10n, state),
              ],
            ),
            const SizedBox(height: QdSpace.x5),
            Row(
              children: [
                Expanded(
                  child: _CountTile(
                    key: const Key('own_employee_orders_count'),
                    value: '${mine.length}',
                    label: l10n.ownEmpOrders,
                  ),
                ),
                const SizedBox(width: QdSpace.x2),
                Expanded(
                  child: _CountTile(
                    key: const Key('own_employee_delivered_count'),
                    value: '${mine.where(isCompleted).length}',
                    label: l10n.ownEmpDelivered,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(l10n.ownEmpCountsNote,
                style: QdText.caption.copyWith(color: c.textSecondary)),
            const SizedBox(height: QdSpace.x4),
            QdListGroup(children: [
              // kye_status of /auth/employees (USER-AUTH-BE item 4).
              QdListTile(
                key: const Key('own_employee_kye'),
                title: l10n.ownEmpIdCheck,
                badge: kyeChip(l10n, kyeStateOf(e.kyeStatus)),
                chevron: true,
                onTap: () => showKyeSheet(context, e),
              ),
              QdListTile(
                key: const Key('own_employee_current'),
                title: l10n.ownEmpCurrentOrder,
                value:
                    current == null ? l10n.ownEmpNone : jobRefIsolated(current),
                chevron: current != null,
                onTap: current == null
                    ? null
                    : () => OwnerOrderDetailPage.open(context, current.id),
              ),
              QdListTile(
                key: const Key('own_employee_all_orders'),
                title: l10n.ownEmpAllOrders,
                chevron: true,
                onTap: () =>
                    OwnerOrdersPage.open(context, query: e.displayName),
              ),
              QdListTile(
                key: const Key('own_employee_map'),
                title: l10n.ownEmpOnMap,
                chevron: true,
                onTap: () => OwnerNavScope.of(context)
                    .openFleetMap(context, employeeId: e.id),
              ),
            ]),
            const SizedBox(height: QdSpace.x6),
            if (e.isActive)
              QdButton.destructive(
                key: const Key('own_employee_freeze'),
                label: l10n.ownFreeze,
                fullWidth: true,
                onPressed: () => _toggle(e),
              )
            else
              QdButton.secondary(
                key: const Key('own_employee_unfreeze'),
                label: l10n.ownUnfreeze,
                fullWidth: true,
                onPressed: () => _toggle(e),
              ),
            const SizedBox(height: QdSpace.x2),
            Text(
              e.isActive ? l10n.ownFreezeHint : l10n.ownUnfreezeHint,
              textAlign: TextAlign.center,
              style: QdText.caption.copyWith(color: c.textSecondary),
            ),
          ],
        ),
      ),
    );
  }
}

class _CountTile extends StatelessWidget {
  const _CountTile({super.key, required this.value, required this.label});

  final String value;
  final String label;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return MergeSemantics(
      child: Container(
        padding: const EdgeInsetsDirectional.all(QdSpace.x3),
        decoration: BoxDecoration(
          border: Border.all(color: c.border),
          borderRadius: BorderRadius.circular(QdRadius.button),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(value,
                style: QdText.amountLg
                    .copyWith(fontSize: 22, color: c.textPrimary)),
            Text(label, style: QdText.caption.copyWith(color: c.textSecondary)),
          ],
        ),
      ),
    );
  }
}
