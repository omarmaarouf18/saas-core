import 'dart:async';

import 'package:frontend/services/push_notification_service.dart';

/// A scriptable FCM adapter (PUSH-FCM): token, availability, the phone's
/// permission and its answer to the system dialog.
class FakePushAdapter implements PushMessagingAdapter {
  FakePushAdapter({
    this.available = true,
    this.token = 'fcm-token-1',
    this.status = PushPermission.notDetermined,
    this.answer = PushPermission.granted,
  });

  @override
  bool available;
  String? token;

  /// What [permissionStatus] reports.
  PushPermission status;

  /// What the system dialog answers ([requestPermission]).
  PushPermission answer;

  /// When set, [getToken] waits for it (a hanging Play services call).
  Completer<String?>? tokenGate;

  int getTokenCalls = 0;
  int deleteTokenCalls = 0;
  int requestCalls = 0;
  void Function(String token)? _refresh;

  bool get listensForRefresh => _refresh != null;

  /// FCM issues a new token.
  void refreshTo(String newToken) {
    token = newToken;
    _refresh?.call(newToken);
  }

  @override
  Future<String?> getToken() async {
    getTokenCalls++;
    final gate = tokenGate;
    if (gate != null) return gate.future;
    return token;
  }

  @override
  Future<void> deleteToken() async => deleteTokenCalls++;

  @override
  void onTokenRefresh(void Function(String token) callback) =>
      _refresh = callback;

  @override
  Future<PushPermission> permissionStatus() async => status;

  @override
  Future<PushPermission> requestPermission() async {
    requestCalls++;
    status = answer;
    return answer;
  }
}

class MemoryPromptMemory implements PushPromptMemory {
  MemoryPromptMemory({this.isAnswered = false});

  bool isAnswered;

  @override
  Future<bool> answered() async => isAnswered;

  @override
  Future<void> markAnswered() async => isAnswered = true;
}
