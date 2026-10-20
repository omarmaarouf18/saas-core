import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../ui/qd_ui.dart';
import 'account_nav.dart';
import 'account_page.dart';

/// Most addresses the server keeps (the old screen's cap).
const int kMaxSavedAddresses = 10;

/// Saved addresses: the profile's `frequent_addresses`, which today are
/// plain strings (no coordinates, so no map).
///
/// Behaviour kept from MyAccountScreen's address card: add (required, at
/// most 10), delete with undo that puts the text back where it was, and
/// read-only while suspended. Changed: every change is saved right away
/// (PATCH frequent_addresses) instead of with the profile's save button;
/// a failed save restores the list and shows the error with retry. New:
/// edit an address.
class SavedAddressesPage extends StatefulWidget {
  const SavedAddressesPage({super.key});

  @override
  State<SavedAddressesPage> createState() => _SavedAddressesPageState();
}

class _SavedAddressesPageState extends State<SavedAddressesPage> {
  late List<String> _addresses =
      List.of(context.read<AuthProvider>().user?.frequentAddresses ?? []);
  bool _saving = false;
  String? _error;
  List<String>? _failed;

  /// Saves [next]; on failure keeps the previous list. Returns success.
  Future<bool> _commit(List<String> next) async {
    final previous = _addresses;
    final auth = context.read<AuthProvider>();
    setState(() {
      _addresses = next;
      _saving = true;
      _error = null;
    });
    try {
      await auth.updateOwnProfile(frequentAddresses: next);
      if (mounted) setState(() => _failed = null);
      return true;
    } catch (e) {
      if (mounted) {
        setState(() {
          _addresses = previous;
          _failed = next;
          _error = auth.error ?? friendlyErrorMessage(e);
        });
      }
      return false;
    } finally {
      if (mounted) setState(() => _saving = false);
    }
  }

  Future<void> _edit({int? index}) async {
    final l10n = context.l10n;
    final current = index == null ? null : _addresses[index];
    final text = await _AddressSheet.show(
      context,
      title: index == null ? l10n.acctAddAddress : l10n.acctEditAddress,
      initial: current,
    );
    if (text == null || !mounted || text == current) return;
    final next = List.of(_addresses);
    if (index == null) {
      next.add(text);
    } else {
      next[index] = text;
    }
    await _commit(next);
  }

  Future<void> _delete(int index) async {
    final removed = _addresses[index];
    final next = List.of(_addresses)..removeAt(index);
    if (!await _commit(next) || !mounted) return;
    final l10n = context.l10n;
    showAccountNotice(
      context,
      l10n.acctAddressDeleted,
      actionLabel: l10n.acctUndo,
      onAction: () {
        if (!mounted) return;
        final back = List.of(_addresses);
        back.insert(index.clamp(0, back.length), removed);
        _commit(back);
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final user = context.watch<AuthProvider>().user;
    final suspended = user?.isSuspended ?? false;
    final full = _addresses.length >= kMaxSavedAddresses;

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
              onAction: _failed == null ? null : () => _commit(_failed!),
            ),
            const SizedBox(height: QdSpace.x4),
          ],
          if (_addresses.isEmpty)
            QdEmptyState(
              key: const Key('addresses_empty'),
              icon: Icons.location_on_outlined,
              title: l10n.acctAddressesEmpty,
              body: l10n.acctAddressesEmptyBody,
            )
          else
            QdListGroup(children: [
              for (var i = 0; i < _addresses.length; i++)
                _AddressRow(
                  key: Key('address_$i'),
                  text: _addresses[i],
                  enabled: !suspended && !_saving,
                  onEdit: () => _edit(index: i),
                  onDelete: () => _delete(i),
                ),
            ]),
          const SizedBox(height: QdSpace.x3),
          Text(
            '${l10n.acctAddressCount(_addresses.length)} · '
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

class _AddressRow extends StatelessWidget {
  const _AddressRow({
    super.key,
    required this.text,
    required this.enabled,
    required this.onEdit,
    required this.onDelete,
  });

  final String text;
  final bool enabled;
  final VoidCallback onEdit;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return InkWell(
      onTap: enabled ? onEdit : null,
      child: ConstrainedBox(
        constraints: const BoxConstraints(minHeight: QdSize.listRow),
        child: Padding(
          padding: const EdgeInsetsDirectional.only(start: 14, end: 4),
          child: Row(
            children: [
              Icon(Icons.location_on_outlined,
                  size: QdSize.icon, color: c.textPrimary),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: Semantics(
                  button: enabled,
                  hint: l10n.acctEditAddress,
                  child: Text(text,
                      style: QdText.body
                          .copyWith(fontSize: 15, color: c.textPrimary)),
                ),
              ),
              IconButton(
                key: const Key('address_delete'),
                tooltip: l10n.acctDeleteAddress(text),
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

/// Add / edit sheet: one text field and a save button. Completes with the
/// trimmed text, or null when closed.
class _AddressSheet extends StatefulWidget {
  const _AddressSheet({this.initial});

  final String? initial;

  static Future<String?> show(BuildContext context,
      {required String title, String? initial}) {
    return QdBottomSheet.show<String>(
      context,
      title: title,
      child: QdThemeScope(child: _AddressSheet(initial: initial)),
    );
  }

  @override
  State<_AddressSheet> createState() => _AddressSheetState();
}

class _AddressSheetState extends State<_AddressSheet> {
  late final _text = TextEditingController(text: widget.initial);
  String? _error;

  @override
  void dispose() {
    _text.dispose();
    super.dispose();
  }

  void _save() {
    final value = _text.text.trim();
    if (value.isEmpty) {
      setState(() => _error = context.l10n.acctAddressRequired);
      return;
    }
    Navigator.of(context).pop(value);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QdTextField(
          key: const Key('address_input'),
          label: l10n.acctAddressLabel,
          hint: l10n.acctAddressHint,
          controller: _text,
          errorText: _error,
          maxLines: 2,
          textInputAction: TextInputAction.done,
          onSubmitted: (_) => _save(),
          onChanged: (_) {
            if (_error != null) setState(() => _error = null);
          },
        ),
        const SizedBox(height: QdSpace.x5),
        QdButton(
          key: const Key('address_save'),
          label: l10n.acctSaveAddress,
          fullWidth: true,
          onPressed: _save,
        ),
      ],
    );
  }
}
