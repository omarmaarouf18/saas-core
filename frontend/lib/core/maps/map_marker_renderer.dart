import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:google_maps_flutter/google_maps_flutter.dart' as gmf;

import '../../ui/qd_ui.dart';
import 'app_map_types.dart';

/// Builds the Flutter widget representation of [icon] for the in-widget test
/// fake map so marker styling stays identical to Redesign A tokens.
Widget buildAppMarkerWidget(BuildContext context, AppMarkerIcon icon) {
  final c = QdColors.of(context);
  return switch (icon.kind) {
    AppMarkerKind.pickupRing => Container(
        width: icon.size.width,
        height: icon.size.height,
        decoration: BoxDecoration(
          color: c.surface,
          shape: BoxShape.circle,
          border: Border.all(color: c.navy, width: 4),
        ),
      ),
    AppMarkerKind.dropoffSquare => Container(
        width: icon.size.width,
        height: icon.size.height,
        decoration: BoxDecoration(
          color: c.gold,
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: c.navy, width: 3),
        ),
      ),
    AppMarkerKind.selfDot => Container(
        width: icon.size.width,
        height: icon.size.height,
        decoration: BoxDecoration(color: c.navy, shape: BoxShape.circle),
        alignment: Alignment.center,
        child: Container(
          width: 10,
          height: 10,
          decoration: BoxDecoration(color: c.gold, shape: BoxShape.circle),
        ),
      ),
    AppMarkerKind.courierPin => Container(
        width: icon.size.width,
        height: icon.size.height,
        decoration: BoxDecoration(color: c.navy, shape: BoxShape.circle),
        child: Icon(Icons.two_wheeler, size: 18, color: c.onNavy),
      ),
    AppMarkerKind.fleetCourier => Container(
        width: icon.size.width,
        height: icon.size.height,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: icon.onJob ? c.navy : c.surface,
          shape: BoxShape.circle,
          border: Border.all(
            color: icon.onJob ? c.gold : c.navy,
            width: icon.selected ? 4 : 3,
          ),
        ),
        child: Text(
          icon.initial,
          style: QdText.chip.copyWith(
            color: icon.onJob ? c.onNavy : c.navy,
            fontSize: icon.selected ? 15 : 13,
            height: 1.2,
          ),
        ),
      ),
  };
}

/// Renders [AppMarkerIcon] to PNG bytes for [gmf.BitmapDescriptor.bytes].
@visibleForTesting
Future<Uint8List> renderAppMarkerPng(
  AppMarkerIcon icon,
  QdColors colors, {
  double pixelRatio = 2.0,
}) async {
  final w = icon.size.width;
  final h = icon.size.height;
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.scale(pixelRatio);

  final center = Offset(w / 2, h / 2);
  final fill = Paint()..style = PaintingStyle.fill;
  final stroke = Paint()..style = PaintingStyle.stroke;

  switch (icon.kind) {
    case AppMarkerKind.pickupRing:
      const bw = 4.0;
      final r = (w / 2) - (bw / 2);
      canvas.drawCircle(center, r, fill..color = colors.surface);
      canvas.drawCircle(
        center,
        r,
        stroke
          ..color = colors.navy
          ..strokeWidth = bw,
      );
    case AppMarkerKind.dropoffSquare:
      const bw = 3.0;
      final rect = Rect.fromLTWH(bw / 2, bw / 2, w - bw, h - bw);
      final rrect = RRect.fromRectAndRadius(rect, const Radius.circular(4));
      canvas.drawRRect(rrect, fill..color = colors.gold);
      canvas.drawRRect(
        rrect,
        stroke
          ..color = colors.navy
          ..strokeWidth = bw,
      );
    case AppMarkerKind.selfDot:
      canvas.drawCircle(center, w / 2, fill..color = colors.navy);
      canvas.drawCircle(center, 5, fill..color = colors.gold);
    case AppMarkerKind.courierPin:
      canvas.drawCircle(center, w / 2, fill..color = colors.navy);
      final tp = TextPainter(
        text: TextSpan(
          text: String.fromCharCode(Icons.two_wheeler.codePoint),
          style: TextStyle(
            fontSize: 18,
            fontFamily: Icons.two_wheeler.fontFamily,
            package: Icons.two_wheeler.fontPackage,
            color: colors.onNavy,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout();
      tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
    case AppMarkerKind.fleetCourier:
      final bw = icon.selected ? 4.0 : 3.0;
      final r = (w / 2) - (bw / 2);
      canvas.drawCircle(
        center,
        r,
        fill..color = icon.onJob ? colors.navy : colors.surface,
      );
      canvas.drawCircle(
        center,
        r,
        stroke
          ..color = icon.onJob ? colors.gold : colors.navy
          ..strokeWidth = bw,
      );
      if (icon.initial.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: icon.initial,
            style: QdText.chip.copyWith(
              color: icon.onJob ? colors.onNavy : colors.navy,
              fontSize: icon.selected ? 15 : 13,
              height: 1.2,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, center - Offset(tp.width / 2, tp.height / 2));
      }
  }

  final picture = recorder.endRecording();
  final image = await picture.toImage(
    (w * pixelRatio).round(),
    (h * pixelRatio).round(),
  );
  try {
    final byteData = await image.toByteData(format: ui.ImageByteFormat.png);
    return byteData!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}

/// In-memory cache of rasterized Google Maps [gmf.BitmapDescriptor] icons.
class AppMarkerBitmapCache {
  final Map<Object, gmf.BitmapDescriptor> _cache = {};
  final Set<Object> _inFlight = {};

  Object _keyOf(AppMarkerIcon icon, QdColors c) => Object.hash(
        icon,
        c.surface.toARGB32(),
        c.gold.toARGB32(),
        c.navy.toARGB32(),
        c.onNavy.toARGB32(),
      );

  /// Returns a cached descriptor, or triggers async rasterization and invokes
  /// [onReady] once available so the map refreshes with the crisp bitmap.
  gmf.BitmapDescriptor resolve(
    AppMarkerIcon icon,
    QdColors colors, {
    VoidCallback? onReady,
  }) {
    final key = _keyOf(icon, colors);
    final cached = _cache[key];
    if (cached != null) return cached;
    if (_inFlight.add(key)) {
      renderAppMarkerPng(icon, colors).then((bytes) {
        _cache[key] = gmf.BitmapDescriptor.bytes(
          bytes,
          width: icon.size.width,
          height: icon.size.height,
        );
        _inFlight.remove(key);
        onReady?.call();
      }).catchError((_) {
        _inFlight.remove(key);
      });
    }
    return gmf.BitmapDescriptor.defaultMarker;
  }
}
