import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';

/// In-memory FlutterSecureStorage mock via its method channel, so provider
/// suites can exercise real token/user persistence paths without the plugin.
class SecureStorageMock {
  final Map<String, String> store = {};
  int deleteAllCalls = 0;

  void install() {
    TestWidgetsFlutterBinding.ensureInitialized();
    const channel =
        MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(channel, (call) async {
      switch (call.method) {
        case 'read':
        case 'contains':
          final args = Map<String, Object?>.from(call.arguments as Map);
          return store[args['key'] as String?];
        case 'write':
          final args = Map<String, Object?>.from(call.arguments as Map);
          store[(args['key'] ?? '') as String] = (args['value'] as String?) ?? '';
          return null;
        case 'delete':
          final args = Map<String, Object?>.from(call.arguments as Map);
          store.remove(args['key'] as String? ?? '');
          return null;
        case 'deleteAll':
          store.clear();
          deleteAllCalls++;
          return null;
        case 'readAll':
          return Map<String, String>.of(store);
        default:
          return null;
      }
    });
  }

  void reset() {
    store.clear();
    deleteAllCalls = 0;
  }
}
