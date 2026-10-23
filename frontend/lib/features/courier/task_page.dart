import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../l10n/l10n.dart';
import '../../models/job.dart';
import '../../ui/qd_ui.dart';
import 'courier_controller.dart';
import 'courier_widgets.dart';

/// The Task tab (المهمة): the open offer when there is one (C-Offer), else
/// the current job (A-Courier), else a waiting state that says whether the
/// courier is online.
class CourierTaskPage extends StatelessWidget {
  const CourierTaskPage({super.key});

  @override
  Widget build(BuildContext context) {
    final ctl = context.watch<CourierController>();
    if (!ctl.loaded && ctl.jobs.isEmpty) {
      return const _Loading();
    }
    final offer = ctl.offer;
    if (offer != null) return _JobSummary(job: offer);
    final current = ctl.current;
    if (current != null) return _JobSummary(job: current);
    return const _IdleView();
  }
}

class _Loading extends StatelessWidget {
  const _Loading();

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      key: const Key('courier_task_loading'),
      backgroundColor: QdColors.of(context).surface,
      body: const Center(child: CircularProgressIndicator()),
    );
  }
}

/// Temporary until the offer and current-job pages land (items 3 and 4).
class _JobSummary extends StatelessWidget {
  const _JobSummary({required this.job});

  final Job job;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Scaffold(
      backgroundColor: c.surface,
      body: SafeArea(
        child: Padding(
          padding: const EdgeInsets.all(QdSpace.gutter),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              CourierHeader(title: context.l10n.courNavTask),
              const SizedBox(height: QdSpace.x4),
              QdJobStatusChips(
                status: job.status,
                cancellationRequestStatus: job.cancellationRequestStatus,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// No offer and no current job.
class _IdleView extends StatelessWidget {
  const _IdleView();

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final ctl = context.watch<CourierController>();
    final online = ctl.location.isAvailableOnline;
    final error = ctl.error;

    return Scaffold(
      key: const Key('courier_task_idle'),
      backgroundColor: c.surface,
      body: SafeArea(
        child: RefreshIndicator(
          onRefresh: ctl.refresh,
          child: ListView(
            padding: const EdgeInsetsDirectional.fromSTEB(
                QdSpace.gutter, 28, QdSpace.gutter, QdSpace.x4),
            children: [
              CourierHeader(title: l10n.courNavTask),
              const SizedBox(height: QdSpace.x3),
              const CourierKyeBanner(),
              if (error != null) ...[
                const SizedBox(height: QdSpace.x3),
                QdBanner(
                  key: const Key('courier_load_error'),
                  tone: QdBannerTone.warning,
                  message: l10n.courLoadError,
                  actionLabel: l10n.retry,
                  onAction: ctl.refresh,
                ),
              ],
              const SizedBox(height: 56),
              if (online)
                QdEmptyState(
                  key: const Key('courier_idle_online'),
                  icon: Icons.inventory_2_outlined,
                  title: l10n.courIdleOnlineTitle,
                  body: l10n.courIdleOnlineBody,
                  actionLabel: l10n.courRefresh,
                  onAction: ctl.refresh,
                )
              else
                QdEmptyState(
                  key: const Key('courier_idle_offline'),
                  icon: Icons.pause_circle_outline,
                  title: l10n.courIdleOfflineTitle,
                  body: l10n.courIdleOfflineBody,
                  actionLabel: l10n.courGoOnline,
                  onAction: () => ctl.setOnline(true),
                ),
            ],
          ),
        ),
      ),
    );
  }
}
