import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/owner_provider.dart';
import '../../ui/qd_ui.dart';
import 'employee_page.dart';
import 'owner_controller.dart';
import 'owner_format.dart';
import 'owner_nav.dart';
import 'owner_rules.dart';
import 'owner_sheets.dart';
import 'owner_widgets.dart';
import 'team_sheets.dart';

/// Team (O-Team): every courier with all / active / frozen filters, a
/// state chip from the loaded data, the current order, a link to the
/// existing fleet map, and "add courier".
class OwnerTeamPage extends StatefulWidget {
  const OwnerTeamPage({super.key});

  @override
  State<OwnerTeamPage> createState() => _OwnerTeamPageState();
}

class _OwnerTeamPageState extends State<OwnerTeamPage> {
  TeamFilter _filter = TeamFilter.all;

  Future<void> _add() async {
    final l10n = context.l10n;
    final owner = context.read<OwnerProvider>();
    final data = context.read<OwnerDataController>();
    final ownerId = context.read<AuthProvider>().user?.id ?? '';
    final name = await AddEmployeeSheet.show(
      context,
      onSubmit: (username, email, password) => owner.registerEmployee(
          email: email,
          username: username,
          password: password,
          ownerId: ownerId),
    );
    if (name == null || !mounted) return;
    showOwnerNotice(context, l10n.ownAdded(name));
    await data.refreshEmployees();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final data = context.watch<OwnerDataController>();
    final all = data.employees;
    final shown = all.where((e) => teamFilterMatches(_filter, e)).toList();

    return SafeArea(
      key: const Key('own_team_page'),
      bottom: false,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                QdSpace.gutter, 28, QdSpace.x2, QdSpace.x3),
            child: Row(
              children: [
                Expanded(
                  child: Semantics(
                    header: true,
                    child: Text(l10n.ownTeamTitle,
                        style:
                            QdText.screenTitle.copyWith(color: c.textPrimary)),
                  ),
                ),
                QdButton.text(
                  key: const Key('own_team_map'),
                  label: l10n.ownOnTheMap,
                  icon: Icons.map_outlined,
                  small: true,
                  onPressed: () =>
                      OwnerNavScope.of(context).openFleetMap(context),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                QdSpace.gutter, 0, QdSpace.gutter, QdSpace.x3),
            child: Semantics(
              label: l10n.ownTeamKind,
              container: true,
              child: QdSegmented<TeamFilter>(
                key: const Key('own_team_tabs'),
                selected: _filter,
                onChanged: (f) => setState(() => _filter = f),
                segments: [
                  QdSegment(
                      value: TeamFilter.all,
                      label: l10n.ownTeamAll(all.length)),
                  QdSegment(
                      value: TeamFilter.active, label: l10n.ownTeamActive),
                  QdSegment(
                      value: TeamFilter.frozen, label: l10n.ownTeamFrozen),
                ],
              ),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: data.refresh,
              child: _list(context, data, shown, all.isEmpty),
            ),
          ),
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(
                QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x3),
            child: QdButton(
              key: const Key('own_team_add'),
              label: l10n.ownAddCourier,
              icon: Icons.person_add_alt_1_outlined,
              fullWidth: true,
              onPressed: _add,
            ),
          ),
        ],
      ),
    );
  }

  Widget _list(BuildContext context, OwnerDataController data,
      List<OwnerEmployee> shown, bool teamEmpty) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    if (shown.isEmpty) {
      if (!data.loaded) {
        return const OwnerScrollableCenter(
          key: Key('own_team_loading'),
          child: CircularProgressIndicator(),
        );
      }
      if (data.employeesError != null && teamEmpty) {
        // GET /auth/employees fails closed (500), so an outage never reads
        // as "no couriers".
        return OwnerScrollableCenter(
          key: const Key('own_team_error'),
          child: QdErrorState(
            title: l10n.ownTeamLoadError,
            retrying: data.loading,
            onRetry: data.refresh,
          ),
        );
      }
      return OwnerScrollableCenter(
        key: const Key('own_team_empty'),
        child: QdEmptyState(
          icon: Icons.badge_outlined,
          title: teamEmpty ? l10n.ownTeamEmpty : l10n.ownTeamNoneHere,
          body: teamEmpty ? l10n.ownTeamEmptyBody : null,
        ),
      );
    }
    return ListView(
      key: const Key('own_team_list'),
      physics: const AlwaysScrollableScrollPhysics(),
      padding: const EdgeInsetsDirectional.fromSTEB(
          QdSpace.gutter, QdSpace.x1, QdSpace.gutter, QdSpace.x3),
      children: [
        ClipRRect(
          borderRadius: BorderRadius.circular(QdRadius.card),
          child: Container(
            foregroundDecoration: BoxDecoration(
              border: Border.all(color: c.border),
              borderRadius: BorderRadius.circular(QdRadius.card),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                for (var i = 0; i < shown.length; i++) ...[
                  if (i > 0)
                    Container(
                      height: 1,
                      margin: const EdgeInsetsDirectional.only(start: 64),
                      color: c.fillMuted,
                    ),
                  _CourierRow(employee: shown[i]),
                ],
              ],
            ),
          ),
        ),
      ],
    );
  }
}

/// The chip for a courier's state: on a job (warning, as A-Owner), free
/// (success), frozen (neutral).
Widget courierStateChip(AppLocalizations l10n, CourierState s) => switch (s) {
      CourierState.onJob =>
        QdStatusChip(label: l10n.ownStateOnJob, tone: QdTone.warning),
      CourierState.free =>
        QdStatusChip(label: l10n.ownStateFree, tone: QdTone.success),
      CourierState.frozen =>
        QdStatusChip(label: l10n.ownStateFrozen, tone: QdTone.neutral),
    };

class _CourierRow extends StatelessWidget {
  const _CourierRow({required this.employee});

  final OwnerEmployee employee;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final data = context.watch<OwnerDataController>();
    final state = courierStateOf(employee, data.jobs);
    final current = currentJobOf(employee.id, data.jobs);
    final subtitle = switch (state) {
      CourierState.onJob => l10n.ownOnJobWith(jobRefIsolated(current!)),
      CourierState.free => l10n.ownNoOrderNow,
      CourierState.frozen => l10n.ownFrozenSubtitle,
    };
    return Material(
      color: c.surface,
      child: InkWell(
        key: Key('own_courier_${employee.id}'),
        onTap: () => OwnerEmployeePage.open(context, employee.id),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 64),
          child: Padding(
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: QdSpace.x4, vertical: 10),
            child: Row(
              children: [
                QdAvatarInitial(
                  name: employee.displayName,
                  size: 36,
                  emphasis: false,
                  dimmed: !employee.isActive,
                ),
                const SizedBox(width: QdSpace.x3),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(employee.displayName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                      const SizedBox(height: 2),
                      Text(subtitle,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style:
                              QdText.caption.copyWith(color: c.textSecondary)),
                    ],
                  ),
                ),
                const SizedBox(width: QdSpace.x2),
                courierStateChip(l10n, state),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
