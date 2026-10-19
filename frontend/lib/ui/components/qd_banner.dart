import 'package:flutter/material.dart';

import '../tokens.dart';

enum QdBannerTone { info, warning, danger }

/// Inline notice at the top of a screen: KYC pending, account suspended,
/// location denied, offline. Navy text on a tone fill, tone-colored icon,
/// optional action link (C-History).
class QdBanner extends StatelessWidget {
  const QdBanner({
    super.key,
    required this.tone,
    required this.message,
    this.title,
    this.icon,
    this.actionLabel,
    this.onAction,
  });

  final QdBannerTone tone;
  final String message;
  final String? title;
  final IconData? icon;
  final String? actionLabel;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final (bg, iconColor, defaultIcon) = switch (tone) {
      QdBannerTone.info => (c.fillMuted, c.textPrimary, Icons.info_outline),
      QdBannerTone.warning => (
          c.warningBg,
          c.warning,
          Icons.warning_amber_rounded
        ),
      QdBannerTone.danger => (c.dangerBg, c.danger, Icons.block),
    };

    return Semantics(
      container: true,
      liveRegion: tone != QdBannerTone.info,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(14, 12, 14, 12),
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(QdRadius.button),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.only(top: 1),
              child: Icon(icon ?? defaultIcon,
                  size: QdSize.icon, color: iconColor),
            ),
            const SizedBox(width: 10),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (title != null) ...[
                    Text(title!,
                        style:
                            QdText.bodyStrong.copyWith(color: c.textPrimary)),
                    const SizedBox(height: 2),
                  ],
                  Text(
                    message,
                    style: QdText.secondary
                        .copyWith(color: c.textPrimary, height: 1.6),
                  ),
                  if (actionLabel != null)
                    Semantics(
                      button: true,
                      label: actionLabel,
                      excludeSemantics: true,
                      onTap: onAction,
                      child: InkWell(
                        onTap: onAction,
                        child: ConstrainedBox(
                          constraints: const BoxConstraints(
                              minHeight: QdSize.minTouch - 8),
                          child: Align(
                            alignment: AlignmentDirectional.centerStart,
                            widthFactor: 1,
                            child: Text(
                              actionLabel!,
                              style: QdText.secondary.copyWith(
                                color: c.textPrimary,
                                fontWeight: FontWeight.w600,
                                decoration: TextDecoration.underline,
                                decorationColor: c.textPrimary,
                              ),
                            ),
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
