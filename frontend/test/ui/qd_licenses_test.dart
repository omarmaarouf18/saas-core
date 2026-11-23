import 'package:flutter/foundation.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/qd_licenses.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('Readex Pro OFL license is registered with LicenseRegistry', () async {
    registerQdFontLicenses();
    final entries = await LicenseRegistry.licenses.toList();
    final fontLicense =
        entries.where((e) => e.packages.contains('Readex Pro')).toList();
    expect(fontLicense, isNotEmpty);
    final text = fontLicense.first.paragraphs.map((p) => p.text).join('\n');
    expect(text, contains('SIL OPEN FONT LICENSE'));
  });
}
