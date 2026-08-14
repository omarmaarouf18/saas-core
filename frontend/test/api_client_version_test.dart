import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/core/api_client.dart';

void main() {
  test('ApiClient manages appVersion and sets X-App-Version header', () {
    final client = ApiClient(appVersion: '1.2.3+45');
    expect(client.appVersion, equals('1.2.3+45'));

    client.setAppVersion('2.0.0+99');
    expect(client.appVersion, equals('2.0.0+99'));
  });
}
