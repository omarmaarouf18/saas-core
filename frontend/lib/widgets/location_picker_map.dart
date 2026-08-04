import 'package:flutter/material.dart';
import 'package:flutter_map/flutter_map.dart';
import 'package:geolocator/geolocator.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants.dart';
import '../core/location_permission.dart';
import '../core/theme.dart';

class LocationPickerMap extends StatefulWidget {
  final LatLng? initialLocation;
  final ValueChanged<LatLng>? onLocationSelected;
  final GeolocatorPlatform? geolocatorPlatform;

  static const LatLng cairoDefault = LatLng(30.0444, 31.2357);

  const LocationPickerMap({
    super.key,
    this.initialLocation,
    this.onLocationSelected,
    this.geolocatorPlatform,
  });

  @override
  State<LocationPickerMap> createState() => _LocationPickerMapState();
}

class _LocationPickerMapState extends State<LocationPickerMap> {
  late final MapController _mapController;
  late LatLng _selectedPoint;
  bool _isLoadingLocation = false;

  @override
  void initState() {
    super.initState();
    _mapController = MapController();
    _selectedPoint = widget.initialLocation ?? LocationPickerMap.cairoDefault;
  }

  @override
  void dispose() {
    _mapController.dispose();
    super.dispose();
  }

  Future<void> _fetchAndSetCurrentLocation() async {
    setState(() {
      _isLoadingLocation = true;
    });

    try {
      final permissionResult = await requestLocationPermission(
        platform: widget.geolocatorPlatform,
      );

      if (permissionResult == LocationPermissionResult.granted) {
        final geolocator =
            widget.geolocatorPlatform ?? GeolocatorPlatform.instance;
        final position = await geolocator.getCurrentPosition();
        final currentPoint = LatLng(position.latitude, position.longitude);

        if (mounted) {
          setState(() {
            _selectedPoint = currentPoint;
          });
          _mapController.move(currentPoint, 14.0);
          widget.onLocationSelected?.call(currentPoint);
        }
      } else {
        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
              content: Text("Location permission denied. Defaulting to Cairo."),
              duration: Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Error fetching location: $e"),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _isLoadingLocation = false;
        });
      }
    }
  }

  void _onMapTap(TapPosition tapPosition, LatLng point) {
    setState(() {
      _selectedPoint = point;
    });
    widget.onLocationSelected?.call(point);
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        FlutterMap(
          mapController: _mapController,
          options: MapOptions(
            initialCenter: _selectedPoint,
            initialZoom: 14.0,
            onTap: _onMapTap,
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
                  key: const Key('location_picker_marker'),
                  width: 40.0,
                  height: 40.0,
                  point: _selectedPoint,
                  child: GestureDetector(
                    onTap: () => widget.onLocationSelected?.call(_selectedPoint),
                    child: const Icon(
                      Icons.location_on,
                      color: AppColors.primary,
                      size: 40.0,
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),

        // Floating Action Button: Use My Current Location
        Positioned(
          right: AppSpacing.md,
          bottom: AppSpacing.md,
          child: FloatingActionButton.extended(
            key: const Key('use_current_location_button'),
            heroTag: 'use_current_location_fab',
            backgroundColor: AppColors.primary,
            foregroundColor: AppColors.onPrimary,
            icon: _isLoadingLocation
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(
                      strokeWidth: 2,
                      valueColor: AlwaysStoppedAnimation<Color>(Colors.white),
                    ),
                  )
                : const Icon(Icons.my_location, size: 20),
            label: const Text(
              "Use My Location",
              style: TextStyle(fontWeight: FontWeight.bold),
            ),
            onPressed: _isLoadingLocation ? null : _fetchAndSetCurrentLocation,
          ),
        ),
      ],
    );
  }
}
