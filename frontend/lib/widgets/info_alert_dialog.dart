import 'package:flutter/material.dart';
import '../core/theme.dart';
import 'primary_button.dart';

/// Informational single-action dialog (ADR-0021): presents a notice that
/// requires acknowledgement only — no confirm/cancel choice. Unlike
/// [ConfirmActionDialog] (which models a decision), this dialog has exactly
/// one dismiss action, so callers only supply title/message/ack label.
class InfoAlertDialog extends StatelessWidget {
  final String title;
  final String message;
  final String ackLabel;
  final IconData? icon;

  const InfoAlertDialog({
    super.key,
    required this.title,
    required this.message,
    required this.ackLabel,
    this.icon,
  });

  static Future<void> show(
    BuildContext context, {
    required String title,
    required String message,
    required String ackLabel,
    IconData? icon,
  }) {
    return showDialog<void>(
      context: context,
      builder: (ctx) => InfoAlertDialog(
        title: title,
        message: message,
        ackLabel: ackLabel,
        icon: icon,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      shape: RoundedRectangleBorder(
        borderRadius: AppRadius.mdBorder,
      ),
      backgroundColor: Theme.of(context).colorScheme.surface,
      title: Row(
        children: [
          Icon(
            icon ?? Icons.info_outline_rounded,
            color: Theme.of(context).colorScheme.primary,
          ),
          const SizedBox(width: AppSpacing.sm),
          Expanded(
            child: Text(
              title,
              style: AppTypography.titleMd.copyWith(
                fontWeight: FontWeight.bold,
                color: Theme.of(context).colorScheme.onSurface,
              ),
            ),
          ),
        ],
      ),
      content: Text(
        message,
        style: AppTypography.bodyMd.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      ),
      actions: [
        PrimaryButton(
          text: ackLabel,
          isFullWidth: false,
          onPressed: () => Navigator.of(context).pop(),
        ),
      ],
    );
  }
}
