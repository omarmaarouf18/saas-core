/// Global constants for the Quick Delivery (qd) frontend client.

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
