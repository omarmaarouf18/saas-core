import 'package:flutter/foundation.dart';
import 'package:flutter/services.dart';

/// Asset path of the bundled IBM Plex Sans Arabic license (SIL OFL 1.1).
const String kQdFontLicenseAsset = 'assets/fonts/IBMPlexSansArabic-OFL.txt';

/// Registers the bundled Plex font license with [LicenseRegistry] so it is
/// listed on Flutter's licenses page. Read lazily from the asset bundle,
/// only when the page asks for licenses. Call once at app start.
void registerQdFontLicenses({AssetBundle? bundle}) {
  LicenseRegistry.addLicense(() async* {
    final text = await (bundle ?? rootBundle).loadString(kQdFontLicenseAsset);
    yield LicenseEntryWithLineBreaks(const ['IBM Plex Sans Arabic'], text);
  });
}
