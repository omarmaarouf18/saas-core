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

  AndroidFlutterLocalNotificationsPlugin? get _androidPlugin =>
      _plugin.resolvePlatformSpecificImplementation<
          AndroidFlutterLocalNotificationsPlugin>();

  Future<bool> _init() => _initialized ??= () async {
        try {
          await _plugin.initialize(
            settings: const InitializationSettings(
              android: AndroidInitializationSettings(kPushSmallIcon),
            ),
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
