import 'dart:async';
import 'dart:convert';

import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter/material.dart';

import '../models/notification_model.dart';
import 'local_notifications.dart';

/// A foreground push as the payload of the local notification that shows
/// it (PUSH-FCM), so a tap on it follows the same link.
String encodePushPayload(NotificationModel n) => jsonEncode({
      'id': n.id,
      'type': n.type,
      'tenant_id': n.tenantId,
      if (n.jobId != null) 'job_id': n.jobId,
      'title': n.title,
      'body': n.body,
    });

/// The notification in a local notification's payload; null when it is
/// not one of ours.
NotificationModel? decodePushPayload(String? payload) {
  if (payload == null || payload.isEmpty) return null;
  try {
    final m = jsonDecode(payload);
    if (m is! Map<String, dynamic>) return null;
    return NotificationModel.fromPushData(m,
        title: m['title']?.toString() ?? '', body: m['body']?.toString() ?? '');
  } catch (_) {
    return null;
  }
}

/// Where push taps come from. The default reads Firebase Messaging; tests
/// swap it.
abstract class PushTapSource {
  /// The push that launched the app from a terminated state (cold start),
  /// or null.
  Future<NotificationModel?> initialTap();

  /// Calls [onOpened] for a push tapped while the app was in the
  /// background, and [onForeground] for a push that arrives while the app
  /// is open (the system shows nothing then).
  void listen({
    required void Function(NotificationModel n) onOpened,
    required void Function(NotificationModel n) onForeground,
  });
}

/// Firebase Messaging. Without Firebase (a build without
/// `google-services.json`: `initPushFirebase` failed) every call is a
/// no-op, like [DefaultPushMessagingAdapter].
class FirebasePushTapSource implements PushTapSource {
  const FirebasePushTapSource();

  bool get _available => Firebase.apps.isNotEmpty;

  static NotificationModel _of(RemoteMessage m) =>
      NotificationModel.fromPushData(m.data,
          title: m.notification?.title ?? '', body: m.notification?.body ?? '');

  @override
  Future<NotificationModel?> initialTap() async {
    if (!_available) return null;
    try {
      final m = await FirebaseMessaging.instance.getInitialMessage();
      return m == null ? null : _of(m);
    } catch (e) {
      debugPrint('[FCM] getInitialMessage failed: $e');
      return null;
    }
  }

  @override
  void listen({
    required void Function(NotificationModel n) onOpened,
    required void Function(NotificationModel n) onForeground,
  }) {
    if (!_available) return;
    FirebaseMessaging.onMessageOpenedApp.listen((m) => onOpened(_of(m)));
    FirebaseMessaging.onMessage.listen((m) => onForeground(_of(m)));
  }
}

/// Holds push taps until a role shell can follow them (a cold-start tap
/// arrives before sign-in is restored), and pushes that arrive while the
/// app is open, for the shell to show.
class NotificationTapRouter extends ChangeNotifier {
  NotificationTapRouter({
    PushTapSource source = const FirebasePushTapSource(),
    this.display,
    this.onForeground,
  }) : _source = source;

  final PushTapSource _source;

  /// Shows a foreground push as a system notification on `qd_default`
  /// (PUSH-FCM); its taps come back here. Without one (tests, platforms
  /// without local notifications) the shell shows a notice instead.
  final LocalNotifier? display;

  /// Every foreground push, as it arrives (the in-app list and badge).
  final void Function(NotificationModel n)? onForeground;
  NotificationModel? _pendingTap;
  NotificationModel? _pendingForeground;
  bool _started = false;

  /// Reads the cold-start tap and listens for the next ones. Once.
  Future<void> start() async {
    if (_started) return;
    _started = true;
    _source.listen(onOpened: deliverTap, onForeground: deliverForeground);
    final initial = await _source.initialTap();
    if (initial != null) deliverTap(initial);
    final d = display;
    if (d != null) {
      // A tap on a foreground push we showed: running, or after the app
      // was killed meanwhile.
      final launch = await d.listenTaps((payload) {
        final n = decodePushPayload(payload);
        if (n != null) deliverTap(n);
      });
      final n = decodePushPayload(launch);
      if (n != null && initial == null) deliverTap(n);
    }
  }

  /// A tapped push (cold start or background): the shell follows it.
  void deliverTap(NotificationModel n) {
    _pendingTap = n;
    notifyListeners();
  }

  /// A push that arrived while the app is open: the shell shows it (a
  /// local notification, or a notice with a "View" action).
  void deliverForeground(NotificationModel n) {
    onForeground?.call(n);
    _pendingForeground = n;
    notifyListeners();
  }

  /// Takes the waiting tap (null when none).
  NotificationModel? takeTap() {
    final n = _pendingTap;
    _pendingTap = null;
    return n;
  }

  /// Takes the waiting foreground push (null when none).
  NotificationModel? takeForeground() {
    final n = _pendingForeground;
    _pendingForeground = null;
    return n;
  }
}

/// Provides the [NotificationTapRouter] above the navigator.
class NotificationTapScope extends InheritedWidget {
  const NotificationTapScope(
      {super.key, required this.router, required super.child});

  final NotificationTapRouter router;

  static NotificationTapRouter? maybeOf(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<NotificationTapScope>()
      ?.router;

  @override
  bool updateShouldNotify(NotificationTapScope oldWidget) =>
      router != oldWidget.router;
}
