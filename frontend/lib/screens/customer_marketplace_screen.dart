import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:geolocator/geolocator.dart';
import '../core/error_messages.dart';
import '../core/location_permission.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/marketplace_service.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/list_screen_template.dart';
import '../widgets/location_picker_map.dart';
import '../widgets/primary_button.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/secondary_button.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
import '../models/job.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_text_field.dart';
import '../widgets/themed_success_banner.dart';
import 'job_status_screen.dart';
import 'notifications_screen.dart';

class CustomerMarketplaceScreen extends StatefulWidget {
  final bool isEmbeddedInTab;
  final bool initialNearBy;

  const CustomerMarketplaceScreen({
    super.key,
    this.isEmbeddedInTab = false,
    this.initialNearBy = false,
  });

  @override
  State<CustomerMarketplaceScreen> createState() =>
      CustomerMarketplaceScreenState();
}

class CustomerMarketplaceScreenState extends State<CustomerMarketplaceScreen> {
  double _customerLat = 30.0444; // default Cairo lat
  double _customerLon = 31.2357; // default Cairo lon
  final _radiusController = TextEditingController(text: "50"); // default radius

  String _selectedCategory =
      'all'; // 'all', 'delivery', 'transport', 'shipping'
  String _sortBy = 'price'; // 'price' or 'none'
  bool _nearBy = false;
  bool _isLocating = true;

  @override
  void initState() {
    super.initState();
    _nearBy = widget.initialNearBy;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _initLocation();
      _loadServices();
    });
  }

  Future<void> _initLocation() async {
    try {
      final perm = await requestLocationPermission();
      if (perm == LocationPermissionResult.granted) {
        final pos = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() {
            _customerLat = pos.latitude;
            _customerLon = pos.longitude;
            _isLocating = false;
          });
          _loadServices();
          return;
        }
      }
    } catch (_) {
      // Keep default Cairo coordinates fallback
    }
    if (mounted) {
      setState(() {
        _isLocating = false;
      });
    }
  }

  void setCustomerLocation(double lat, double lon) {
    setState(() {
      _customerLat = lat;
      _customerLon = lon;
      _isLocating = false;
    });
    _loadServices();
  }

  @override
  void dispose() {
    _radiusController.dispose();
    super.dispose();
  }

  void _loadServices() {
    final radius = double.tryParse(_radiusController.text.trim()) ?? 50.0;

    Provider.of<MarketplaceProvider>(context, listen: false).fetchServices(
      nearBy: _nearBy,
      lat: _customerLat,
      lon: _customerLon,
      radius: radius,
      sortBy: _sortBy,
    );
  }

  Widget _buildNotificationBell(BuildContext context) {
    return Consumer<NotificationsProvider>(
      builder: (context, provider, child) {
        return SizedBox(
          width: 48,
          height: 48,
          child: Stack(
            alignment: Alignment.center,
            children: [
              IconButton(
                icon: const Icon(Icons.notifications),
                tooltip: context.l10n.tooltipNotifications,
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (context) => const NotificationsScreen(),
                    ),
                  );
                },
              ),
              if (provider.unreadCount > 0)
                Positioned(
                  right: 8,
                  top: 8,
                  child: ClipRRect(
                    borderRadius: BorderRadius.circular(AppRadius.radiusSmMd),
                    child: ColoredBox(
                      color: AppColors.error,
                      child: Container(
                        padding:
                            const EdgeInsetsDirectional.all(AppSpacing.xxs),
                        constraints: const BoxConstraints(
                          minWidth: 16,
                          minHeight: 16,
                        ),
                        alignment: Alignment.center,
                        child: Text(
                          '${provider.unreadCount}',
                          style: AppTypography.labelSm.copyWith(
                            color: AppColors.onPrimary,
                            fontWeight: FontWeight.bold,
                          ),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        );
      },
    );
  }

  IconData _getCategoryIcon(String category) {
    switch (category) {
      case 'delivery':
        return Icons.delivery_dining;
      case 'transport':
        return Icons.directions_car;
      case 'shipping':
        return Icons.local_shipping;
      default:
        return Icons.business;
    }
  }

  void selectCategory(String category) {
    setState(() {
      _selectedCategory = category;
    });
  }

  @override
  Widget build(BuildContext context) {
    final auth = Provider.of<AuthProvider>(context);
    final marketplace = Provider.of<MarketplaceProvider>(context);
    final l10n = context.l10n;

    // Filter services client-side by category if not 'all'
    final filteredServices = _selectedCategory == 'all'
        ? marketplace.services
        : marketplace.services
            .where((s) => s.category == _selectedCategory)
            .toList();

    return ListScreenTemplate<MarketplaceService>(
      title: l10n.customerMarketplaceTitle,
      isEmbeddedInTab: widget.isEmbeddedInTab,
      actions: [
        _buildNotificationBell(context),
      ],
      header: _buildFilterControlCard(l10n),
      items: filteredServices,
      isLoading: marketplace.isLoading,
      // QA audit A5: a failed fetch previously fell through to the
      // "no services nearby" empty state — customers read a backend outage
      // as "no couriers exist". Surface the error with retry instead.
      errorMessage: marketplace.error,
      onRefresh: () async => _loadServices(),
      listViewKey: const ValueKey('marketplace_services_list'),
      loadingWidget: ListView.builder(
        key: const ValueKey('marketplace_skeleton_list'),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md),
        itemCount: 4,
        itemBuilder: (context, index) => const MarketplaceCardSkeleton(),
      ),
      errorWidget: Padding(
        key: const ValueKey('marketplace_error_banner'),
        padding: const EdgeInsets.all(AppSpacing.lg),
        child: ThemedErrorBanner(
          message: marketplace.error ?? '',
          onRetry: _loadServices,
        ),
      ),
      emptyWidget: SingleChildScrollView(
        key: const ValueKey('marketplace_empty_state'),
        physics: const AlwaysScrollableScrollPhysics(),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
          child: ThemedCard(
            elevation: AppElevation.shadowLevel1List,
            borderRadius: AppRadius.md,
            padding: AppSpacing.lg,
            child: ThemedEmptyState(
              icon: Icons.search_off,
              title: l10n.noServicesNearby,
              description: l10n.marketplaceEmptyHint,
              actionText: l10n.tooltipRefreshList,
              onActionPressed: _loadServices,
            ),
          ),
        ),
      ),
      listPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.md,
        vertical: AppSpacing.xs,
      ),
      itemSpacing: 0,
      itemBuilder: (context, service, index) {
        return _buildServiceCard(context, service, l10n, auth);
      },
    );
  }

  Widget _buildFilterControlCard(AppLocalizations l10n) {
    // Declutter V2: single quick-filter row (Category / Sort / Filters).
    // The Nearby toggle, map location picker, and radius input live in the
    // Filters bottom sheet.
    return Padding(
      padding: const EdgeInsets.fromLTRB(
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.md,
        AppSpacing.xs,
      ),
      child: ThemedCard(
        elevation: AppElevation.shadowLevel1List,
        borderRadius: AppRadius.md,
        padding: AppSpacing.md,
        child: Row(
          children: [
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _selectedCategory,
                isExpanded: true,
                style: AppTypography.bodyMd.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  labelText: l10n.customerMarketplaceFilterCategory,
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.defaultBorder,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                ),
                items: [
                  DropdownMenuItem(
                      value: 'all', child: Text(l10n.customerHomeCatBrowseAll)),
                  ...serviceCategoryLabels.entries.map(
                    (entry) => DropdownMenuItem(
                      value: entry.key,
                      child: Text(entry.value),
                    ),
                  ),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _selectedCategory = val;
                    });
                  }
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: DropdownButtonFormField<String>(
                initialValue: _sortBy,
                isExpanded: true,
                style: AppTypography.bodyMd.copyWith(
                  color: Theme.of(context).colorScheme.onSurface,
                ),
                decoration: InputDecoration(
                  labelText: l10n.sortByLabel,
                  border: OutlineInputBorder(
                    borderRadius: AppRadius.defaultBorder,
                  ),
                  contentPadding: const EdgeInsets.symmetric(
                    horizontal: AppSpacing.sm,
                    vertical: AppSpacing.xs,
                  ),
                ),
                items: [
                  DropdownMenuItem(
                      value: 'price', child: Text(l10n.filterSortPrice)),
                  DropdownMenuItem(
                      value: 'none', child: Text(l10n.filterSortNone)),
                ],
                onChanged: (val) {
                  if (val != null) {
                    setState(() {
                      _sortBy = val;
                    });
                    _loadServices();
                  }
                },
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            IconButton(
              key: const Key('marketplace_filters_button'),
              tooltip: l10n.marketplaceFiltersTooltip,
              onPressed: _showFiltersSheet,
              style: IconButton.styleFrom(
                backgroundColor: Theme.of(context).colorScheme.primary,
                foregroundColor: AppColors.onPrimary,
                shape: RoundedRectangleBorder(
                  borderRadius: AppRadius.defaultBorder,
                ),
              ),
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
      ),
    );
  }

  void _showFiltersSheet() {
    // Declutter V2: secondary filter controls (nearby toggle, map location
    // picker, radius) moved into a bottom sheet.
    showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      builder: (sheetContext) {
        final l10n = context.l10n;
        return StatefulBuilder(
          builder: (sheetInnerContext, setSheetState) {
            return SafeArea(
              child: Padding(
                padding: EdgeInsets.only(
                  left: AppSpacing.lg,
                  right: AppSpacing.lg,
                  top: AppSpacing.lg,
                  bottom: AppSpacing.lg +
                      MediaQuery.of(sheetInnerContext).viewInsets.bottom,
                ),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Switch(
                          key: const Key('nearby_filter_switch'),
                          value: _nearBy,
                          activeTrackColor:
                              Theme.of(context).colorScheme.primary,
                          onChanged: (val) {
                            setSheetState(() => _nearBy = val);
                            setState(() => _nearBy = val);
                          },
                        ),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          l10n.customerMarketplaceFilterNearby,
                          style: AppTypography.bodyMd.copyWith(
                            color: Theme.of(context).colorScheme.onSurface,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.md),
                    SecondaryButton(
                      key: const Key('choose_location_map_button'),
                      isOutlined: true,
                      icon: Icons.map_outlined,
                      text: l10n.customerMarketplaceChooseMap,
                      onPressed: () async {
                        await _openLocationPickerDialog(context);
                      },
                    ),
                    const SizedBox(height: AppSpacing.md),
                    ThemedTextField(
                      controller: _radiusController,
                      labelText: l10n.customerMarketplaceFilterRadius,
                      keyboardType: TextInputType.number,
                    ),
                    const SizedBox(height: AppSpacing.lg),
                    PrimaryButton(
                      key: const Key('apply_filters_button'),
                      text: l10n.applyFiltersBtn,
                      onPressed: () {
                        Navigator.pop(sheetContext);
                        _loadServices();
                      },
                    ),
                  ],
                ),
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildServiceCard(
    BuildContext context,
    MarketplaceService service,
    AppLocalizations l10n,
    AuthProvider auth,
  ) {
    final categoryLabel =
        serviceCategoryLabels[service.category] ?? service.category;

    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.md),
      child: ThemedCard(
        elevation: AppElevation.shadowLevel1List,
        borderRadius: AppRadius.md,
        padding: AppSpacing.md,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 22,
                  backgroundColor: AppColors.secondary.withValues(alpha: 0.15),
                  child: Icon(
                    _getCategoryIcon(service.category),
                    color: Theme.of(context).colorScheme.primary,
                    size: 22,
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        service.name,
                        style: AppTypography.titleMd.copyWith(
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: AppSpacing.xs),
                      Wrap(
                        spacing: AppSpacing.sm,
                        runSpacing: AppSpacing.xxs,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: [
                          ClipRRect(
                            borderRadius: BorderRadius.circular(AppRadius.xs),
                            child: ColoredBox(
                              color: Theme.of(context)
                                  .colorScheme
                                  .surfaceContainerHigh,
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: AppSpacing.sm,
                                  vertical: 2,
                                ),
                                child: Text(
                                  categoryLabel,
                                  style: AppTypography.caption.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: Theme.of(context)
                                        .colorScheme
                                        .onSurfaceVariant,
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Text(
                            l10n.distanceAwayLine("${service.distanceKM}"),
                            style: AppTypography.bodySm.copyWith(
                              color: Theme.of(context)
                                  .colorScheme
                                  .onSurfaceVariant,
                            ),
                          ),
                          ServiceRatingWidget(
                            tenantId: service.tenantId,
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            if (service.workingHours != null &&
                service.workingHours!.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.schedule,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        l10n.workingHoursLine(service.workingHours!),
                        key: const Key('service_working_hours_text'),
                        style: AppTypography.bodySm.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            if (service.coverageRadiusKm != null)
              Padding(
                padding: const EdgeInsets.only(bottom: AppSpacing.xxs),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      Icons.radar,
                      size: 14,
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Flexible(
                      child: Text(
                        l10n.coverageRadiusLine("${service.coverageRadiusKm}"),
                        key: const Key('service_coverage_radius_text'),
                        style: AppTypography.bodySm.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                Expanded(
                  child: Text(
                    l10n.estPriceLine("${service.finalPrice}"),
                    style: AppTypography.titleMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                const SizedBox(width: AppSpacing.sm),
                SizedBox(
                  width: 80,
                  child: PrimaryButton(
                    text: l10n.bookNowBtn,
                    isFullWidth: false,
                    isLoading: _isLocating,
                    onPressed: _isLocating
                        ? null
                        : () => _showBookingDialog(
                              context,
                              service,
                              auth.token ?? '',
                            ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _openLocationPickerDialog(BuildContext context) async {
    final l10n = context.l10n;
    LatLng tempLocation = LatLng(_customerLat, _customerLon);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.95;
    final dialogHeight = screenHeight > 800 ? 600.0 : screenHeight * 0.75;

    await showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          key: const Key('location_picker_dialog'),
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
                          context.l10n.chooseSearchLocation,
                          style: AppTypography.titleMd.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.tooltipClose,
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: LocationPickerMap(
                        initialLocation: tempLocation,
                        onLocationSelected: (newLocation) {
                          tempLocation = newLocation;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    key: const Key('confirm_location_button'),
                    text: context.l10n.locationPickerConfirmBtn,
                    trailingIcon: Icons.arrow_forward,
                    onPressed: () {
                      setState(() {
                        _customerLat = tempLocation.latitude;
                        _customerLon = tempLocation.longitude;
                      });
                      Navigator.of(dialogCtx).pop();
                      _loadServices();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _showBookingDialog(BuildContext context,
      MarketplaceService service, String userToken) async {
    final createdJob = await showDialog<Job?>(
      context: context,
      barrierDismissible: false,
      builder: (dialogCtx) {
        return _BookingDialog(
          service: service,
          userToken: userToken,
          customerLat: _customerLat,
          customerLon: _customerLon,
        );
      },
    );

    if (createdJob != null && context.mounted) {
      await Navigator.of(context).push(
        MaterialPageRoute(
          builder: (context) => JobStatusScreen(job: createdJob),
        ),
      );
      if (mounted) {
        _loadServices();
      }
    }
  }
}

class _BookingDialog extends StatefulWidget {
  final MarketplaceService service;
  final String userToken;
  final double customerLat;
  final double customerLon;

  const _BookingDialog({
    required this.service,
    required this.userToken,
    required this.customerLat,
    required this.customerLon,
  });

  @override
  State<_BookingDialog> createState() => _BookingDialogState();
}

class _BookingDialogState extends State<_BookingDialog> {
  bool _isSubmitting = false;
  late double _pickupLat;
  late double _pickupLon;
  double? _destinationLat;
  double? _destinationLon;
  double? _tripDistanceKM;
  double? _estimatedPrice;

  @override
  void initState() {
    super.initState();
    _pickupLat = widget.customerLat;
    _pickupLon = widget.customerLon;
  }

  double _haversineKm(double lat1, double lon1, double lat2, double lon2) {
    const double r = 6371.0;
    final double dLat = (lat2 - lat1) * math.pi / 180.0;
    final double dLon = (lon2 - lon1) * math.pi / 180.0;
    final double a = math.sin(dLat / 2) * math.sin(dLat / 2) +
        math.cos(lat1 * math.pi / 180.0) *
            math.cos(lat2 * math.pi / 180.0) *
            math.sin(dLon / 2) *
            math.sin(dLon / 2);
    final double c = 2 * math.atan2(math.sqrt(a), math.sqrt(1 - a));
    return r * c;
  }

  void _recalculatePrice() {
    if (_destinationLat != null && _destinationLon != null) {
      final dist = _haversineKm(
        _pickupLat,
        _pickupLon,
        _destinationLat!,
        _destinationLon!,
      );
      _tripDistanceKM = dist;
      final base = widget.service.tenantBasePrice > 0
          ? widget.service.tenantBasePrice
          : widget.service.basePrice;
      final rate = widget.service.tenantPricePerKM;
      _estimatedPrice = ((base + (dist * rate)) * 100).round() / 100;
    } else {
      _tripDistanceKM = null;
      _estimatedPrice = null;
    }
  }

  Future<void> _useCurrentLocationForPickup() async {
    try {
      final perm = await requestLocationPermission();
      if (perm == LocationPermissionResult.granted) {
        final pos = await Geolocator.getCurrentPosition();
        if (mounted) {
          setState(() {
            _pickupLat = pos.latitude;
            _pickupLon = pos.longitude;
            _recalculatePrice();
          });
        }
      } else {
        if (mounted) {
          ThemedSnackBar.showError(
            context,
            context.l10n.locationPermissionDeniedDefault,
          );
        }
      }
    } catch (e) {
      if (mounted) {
        ThemedSnackBar.showError(context, friendlyErrorMessage(e));
      }
    }
  }

  void _openLocationPicker({required bool isPickup}) {
    final l10n = context.l10n;
    LatLng tempLocation = isPickup
        ? LatLng(_pickupLat, _pickupLon)
        : LatLng(_destinationLat ?? _pickupLat, _destinationLon ?? _pickupLon);
    final screenWidth = MediaQuery.of(context).size.width;
    final screenHeight = MediaQuery.of(context).size.height;
    final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.95;
    final dialogHeight = screenHeight > 800 ? 600.0 : screenHeight * 0.75;

    showDialog(
      context: context,
      builder: (dialogCtx) {
        return Dialog(
          key: Key(isPickup
              ? 'pickup_location_picker_dialog'
              : 'destination_location_picker_dialog'),
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
                          isPickup
                              ? l10n.pickupLocationLabel
                              : l10n.destinationLocationLabel,
                          style: AppTypography.titleMd.copyWith(
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
                        tooltip: l10n.tooltipClose,
                        icon: const Icon(Icons.close),
                        onPressed: () => Navigator.of(dialogCtx).pop(),
                      ),
                    ],
                  ),
                  const SizedBox(height: AppSpacing.sm),
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(AppRadius.md),
                      child: LocationPickerMap(
                        initialLocation: tempLocation,
                        onLocationSelected: (newLocation) {
                          tempLocation = newLocation;
                        },
                      ),
                    ),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  PrimaryButton(
                    key: Key(isPickup
                        ? 'confirm_pickup_location_button'
                        : 'confirm_destination_location_button'),
                    text: l10n.locationPickerConfirmBtn,
                    trailingIcon: Icons.arrow_forward,
                    onPressed: () {
                      setState(() {
                        if (isPickup) {
                          _pickupLat = tempLocation.latitude;
                          _pickupLon = tempLocation.longitude;
                        } else {
                          _destinationLat = tempLocation.latitude;
                          _destinationLon = tempLocation.longitude;
                        }
                        _recalculatePrice();
                      });
                      Navigator.of(dialogCtx).pop();
                    },
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Future<void> _confirmBooking() async {
    final l10n = AppLocalizations.of(context)!;
    if (_destinationLat == null || _destinationLon == null) {
      ThemedSnackBar.showError(
        context,
        l10n.destinationRequiredError,
      );
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    final provider = Provider.of<MarketplaceProvider>(context, listen: false);
    try {
      final job = await provider.bookJob(
        serviceId: widget.service.id,
        userId: widget.userToken,
        latitude: _pickupLat,
        longitude: _pickupLon,
        destinationLatitude: _destinationLat!,
        destinationLongitude: _destinationLon!,
        paymentMethod: "cod", // forced COD only
      );

      if (!mounted) return;
      Navigator.of(context).pop(job); // close dialog and return created job
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      ThemedSnackBar.showError(
        context,
        l10n.bookingFailed(friendlyErrorMessage(e)),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final screenWidth = MediaQuery.of(context).size.width;
    final dialogWidth = screenWidth > 600 ? 500.0 : screenWidth * 0.92;
    final categoryLabel = serviceCategoryLabels[widget.service.category] ??
        widget.service.category;
    final hasDestination = _destinationLat != null && _destinationLon != null;

    return AlertDialog(
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      title: Text(
        l10n.confirmBookingTitle,
        style: AppTypography.titleMd.copyWith(
          color: Theme.of(context).colorScheme.onSurface,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SizedBox(
        width: dialogWidth,
        child: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                widget.service.name,
                style: AppTypography.headlineLgMobile.copyWith(
                  fontWeight: FontWeight.bold,
                  color: Theme.of(context).colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.categoryLine(categoryLabel),
                style: AppTypography.bodyMd.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: AppSpacing.md),
              const Divider(color: AppColors.outlineVariant),
              const SizedBox(height: AppSpacing.sm),

              // Pickup Location Block
              ThemedCard(
                padding: AppSpacing.sm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.trip_origin,
                            size: 18, color: AppColors.primary),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          l10n.pickupLocationLabel,
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Text(
                      "${_pickupLat.toStringAsFixed(4)}, ${_pickupLon.toStringAsFixed(4)}",
                      key: const Key('booking_pickup_coords_text'),
                      style: AppTypography.labelMd.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: Wrap(
                        alignment: WrapAlignment.end,
                        spacing: AppSpacing.xs,
                        children: [
                          TextButton.icon(
                            key:
                                const Key('use_current_location_pickup_button'),
                            icon: const Icon(Icons.my_location, size: 16),
                            label: Text(l10n.locationPickerUseMyLocation),
                            onPressed: _useCurrentLocationForPickup,
                          ),
                          TextButton.icon(
                            key: const Key('choose_pickup_button'),
                            icon: const Icon(Icons.edit_location_alt_outlined,
                                size: 16),
                            label: Text(l10n.changePickupLocationBtn),
                            onPressed: () =>
                                _openLocationPicker(isPickup: true),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),

              // Destination Location Block
              ThemedCard(
                padding: AppSpacing.sm,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        const Icon(Icons.location_on,
                            size: 18, color: AppColors.secondary),
                        const SizedBox(width: AppSpacing.xs),
                        Text(
                          l10n.destinationLocationLabel,
                          style: AppTypography.bodyMd.copyWith(
                            fontWeight: FontWeight.bold,
                            color: Theme.of(context).colorScheme.onSurface,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    if (hasDestination)
                      Text(
                        "${_destinationLat!.toStringAsFixed(4)}, ${_destinationLon!.toStringAsFixed(4)}",
                        key: const Key('booking_destination_coords_text'),
                        style: AppTypography.labelMd.copyWith(
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                        ),
                      )
                    else
                      Text(
                        l10n.selectDestinationPrompt,
                        style: AppTypography.bodySm.copyWith(
                          color: Theme.of(context).colorScheme.error,
                        ),
                      ),
                    const SizedBox(height: AppSpacing.xs),
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: OutlinedButton.icon(
                        key: const Key('choose_destination_button'),
                        icon: const Icon(Icons.map, size: 16),
                        label: Text(hasDestination
                            ? l10n.changeDestinationLocationBtn
                            : l10n.chooseDestinationLocationBtn),
                        onPressed: () => _openLocationPicker(isPickup: false),
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
              const Divider(color: AppColors.outlineVariant),
              const SizedBox(height: AppSpacing.sm),

              // Distance and Price Summary
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      l10n.tripDistanceLabel,
                      style: AppTypography.bodyMd.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _tripDistanceKM != null
                        ? l10n.kmUnitLine(_tripDistanceKM!.toStringAsFixed(2))
                        : " — ",
                    key: const Key('booking_trip_distance_text'),
                    style: AppTypography.bodyMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurface,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.sm),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Expanded(
                    child: Text(
                      l10n.estimatedTotalLabel,
                      style: AppTypography.bodyMd.copyWith(
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Text(
                    _estimatedPrice != null
                        ? l10n.creditsAmountLine(
                            _estimatedPrice!.toStringAsFixed(2))
                        : " — ",
                    key: const Key('booking_estimated_price_text'),
                    style: AppTypography.titleMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                ],
              ),
              const SizedBox(height: AppSpacing.xs),
              Text(
                l10n.estimatedPriceTripNotice,
                style: AppTypography.caption.copyWith(
                  color: Theme.of(context).colorScheme.onSurfaceVariant,
                  fontStyle: FontStyle.italic,
                ),
              ),
              const SizedBox(height: AppSpacing.lg),
              ThemedSectionHeader(
                title: l10n.paymentMethodLabel,
              ),
              const SizedBox(height: AppSpacing.xs),
              // Forced Option: Cash on Delivery (COD)
              ListTile(
                leading: Icon(
                  Icons.radio_button_checked,
                  color: Theme.of(context).colorScheme.primary,
                ),
                title: Text(
                  l10n.codOptionTitle,
                  style: AppTypography.bodyMd.copyWith(
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: Text(
                  l10n.codOptionSubtitle,
                  style: AppTypography.labelMd.copyWith(
                    color: Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                ),
                dense: true,
                contentPadding: EdgeInsets.zero,
              ),
              const SizedBox(height: AppSpacing.sm),
              // Inline note explaining escrow/other methods are deferred
              ThemedWarningBanner(
                message: l10n.betaEscrowNote,
              ),
            ],
          ),
        ),
      ),
      actionsPadding: const EdgeInsets.symmetric(
        horizontal: AppSpacing.lg,
        vertical: AppSpacing.md,
      ),
      actions: [
        Row(
          children: [
            Expanded(
              child: SecondaryButton(
                text: l10n.cancel,
                isOutlined: true,
                isFullWidth: false,
                onPressed:
                    _isSubmitting ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: AppSpacing.sm),
            Expanded(
              child: PrimaryButton(
                key: const Key('confirm_booking_button'),
                text: l10n.confirmAndRequestBtn,
                trailingIcon: Icons.arrow_forward,
                isLoading: _isSubmitting,
                isFullWidth: false,
                onPressed:
                    (_isSubmitting || !hasDestination) ? null : _confirmBooking,
              ),
            ),
          ],
        ),
      ],
    );
  }
}

class ServiceRatingWidget extends StatefulWidget {
  final String tenantId;

  const ServiceRatingWidget({super.key, required this.tenantId});

  @override
  State<ServiceRatingWidget> createState() => _ServiceRatingWidgetState();
}

class _ServiceRatingWidgetState extends State<ServiceRatingWidget> {
  double? _avg;
  int? _count;
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _loadRating();
  }

  Future<void> _loadRating() async {
    final provider = Provider.of<MarketplaceProvider>(context, listen: false);
    try {
      final res = await provider.fetchRatings(widget.tenantId);
      if (mounted) {
        setState(() {
          _avg = (res['average_rating'] as num?)?.toDouble() ?? 0.0;
          _count = (res['count'] as num?)?.toInt() ?? 0;
          _loading = false;
        });
      }
    } catch (_) {
      if (mounted) {
        setState(() {
          _loading = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_loading) {
      return const SizedBox.shrink();
    }
    if (_count == null || _count == 0) {
      return Text(
        context.l10n.noRatingsLabel,
        style: AppTypography.labelMd.copyWith(
          color: Theme.of(context).colorScheme.onSurfaceVariant,
        ),
      );
    }
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        const Icon(Icons.star, color: AppColors.secondary, size: 16),
        const SizedBox(width: AppSpacing.xs),
        Text(
          "${_avg!.toStringAsFixed(1)} ($_count)",
          style: AppTypography.labelMd.copyWith(
            fontWeight: FontWeight.bold,
            color: Theme.of(context).colorScheme.onSurface,
          ),
        ),
      ],
    );
  }
}
