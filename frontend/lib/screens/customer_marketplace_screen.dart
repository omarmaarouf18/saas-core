import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:provider/provider.dart';
import 'package:latlong2/latlong.dart';
import 'dart:math' as math;
import '../core/constants.dart';
import '../core/theme.dart';
import '../models/marketplace_service.dart';
import '../providers/auth_provider.dart';
import '../providers/marketplace_provider.dart';
import '../providers/notifications_provider.dart';
import '../widgets/location_picker_map.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/skeleton_loader.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_empty_state.dart';
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

  @override
  void initState() {
    super.initState();
    _nearBy = widget.initialNearBy;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadServices();
    });
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
                  child: Container(
                    padding: const EdgeInsetsDirectional.all(AppSpacing.xxs),
                    decoration: BoxDecoration(
                      color: AppColors.error,
                      borderRadius: BorderRadius.circular(AppRadius.radiusSmMd),
                    ),
                    constraints: const BoxConstraints(
                      minWidth: 16,
                      minHeight: 16,
                    ),
                    child: Text(
                      '${provider.unreadCount}',
                      style: AppTypography.labelMd.copyWith(
                        color: AppColors.onPrimary,
                        fontWeight: FontWeight.bold,
                        fontSize: 10,
                      ),
                      textAlign: TextAlign.center,
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

    final bodyContent = Column(
      children: [
        // Filter & Coordinates Control Panel
        Padding(
          padding: const EdgeInsets.all(AppSpacing.md),
          child: ThemedCard(
            elevation: AppElevation.shadowLevel1List,
            borderRadius: AppRadius.md,
            padding: AppSpacing.md,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Nearby Distance Filter Toggle Row
                Row(
                  children: [
                    Switch(
                      key: const Key('nearby_filter_switch'),
                      value: _nearBy,
                      activeTrackColor: AppColors.primary,
                      onChanged: (val) {
                        setState(() {
                          _nearBy = val;
                        });
                        _loadServices();
                      },
                    ),
                    const SizedBox(width: AppSpacing.xs),
                    Text(
                      l10n.customerMarketplaceFilterNearby,
                      style: AppTypography.bodyMd.copyWith(
                        color: AppColors.onSurface,
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.xs),
                // Location Picker & Radius row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 2,
                      child: OutlinedButton.icon(
                        key: const Key('choose_location_map_button'),
                        icon: const Icon(Icons.map_outlined,
                            color: AppColors.primary),
                        label: Text(
                          l10n.customerMarketplaceChooseMap,
                          overflow: TextOverflow.ellipsis,
                          style: AppTypography.bodyMd
                              .copyWith(fontWeight: FontWeight.w600),
                        ),
                        style: OutlinedButton.styleFrom(
                          padding: const EdgeInsets.symmetric(
                            vertical: AppSpacing.md,
                            horizontal: AppSpacing.sm,
                          ),
                          side:
                              const BorderSide(color: AppColors.outlineVariant),
                          shape: RoundedRectangleBorder(
                            borderRadius: AppRadius.defaultBorder,
                          ),
                        ),
                        onPressed: () => _openLocationPickerDialog(context),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.sm),
                    Expanded(
                      flex: 1,
                      child: ThemedTextField(
                        controller: _radiusController,
                        labelText: l10n.customerMarketplaceFilterRadius,
                        keyboardType: TextInputType.number,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: AppSpacing.md),
                // Filters row
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      flex: 3,
                      child: DropdownButtonFormField<String>(
                        initialValue: _selectedCategory,
                        isExpanded: true,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.customerMarketplaceFilterCategory,
                          labelStyle: AppTypography.labelLg.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppRadius.defaultBorder,
                            borderSide: const BorderSide(
                              color: AppColors.outlineVariant,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: AppRadius.defaultBorder,
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                              value: 'all',
                              child: Text(l10n.customerHomeCatBrowseAll)),
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
                      flex: 2,
                      child: DropdownButtonFormField<String>(
                        initialValue: _sortBy,
                        isExpanded: true,
                        style: AppTypography.bodyMd.copyWith(
                          color: AppColors.onSurface,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.sortByLabel,
                          labelStyle: AppTypography.labelLg.copyWith(
                            color: AppColors.onSurfaceVariant,
                          ),
                          filled: true,
                          fillColor: AppColors.surface,
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md,
                            vertical: AppSpacing.md,
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: AppRadius.defaultBorder,
                            borderSide: const BorderSide(
                              color: AppColors.outlineVariant,
                              width: 1,
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: AppRadius.defaultBorder,
                            borderSide: const BorderSide(
                              color: AppColors.primary,
                              width: 1.5,
                            ),
                          ),
                        ),
                        items: [
                          DropdownMenuItem(
                              value: 'price',
                              child: Text(l10n.filterSortPrice)),
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
                    ElevatedButton(
                      onPressed: _loadServices,
                      style: ElevatedButton.styleFrom(
                        padding: EdgeInsets.zero,
                        minimumSize: const Size(52, 52),
                        backgroundColor: AppColors.primary,
                        foregroundColor: AppColors.onPrimary,
                        shape: RoundedRectangleBorder(
                          borderRadius: AppRadius.defaultBorder,
                        ),
                        elevation: 0,
                      ),
                      child: const Icon(Icons.search),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ),
        // Services Listing
        Expanded(
          child: AnimatedSwitcher(
            duration: AppMotion.durationMedium,
            switchInCurve: AppMotion.curveStateChange,
            switchOutCurve: AppMotion.curveStateChange,
            child: marketplace.isLoading
                ? ListView.builder(
                    key: const ValueKey('marketplace_skeleton_list'),
                    padding:
                        const EdgeInsets.symmetric(horizontal: AppSpacing.md),
                    itemCount: 4,
                    itemBuilder: (context, index) =>
                        const MarketplaceCardSkeleton(),
                  )
                : filteredServices.isEmpty
                    ? SingleChildScrollView(
                        key: const ValueKey('marketplace_empty_state'),
                        physics: const AlwaysScrollableScrollPhysics(),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                              horizontal: AppSpacing.lg),
                          child: ThemedCard(
                            elevation: AppElevation.shadowLevel1List,
                            borderRadius: AppRadius.md,
                            padding: AppSpacing.lg,
                            child: ThemedEmptyState(
                              icon: Icons.search_off,
                              title: l10n.noServicesNearby,
                              description:
                                  "Try broadening your search radius or changing your coordinates.",
                              actionText: "Refresh List",
                              onActionPressed: _loadServices,
                            ),
                          ),
                        ),
                      )
                    : ListView.builder(
                        key: const ValueKey('marketplace_services_list'),
                        padding: const EdgeInsets.symmetric(
                            horizontal: AppSpacing.md),
                        itemCount: filteredServices.length,
                        itemBuilder: (context, index) {
                          final service = filteredServices[index];
                          final categoryLabel =
                              serviceCategoryLabels[service.category] ??
                                  service.category;

                          return Padding(
                            padding:
                                const EdgeInsets.only(bottom: AppSpacing.sm),
                            child: ThemedCard(
                              elevation: AppElevation.shadowLevel2List,
                              borderRadius: AppRadius.md,
                              padding: AppSpacing.md,
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CircleAvatar(
                                    backgroundColor: AppColors.secondary
                                        .withValues(alpha: 0.2),
                                    foregroundColor: AppColors.primary,
                                    child: Icon(
                                        _getCategoryIcon(service.category)),
                                  ),
                                  const SizedBox(width: AppSpacing.md),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          service.name,
                                          style: AppTypography.titleMd.copyWith(
                                            fontWeight: FontWeight.bold,
                                            color: AppColors.primary,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Row(
                                          children: [
                                            Container(
                                              padding:
                                                  const EdgeInsets.symmetric(
                                                      horizontal: 8,
                                                      vertical: 2),
                                              decoration: BoxDecoration(
                                                color: AppColors.primary
                                                    .withValues(alpha: 0.1),
                                                borderRadius:
                                                    BorderRadius.circular(
                                                        AppRadius.sm),
                                              ),
                                              child: Text(
                                                categoryLabel,
                                                style: AppTypography.labelMd
                                                    .copyWith(
                                                  fontSize: 12,
                                                  fontWeight: FontWeight.bold,
                                                  color: AppColors.primary,
                                                ),
                                              ),
                                            ),
                                            const SizedBox(
                                                width: AppSpacing.base),
                                            Text(
                                              "${service.distanceKM} km away",
                                              style:
                                                  AppTypography.bodyMd.copyWith(
                                                color:
                                                    AppColors.onSurfaceVariant,
                                              ),
                                            ),
                                            const SizedBox(
                                                width: AppSpacing.base),
                                            ServiceRatingWidget(
                                                tenantId: service.tenantId),
                                          ],
                                        ),
                                        const SizedBox(height: AppSpacing.base),
                                        Text(
                                          "Base: \$${service.tenantBasePrice} + \$${service.tenantPricePerKM}/km",
                                          style: AppTypography.bodyMd.copyWith(
                                            color: AppColors.onSurfaceVariant,
                                          ),
                                        ),
                                        const SizedBox(height: AppSpacing.xs),
                                        Text(
                                          "Est. Price: \$${service.finalPrice}",
                                          style: AppTypography.titleMd.copyWith(
                                            color: AppColors.secondary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  const SizedBox(width: AppSpacing.sm),
                                  SizedBox(
                                    width: 80,
                                    child: PrimaryButton(
                                      text: "Book",
                                      onPressed: () => _showBookingDialog(
                                          context, service, auth.token!),
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
    );

    if (widget.isEmbeddedInTab) {
      return Scaffold(
        backgroundColor: AppColors.scaffoldBackground,
        body: SizedBox.expand(child: bodyContent),
      );
    }

    return Scaffold(
      backgroundColor: AppColors.scaffoldBackground,
      appBar: AppBar(
        title: Text(l10n.customerMarketplaceTitle),
        backgroundColor: AppColors.primary,
        foregroundColor: AppColors.onPrimary,
        actions: [
          _buildNotificationBell(context),
        ],
      ),
      body: bodyContent,
    );
  }

  void _openLocationPickerDialog(BuildContext context) {
    LatLng tempLocation = LatLng(_customerLat, _customerLon);

    showDialog(
      context: context,
      builder: (dialogCtx) {
        final screenSize = MediaQuery.of(dialogCtx).size;
        final dialogWidth = math.min(500.0, screenSize.width * 0.9);
        final dialogHeight = math.min(550.0, screenSize.height * 0.8);

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
                      const Expanded(
                        child: Text(
                          "Choose Search Location",
                          style: TextStyle(
                            fontSize: 18,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                      IconButton(
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
                    text: "Confirm Location",
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

  void _showBookingDialog(
      BuildContext context, MarketplaceService service, String userToken) {
    showDialog(
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

  Future<void> _confirmBooking() async {
    setState(() {
      _isSubmitting = true;
    });

    final provider = Provider.of<MarketplaceProvider>(context, listen: false);
    try {
      final job = await provider.bookJob(
        serviceId: widget.service.id,
        userId: widget.userToken,
        latitude: widget.customerLat,
        longitude: widget.customerLon,
        paymentMethod: "cod", // forced COD only
      );

      if (!mounted) return;
      Navigator.of(context).pop(); // close dialog

      if (job != null) {
        Navigator.of(context).push(
          MaterialPageRoute(
            builder: (context) => JobStatusScreen(job: job),
          ),
        );
      }
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isSubmitting = false;
      });
      final l10n = AppLocalizations.of(context)!;
      ThemedSnackBar.showError(
        context,
        l10n.bookingFailed(e.toString()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final categoryLabel = serviceCategoryLabels[widget.service.category] ??
        widget.service.category;
    return AlertDialog(
      backgroundColor: AppColors.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(AppRadius.md),
      ),
      title: Text(
        "Confirm Booking",
        style: AppTypography.titleMd.copyWith(
          color: AppColors.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text(
              widget.service.name,
              style: AppTypography.headlineLgMobile.copyWith(
                fontWeight: FontWeight.bold,
                color: AppColors.onSurface,
              ),
            ),
            const SizedBox(height: AppSpacing.xs),
            Text(
              "Category: $categoryLabel",
              style: AppTypography.bodyMd.copyWith(
                color: AppColors.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: AppSpacing.md),
            const Divider(color: AppColors.outlineVariant),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Pickup Distance:",
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  "${widget.service.distanceKM} km",
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onSurface,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  "Estimated Total:",
                  style: AppTypography.bodyMd.copyWith(
                    color: AppColors.onSurface,
                  ),
                ),
                Text(
                  "\$${widget.service.finalPrice}",
                  style: AppTypography.titleMd.copyWith(
                    fontWeight: FontWeight.bold,
                    color: AppColors.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: AppSpacing.lg),
            ThemedSectionHeader(
              title: l10n.paymentMethodLabel,
            ),
            const SizedBox(height: AppSpacing.xs),
            // Forced Option: Cash on Delivery (COD)
            ListTile(
              leading: const Icon(
                Icons.radio_button_checked,
                color: AppColors.primary,
              ),
              title: Text(
                "Cash on Delivery (COD)",
                style: AppTypography.bodyMd.copyWith(
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                "Pay in cash directly to the driver upon arrival",
                style: AppTypography.labelMd.copyWith(
                  color: AppColors.onSurfaceVariant,
                ),
              ),
              dense: true,
              contentPadding: EdgeInsets.zero,
            ),
            const SizedBox(height: AppSpacing.sm),
            // Inline note explaining escrow/other methods are deferred
            Container(
              padding: const EdgeInsets.all(AppSpacing.sm),
              decoration: BoxDecoration(
                color: AppColors.warning.withValues(alpha: 0.1),
                border: Border.all(
                  color: AppColors.warning.withValues(alpha: 0.3),
                ),
                borderRadius: AppRadius.defaultBorder,
              ),
              child: Text(
                "Note: Escrow payments and wallet deductions are currently deferred for this beta launch.",
                style: AppTypography.labelMd.copyWith(
                  color: AppColors.warning,
                ),
              ),
            ),
          ],
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
                text: "Cancel",
                isOutlined: true,
                onPressed:
                    _isSubmitting ? null : () => Navigator.of(context).pop(),
              ),
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: PrimaryButton(
                text: "Confirm & Request",
                isLoading: _isSubmitting,
                onPressed: _confirmBooking,
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
        "No ratings",
        style: AppTypography.labelMd.copyWith(color: AppColors.outline),
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
            color: AppColors.onSurface,
          ),
        ),
      ],
    );
  }
}
