import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';

import '../l10n/l10n.dart';

/// The Android notification channel every push names
/// (notification-service `fcm.DefaultAndroidChannelID`, PUSH-BE). The app
/// creates it at startup; the manifest also names it as the Firebase
/// default.
const String kPushChannelId = 'qd_default';

/// The small icon (white silhouette) in `android/app/src/main/res/drawable`.
const String kPushSmallIcon = 'ic_stat_notification';

/// Notifications the app shows itself (the `qd_default` channel). Tests
/// swap it.
abstract class LocalNotifier {
  /// Creates the `qd_default` channel, or renames it (a channel's
  /// importance is fixed once created; its name and description follow the
  /// app language). False where there are no channels or it failed.
  Future<bool> ensureChannel(
      {required String name, required String description});

  /// Opens the phone's notification settings for this app. False where it
  /// cannot.
  Future<bool> openAppSettings();

  /// Shows a notification on `qd_default` now (a push that arrived while
  /// the app is open: FCM shows nothing then). False where it cannot.
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  });

  /// Calls [onTap] with the payload of a notification from [show] that is
  /// tapped while the app runs; returns the payload of the one that
  /// launched the app (it was killed meanwhile), if any.
  Future<String?> listenTaps(void Function(String payload) onTap);
}

/// [flutter_local_notifications] on Android; a no-op elsewhere (iOS has no
/// channels, desktop and web have no push).
class PluginLocalNotifier implements LocalNotifier {
  PluginLocalNotifier({FlutterLocalNotificationsPlugin? plugin, bool? android})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin(),
        _android = android ??
            (!kIsWeb && defaultTargetPlatform == TargetPlatform.android);

  final FlutterLocalNotificationsPlugin _plugin;
  final bool _android;
  Future<bool>? _initialized;
  void Function(String payload)? _onTap;

  /// The channel's current (localized) name and description, also given
  /// with each notification in case the channel is missing.
  String _channelName = 'Order updates';
  String? _channelDescription;

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> _init() => _initialized ??= () async {
        try {
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings(kPushSmallIcon),
            ),
            onDidReceiveNotificationResponse: (r) {
              final payload = r.payload;
              if (payload != null && payload.isNotEmpty) {
                _onTap?.call(payload);
              }
            },
          );
          return true;
        } catch (e) {
          debugPrint('[PUSH] local notifications unavailable: $e');
          return false;
        }
      }();

  @override
  Future<bool> ensureChannel(
      {required String name, required String description}) async {
    if (!_android || !await _init()) return false;
    _channelName = name;
    _channelDescription = description;
    try {
      await _androidPlugin?.createNotificationChannel(
        AndroidNotificationChannel(
          kPushChannelId,
          name,
          description: description,
          importance: Importance.high,
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[PUSH] notification channel not created: $e');
      return false;
    }
  }

  @override
  Future<bool> show({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
    if (!_android || !await _init()) return false;
    try {
      await _plugin.show(
        id: id,
        title: title,
        body: body,
        payload: payload,
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            kPushChannelId,
            _channelName,
            channelDescription: _channelDescription,
            importance: Importance.high,
            priority: Priority.high,
            icon: kPushSmallIcon,
            color: const Color(0xFFFFC107), // QdColors.gold
          ),
        ),
      );
      return true;
    } catch (e) {
      debugPrint('[PUSH] foreground notification not shown: $e');
      return false;
    }
  }

  @override
  Future<String?> listenTaps(void Function(String payload) onTap) async {
    _onTap = onTap;
    if (!_android || !await _init()) return null;
    try {
      final launch = await _plugin.getNotificationAppLaunchDetails();
      if (launch?.didNotificationLaunchApp != true) return null;
      return launch?.notificationResponse?.payload;
    } catch (e) {
      debugPrint('[PUSH] launch notification not read: $e');
      return null;
    }
  }

  @override
  Future<bool> openAppSettings() async {
    if (!_android) return false;
    try {
      return await _androidPlugin?.openAppNotificationSettings() ?? false;
    } catch (e) {
      debugPrint('[PUSH] notification settings not opened: $e');
      return false;
    }
  }
}

/// Keeps the `qd_default` channel's name and description in the app
/// language: creates the channel on the first frame (startup) and renames
/// it when the language changes. Place it below the app's Localizations.
class PushChannelSync extends StatefulWidget {
  const PushChannelSync(
      {super.key, required this.notifier, required this.child});

  final LocalNotifier notifier;
  final Widget child;

  @override
  State<PushChannelSync> createState() => _PushChannelSyncState();
}

class _PushChannelSyncState extends State<PushChannelSync> {
  String? _synced;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final l10n = context.l10n;
    final name = l10n.pushChannelName;
    final description = l10n.pushChannelDescription;
    final key = '$name\n$description';
    if (key == _synced) return;
    _synced = key;
    widget.notifier.ensureChannel(name: name, description: description);
  }

  @override
  Widget build(BuildContext context) => widget.child;
}
