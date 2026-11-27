import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../../ui/qd_ui.dart';
import '../text_limits.dart';
import 'geo_models.dart';
import 'geo_service.dart';

/// Shared address text field with debounced Google Places autocomplete and
/// session-token lifecycle, used in both the booking picker and the
/// saved-address editor.
///
/// Falls back cleanly to manual typing on `geo_unavailable`, network error, or
/// rate limit without blocking the form.
class AddressSearchField extends StatefulWidget {
  const AddressSearchField({
    super.key,
    this.fieldKey,
    required this.label,
    required this.controller,
    this.hint,
    this.errorText,
    this.helperText,
    this.maxLines = 1,
    this.maxRunes = kAddressTextMaxRunes,
    this.textInputAction,
    this.enabled = true,
    this.onChanged,
    this.onPlaceSelected,
    this.geoService,
    this.debounceDuration = const Duration(milliseconds: 400),
    this.statusHint,
  });

  final Key? fieldKey;
  final String label;
  final TextEditingController controller;
  final String? hint;
  final String? errorText;
  final String? helperText;
  final int maxLines;
  final int? maxRunes;
  final TextInputAction? textInputAction;
  final bool enabled;
  final ValueChanged<String>? onChanged;
  final ValueChanged<GeoPlace>? onPlaceSelected;
  final GeoService? geoService;
  final Duration debounceDuration;

  /// Optional non-blocking inline hint (e.g. reverse-geocoding in progress)
  /// displayed directly above the suggestions / below the field.
  final Widget? statusHint;

  @override
  State<AddressSearchField> createState() => _AddressSearchFieldState();
}

class _AddressSearchFieldState extends State<AddressSearchField> {
  static final math.Random _rng = math.Random();
  static const int _minQueryRunes = 3;
  static const int _maxQueryRunes = 100;

  Timer? _debounce;
  String? _sessionToken;
  int _searchSeq = 0;
  bool _searching = false;
  bool _resolvingPlace = false;
  String? _fallbackNote;
  List<GeoSuggestion> _suggestions = const [];
  late String _lastObservedText = widget.controller.text;

  @override
  void initState() {
    super.initState();
    widget.controller.addListener(_onControllerChanged);
  }

  @override
  void didUpdateWidget(AddressSearchField oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.controller != widget.controller) {
      oldWidget.controller.removeListener(_onControllerChanged);
      _lastObservedText = widget.controller.text;
      widget.controller.addListener(_onControllerChanged);
    }
  }

  @override
  void dispose() {
    _debounce?.cancel();
    widget.controller.removeListener(_onControllerChanged);
    super.dispose();
  }

  void _onControllerChanged() {
    final current = widget.controller.text;
    if (current == _lastObservedText) return;
    // EditableText updates controller.value synchronously right before calling
    // onChanged; wait a microtask so user typing updates _lastObservedText
    // first, while external programmatic edits cancel search & clear stale
    // suggestions.
    scheduleMicrotask(() {
      if (!mounted) return;
      final latest = widget.controller.text;
      if (latest == _lastObservedText) return;
      _lastObservedText = latest;
      _debounce?.cancel();
      _searchSeq++;
      _sessionToken = null;
      if (_suggestions.isNotEmpty || _searching) {
        setState(() {
          _suggestions = const [];
          _searching = false;
        });
      }
    });
  }

  String _nextSessionToken() {
    final buf = StringBuffer('qd_');
    for (var i = 0; i < 24; i++) {
      buf.write(_rng.nextInt(16).toRadixString(16));
    }
    return buf.toString();
  }

  GeoService? _resolveGeoService(BuildContext context) =>
      widget.geoService ?? GeoScope.maybeOf(context);

  void _handleUserChanged(String value) {
    _lastObservedText = value;
    widget.onChanged?.call(value);

    final geo = _resolveGeoService(context);
    _debounce?.cancel();
    if (geo == null || !widget.enabled) {
      if (_suggestions.isNotEmpty || _searching) {
        setState(() {
          _suggestions = const [];
          _searching = false;
        });
      }
      return;
    }

    final trimmed = value.trim();
    final runes = runeLength(trimmed);
    if (runes == 0) {
      _sessionToken = null;
    }
    if (runes < _minQueryRunes || runes > _maxQueryRunes) {
      _searchSeq++;
      if (_suggestions.isNotEmpty || _searching || _fallbackNote != null) {
        setState(() {
          _suggestions = const [];
          _searching = false;
          _fallbackNote = null;
        });
      }
      return;
    }

    _sessionToken ??= _nextSessionToken();
    if (_fallbackNote != null) {
      setState(() => _fallbackNote = null);
    }
    _debounce = Timer(widget.debounceDuration, () => _runAutocomplete(trimmed));
  }

  Future<void> _runAutocomplete(String query) async {
    final geo = _resolveGeoService(context);
    if (geo == null || !mounted) return;

    final seq = ++_searchSeq;
    final token = _sessionToken ??= _nextSessionToken();
    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';

    setState(() {
      _searching = true;
      _fallbackNote = null;
    });

    try {
      final results = await geo.autocomplete(
        query: query,
        sessionToken: token,
        languageCode: lang,
      );
      if (!mounted ||
          seq != _searchSeq ||
          widget.controller.text.trim() != query) {
        return;
      }
      setState(() {
        _searching = false;
        _suggestions = results.take(5).toList();
        _fallbackNote = null;
      });
    } catch (_) {
      if (!mounted || seq != _searchSeq) return;
      final l10n = context.l10n;
      setState(() {
        _searching = false;
        _suggestions = const [];
        _fallbackNote = l10n.geoFallbackManual;
      });
    }
  }

  Future<void> _selectSuggestion(GeoSuggestion suggestion) async {
    final geo = _resolveGeoService(context);
    _debounce?.cancel();
    _searchSeq++;
    final token = _sessionToken ?? _nextSessionToken();
    _sessionToken = null;

    if (geo == null) {
      _applyText(_capRunes(suggestion.primary, widget.maxRunes));
      setState(() => _suggestions = const []);
      return;
    }

    final lang = Localizations.maybeLocaleOf(context)?.languageCode ?? 'en';
    setState(() {
      _suggestions = const [];
      _searching = false;
      _resolvingPlace = true;
      _fallbackNote = null;
    });

    try {
      final place = await geo.placeDetails(
        placeId: suggestion.placeId,
        sessionToken: token,
        languageCode: lang,
      );
      if (!mounted) return;
      final address = place.address.trim().isNotEmpty
          ? place.address.trim()
          : suggestion.primary;
      _applyText(_capRunes(address, widget.maxRunes));
      setState(() {
        _resolvingPlace = false;
        _fallbackNote = null;
      });
      widget.onPlaceSelected?.call(place);
    } catch (_) {
      if (!mounted) return;
      final l10n = context.l10n;
      _applyText(_capRunes(suggestion.primary, widget.maxRunes));
      setState(() {
        _resolvingPlace = false;
        _fallbackNote = l10n.geoFallbackManual;
      });
    }
  }

  void _applyText(String text) {
    _lastObservedText = text;
    widget.controller.value = TextEditingValue(
      text: text,
      selection: TextSelection.collapsed(offset: text.length),
    );
  }

  static String _capRunes(String value, int? maxRunes) {
    if (maxRunes == null || runeLength(value) <= maxRunes) return value;
    return String.fromCharCodes(value.runes.take(maxRunes));
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final busy = _searching || _resolvingPlace;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QdTextField(
          key: widget.fieldKey,
          label: widget.label,
          hint: widget.hint,
          controller: widget.controller,
          errorText: widget.errorText,
          helperText: widget.helperText ?? _fallbackNote,
          maxLines: widget.maxLines,
          maxRunes: widget.maxRunes,
          textInputAction: widget.textInputAction,
          enabled: widget.enabled,
          onChanged: _handleUserChanged,
        ),
        if (widget.statusHint != null) ...[
          const SizedBox(height: QdSpace.x1),
          widget.statusHint!,
        ] else if (busy) ...[
          const SizedBox(height: QdSpace.x1),
          Row(
            key: const Key('addr_search_loading'),
            children: [
              SizedBox(
                width: 12,
                height: 12,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: c.gold,
                ),
              ),
              const SizedBox(width: QdSpace.x2),
              Flexible(
                child: Text(
                  l10n.geoSearching,
                  style: QdText.caption.copyWith(color: c.textSecondary),
                ),
              ),
            ],
          ),
        ],
        if (_suggestions.isNotEmpty) ...[
          const SizedBox(height: QdSpace.x2),
          Material(
            key: const Key('addr_search_suggestions'),
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(QdRadius.sm),
              side: BorderSide(color: c.border),
            ),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxHeight: 192),
              child: ListView.separated(
                padding: EdgeInsets.zero,
                shrinkWrap: true,
                itemCount: _suggestions.length,
                separatorBuilder: (_, __) =>
                    Divider(height: 1, thickness: 1, color: c.border),
                itemBuilder: (context, index) {
                  final item = _suggestions[index];
                  return InkWell(
                    key: Key('addr_suggestion_$index'),
                    onTap: () => _selectSuggestion(item),
                    child: Padding(
                      padding: const EdgeInsetsDirectional.symmetric(
                        horizontal: QdSpace.x3,
                        vertical: QdSpace.x2,
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.place_outlined,
                            size: QdSize.icon,
                            color: c.textSecondary,
                          ),
                          const SizedBox(width: QdSpace.x2),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  item.primary,
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                  style: QdText.bodyStrong
                                      .copyWith(color: c.textPrimary),
                                ),
                                if (item.secondary.isNotEmpty)
                                  Text(
                                    item.secondary,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: QdText.caption
                                        .copyWith(color: c.textSecondary),
                                  ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ],
    );
  }
}
