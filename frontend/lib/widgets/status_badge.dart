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

  static Color getStatusColor(String status) {
    switch (status.toLowerCase().trim()) {
      case 'completed':
      case 'approved':
      case 'paid':
        return AppColors.success;
      case 'active':
        return AppColors.primary;
      case 'awaiting_price_response':
      case 'awaiting price':
      case 'pending_super_admin_approval':
      case 'escrow_reconciliation_required':
      case 'reconciliation_required':
      case 'reconciliation required':
      case 'requested':
        return AppColors.warning;
      case 'cancelled':
      case 'canceled':
      case 'rejected':
        return AppColors.error;
      case 'pending':
      case 'unverified':
      case 'none':
      default:
        return AppColors.outline;
    }
  }

  static IconData getStatusIcon(String status) {
    switch (status.toLowerCase().trim()) {
      case 'completed':
        return Icons.check_circle_outline;
      case 'paid':
        return Icons.payments_outlined;
      case 'active':
        return Icons.local_shipping_outlined;
      case 'awaiting_price_response':
      case 'awaiting price':
        return Icons.request_quote_outlined;
      case 'pending':
        return Icons.schedule_outlined;
      case 'requested':
        return Icons.hourglass_empty_rounded;
      case 'cancelled':
      case 'canceled':
        return Icons.cancel_outlined;
      case 'pending_super_admin_approval':
        return Icons.hourglass_empty_rounded;
      case 'approved':
        return Icons.verified_user_outlined;
      case 'rejected':
        return Icons.gavel_outlined;
      case 'unverified':
      case 'none':
        return Icons.shield_outlined;
      case 'escrow_reconciliation_required':
      case 'reconciliation_required':
      case 'reconciliation required':
        return Icons.warning_amber_rounded;
      default:
        return Icons.info_outline;
    }
  }

  static StatusBadgeConfig getConfig(BuildContext context, String status) {
    final l10n = context.l10n;
    final color = getStatusColor(status);
    final icon = getStatusIcon(status);
    String label;
    switch (status.toLowerCase().trim()) {
      case 'completed':
        label = l10n.statusCompleted;
        break;
      case 'paid':
        label = l10n.statusPaid;
        break;
      case 'active':
        label = l10n.statusActive;
        break;
      case 'awaiting_price_response':
      case 'awaiting price':
        label = l10n.statusAwaitingPrice;
        break;
      case 'pending':
        label = l10n.statusPending;
        break;
      case 'requested':
        label = l10n.statusRequested;
        break;
      case 'cancelled':
      case 'canceled':
        label = l10n.statusCancelled;
        break;
      case 'pending_super_admin_approval':
        label = l10n.statusPendingApproval;
        break;
      case 'approved':
        label = l10n.statusApproved;
        break;
      case 'rejected':
        label = l10n.statusRejected;
        break;
      case 'unverified':
      case 'none':
        label = l10n.statusUnverified;
        break;
      case 'escrow_reconciliation_required':
      case 'reconciliation_required':
      case 'reconciliation required':
        label = l10n.statusReconciliationRequired;
        break;
      default:
        label = status.isEmpty
            ? l10n.statusUnknown
            : status.replaceAll('_', ' ').toUpperCase();
        break;
    }
    return StatusBadgeConfig(
      color: color,
      label: label,
      icon: icon,
    );
  }

  static String getStatusLabel(BuildContext context, String status) =>
      getConfig(context, status).label;

  static String getLocalizedStatusLabel(BuildContext context, String status) =>
      getConfig(context, status).label;

  @override
  Widget build(BuildContext context) {
    final config = getConfig(context, status);
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
            config.label.toUpperCase(),
            style: textStyle,
          ),
        ],
      ),
    );
  }
}
