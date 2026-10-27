import 'dart:typed_data';

import 'package:flutter/material.dart';
import 'package:image_picker/image_picker.dart';

import '../../l10n/l10n.dart';
import '../../providers/service_photo_store.dart';
import '../../ui/qd_ui.dart';
import '../customer/service_photo_tile.dart';

enum ServicePhotoSource { camera, gallery }

/// Opens the camera or the photo library, scaled down to
/// [kServicePhotoMaxSide] px at quality [kServicePhotoQuality] so a phone
/// photo fits the 5 MB limit. Null when the owner backs out. Swapped in
/// tests.
class ServicePhotoPicker {
  const ServicePhotoPicker();

  Future<Uint8List?> pick(ServicePhotoSource source) async {
    final x = await ImagePicker().pickImage(
      source: source == ServicePhotoSource.camera
          ? ImageSource.camera
          : ImageSource.gallery,
      maxWidth: kServicePhotoMaxSide,
      maxHeight: kServicePhotoMaxSide,
      imageQuality: kServicePhotoQuality,
    );
    return x == null ? null : await x.readAsBytes();
  }
}

enum _SheetChoice { camera, gallery, remove }

/// The service photo row of the setup page (O-Service): the photo or the
/// initial tile, add / replace / remove, upload progress, and the error
/// with retry.
///
/// A picked photo is checked here (JPEG / PNG, ≤ 5 MB) and uploaded at
/// once: with [serviceId] the server stores it on the service; without one
/// (first save) the returned key goes to [onKey] and is sent as
/// `photo_url` when the service is created. [onRemove] clears the stored
/// photo of an existing service (PUT `photo_url: ""`); it throws on
/// failure.
class ServicePhotoSection extends StatefulWidget {
  const ServicePhotoSection({
    super.key,
    required this.serviceId,
    required this.photoUrl,
    required this.name,
    required this.onKey,
    required this.onRemove,
    this.picker = const ServicePhotoPicker(),
    this.enabled = true,
  });

  final String? serviceId;
  final String? photoUrl;
  final String name;
  final ValueChanged<String?> onKey;
  final Future<void> Function() onRemove;
  final ServicePhotoPicker picker;
  final bool enabled;

  @override
  State<ServicePhotoSection> createState() => _ServicePhotoSectionState();
}

class _ServicePhotoSectionState extends State<ServicePhotoSection> {
  Uint8List? _preview;
  Uint8List? _failedBytes;
  bool _busy = false;
  double? _progress;
  String? _error;
  bool _removeFailed = false;

  bool get _hasPhoto => _preview != null || isStoredPhotoKey(widget.photoUrl);

  String _failureText(ServicePhotoFailure f) {
    final l10n = context.l10n;
    return switch (f) {
      ServicePhotoFailure.unavailable => l10n.ownSvcPhotoErrUnavailable,
      ServicePhotoFailure.kybNotApproved => l10n.ownSvcErrKyb,
      ServicePhotoFailure.paidPlanRequired => l10n.ownSvcErrPlan,
      ServicePhotoFailure.rejected => l10n.ownSvcPhotoErrRejected,
      ServicePhotoFailure.network ||
      ServicePhotoFailure.other =>
        l10n.ownSvcPhotoErrNetwork,
    };
  }

  Future<void> _choose() async {
    final l10n = context.l10n;
    final choice = await QdBottomSheet.show<_SheetChoice>(
      context,
      title: l10n.ownSvcPhotoSheetTitle,
      child: Builder(builder: (sheet) {
        Widget tile(_SheetChoice v, IconData icon, String title) => QdListTile(
              key: Key('own_service_photo_${v.name}'),
              icon: icon,
              title: title,
              onTap: () => Navigator.of(sheet).pop(v),
            );
        return QdListGroup(children: [
          tile(_SheetChoice.camera, Icons.photo_camera_outlined,
              l10n.ownSvcPhotoCamera),
          tile(_SheetChoice.gallery, Icons.photo_library_outlined,
              l10n.ownSvcPhotoGallery),
          if (_hasPhoto)
            tile(_SheetChoice.remove, Icons.delete_outline,
                l10n.ownSvcPhotoRemove),
        ]);
      }),
    );
    if (choice == null || !mounted) return;
    if (choice == _SheetChoice.remove) return _remove();
    final bytes = await widget.picker.pick(choice == _SheetChoice.camera
        ? ServicePhotoSource.camera
        : ServicePhotoSource.gallery);
    if (bytes == null || !mounted) return;
    await _upload(bytes);
  }

  Future<void> _upload(Uint8List bytes) async {
    final l10n = context.l10n;
    final problem = checkServicePhoto(bytes);
    if (problem != null) {
      setState(() {
        _failedBytes = null;
        _error = switch (problem) {
          ServicePhotoProblem.tooLarge => l10n.ownSvcPhotoErrTooLarge,
          ServicePhotoProblem.empty ||
          ServicePhotoProblem.notJpegOrPng =>
            l10n.ownSvcPhotoErrFormat,
        };
      });
      return;
    }
    final store = ServicePhotoScope.maybeOf(context);
    if (store == null) {
      setState(() => _error = l10n.ownSvcPhotoErrUnavailable);
      return;
    }
    setState(() {
      _busy = true;
      _progress = 0;
      _error = null;
      _removeFailed = false;
    });
    try {
      final key = await store.upload(bytes, serviceId: widget.serviceId,
          onProgress: (p) {
        if (mounted) setState(() => _progress = p);
      });
      if (!mounted) return;
      setState(() {
        _busy = false;
        _progress = null;
        _preview = bytes;
        _failedBytes = null;
      });
      widget.onKey(key);
    } catch (e) {
      if (!mounted) return;
      final failure = servicePhotoFailureOf(e);
      setState(() {
        _busy = false;
        _progress = null;
        _error = _failureText(failure);
        // A refused image will be refused again; the rest can be retried.
        _failedBytes = failure == ServicePhotoFailure.rejected ||
                failure == ServicePhotoFailure.kybNotApproved ||
                failure == ServicePhotoFailure.paidPlanRequired
            ? null
            : bytes;
      });
    }
  }

  Future<void> _remove() async {
    setState(() {
      _busy = true;
      _error = null;
      _failedBytes = null;
      _removeFailed = false;
    });
    try {
      if (widget.serviceId != null && isStoredPhotoKey(widget.photoUrl)) {
        await widget.onRemove();
        if (!mounted) return;
        ServicePhotoScope.maybeOf(context)?.invalidate(widget.serviceId!);
      }
      if (!mounted) return;
      setState(() {
        _busy = false;
        _preview = null;
      });
      widget.onKey(null);
    } catch (_) {
      if (!mounted) return;
      setState(() {
        _busy = false;
        _removeFailed = true;
        _error = context.l10n.ownSvcPhotoErrRemove;
      });
    }
  }

  void _retry() {
    final bytes = _failedBytes;
    if (bytes != null) {
      _upload(bytes);
    } else if (_removeFailed) {
      _remove();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final progress = _progress;
    final canRetry = _failedBytes != null || _removeFailed;
    final pendingKey = widget.serviceId == null && _preview != null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Row(
          children: [
            Stack(
              alignment: Alignment.center,
              children: [
                ServicePhotoTile(
                  key: const Key('own_service_photo'),
                  serviceId: widget.serviceId ?? '',
                  photoUrl: widget.photoUrl,
                  name: widget.name,
                  bytes: _preview,
                  size: 64,
                  tone: QdIconTileTone.gold,
                ),
                if (_busy)
                  SizedBox(
                    width: 32,
                    height: 32,
                    child: CircularProgressIndicator(
                      key: const Key('own_service_photo_progress'),
                      value:
                          progress == null || progress <= 0 ? null : progress,
                      strokeWidth: 3,
                    ),
                  ),
              ],
            ),
            const SizedBox(width: QdSpace.x3),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    _busy && progress != null
                        ? l10n.ownSvcPhotoUploading((progress * 100).round())
                        : pendingKey
                            ? l10n.ownSvcPhotoPending
                            : l10n.ownSvcPhotoNote,
                    key: const Key('own_service_photo_note'),
                    style: QdText.secondary.copyWith(color: c.textSecondary),
                  ),
                  const SizedBox(height: QdSpace.x1),
                  QdButton.secondary(
                    key: const Key('own_service_photo_pick'),
                    label: _hasPhoto
                        ? l10n.ownSvcPhotoReplace
                        : l10n.ownSvcPhotoAdd,
                    icon: Icons.add_a_photo_outlined,
                    small: true,
                    onPressed: _busy || !widget.enabled ? null : _choose,
                  ),
                ],
              ),
            ),
          ],
        ),
        if (_error != null) ...[
          const SizedBox(height: QdSpace.x3),
          QdBanner(
            key: const Key('own_service_photo_error'),
            tone: QdBannerTone.danger,
            icon: Icons.error_outline,
            message: _error!,
            actionLabel: canRetry ? l10n.retry : null,
            onAction: canRetry && !_busy ? _retry : null,
          ),
        ],
      ],
    );
  }
}
