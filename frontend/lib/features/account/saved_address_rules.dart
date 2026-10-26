import '../../core/text_limits.dart';
import '../../l10n/app_localizations.dart';
import '../../models/saved_address.dart';
import '../../models/user_profile.dart';

/// Rules for saved addresses (ADR-0028 §2.8; auth-service `UpdateUser`
/// `saved_addresses` checks): at most 10, an address (≤ 250 characters),
/// a label (≤ 100), a landmark note (≤ 500), coordinates in range. The
/// server lets the label be empty; the app always sends one ("Home",
/// "Work" or the customer's word) so the booking list can name it.

/// Most addresses the server keeps.
const int kMaxSavedAddresses = 10;

enum SavedLabelKind { home, work, other }

/// The kind of a stored label. "Home" / "Work" are stored in English and
/// shown in the app language; the Arabic words count too (the server
/// documents them as examples).
SavedLabelKind savedLabelKindOf(String label) =>
    switch (label.trim().toLowerCase()) {
      'home' || 'البيت' || 'بيت' => SavedLabelKind.home,
      'work' || 'الشغل' || 'شغل' => SavedLabelKind.work,
      _ => SavedLabelKind.other,
    };

/// The label to store for [kind]; [custom] for [SavedLabelKind.other].
String savedLabelValue(SavedLabelKind kind, String custom) => switch (kind) {
      SavedLabelKind.home => 'Home',
      SavedLabelKind.work => 'Work',
      SavedLabelKind.other => custom.trim(),
    };

/// The label as shown: "Home" / "Work" in the app language, else as typed.
String savedLabelText(AppLocalizations l10n, String label) =>
    switch (savedLabelKindOf(label)) {
      SavedLabelKind.home => l10n.addrLabelHome,
      SavedLabelKind.work => l10n.addrLabelWork,
      SavedLabelKind.other =>
        label.trim().isEmpty ? l10n.addrLabelOther : label.trim(),
    };

class SavedAddressProblems {
  const SavedAddressProblems({
    this.labelMissing = false,
    this.labelTooLong = false,
    this.addressMissing = false,
    this.addressTooLong = false,
    this.noteTooLong = false,
    this.pinMissing = false,
  });

  final bool labelMissing;
  final bool labelTooLong;
  final bool addressMissing;
  final bool addressTooLong;
  final bool noteTooLong;
  final bool pinMissing;

  bool get any =>
      labelMissing ||
      labelTooLong ||
      addressMissing ||
      addressTooLong ||
      noteTooLong ||
      pinMissing;
}

bool validCoordinates(double lat, double lng) =>
    lat >= -90 && lat <= 90 && lng >= -180 && lng <= 180;

/// Every problem of one entry, counted in characters (runes), the way the
/// server counts.
SavedAddressProblems validateSavedAddress({
  required String label,
  required String address,
  required String note,
  required double? latitude,
  required double? longitude,
}) {
  final l = label.trim();
  final a = address.trim();
  final n = note.trim();
  return SavedAddressProblems(
    labelMissing: l.isEmpty,
    labelTooLong: runeLength(l) > kNameMaxRunes,
    addressMissing: a.isEmpty,
    addressTooLong: runeLength(a) > kAddressTextMaxRunes,
    noteTooLong: runeLength(n) > kAddressNoteMaxRunes,
    pinMissing: latitude == null ||
        longitude == null ||
        !validCoordinates(latitude, longitude),
  );
}

/// Old string-only addresses (`frequent_addresses`) that no saved address
/// covers: accounts from before saved addresses. They have no coordinates,
/// so they must be pinned before they can fill a booking.
List<String> legacyAddressesOf(UserProfile? user) {
  if (user == null) return const [];
  final covered = {for (final s in user.savedAddresses) s.address.trim()};
  final seen = <String>{};
  return [
    for (final raw in user.frequentAddresses ?? const <String>[])
      if (raw.trim().isNotEmpty &&
          !covered.contains(raw.trim()) &&
          seen.add(raw.trim()))
        raw.trim(),
  ];
}

/// [list] with [entry] added (at the end) or replacing index [at].
List<SavedAddress> withSaved(List<SavedAddress> list, SavedAddress entry,
    {int? at}) {
  final next = List.of(list);
  if (at == null) {
    next.add(entry);
  } else {
    next[at] = entry;
  }
  return next;
}
