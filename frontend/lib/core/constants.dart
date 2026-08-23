// Global constants for the Quick Delivery (qd) frontend client.

/// Fixed brand name constant used across all locales.
const String quickDeliveryAppName = 'Quick Delivery';

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

/// Map tile URL template configurable via compile-time environment variable MAP_TILE_URL.
/// Default: OpenStreetMap standard raster tiles.
/// Can be overridden for production to point to Carto Voyager raster tiles:
/// https://{s}.basemaps.cartocdn.com/rastertiles/voyager/{z}/{x}/{y}.png
const String mapTileUrlTemplate = String.fromEnvironment(
  'MAP_TILE_URL',
  defaultValue: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',
);

/// Custom User-Agent header required by OpenStreetMap tile usage policy.
const String mapTileUserAgent = String.fromEnvironment(
  'MAP_TILE_USER_AGENT',
  defaultValue: 'QuickDeliveryApp/1.0',
);

/// WebSocket Origin header required by chat-service's origin allow-list.
/// Configurable via compile-time environment variable CHAT_WS_ORIGIN so
/// production builds can be paired with the server's ALLOWED_ORIGIN setting;
/// defaults to the backend's own dev default.
const String chatWsOrigin = String.fromEnvironment(
  'CHAT_WS_ORIGIN',
  defaultValue: 'http://localhost:3000',
);
