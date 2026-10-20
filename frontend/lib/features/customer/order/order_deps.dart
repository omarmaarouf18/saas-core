import 'package:flutter/widgets.dart';
import 'package:provider/provider.dart';

import '../../../providers/auth_provider.dart';

/// Resolves a courier's display name, the way the old JobStatusScreen did:
/// `GET /auth/user/public-profile?id=<id>&requester_id=<token>` (any
/// signed-in user may read another user's username there). Null when it
/// cannot be resolved; the page then shows a generic "Your courier".
/// Swappable through [CourierLookupScope] for tests.
class CourierLookup {
  const CourierLookup();

  Future<String?> nameOf(BuildContext context, String userId) async {
    final auth = context.read<AuthProvider>();
    final token = auth.token;
    if (token == null || userId.isEmpty) return null;
    try {
      final res = await auth.apiClient.get(
        '/auth/user/public-profile',
        queryParams: {'id': userId, 'requester_id': token},
      );
      if (res is Map && res['username'] is String) {
        final name = (res['username'] as String).trim();
        return name.isEmpty ? null : name;
      }
    } catch (_) {
      // Graceful fallback, as before: the generic courier label.
    }
    return null;
  }
}

class CourierLookupScope extends InheritedWidget {
  const CourierLookupScope(
      {super.key, required this.lookup, required super.child});

  final CourierLookup lookup;

  /// Reads without subscribing, so it can be called from initState.
  static CourierLookup of(BuildContext context) =>
      context.getInheritedWidgetOfExactType<CourierLookupScope>()?.lookup ??
      const CourierLookup();

  @override
  bool updateShouldNotify(CourierLookupScope oldWidget) =>
      lookup != oldWidget.lookup;
}
