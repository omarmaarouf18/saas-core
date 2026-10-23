import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';
import 'package:url_launcher/url_launcher.dart';

/// Opens things outside the app (FE-V2-CONSUME): the phone app, a maps
/// app. Swappable through [QdLauncherScope] so tests never reach the
/// platform.
abstract class QdLauncher {
  const QdLauncher();

  /// Opens [uri] in another app. False when nothing could open it.
  Future<bool> open(Uri uri);
}

/// The real launcher: `url_launcher`, always in an external app. A thrown
/// platform error (no app for the scheme, plugin missing) counts as false.
class UrlQdLauncher extends QdLauncher {
  const UrlQdLauncher();

  @override
  Future<bool> open(Uri uri) async {
    try {
      return await launchUrl(uri, mode: LaunchMode.externalApplication);
    } catch (_) {
      return false;
    }
  }
}

/// Provides the [QdLauncher] below it (default: [UrlQdLauncher]).
class QdLauncherScope extends InheritedWidget {
  const QdLauncherScope(
      {super.key, required this.launcher, required super.child});

  final QdLauncher launcher;

  static QdLauncher of(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<QdLauncherScope>()?.launcher ??
      const UrlQdLauncher();

  @override
  bool updateShouldNotify(QdLauncherScope oldWidget) =>
      launcher != oldWidget.launcher;
}

/// `tel:` link for [phone]; spaces, dashes and brackets are dropped, a
/// leading `+` is kept.
Uri phoneCallUri(String phone) =>
    Uri(scheme: 'tel', path: phone.replaceAll(RegExp(r'[^0-9+]'), ''));

/// `lat,lng` with 6 decimals (about 10 cm), the text that is copied when no
/// maps app opens.
String coordsText(double latitude, double longitude) =>
    '${latitude.toStringAsFixed(6)},${longitude.toStringAsFixed(6)}';

/// Map links for a point, tried in order: Android a `geo:` link (any maps
/// app) then Google Maps on the web; iOS Apple Maps then Google Maps on the
/// web; elsewhere Google Maps on the web. No routing API (ADR-0028 §2.5).
List<Uri> mapsUris(double latitude, double longitude,
    {TargetPlatform? platform}) {
  final c = coordsText(latitude, longitude);
  final web = Uri.https('www.google.com', '/maps/search/', {
    'api': '1',
    'query': c,
  });
  return switch (platform ?? defaultTargetPlatform) {
    TargetPlatform.android => [Uri.parse('geo:$c?q=$c'), web],
    TargetPlatform.iOS => [
        Uri.https('maps.apple.com', '/', {'q': c}),
        web
      ],
    _ => [web],
  };
}

/// Tries [uris] in order with the scope's launcher. When none opens,
/// copies [copyText] to the clipboard and calls [onCopied] (the page shows
/// its notice). Returns whether an app opened.
Future<bool> openOrCopy(
  BuildContext context,
  List<Uri> uris, {
  required String copyText,
  required VoidCallback onCopied,
}) async {
  final launcher = QdLauncherScope.of(context);
  for (final uri in uris) {
    if (await launcher.open(uri)) return true;
  }
  await Clipboard.setData(ClipboardData(text: copyText));
  onCopied();
  return false;
}
