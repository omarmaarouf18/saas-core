import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../core/text_limits.dart';
import '../../l10n/l10n.dart';
import '../../models/saved_address.dart';
import '../../providers/auth_provider.dart';
import '../../ui/qd_ui.dart';
import '../customer/customer_location.dart';
import '../customer/picker_page.dart';
import 'account_nav.dart';
import 'account_page.dart';
import 'saved_address_rules.dart';

export 'saved_address_rules.dart' show kMaxSavedAddresses;

/// Opens the map picker for a saved address and returns the pinned place
/// (null when the customer backs out). Swapped in tests.
typedef SavedAddressPinPicker = Future<PickedPlace?> Function(
    BuildContext context, PickedPlace? initial);

Future<PickedPlace?> _defaultPinPicker(
        BuildContext context, PickedPlace? initial) =>
    CustomerPickerPage.open(context,
        title: context.l10n.addrPinTitle, initial: initial, showNote: false);

/// Saved addresses (ADR-0028 §2.8): the profile's `saved_addresses`, each
/// with a label (Home / Work / the customer's word), the address text, a
/// landmark note and a map pin, so booking can fill a stop in one tap.
///
/// Kept from the first version: at most 10, delete with undo, read-only
/// while suspended, every change saved right away (PATCH the whole list)
/// and a failed save restores the list with the error and retry.
/// New: the editor page with the label choice and the map pin; old
/// string-only addresses (`frequent_addresses` with no saved entry) are
/// listed apart and can be pinned. The server rebuilds
/// `frequent_addresses` from the saved list, so writing it drops the
/// unpinned old ones: the page asks first.
class SavedAddressesPage extends StatefulWidget {
  const SavedAddressesPage({super.key, this.pickPin});

  /// Map picker (tests); default: the redesigned picker.
  final SavedAddressPinPicker? pickPin;

  @override
  State<SavedAddressesPage> createState() => _SavedAddressesPageState();
}

class _SavedAddressesPageState extends State<SavedAddressesPage> {
  late List<SavedAddress> _saved =
      List.of(context.read<AuthProvider>().user?.savedAddresses ?? const []);
  bool _saving = false;
  String? _error;
  List<SavedAddress>? _failed;

  /// Saves [next]; on failure keeps the previous list. [keepLegacy] is the
  /// old address being pinned (it is not dropped). Returns success.
  Future<bool> _commit(List<SavedAddress> next,
      {String? keepLegacy, bool confirmed = false}) async {
    final auth = context.read<AuthProvider>();
    final dropped =
        legacyAddressesOf(auth.user).where((a) => a != keepLegacy).toList();
    if (dropped.isNotEmpty && !confirmed && !await _confirmDrop(dropped)) {
      return false;
    }
    if (!mounted) return false;
    final previous = _saved;
    setState(() {
      _saved = next;
      _saving = true;
      _error = null;
    });
    try {
      await auth.updateOwnProfile(savedAddresses: next);
      if (mounted) {
        setState(() {
          _failed = null;
          // The server assigns ids to new entries.
          _saved = List.of(auth.user?.savedAddresses ?? next);
        });
      }
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _saved = previous;
          _failed = next;
          _error = auth.error ?? friendlyErrorMessage(e);
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<bool> _confirmDrop(List<String> dropped) async {
    final l10n = context.l10n;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final c = QdColors.of(ctx);
        return AlertDialog(
          key: const Key('addresses_drop_dialog'),
          backgroundColor: c.surface,
          title: Text(l10n.addrDropLegacyTitle,
              style: QdText.header.copyWith(color: c.textPrimary)),
          content: Text(l10n.addrDropLegacyBody(dropped.length),
              style: QdText.body.copyWith(color: c.textSecondary)),
          actions: [
            QdButton.text(
              key: const Key('addresses_drop_cancel'),
              label: l10n.acctCancel,
              small: true,
              onPressed: () => Navigator.of(ctx).pop(false),
            ),
            QdButton.destructive(
              key: const Key('addresses_drop_confirm'),
              label: l10n.addrDropLegacyConfirm,
              small: true,
              onPressed: () => Navigator.of(ctx).pop(true),
            ),
          ],
        );
      },
    );
    return ok == true;
  }

  Future<void> _edit({int? index, String? legacy}) async {
    final l10n = context.l10n;
    final current = index == null ? null : _saved[index];
    final entry = await Navigator.of(context).push<SavedAddress>(
      MaterialPageRoute(
        builder: (_) => SavedAddressEditorPage(
          title: index == null ? l10n.acctAddAddress : l10n.acctEditAddress,
          initial: current,
          initialAddress: legacy,
          pickPin: widget.pickPin ?? _defaultPinPicker,
        ),
      ),
    );
    if (entry == null || !mounted || entry == current) return;
    await _commit(withSaved(_saved, entry, at: index), keepLegacy: legacy);
  }

  Future<void> _delete(int index) async {
    final removed = _saved[index];
    final next = List.of(_saved)..removeAt(index);
    if (!await _commit(next) || !mounted) return;
    final l10n = context.l10n;
    showAccountNotice(
      context,
      l10n.acctAddressDeleted,
      actionLabel: l10n.acctUndo,
      onAction: () {
        if (!mounted) return;
        final back = List.of(_saved);
        back.insert(index.clamp(0, back.length), removed);
        _commit(back, confirmed: true);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final user = context.watch<AuthProvider>().user;
    final suspended = user?.isSuspended ?? false;
    final legacy = legacyAddressesOf(user);
    final full = _saved.length >= kMaxSavedAddresses;
    final enabled = !suspended && !_saving;

    return Scaffold(
      backgroundColor: c.surface,
      appBar: accountAppBar(context, l10n.acctSavedAddresses),
      body: ListView(
        key: const Key('addresses_list'),
        padding: const EdgeInsets.fromLTRB(
            QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x6),
        children: [
          if (suspended) ...[
            SuspendedBanner(user: user!),
            const SizedBox(height: QdSpace.x4),
          ],
          if (_error != null) ...[
            QdBanner(
              key: const Key('addresses_error'),
              tone: QdBannerTone.danger,
              icon: Icons.error_outline,
              message: _error!,
              actionLabel: _failed == null ? null : l10n.retry,
              onAction: _failed == null
                  ? null
                  : () => _commit(_failed!, confirmed: true),
            ),
            const SizedBox(height: QdSpace.x4),
          ],
          if (_saved.isEmpty && legacy.isEmpty)
            QdEmptyState(
              key: const Key('addresses_empty'),
              icon: Icons.location_on_outlined,
              title: l10n.acctAddressesEmpty,
              body: l10n.acctAddressesEmptyBody,
            )
          else if (_saved.isNotEmpty)
            QdListGroup(children: [
              for (var i = 0; i < _saved.length; i++)
                _SavedRow(
                  key: Key('address_$i'),
                  entry: _saved[i],
                  enabled: enabled,
                  onEdit: () => _edit(index: i),
                  onDelete: () => _delete(i),
                ),
            ]),
          if (legacy.isNotEmpty) ...[
            const SizedBox(height: QdSpace.x5),
            Semantics(
              header: true,
              child: Text(l10n.addrLegacyTitle,
                  style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
            ),
            const SizedBox(height: QdSpace.x1),
            Text(l10n.addrLegacyBody,
                style: QdText.secondary.copyWith(color: c.textSecondary)),
            const SizedBox(height: QdSpace.x3),
            QdListGroup(children: [
              for (var i = 0; i < legacy.length; i++)
                _LegacyRow(
                  key: Key('address_legacy_$i'),
                  text: legacy[i],
                  enabled: enabled && !full,
                  onPin: () => _edit(legacy: legacy[i]),
                ),
            ]),
          ],
          const SizedBox(height: QdSpace.x3),
          Text(
            '${l10n.acctAddressCount(_saved.length)} · '
            '${l10n.acctAddressesNote}',
            style: QdText.caption.copyWith(color: c.textSecondary),
          ),
          if (full) ...[
            const SizedBox(height: QdSpace.x1),
            Text(l10n.acctAddressMax,
                key: const Key('addresses_full'),
                style: QdText.caption.copyWith(color: c.warning)),
          ],
          const SizedBox(height: QdSpace.x5),
          QdButton.secondary(
            key: const Key('addresses_add'),
            label: l10n.acctAddAddress,
            icon: Icons.add,
            loading: _saving,
            fullWidth: true,
            onPressed: suspended || full ? null : () => _edit(),
          ),
        ],
      ),
    );
  }
}

IconData savedLabelIcon(String label) => switch (savedLabelKindOf(label)) {
      SavedLabelKind.home => Icons.home_outlined,
      SavedLabelKind.work => Icons.work_outline,
      SavedLabelKind.other => Icons.location_on_outlined,
    };

class _SavedRow extends StatelessWidget {
  const _SavedRow({
    super.key,
    required this.entry,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  final SavedAddress entry;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final label = savedLabelText(l10n, entry.label);
    final note = entry.addressNote.trim();
    return InkWell(
      onTap: enabled ? onEdit : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: QdSize.listRow),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(
              start: 14, end: 4, top: QdSpace.x2, bottom: QdSpace.x2),
          child: Row(
            children: [
              Icon(savedLabelIcon(entry.label),
                  size: QdSize.icon, color: c.textPrimary),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: Semantics(
                  button: enabled,
                  hint: l10n.acctEditAddress,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(label,
                          style:
                              QdText.rowTitleSm.copyWith(color: c.textPrimary)),
                      Text(entry.address,
                          style: QdText.secondary
                              .copyWith(color: c.textSecondary)),
                      if (note.isNotEmpty)
                        Text(note,
                            maxLines: 2,
                            overflow: TextOverflow.ellipsis,
                            style: QdText.caption
                                .copyWith(color: c.textSecondary)),
                    ],
                  ),
                ),
              ),
              IconButton(
                key: const Key('address_delete'),
                tooltip: l10n.acctDeleteAddress(label),
                onPressed: enabled ? onDelete : null,
                icon: Icon(Icons.delete_outline,
                    size: QdSize.icon, color: enabled ? c.danger : c.border),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LegacyRow extends StatelessWidget {
  const _LegacyRow({
    super.key,
    required this.text,
    required this.enabled,
    required this.onPin,
  });

  final String text;
  final bool enabled;
  final VoidCallback onPin;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return ConstrainedBox(
      constraints: const BoxConstraints(minHeight: QdSize.listRow),
      child: Padding(
        padding: const EdgeInsetsDirectional.only(start: 14, end: 8),
        child: Row(
          children: [
            Icon(Icons.location_off_outlined,
                size: QdSize.icon, color: c.textSecondary),
            const SizedBox(width: QdSpace.x3),
            Expanded(
              child: Text(text,
                  style:
                      QdText.body.copyWith(fontSize: 15, color: c.textPrimary)),
            ),
            Semantics(
              label: l10n.addrLegacyPinFor(text),
              excludeSemantics: true,
              button: true,
              child: QdButton.text(
                key: const Key('address_legacy_pin'),
                label: l10n.addrLegacyPin,
                small: true,
                onPressed: enabled ? onPin : null,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Add / edit one saved address: label (Home / Work / a custom name), the
/// address text, the landmark note and the map pin. Returns the entry
/// (with its id kept) or null when closed.
class SavedAddressEditorPage extends StatefulWidget {
  const SavedAddressEditorPage({
    super.key,
    required this.title,
    required this.pickPin,
    this.initial,
    this.initialAddress,
  });

  final String title;
  final SavedAddressPinPicker pickPin;
  final SavedAddress? initial;

  /// An old string-only address being pinned.
  final String? initialAddress;

  @override
  State<SavedAddressEditorPage> createState() => _SavedAddressEditorState();
}

class _SavedAddressEditorState extends State<SavedAddressEditorPage> {
  late SavedLabelKind _kind = widget.initial == null
      ? SavedLabelKind.home
      : savedLabelKindOf(widget.initial!.label);
  late final _custom = TextEditingController(
      text: _kind == SavedLabelKind.other ? widget.initial?.label : '');
  late final _address = TextEditingController(
      text: widget.initial?.address ?? widget.initialAddress ?? '');
  late final _note =
      TextEditingController(text: widget.initial?.addressNote ?? '');
  late double? _lat = widget.initial?.latitude;
  late double? _lng = widget.initial?.longitude;
  bool _tried = false;

  @override
  void dispose() {
    _custom.dispose();
    _address.dispose();
    _note.dispose();
    super.dispose();
  }

  String get _label => savedLabelValue(_kind, _custom.text);

  SavedAddressProblems get _problems => validateSavedAddress(
        label: _label,
        address: _address.text,
        note: _note.text,
        latitude: _lat,
        longitude: _lng,
      );

  Future<void> _pin() async {
    final initial = _lat == null || _lng == null
        ? null
        : PickedPlace(latitude: _lat!, longitude: _lng!);
    final place = await widget.pickPin(context, initial);
    if (place == null || !mounted) return;
    setState(() {
      _lat = place.latitude;
      _lng = place.longitude;
    });
  }

  void _save() {
    setState(() => _tried = true);
    if (_problems.any) return;
    Navigator.of(context).pop(SavedAddress(
      id: widget.initial?.id ?? '',
      label: _label,
      address: _address.text.trim(),
      addressNote: _note.text.trim(),
      latitude: _lat!,
      longitude: _lng!,
    ));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final p = _tried ? _problems : const SavedAddressProblems();
    const gap = SizedBox(height: QdSpace.x4);
    return Scaffold(
      key: const Key('address_editor'),
      backgroundColor: c.surface,
      appBar: accountAppBar(context, widget.title),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(
            QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x6),
        children: [
          Text(l10n.addrLabelTitle,
              style: QdText.body
                  .copyWith(color: c.textPrimary, fontWeight: FontWeight.w500)),
          const SizedBox(height: QdSpace.x2),
          QdChoiceChips<SavedLabelKind>(
            key: const Key('address_label_kind'),
            semanticLabel: l10n.addrLabelTitle,
            selected: _kind,
            onChanged: (k) => setState(() => _kind = k),
            choices: [
              QdChoice(value: SavedLabelKind.home, label: l10n.addrLabelHome),
              QdChoice(value: SavedLabelKind.work, label: l10n.addrLabelWork),
              QdChoice(value: SavedLabelKind.other, label: l10n.addrLabelOther),
            ],
          ),
          if (_kind == SavedLabelKind.other) ...[
            const SizedBox(height: QdSpace.x3),
            QdTextField(
              key: const Key('address_label_custom'),
              label: l10n.addrLabelCustom,
              hint: l10n.addrLabelCustomHint,
              controller: _custom,
              maxRunes: kNameMaxRunes,
              textInputAction: TextInputAction.next,
              errorText: p.labelMissing
                  ? l10n.addrErrLabel
                  : p.labelTooLong
                      ? l10n.addrErrTooLong(kNameMaxRunes)
                      : null,
              onChanged: (_) => setState(() {}),
            ),
          ],
          gap,
          QdTextField(
            key: const Key('address_input'),
            label: l10n.acctAddressLabel,
            hint: l10n.acctAddressHint,
            controller: _address,
            maxLines: 2,
            maxRunes: kAddressTextMaxRunes,
            textInputAction: TextInputAction.next,
            errorText: p.addressMissing
                ? l10n.acctAddressRequired
                : p.addressTooLong
                    ? l10n.addrErrTooLong(kAddressTextMaxRunes)
                    : null,
            onChanged: (_) => setState(() {}),
          ),
          gap,
          QdTextField(
            key: const Key('address_note_input'),
            label: l10n.custNoteLabel,
            hint: l10n.custNoteHint,
            controller: _note,
            maxLines: 2,
            maxRunes: kAddressNoteMaxRunes,
            errorText: p.noteTooLong
                ? l10n.addrErrTooLong(kAddressNoteMaxRunes)
                : null,
          ),
          gap,
          _PinRow(
            latitude: _lat,
            longitude: _lng,
            error: p.pinMissing,
            onTap: _pin,
          ),
        ],
      ),
      bottomNavigationBar: QdFooterBar(
        child: QdButton(
          key: const Key('address_save'),
          label: l10n.acctSaveAddress,
          fullWidth: true,
          onPressed: _save,
        ),
      ),
    );
  }
}

/// "Place on the map" row: "Required" until pinned, then the coordinates.
class _PinRow extends StatelessWidget {
  const _PinRow({
    required this.latitude,
    required this.longitude,
    required this.error,
    required this.onTap,
  });

  final double? latitude;
  final double? longitude;
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final pinned = latitude != null && longitude != null;
    final value = pinned
        ? '${latitude!.toStringAsFixed(4)}, ${longitude!.toStringAsFixed(4)}'
        : error
            ? l10n.addrErrPin
            : l10n.addrPinMissing;
    return Semantics(
      button: true,
      label: '${l10n.addrPin}, ${pinned ? l10n.addrPinSet : value}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        key: const Key('address_pin'),
        color: c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QdRadius.sm),
          side: BorderSide(color: error ? c.danger : c.borderInput),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: 60),
            child: Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: 14, vertical: QdSpace.x2),
              child: Row(
                children: [
                  Icon(Icons.map_outlined,
                      size: QdSize.icon, color: c.textPrimary),
                  const SizedBox(width: QdSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.addrPin,
                            style: QdText.body.copyWith(
                                fontSize: 15,
                                color: c.textPrimary,
                                fontWeight: FontWeight.w500)),
                        Text(
                          value,
                          key: const Key('address_pin_value'),
                          textDirection: pinned ? TextDirection.ltr : null,
                          style: QdText.caption.copyWith(
                              color: pinned
                                  ? c.textSecondary
                                  : error
                                      ? c.danger
                                      : c.warning),
                        ),
                      ],
                    ),
                  ),
                  Icon(Icons.chevron_right,
                      size: QdSize.icon, color: c.textSecondary),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
