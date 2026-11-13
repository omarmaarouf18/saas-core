/// A customer's saved place with coordinates (ADR-0028 §2.8,
/// USER-AUTH-BE item 5): `saved_addresses` on `GET /auth/user`, written with
/// `PATCH /auth/user` (the whole list). The server re-derives the legacy
/// `frequent_addresses` strings from it.
class SavedAddress {
  const SavedAddress({
    this.id = '',
    required this.label,
    required this.address,
    this.building,
    this.floor,
    this.apartment,
    this.addressNote = '',
    required this.latitude,
    required this.longitude,
  });

  /// Server id (`addr_…`); empty for a new entry, the server assigns one.
  final String id;

  /// "Home", "Work" or the customer's own word.
  final String label;

  /// Street / building / area (≤ 250 characters).
  final String address;

  /// Structured address details (ADDR-REQUIRED). Optional.
  final String? building;
  final String? floor;
  final String? apartment;

  /// Landmark note (≤ 500 characters).
  final String addressNote;
  final double latitude;
  final double longitude;

  /// Reads `latitude` / `longitude`, or the `lat` / `lng` (`lon`) aliases
  /// the server also accepts and returns.
  factory SavedAddress.fromJson(Map<String, dynamic> json) {
    double coord(List<String> keys) {
      for (final k in keys) {
        final v = json[k];
        if (v is num) return v.toDouble();
      }
      return 0;
    }

    String? optText(Object? v) {
      if (v is! String) return null;
      final t = v.trim();
      return t.isEmpty ? null : t;
    }

    return SavedAddress(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      building: optText(json['building']),
      floor: optText(json['floor']),
      apartment: optText(json['apartment']),
      addressNote: json['address_note']?.toString() ?? '',
      latitude: coord(const ['latitude', 'lat']),
      longitude: coord(const ['longitude', 'lng', 'lon']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'label': label,
        'address': address,
        if (building != null && building!.isNotEmpty) 'building': building,
        if (floor != null && floor!.isNotEmpty) 'floor': floor,
        if (apartment != null && apartment!.isNotEmpty) 'apartment': apartment,
        if (addressNote.isNotEmpty) 'address_note': addressNote,
        'latitude': latitude,
        'longitude': longitude,
      };

  SavedAddress copyWith({
    String? id,
    String? label,
    String? address,
    String? building,
    String? floor,
    String? apartment,
    String? addressNote,
    double? latitude,
    double? longitude,
  }) =>
      SavedAddress(
        id: id ?? this.id,
        label: label ?? this.label,
        address: address ?? this.address,
        building: building ?? this.building,
        floor: floor ?? this.floor,
        apartment: apartment ?? this.apartment,
        addressNote: addressNote ?? this.addressNote,
        latitude: latitude ?? this.latitude,
        longitude: longitude ?? this.longitude,
      );

  @override
  bool operator ==(Object other) =>
      other is SavedAddress &&
      other.id == id &&
      other.label == label &&
      other.address == address &&
      other.building == building &&
      other.floor == floor &&
      other.apartment == apartment &&
      other.addressNote == addressNote &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode => Object.hash(id, label, address, building, floor,
      apartment, addressNote, latitude, longitude);

  @override
  String toString() => 'SavedAddress($id, $label, $address)';
}
