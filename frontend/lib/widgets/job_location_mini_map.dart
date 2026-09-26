import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/job.dart';

/// Static destination preview (Issue-2 Option A, frontend-only).
///
/// `JobLocation` carries only latitude/longitude — no address field exists
/// anywhere in the data model — so job cards rendered raw coordinate pairs.
/// Until reverse geocoding lands (see
/// `docs/frontend/DESTINATION_ADDRESS_PROPOSAL.md` Option B), this widget
/// replaces the raw-numbers-first presentation with a small non-interactive
/// `flutter_map` thumbnail (same OSM tile template + User-Agent constants
/// the app already ships) showing a pin at the location. The exact
/// coordinates stay as a small caption underneath for precision (rural
/// handoff, tile-label gaps) — visual primary, numbers secondary.
///
/// Tokens only (`AppColors`/`AppSpacing`/`AppRadius`/`AppTypography`/`AppIconSize`);
/// no new colors. Gestures are fully disabled so the thumbnail never traps
/// scroll inside job cards.
class JobLocationMiniMap extends StatelessWidget {
  /// Destination (or pickup) to preview. Never null at call sites — the
  /// `routeDestinationNotSetYet` fallback covers missing destinations.
  final JobLocation location;

  /// Thumbnail height in dp. Width always stretches to the card.
  final double height;

  /// Option C: typed landmark note rendered as the primary label above the
  /// map (text for quick reading, map for spatial confirmation). Null (or
  /// blank) keeps the previous map-only treatment for jobs without a note.
  final String? label;

  const JobLocationMiniMap({
    super.key,
    required this.location,
    this.height = 110,
    this.label,
  });

  @override
  Widget build(BuildContext context) {
    final point = LatLng(location.latitude, location.longitude);
    final note =
        (label != null && label!.trim().isNotEmpty) ? label!.trim() : null;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (note != null) ...[
          Text(
            note,
            style: AppTypography.bodyMd.copyWith(
              color: Theme.of(context).colorScheme.onSurface,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: AppSpacing.xxs),
        ],
        ClipRRect(
          borderRadius: BorderRadius.circular(AppRadius.md),
          child: SizedBox(
            height: height,
            child: FlutterMap(
              options: MapOptions(
                initialCenter: point,
                initialZoom: 15,
                interactionOptions: const InteractionOptions(
                  flags: InteractiveFlag.none,
                ),
              ),
              children: [
                TileLayer(
                  urlTemplate: mapTileUrlTemplate,
                  userAgentPackageName: mapTileUserAgent,
                  errorTileCallback: (tile, error, stackTrace) {},
                ),
                MarkerLayer(
                  markers: [
                    Marker(
                      point: point,
                      width: 40,
                      height: 40,
                      child: const Icon(
                        Icons.location_on,
                        color: AppColors.primary,
                        size: AppIconSize.lg,
                      ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: AppSpacing.xxs),
        Text(
          location.formatCoordinates(),
          key: const Key('job_mini_map_coords'),
          style: AppTypography.labelSm.copyWith(
            color: Theme.of(context).colorScheme.onSurfaceVariant,
          ),
          textAlign: TextAlign.center,
        ),
      ],
    );
  }
}
