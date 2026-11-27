// Global constants for the Waddify (qd) frontend client.

/// Fixed brand name constant used across all locales.
const String quickDeliveryAppName = 'Waddify';

/// Map of backend service category keys to client-facing UI labels.
/// - 'transport' maps to "Ride" (representing passenger ride-hailing / travel).
/// - 'delivery' maps to "Delivery".
/// - 'shipping' maps to "Shipping".
///
/// NOTE: A 4th service category for cargo/goods transport (distinct from passenger 'Ride')
/// is deferred and not scoped for the current launch. If added later, it will require a
/// backend category value distinct from 'transport' to avoid ambiguity.
const Map<String, String> serviceCategoryLabels = {
  'delivery': 'Delivery',
  'transport': 'Ride',
  'shipping': 'Shipping',
};

/// Optional WebSocket Origin header for browser-hosted web builds.
/// Non-browser clients (dart:io WebSocket on Android/iOS) send no Origin header
/// by default, which chat-service admits without CSRF gating.
/// If CHAT_WS_ORIGIN is provided via --dart-define, it is passed explicitly.
const String chatWsOrigin = String.fromEnvironment(
  'CHAT_WS_ORIGIN',
  defaultValue: '',
);
