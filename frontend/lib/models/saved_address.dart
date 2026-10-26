/// A customer's saved place with coordinates (ADR-0028 §2.8,
/// USER-AUTH-BE item 5): `saved_addresses` on `GET /auth/user`, written with
/// `PATCH /auth/user` (the whole list). The server re-derives the legacy
/// `frequent_addresses` strings from it.
class SavedAddress {
  const SavedAddress({
    this.id = '',
    required this.label,
    required this.address,
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

    return SavedAddress(
      id: json['id']?.toString() ?? '',
      label: json['label']?.toString() ?? '',
      address: json['address']?.toString() ?? '',
      addressNote: json['address_note']?.toString() ?? '',
      latitude: coord(const ['latitude', 'lat']),
      longitude: coord(const ['longitude', 'lng', 'lon']),
    );
  }

  Map<String, dynamic> toJson() => {
        if (id.isNotEmpty) 'id': id,
        'label': label,
        'address': address,
        if (addressNote.isNotEmpty) 'address_note': addressNote,
        'latitude': latitude,
        'longitude': longitude,
      };

  SavedAddress copyWith({
    String? id,
    String? label,
    String? address,
    String? addressNote,
    double? latitude,
    double? longitude,
  }) =>
      SavedAddress(
        id: id ?? this.id,
        label: label ?? this.label,
        address: address ?? this.address,
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
      other.addressNote == addressNote &&
      other.latitude == latitude &&
      other.longitude == longitude;

  @override
  int get hashCode =>
      Object.hash(id, label, address, addressNote, latitude, longitude);

  @override
  String toString() => 'SavedAddress($id, $label, $address)';
}
