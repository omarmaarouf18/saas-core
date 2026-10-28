import 'dart:typed_data';

import 'package:flutter/material.dart';

import '../../providers/service_photo_store.dart';
import '../../ui/qd_ui.dart';

/// A company's photo in a rounded square (marketplace card, booking page,
/// owner service setup), or its initial tile when there is no stored photo,
/// no [ServicePhotoScope], or the photo fails to load. Decorative: the name
/// is always shown next to it.
class ServicePhotoTile extends StatefulWidget {
  const ServicePhotoTile({
    super.key,
    required this.serviceId,
    required this.photoUrl,
    this.photoVersion,
    required this.name,
    this.size = QdSize.iconTile,
    this.tone = QdIconTileTone.muted,
    this.bytes,
  });

  final String serviceId;

  /// The stored key from the API (`photo_url`); never a device path.
  final String? photoUrl;

  /// The service's `photo_version` (changes with the photo); null when the
  /// server did not send one.
  final String? photoVersion;

  /// For the placeholder initial.
  final String name;
  final double size;
  final QdIconTileTone tone;

  /// Shown instead of loading (the owner's just-picked photo).
  final Uint8List? bytes;

  @override
  State<ServicePhotoTile> createState() => _ServicePhotoTileState();
}

class _ServicePhotoTileState extends State<ServicePhotoTile> {
  Future<Uint8List?>? _future;
  ServicePhotoStore? _store;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final store = ServicePhotoScope.maybeOf(context);
    if (store != _store) {
      _store = store;
      _future = _load();
    }
  }

  @override
  void didUpdateWidget(ServicePhotoTile old) {
    super.didUpdateWidget(old);
    if (old.serviceId != widget.serviceId ||
        old.photoUrl != widget.photoUrl ||
        old.photoVersion != widget.photoVersion) {
      _future = _load();
    }
  }

  Future<Uint8List?>? _load() {
    final store = _store;
    if (store == null || !isStoredPhotoKey(widget.photoUrl)) return null;
    return store.load(widget.serviceId, widget.photoUrl,
        photoVersion: widget.photoVersion);
  }

  @override
  Widget build(BuildContext context) {
    final placeholder = QdIconTile.initialOf(widget.name,
        key: const Key('service_photo_placeholder'),
        size: widget.size,
        tone: widget.tone);
    final picked = widget.bytes;
    if (picked != null) return _image(picked);
    final future = _future;
    if (future == null) return placeholder;
    return FutureBuilder<Uint8List?>(
      future: future,
      builder: (context, snap) {
        final data = snap.data;
        return data == null ? placeholder : _image(data);
      },
    );
  }

  Widget _image(Uint8List data) {
    final c = QdColors.of(context);
    return ExcludeSemantics(
      child: ClipRRect(
        key: const Key('service_photo_image'),
        borderRadius: BorderRadius.circular(QdRadius.sm),
        child: Container(
          width: widget.size,
          height: widget.size,
          color: c.fillMuted,
          child: Image.memory(
            data,
            fit: BoxFit.cover,
            gaplessPlayback: true,
            errorBuilder: (_, __, ___) => QdIconTile.initialOf(widget.name,
                size: widget.size, tone: widget.tone),
          ),
        ),
      ),
    );
  }
}
