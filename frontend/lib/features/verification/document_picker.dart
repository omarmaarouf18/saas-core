import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/l10n.dart';
import '../../ui/qd_ui.dart';
import 'verification_rules.dart';

enum DocumentSource { camera, gallery, file }

/// Opens the camera, the photo library or the file picker, with the old
/// upload screen's settings (photos scaled to 1920 px at quality 85; files
/// limited to JPG / PNG, plus PDF where the slot allows it). Returns null
/// when the person backs out. Swapped in tests.
class DocumentPicker {
  const DocumentPicker();

  Future<PickedDocument?> pick(DocumentSource source,
      {required bool allowPdf}) async {
    switch (source) {
      case DocumentSource.camera:
      case DocumentSource.gallery:
        final x = await ImagePicker().pickImage(
          source: source == DocumentSource.camera
              ? ImageSource.camera
              : ImageSource.gallery,
          maxWidth: 1920,
          maxHeight: 1920,
          imageQuality: 85,
        );
        if (x == null) return null;
        return PickedDocument(filename: x.name, bytes: await x.readAsBytes());
      case DocumentSource.file:
        final result = await FilePicker.platform.pickFiles(
          type: FileType.custom,
          allowedExtensions: [
            'jpg',
            'jpeg',
            'png',
            if (allowPdf) 'pdf',
          ],
          withData: true,
        );
        final file = result?.files.firstOrNull;
        final bytes = file?.bytes;
        if (file == null || bytes == null) return null;
        return PickedDocument(filename: file.name, bytes: bytes);
    }
  }
}

/// Camera / photos / file choice for one slot.
Future<DocumentSource?> showDocumentSourceSheet(
    BuildContext context, String slotTitle,
    {required bool allowPdf}) {
  final l10n = context.l10n;
  return QdBottomSheet.show<DocumentSource>(
    context,
    title: l10n.vrfSourceTitle(slotTitle),
    // The sheet lives in the navigator overlay, outside the page theme.
    child: Builder(builder: (sheetContext) {
      Widget tile(DocumentSource s, IconData icon, String title,
              {String? subtitle}) =>
          QdListTile(
            key: Key('vrf_source_${s.name}'),
            icon: icon,
            title: title,
            subtitle: subtitle,
            onTap: () => Navigator.of(sheetContext).pop(s),
          );
      return QdListGroup(children: [
        tile(DocumentSource.camera, Icons.photo_camera_outlined,
            l10n.vrfSourceCamera),
        tile(DocumentSource.gallery, Icons.photo_library_outlined,
            l10n.vrfSourceGallery),
        tile(DocumentSource.file, Icons.attach_file, l10n.vrfSourceFile,
            subtitle: allowPdf
                ? l10n.vrfSourceFileHintPdf
                : l10n.vrfSourceFileHintPhoto),
      ]);
    }),
  );
}
