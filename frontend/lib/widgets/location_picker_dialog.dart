import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:latlong2/latlong.dart';
import '../core/theme.dart';
import 'location_picker_map.dart';
import 'primary_button.dart';

/// Shared location-picker dialog shell (UI visual audit 2026-09, gap G1).
///
/// Four call sites (`customer_home_screen.dart`,
/// `customer_marketplace_screen.dart` x2, `owner_configuration_screen.dart`)
/// carried byte-near-identical `Dialog` chrome — responsive width cap,
/// `lg` radius, `md` inset/padding, title row with close, `md`-clipped
/// `LocationPickerMap`, confirm `PrimaryButton` — differing only in title
/// copy, button keys, and the confirm callback. Per DESIGN_SYSTEM.md rule
/// #2 this is now one widget: callers pass copy + keys + a
/// `ValueChanged<LatLng>` and keep zero chrome.
///
/// Geometry follows the three-site majority (500px cap over 600px
/// viewports, 95% width / 75% height below; 600px height cap over 800px
/// viewports). The owner-config variant previously used a
/// `min(500, 0.9w) x min(550, 0.8h)` formula — adopting the majority makes
/// its picker slightly wider/taller on small screens, matching the other
/// three pickers. Dismissal stays `barrierDismissible: true` (unchanged
/// behavior at all four sites).
class LocationPickerDialog extends StatefulWidget {
  /// Key applied to the [Dialog] (tests target per-site keys).
  final Key? dialogKey;

  /// Header title (already localized by the caller).
  final String title;

  /// Map's initial camera/selection.
  final LatLng initialLocation;

  /// Confirm button label (already localized by the caller).
  final String confirmLabel;

  /// Key applied to the confirm [PrimaryButton].
  final Key? confirmButtonKey;

  /// Optional trailing icon on the confirm button (marketplace/home pass
  /// `Icons.arrow_forward`; owner config passes none).
  final IconData? confirmTrailingIcon;

  /// Fired with the map's current selection when the user confirms. The
  /// dialog pops itself afterwards; callers only persist state.
  final ValueChanged<LatLng> onConfirmed;

  const LocationPickerDialog({
    super.key,
    this.dialogKey,
    required this.title,
    required this.initialLocation,
    required this.confirmLabel,
    this.confirmButtonKey,
    this.confirmTrailingIcon,
    required this.onConfirmed,
  });

  /// Shows the picker. Returns when the dialog closes (confirm or close).
  static Future<void> show(
    BuildContext context, {
    Key? dialogKey,
    required String title,
    required LatLng initialLocation,
    required String confirmLabel,
    Key? confirmButtonKey,
    IconData? confirmTrailingIcon,
    required ValueChanged<LatLng> onConfirmed,
  }) {
    return showDialog<void>(
      context: context,
      builder: (dialogCtx) => LocationPickerDialog(
        dialogKey: dialogKey,
        title: title,
        initialLocation: initialLocation,
        confirmLabel: confirmLabel,
        confirmButtonKey: confirmButtonKey,
        confirmTrailingIcon: confirmTrailingIcon,
        onConfirmed: onConfirmed,
      ),
    );
  }

  @override
  State<LocationPickerDialog> createState() => _LocationPickerDialogState();
}

class _LocationPickerDialogState extends State<LocationPickerDialog> {
  late LatLng _tempLocation;

  @override
  void initState() {
    super.initState();
    _tempLocation = widget.initialLocation;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.95;
    final dialogHeight = screenHeight > 800 ? 600.0 : screenHeight * 0.75;

    return Dialog(
      key: widget.dialogKey ?? const Key('location_picker_dialog'),
      insetPadding: const EdgeInsets.all(AppSpacing.md),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.lg),
      ),
      child: SizedBox(
        width: dialogWidth,
        height: dialogHeight,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      widget.title,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                  IconButton(
                    tooltip: l10n.tooltipClose,
                    icon: const Icon(Icons.close),
                    onPressed: () => Navigator.of(context).pop(),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Expanded(
                child: ClipRRect(
                  borderRadius: BorderRadius.circular(AppRadius.md),
                  child: LocationPickerMap(
                    initialLocation: _tempLocation,
                    onLocationSelected: (newLocation) {
                      _tempLocation = newLocation;
                    },
                  ),
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              PrimaryButton(
                key: widget.confirmButtonKey,
                text: widget.confirmLabel,
                trailingIcon: widget.confirmTrailingIcon,
                onPressed: () {
                  widget.onConfirmed(_tempLocation);
                  Navigator.of(context).pop();
                },
              ),
            ],
          ),
        ),
      ),
    );
  }
}
