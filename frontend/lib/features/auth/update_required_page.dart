import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../l10n/l10n.dart';
import '../../ui/qd_ui.dart';
import 'widgets/auth_scaffold.dart';

/// Release download used when the server sends no `download_url` (the
/// same fallback as the old UpdateRequiredScreen).
const String kFallbackDownloadUrl =
    'https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release.apk';

/// Forced update (HTTP 426, ADR-0018): no way back into the app.
///
/// The old screen's "update now" button did nothing. The app has no
/// url_launcher dependency, so this one copies the download link (shown on
/// the page, selectable) to the clipboard instead of opening it. Versions
/// are shown only when the server sent them (the old screen showed made-up
/// defaults).
class UpdateRequiredPage extends StatelessWidget {
  const UpdateRequiredPage({
    super.key,
    this.currentVersion,
    this.minimumVersion,
    this.latestVersion,
    this.downloadUrl,
  });

  final String? currentVersion;
  final String? minimumVersion;
  final String? latestVersion;
  final String? downloadUrl;

  String get url => downloadUrl == null || downloadUrl!.trim().isEmpty
      ? kFallbackDownloadUrl
      : downloadUrl!.trim();

  Future<void> _copy(BuildContext context) async {
    await Clipboard.setData(ClipboardData(text: url));
    if (context.mounted) showAuthNotice(context, context.l10n.updCopied);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final versions = [
      (l10n.updInstalled, currentVersion),
      (l10n.updMinimum, minimumVersion),
      (l10n.updLatest, latestVersion),
    ].where((v) => v.$2 != null && v.$2!.isNotEmpty).toList();

    return PopScope(
      canPop: false,
      child: AuthScaffold(
        footer: QdButton(
          key: const Key('update_copy'),
          label: l10n.updCopy,
          icon: Icons.copy,
          fullWidth: true,
          onPressed: () => _copy(context),
        ),
        children: [
          const SizedBox(height: 48),
          Builder(builder: (context) {
            final c = QdColors.of(context);
            return Align(
              alignment: AlignmentDirectional.centerStart,
              child: ExcludeSemantics(
                child: Container(
                  width: 56,
                  height: 56,
                  decoration: BoxDecoration(
                    color: c.gold,
                    borderRadius: BorderRadius.circular(QdRadius.card),
                  ),
                  child: Icon(Icons.system_update_outlined,
                      size: 28, color: c.onGold),
                ),
              ),
            );
          }),
          const SizedBox(height: QdSpace.x5),
          AuthHeading(title: l10n.updTitle, subtitle: l10n.updBody),
          const SizedBox(height: QdSpace.x6),
          if (versions.isNotEmpty) ...[
            QdListGroup(children: [
              for (final (label, value) in versions)
                QdListTile(title: label, value: '\u2066$value\u2069'),
            ]),
            const SizedBox(height: QdSpace.x5),
          ],
          Builder(builder: (context) {
            final c = QdColors.of(context);
            return Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text(l10n.updLinkLabel,
                    style: QdText.body.copyWith(
                        color: c.textPrimary, fontWeight: FontWeight.w500)),
                const SizedBox(height: 6),
                QdCard(
                  subtle: true,
                  child: SelectableText(
                    url,
                    key: const Key('update_url'),
                    textDirection: TextDirection.ltr,
                    style: QdText.secondary.copyWith(color: c.textPrimary),
                  ),
                ),
              ],
            );
          }),
        ],
      ),
    );
  }
}
