import 'package:flutter/material.dart';
import '../core/theme.dart';
import '../l10n/l10n.dart';

class StatusBadgeConfig {
  final Color color;
  final String label;
  final IconData icon;

  const StatusBadgeConfig({
    required this.color,
    required this.label,
    required this.icon,
  });
}

class StatusBadge extends StatelessWidget {
  final String status;
  final bool showIcon;
  final bool compact;
  final Color? customColor;

  const StatusBadge({
    super.key,
    required this.status,
    this.showIcon = true,
    this.compact = false,
    this.customColor,
  });

  static StatusBadgeConfig getConfig(String status) {
    switch (status.toLowerCase().trim()) {
      case 'completed':
        return const StatusBadgeConfig(
          color: AppColors.success,
          label: 'Completed',
          icon: Icons.check_circle_outline,
        );
      case 'active':
        return const StatusBadgeConfig(
          color: AppColors.primary,
          label: 'Active',
          icon: Icons.local_shipping_outlined,
        );
      case 'awaiting_price_response':
      case 'awaiting price':
        return const StatusBadgeConfig(
          color: AppColors.warning,
          label: 'Awaiting Price',
          icon: Icons.request_quote_outlined,
        );
      case 'pending':
        return const StatusBadgeConfig(
          color: AppColors.outline,
          label: 'Pending',
          icon: Icons.schedule_outlined,
        );
      case 'cancelled':
      case 'canceled':
        return const StatusBadgeConfig(
          color: AppColors.error,
          label: 'Cancelled',
          icon: Icons.cancel_outlined,
        );
      case 'pending_super_admin_approval':
        return const StatusBadgeConfig(
          color: AppColors.warning,
          label: 'Pending Approval',
          icon: Icons.hourglass_empty_rounded,
        );
      case 'approved':
        return const StatusBadgeConfig(
          color: AppColors.success,
          label: 'Approved',
          icon: Icons.verified_user_outlined,
        );
      case 'rejected':
        return const StatusBadgeConfig(
          color: AppColors.error,
          label: 'Rejected',
          icon: Icons.gavel_outlined,
        );
      case 'unverified':
      case 'none':
        return const StatusBadgeConfig(
          color: AppColors.outline,
          label: 'Unverified',
          icon: Icons.shield_outlined,
        );
      case 'escrow_reconciliation_required':
      case 'reconciliation_required':
      case 'reconciliation required':
        return const StatusBadgeConfig(
          color: AppColors.warning,
          label: 'Reconciliation Required',
          icon: Icons.warning_amber_rounded,
        );
      default:
        final formattedLabel = status.isEmpty
            ? 'Unknown'
            : status.replaceAll('_', ' ').toUpperCase();
        return StatusBadgeConfig(
          color: AppColors.outline,
          label: formattedLabel,
          icon: Icons.info_outline,
        );
    }
  }

  static Color getStatusColor(String status) => getConfig(status).color;
  static String getStatusLabel(String status) => getConfig(status).label;
  static IconData getStatusIcon(String status) => getConfig(status).icon;

  static String getLocalizedStatusLabel(BuildContext context, String status) {
    final l10n = AppLocalizations.of(context);
    if (l10n == null) return getStatusLabel(status);
    switch (status.toLowerCase().trim()) {
      case 'completed':
        return l10n.statusCompleted;
      case 'active':
        return l10n.statusActive;
      case 'awaiting_price_response':
      case 'awaiting price':
        return l10n.statusAwaitingPrice;
      case 'pending':
        return l10n.statusPending;
      case 'cancelled':
      case 'canceled':
        return l10n.statusCancelled;
      case 'pending_super_admin_approval':
        return l10n.statusPendingApproval;
      case 'approved':
        return l10n.statusApproved;
      case 'rejected':
        return l10n.statusRejected;
      case 'unverified':
      case 'none':
        return l10n.statusUnverified;
      case 'escrow_reconciliation_required':
      case 'reconciliation_required':
      case 'reconciliation required':
        return l10n.statusReconciliationRequired;
      default:
        return getStatusLabel(status);
    }
  }

  @override
  Widget build(BuildContext context) {
    final config = getConfig(status);
    final badgeColor = customColor ?? config.color;

    final verticalPadding = compact ? AppSpacing.xs / 2 : AppSpacing.xs;
    final horizontalPadding = compact ? AppSpacing.base / 2 : AppSpacing.sm;
    final iconSize = compact ? 14.0 : 16.0;
    final textStyle = compact
        ? AppTypography.labelMd.copyWith(
            color: badgeColor,
            fontWeight: FontWeight.bold,
          )
        : AppTypography.labelLg.copyWith(
            color: badgeColor,
            fontWeight: FontWeight.bold,
          );

    return Container(
      padding: EdgeInsets.symmetric(
        horizontal: horizontalPadding,
        vertical: verticalPadding,
      ),
      decoration: BoxDecoration(
        color: badgeColor.withValues(alpha: 0.12),
        borderRadius: AppRadius.smBorder,
        border: Border.all(color: badgeColor, width: 1),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (showIcon) ...[
            Icon(
              config.icon,
              size: iconSize,
              color: badgeColor,
            ),
            const SizedBox(width: AppSpacing.xs),
          ],
          Text(
            getLocalizedStatusLabel(context, status).toUpperCase(),
            style: textStyle,
          ),
        ],
      ),
    );
  }
}
