import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../models/notification_model.dart';
import '../../../ui/qd_ui.dart';
import 'notification_rules.dart';

/// Shows a bottom sheet displaying the full localized title and body of an announcement.
Future<void> showAnnouncementDetail(BuildContext context, NotificationModel n) {
  final l10n = context.l10n;
  final (title, body) = notificationCopy(l10n, n);
  final c = QdColors.of(context);

  return showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    backgroundColor: c.surface,
    barrierColor: c.scrim,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(QdRadius.sheet)),
    ),
    builder: (ctx) => AnnouncementDetailSheet(
      title: title.isEmpty ? n.title : title,
      body: body.isEmpty ? n.body : body,
    ),
  );
}

class AnnouncementDetailSheet extends StatelessWidget {
  const AnnouncementDetailSheet({
    super.key,
    required this.title,
    required this.body,
  });

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final l10n = context.l10n;

    return Padding(
      padding: const EdgeInsets.fromLTRB(
        QdSpace.gutter,
        QdSpace.x2,
        QdSpace.gutter,
        QdSpace.x4,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Center(
            child: Container(
              width: 36,
              height: 4,
              decoration: BoxDecoration(
                color: c.border,
                borderRadius: BorderRadius.circular(2),
              ),
            ),
          ),
          const SizedBox(height: QdSpace.x3),
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Container(
                width: QdSize.iconTile,
                height: QdSize.iconTile,
                decoration: BoxDecoration(
                  color: c.gold,
                  borderRadius: BorderRadius.circular(QdRadius.sm),
                ),
                child: Icon(Icons.campaign, size: QdSize.icon, color: c.onGold),
              ),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: Text(
                  title,
                  key: const Key('announcement_detail_title'),
                  style: QdText.header.copyWith(color: c.textPrimary),
                ),
              ),
            ],
          ),
          const SizedBox(height: QdSpace.x3),
          Flexible(
            child: SingleChildScrollView(
              child: Text(
                body,
                key: const Key('announcement_detail_body'),
                style: QdText.body.copyWith(color: c.textPrimary, height: 1.5),
              ),
            ),
          ),
          const SizedBox(height: QdSpace.x4),
          QdButton.secondary(
            key: const Key('announcement_detail_close'),
            label: l10n.close,
            fullWidth: true,
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}
