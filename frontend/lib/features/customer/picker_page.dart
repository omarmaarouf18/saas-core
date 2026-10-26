import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';

import '../../core/constants.dart';
import '../../core/text_limits.dart';
import '../../l10n/l10n.dart';
import '../../models/saved_address.dart';
import '../../providers/auth_provider.dart';
import '../../ui/qd_ui.dart';
import '../account/saved_address_rules.dart';
import 'customer_location.dart';

/// Max landmark note length, as the old picker dialog and the backend.
const int kAddressNoteMaxLength = kAddressNoteMaxRunes;

/// Supplies the map tile provider to [CustomerPickerPage] (default: network
/// tiles from `mapTileUrlTemplate`). Tests use it to avoid network tiles.
class CustomerMapTilesScope extends InheritedWidget {
  const CustomerMapTilesScope(
      {super.key, required this.tileProvider, required super.child});

  final TileProvider tileProvider;

  static TileProvider? of(BuildContext context) => context
      .dependOnInheritedWidgetOfExactType<CustomerMapTilesScope>()
      ?.tileProvider;

  @override
  bool updateShouldNotify(CustomerMapTilesScope oldWidget) =>
      tileProvider != oldWidget.tileProvider;
}

/// Full-screen location picker (A-Picker): the map moves under a fixed
/// centre pin, "my location" recentres it, optional address text (job
/// model v2, ≤ 250) and landmark note, and one confirm button that returns
/// a [PickedPlace].
///
/// Without an [initial] place it tries the device location first; when
/// location is denied or off it says so and the customer picks by hand.
///
/// With the address and note fields shown (booking stops), the customer's
/// saved places come first (FE-BE-GAPS, ADR-0028 §2.8): one tap moves the
/// pin there and fills the address text and the note. Old string-only
/// addresses (`frequent_addresses`) fill the text only; the customer still
/// has to move the pin.
class CustomerPickerPage extends StatefulWidget {
  const CustomerPickerPage({
    super.key,
    required this.title,
    this.initial,
    this.showNote = true,
  });

  final String title;
  final PickedPlace? initial;

  /// The marketplace search-area picker needs no address or landmark note.
  final bool showNote;

  /// Pushes the picker and returns the confirmed place, or null when the
  /// customer backs out.
  static Future<PickedPlace?> open(
    BuildContext context, {
    required String title,
    PickedPlace? initial,
    bool showNote = true,
  }) =>
      Navigator.of(context).push<PickedPlace>(MaterialPageRoute(
        builder: (_) => CustomerPickerPage(
            title: title, initial: initial, showNote: showNote),
      ));

  @override
  State<CustomerPickerPage> createState() => _CustomerPickerPageState();
}

class _CustomerPickerPageState extends State<CustomerPickerPage> {
  final MapController _map = MapController();
  late final TextEditingController _note;
  late final TextEditingController _address;
  late LatLng _center;
  bool _fromDevice = false;
  bool _locating = false;
  bool _denied = false;
  bool _mapReady = false;

  /// An old string-only address was chosen: it has no pin yet.
  bool _needsPin = false;

  @override
  void initState() {
    super.initState();
    final initial = widget.initial;
    _center = initial == null
        ? const LatLng(kDefaultLatitude, kDefaultLongitude)
        : LatLng(initial.latitude, initial.longitude);
    _fromDevice = initial?.isDeviceLocation ?? false;
    _note = TextEditingController(text: initial?.trimmedNote ?? '');
    _address = TextEditingController(text: initial?.trimmedAddress ?? '');
    if (initial == null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _locate());
    }
  }

  @override
  void dispose() {
    _note.dispose();
    _address.dispose();
    _map.dispose();
    super.dispose();
  }

  Future<void> _locate() async {
    if (_locating) return;
    setState(() => _locating = true);
    final result = await CustomerLocatorScope.of(context).locate();
    if (!mounted) return;
    setState(() {
      _locating = false;
      final place = result.place;
      if (place == null) {
        _denied = true;
        return;
      }
      _denied = false;
      _fromDevice = true;
      _center = LatLng(place.latitude, place.longitude);
    });
    if (_mapReady && result.place != null) {
      _map.move(_center, _map.camera.zoom);
    }
  }

  void _useSaved(SavedAddress a) {
    setState(() {
      _center = LatLng(a.latitude, a.longitude);
      _fromDevice = false;
      _needsPin = false;
      _address.text = a.address;
      _note.text = a.addressNote;
    });
    if (_mapReady) _map.move(_center, _map.camera.zoom);
  }

  void _useLegacy(String text) {
    setState(() {
      _address.text = text;
      _needsPin = true;
    });
  }

  void _confirm() {
    Navigator.of(context).pop(PickedPlace(
      latitude: _center.latitude,
      longitude: _center.longitude,
      note: widget.showNote ? _note.text.trim() : null,
      address: widget.showNote ? _address.text.trim() : null,
      isDeviceLocation: _fromDevice,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return Scaffold(
      backgroundColor: c.fillMuted,
      body: Column(
        children: [
          Expanded(
            child: Stack(
              children: [
                Positioned.fill(
                  child: Semantics(
                    label: widget.title,
                    child: FlutterMap(
                      mapController: _map,
                      options: MapOptions(
                        initialCenter: _center,
                        initialZoom: 15,
                        onMapReady: () => _mapReady = true,
                        onPositionChanged: (camera, hasGesture) {
                          if (!hasGesture) return;
                          _center = camera.center;
                          _fromDevice = false;
                          // The customer moved the pin: it is placed now.
                          if (_needsPin) setState(() => _needsPin = false);
                        },
                      ),
                      children: [
                        TileLayer(
                          tileProvider: CustomerMapTilesScope.of(context),
                          urlTemplate: mapTileUrlTemplate,
                          userAgentPackageName: mapTileUserAgent,
                          errorTileCallback: (tile, error, stackTrace) {},
                        ),
                      ],
                    ),
                  ),
                ),
                // The pin's tip sits on the map centre.
                const Positioned.fill(
                  child: IgnorePointer(
                    child: Center(
                      child: Padding(
                        padding: EdgeInsets.only(bottom: QdMapPin.height),
                        child: QdMapPin(key: Key('cust_picker_pin')),
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  top: 0,
                  start: 0,
                  end: 0,
                  child: SafeArea(
                    bottom: false,
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          QdSpace.x3, QdSpace.x3, QdSpace.x3, 0),
                      child: Row(
                        children: [
                          QdIconButton(
                            key: const Key('cust_picker_back'),
                            icon: Icons.arrow_back,
                            label: MaterialLocalizations.of(context)
                                .backButtonTooltip,
                            round: true,
                            onPressed: () => Navigator.of(context).maybePop(),
                          ),
                          const SizedBox(width: QdSpace.x2),
                          Flexible(child: QdMapLabel(label: widget.title)),
                        ],
                      ),
                    ),
                  ),
                ),
                PositionedDirectional(
                  end: QdSpace.x3,
                  bottom: QdSpace.x4,
                  child: QdIconButton(
                    key: const Key('cust_picker_my_location'),
                    icon: Icons.my_location,
                    label: l10n.custMyLocation,
                    round: true,
                    loading: _locating,
                    onPressed: _locate,
                  ),
                ),
              ],
            ),
          ),
          QdDockedPanel(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              mainAxisSize: MainAxisSize.min,
              children: [
                if (_denied) ...[
                  QdBanner(
                    key: const Key('cust_picker_denied'),
                    tone: QdBannerTone.warning,
                    icon: Icons.location_off_outlined,
                    message: l10n.custLocationDenied,
                    actionLabel: l10n.retry,
                    onAction: _locate,
                  ),
                  const SizedBox(height: QdSpace.x3),
                ],
                if (widget.showNote) ..._savedPlaces(context),
                Text(
                  l10n.custPickerHint,
                  style: QdText.body.copyWith(color: c.textSecondary),
                ),
                if (widget.showNote) ...[
                  const SizedBox(height: 14),
                  QdTextField(
                    key: const Key('cust_picker_address'),
                    label: l10n.bookAddressLabel,
                    hint: l10n.bookAddressHint,
                    controller: _address,
                    textInputAction: TextInputAction.next,
                    maxRunes: kAddressTextMaxRunes,
                  ),
                  const SizedBox(height: QdSpace.x3),
                  QdTextField(
                    key: const Key('cust_picker_note'),
                    label: l10n.custNoteLabel,
                    hint: l10n.custNoteHint,
                    controller: _note,
                    textInputAction: TextInputAction.done,
                    maxRunes: kAddressNoteMaxRunes,
                  ),
                ],
                const SizedBox(height: 14),
                QdButton(
                  key: const Key('cust_picker_confirm'),
                  label: l10n.custConfirmPlace,
                  fullWidth: true,
                  onPressed: _confirm,
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  /// "Saved places": the customer's saved addresses, then old
  /// string-only ones. Empty when there are none.
  List<Widget> _savedPlaces(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final user = Provider.of<AuthProvider?>(context)?.user;
    final saved = user?.savedAddresses ?? const <SavedAddress>[];
    final legacy = legacyAddressesOf(user);
    if (saved.isEmpty && legacy.isEmpty) return const [];
    Widget chip(Key key, IconData icon, String label, String semantic,
            VoidCallback onTap) =>
        Padding(
          padding: const EdgeInsetsDirectional.only(end: QdSpace.x2),
          child: Semantics(
            button: true,
            label: semantic,
            excludeSemantics: true,
            child: ActionChip(
              key: key,
              avatar: Icon(icon, size: 18, color: c.textPrimary),
              label: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 160),
                child: Text(label,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: QdText.secondary.copyWith(color: c.textPrimary)),
              ),
              backgroundColor: c.surface,
              side: BorderSide(color: c.borderInput),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(QdRadius.pill)),
              onPressed: onTap,
            ),
          ),
        );
    return [
      Text(l10n.custSavedPlaces,
          style: QdText.secondary
              .copyWith(color: c.textSecondary, fontWeight: FontWeight.w600)),
      const SizedBox(height: QdSpace.x2),
      SingleChildScrollView(
        key: const Key('cust_picker_saved'),
        scrollDirection: Axis.horizontal,
        child: Row(children: [
          for (var i = 0; i < saved.length; i++)
            chip(
              Key('cust_picker_saved_$i'),
              savedLabelKindOf(saved[i].label) == SavedLabelKind.work
                  ? Icons.work_outline
                  : savedLabelKindOf(saved[i].label) == SavedLabelKind.home
                      ? Icons.home_outlined
                      : Icons.location_on_outlined,
              savedLabelText(l10n, saved[i].label),
              l10n.custSavedUse(
                  savedLabelText(l10n, saved[i].label), saved[i].address),
              () => _useSaved(saved[i]),
            ),
          for (var i = 0; i < legacy.length; i++)
            chip(
              Key('cust_picker_legacy_$i'),
              Icons.location_off_outlined,
              legacy[i],
              l10n.custSavedUse(legacy[i], l10n.custSavedNeedsPin),
              () => _useLegacy(legacy[i]),
            ),
        ]),
      ),
      if (_needsPin) ...[
        const SizedBox(height: QdSpace.x2),
        QdBanner(
          key: const Key('cust_picker_needs_pin'),
          tone: QdBannerTone.warning,
          icon: Icons.push_pin_outlined,
          message: l10n.custSavedNeedsPin,
        ),
      ],
      const SizedBox(height: 14),
    ];
  }
}
