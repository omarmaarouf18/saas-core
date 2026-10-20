import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/qd_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Plex OFL license is registered with LicenseRegistry', () async {
    registerQdFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final plex = entries
        .where((e) => e.packages.contains('IBM Plex Sans Arabic'))
        .toList();
    expect(plex, isNotEmpty);
    final text = plex.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL OPEN FONT LICENSE'));
  });
}
