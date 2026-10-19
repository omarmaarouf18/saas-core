import 'package:flutter/material.dart';

import '../tokens.dart';
import 'qd_button.dart';

/// Bottom sheet body: handle, title, optional subtitle, content and at most
/// one primary action. Use [QdBottomSheet.show] to present it modally.
class QdBottomSheet extends StatelessWidget {
  const QdBottomSheet({
    super.key,
    required this.title,
    required this.child,
    this.subtitle,
    this.primaryLabel,
    this.onPrimary,
    this.primaryLoading = false,
  });

  final String title;
  final String? subtitle;
  final Widget child;
  final String? primaryLabel;
  final VoidCallback? onPrimary;
  final bool primaryLoading;

  static Future<T?> show<T>(
    BuildContext context, {
    required String title,
    required Widget child,
    String? subtitle,
    String? primaryLabel,
    VoidCallback? onPrimary,
  }) {
    final c = QdColors.of(context);
    return showModalBottomSheet<T>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: c.surface,
      barrierColor: c.scrim,
      shape: const RoundedRectangleBorder(
        borderRadius:
            BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
      ),
      builder: (ctx) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
        child: QdBottomSheet(
          title: title,
          subtitle: subtitle,
          primaryLabel: primaryLabel,
          onPrimary: onPrimary,
          child: child,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return DecoratedBox(
      decoration: BoxDecoration(
        color: c.surface,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
      ),
      child: SafeArea(
        top: false,
        minimum: const EdgeInsets.only(bottom: QdSpace.x5),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(
              QdSpace.gutter, QdSpace.x3, QdSpace.gutter, 0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: ExcludeSemantics(
                  child: Container(
                    width: 40,
                    height: 4,
                    decoration: BoxDecoration(
                      color: c.borderInput,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
              ),
              const SizedBox(height: QdSpace.x4),
              Semantics(
                header: true,
                child: Text(title,
                    style: QdText.sheetTitle.copyWith(color: c.textPrimary)),
              ),
              if (subtitle != null) ...[
                const SizedBox(height: QdSpace.x1),
                Text(subtitle!,
                    style: QdText.body.copyWith(color: c.textSecondary)),
              ],
              const SizedBox(height: QdSpace.x4),
              Flexible(child: child),
              if (primaryLabel != null) ...[
                const SizedBox(height: QdSpace.x5),
                QdButton(
                  label: primaryLabel!,
                  onPressed: onPrimary,
                  loading: primaryLoading,
                  fullWidth: true,
                ),
              ],
            ],
          ),
        ),
      ),
    );
  }
}
