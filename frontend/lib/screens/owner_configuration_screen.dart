import 'package:flutter/material.dart';
import 'package:frontend/l10n/l10n.dart';
import 'package:image_picker/image_picker.dart';
import 'package:latlong2/latlong.dart';
import 'package:provider/provider.dart';
import '../core/constants.dart';
import '../core/error_messages.dart';
import '../core/theme.dart';
import '../providers/auth_provider.dart';
import '../providers/owner_provider.dart';
import '../widgets/themed_panel.dart';
import '../widgets/form_screen_template.dart';
import '../widgets/location_picker_dialog.dart';
import '../widgets/location_picker_map.dart';
import '../widgets/primary_button.dart';
import '../widgets/secondary_button.dart';
import '../widgets/themed_card.dart';
import '../widgets/themed_error_banner.dart';
import '../widgets/themed_loading_indicator.dart';
import '../widgets/themed_section_header.dart';
import '../widgets/themed_text_field.dart';
import '../widgets/themed_success_banner.dart';
import '../widgets/status_badge.dart';
import '../models/user_profile.dart';
import 'kyc_document_upload_screen.dart';

typedef ImagePickerCallback = Future<String?> Function(BuildContext context);

/// One per-day schedule row (ADR-0025). Times are null until picked;
/// isOff rows ignore their times server-side.
class _ScheduleDayRow {
  final String day;
  TimeOfDay? open;
  TimeOfDay? close;
  bool isOff;
  _ScheduleDayRow({
    required this.day,
    this.open,
    this.close,
    this.isOff = false,
  });
}

class OwnerConfigurationScreen extends StatefulWidget {
  final ImagePickerCallback? onPickImage;
  const OwnerConfigurationScreen({super.key, this.onPickImage});

  @override
  State<OwnerConfigurationScreen> createState() =>
      _OwnerConfigurationScreenState();
}

class _OwnerConfigurationScreenState extends State<OwnerConfigurationScreen> {
  final _formKey = GlobalKey<FormState>();

  final _nameController = TextEditingController();
  final _addressController = TextEditingController();
  final _workingHoursController = TextEditingController();
  final _radiusController = TextEditingController();
  final _basePriceController = TextEditingController();
  final _pricePerKmController = TextEditingController();
  final _photoUrlController = TextEditingController();

  String _selectedCategory = 'delivery';
  double? _latitude;
  double? _longitude;
  bool _isSubmitting = false;
  String? _errorMessage;
  String? _fetchError;
  String? _locationError;
  bool _isInitialized = false;
  Map<String, dynamic>? _existingService;

  // Weekly schedule editor state (ADR-0025). _scheduleTouched tracks owner
  // intent: pre-population from GET never sets it, so an untouched editor
  // sends none of the 5 schedule fields (unknown schedule stays unknown).
  // A touched editor with null mode sends schedule_mode:"" (explicit clear).
  bool _scheduleTouched = false;
  String? _scheduleMode; // 'same_daily' | 'per_day' | null
  TimeOfDay? _sameOpen;
  TimeOfDay? _sameClose;
  List<_ScheduleDayRow> _dayRows = [];

  static const List<String> _weekdayKeys = [
    'mon',
    'tue',
    'wed',
    'thu',
    'fri',
    'sat',
    'sun'
  ];

  static String toHHmm(TimeOfDay t) =>
      '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';

  static TimeOfDay? parseHHmm(String? s) {
    if (s == null) return null;
    final m = RegExp(r'^(\d{2}):(\d{2})$').firstMatch(s.trim());
    if (m == null) return null;
    final h = int.parse(m.group(1)!);
    final mi = int.parse(m.group(2)!);
    if (h > 23 || mi > 59) return null;
    return TimeOfDay(hour: h, minute: mi);
  }

  Future<void> _pickImage() async {
    if (widget.onPickImage != null) {
      final path = await widget.onPickImage!(context);
      if (path != null && mounted) {
        setState(() {
          _photoUrlController.text = path;
        });
      }
      return;
    }
    try {
      final picker = ImagePicker();
      final xfile = await picker.pickImage(source: ImageSource.gallery);
      if (xfile != null && mounted) {
        setState(() {
          _photoUrlController.text = xfile.path;
        });
      }
    } catch (_) {}
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _loadAndPrepopulate();
    });
  }

  Future<void> _loadAndPrepopulate() async {
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    final authProvider = Provider.of<AuthProvider>(context, listen: false);

    setState(() {
      _fetchError = null;
    });

    await authProvider.fetchUserProfile();

    if (ownerProvider.services.isEmpty) {
      await ownerProvider.fetchServices();
    }

    if (mounted) {
      if (ownerProvider.error != null && ownerProvider.services.isEmpty) {
        setState(() {
          _fetchError = ownerProvider.error;
          _isInitialized = true;
        });
        return;
      }

      final user = authProvider.user;
      final services = ownerProvider.services;
      Map<String, dynamic>? match;
      for (final s in services) {
        if (s is Map &&
            (s['tenant_id'] == user?.id || s['owner_id'] == user?.id)) {
          match = Map<String, dynamic>.from(s);
          break;
        }
      }

      if (match != null) {
        _existingService = match;
        _nameController.text = match['name']?.toString() ?? '';
        _selectedCategory = match['category']?.toString() ?? 'delivery';
        _addressController.text = match['address']?.toString() ?? '';
        _workingHoursController.text = match['working_hours']?.toString() ?? '';
        _radiusController.text = match['coverage_radius_km']?.toString() ?? '';
        _basePriceController.text =
            match['tenant_base_price']?.toString() ?? '';
        _pricePerKmController.text =
            match['tenant_price_per_km']?.toString() ?? '';
        _photoUrlController.text = match['photo_url']?.toString() ?? '';
        _populateSchedule(match);
        final rawLat = match['latitude'];
        final rawLon = match['longitude'];
        _latitude = (rawLat as num?)?.toDouble() ?? 30.0444;
        _longitude = (rawLon as num?)?.toDouble() ?? 31.2357;
      }

      setState(() {
        _isInitialized = true;
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _addressController.dispose();
    _workingHoursController.dispose();
    _radiusController.dispose();
    _basePriceController.dispose();
    _pricePerKmController.dispose();
    _photoUrlController.dispose();
    super.dispose();
  }

  void _openLocationPickerDialog(BuildContext context) {
    LatLng tempLocation = (_latitude != null && _longitude != null)
        ? LatLng(_latitude!, _longitude!)
        : LocationPickerMap.cairoDefault;

    LocationPickerDialog.show(
      context,
      title: context.l10n.customerMarketplaceChooseMap,
      initialLocation: tempLocation,
      confirmLabel: context.l10n.locationPickerConfirmBtn,
      confirmButtonKey: const Key('confirm_location_button'),
      onConfirmed: (picked) {
        setState(() {
          _latitude = picked.latitude;
          _longitude = picked.longitude;
          _locationError = null;
        });
      },
    );
  }

  /// Pre-populates the schedule editor from a GET service map (ADR-0025).
  /// Never marks the editor touched: loaded values submit as no-ops unless
  /// the owner edits them. Malformed stored data degrades to untouched.
  void _populateSchedule(Map<String, dynamic> match) {
    _scheduleTouched = false;
    _scheduleMode = null;
    _sameOpen = null;
    _sameClose = null;
    _dayRows = [];
    final mode = match['schedule_mode']?.toString();
    if (mode == 'same_daily') {
      final o = parseHHmm(match['open_time']?.toString());
      final c = parseHHmm(match['close_time']?.toString());
      if (o != null && c != null) {
        _scheduleMode = mode;
        _sameOpen = o;
        _sameClose = c;
      }
    } else if (mode == 'per_day') {
      final raw = match['per_day_schedule'];
      if (raw is List && raw.length == 7) {
        final rows = <_ScheduleDayRow>[];
        final seen = <String>{};
        var valid = true;
        for (final e in raw) {
          if (e is! Map) {
            valid = false;
            break;
          }
          final day = e['day']?.toString().toLowerCase() ?? '';
          if (!_weekdayKeys.contains(day) || !seen.add(day)) {
            valid = false;
            break;
          }
          rows.add(_ScheduleDayRow(
            day: day,
            open: parseHHmm(e['open_time']?.toString()),
            close: parseHHmm(e['close_time']?.toString()),
            isOff: e['is_off'] == true,
          ));
        }
        if (valid) {
          _scheduleMode = mode;
          _dayRows = rows;
        }
      }
    }
  }

  Future<void> _submitForm() async {
    final l10n = context.l10n;
    setState(() {
      _errorMessage = null;
      _locationError = null;
    });

    if (!_formKey.currentState!.validate()) {
      return;
    }

    if (_latitude == null || _longitude == null) {
      setState(() {
        _locationError = l10n.ownerConfigLocationReq;
      });
      return;
    }

    final radius = double.tryParse(_radiusController.text.trim()) ?? 0.0;
    final basePrice = double.tryParse(_basePriceController.text.trim()) ?? 0.0;
    final pricePerKm =
        double.tryParse(_pricePerKmController.text.trim()) ?? 0.0;

    final authProvider = Provider.of<AuthProvider>(context, listen: false);
    final ownerProvider = Provider.of<OwnerProvider>(context, listen: false);
    final user = authProvider.user;

    if (user == null) {
      setState(() {
        _errorMessage = l10n.userNotAuthenticatedError;
      });
      return;
    }

    setState(() {
      _isSubmitting = true;
    });

    try {
      final serviceId = _existingService?['id']?.toString() ??
          _existingService?['service_id']?.toString() ??
          '';

      // Weekly schedule payload (ADR-0025). Untouched editors send none of
      // the 5 fields (unknown stays unknown); a touched-but-cleared editor
      // sends schedule_mode:"" (explicit clear); timezone is left null so
      // the backend default (Africa/Cairo) applies.
      String? scheduleMode;
      String? openTime;
      String? closeTime;
      List<Map<String, dynamic>>? perDaySchedule;
      if (_scheduleTouched) {
        if (_scheduleMode == null) {
          scheduleMode = '';
        } else if (_scheduleMode == 'same_daily') {
          scheduleMode = 'same_daily';
          if (_sameOpen != null) openTime = toHHmm(_sameOpen!);
          if (_sameClose != null) closeTime = toHHmm(_sameClose!);
        } else {
          scheduleMode = 'per_day';
          perDaySchedule = _dayRows
              .map((r) => {
                    'day': r.day,
                    'open_time': r.open != null ? toHHmm(r.open!) : '',
                    'close_time': r.close != null ? toHHmm(r.close!) : '',
                    'is_off': r.isOff,
                  })
              .toList();
        }
      }

      if (serviceId.isNotEmpty) {
        await ownerProvider.updateOwnerServiceConfig(
          serviceId: serviceId,
          ownerId: user.id,
          name: _nameController.text.trim(),
          category: _selectedCategory,
          tenantBasePrice: basePrice,
          tenantPricePerKM: pricePerKm,
          photoUrl: _photoUrlController.text.trim(),
          address: _addressController.text.trim(),
          workingHours: _workingHoursController.text.trim(),
          coverageRadiusKm: radius,
          latitude: _latitude,
          longitude: _longitude,
          scheduleMode: scheduleMode,
          openTime: openTime,
          closeTime: closeTime,
          perDaySchedule: perDaySchedule,
        );
      } else {
        await ownerProvider.createService(
          name: _nameController.text.trim(),
          category: _selectedCategory,
          tenantBasePrice: basePrice,
          tenantPricePerKM: pricePerKm,
          latitude: _latitude!,
          longitude: _longitude!,
          ownerId: user.id,
        );
      }

      await authProvider.fetchUserProfile();

      if (mounted) {
        ThemedSnackBar.showSuccess(context, l10n.ownerConfigSuccessMsg);
        if (Navigator.canPop(context)) {
          Navigator.pop(context);
        }
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = friendlyErrorMessage(e);
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _isSubmitting = false;
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final auth = Provider.of<AuthProvider>(context);
    final user = auth.user;
    final isKycApproved = user?.kycStatus == 'approved';

    return FormScreenTemplate(
      title: l10n.ownerConfigTitle,
      padding: const EdgeInsets.all(AppSpacing.lg),
      body: !_isInitialized
          ? Center(child: ThemedLoadingIndicator(message: l10n.loading))
          : Form(
              key: _formKey,
              autovalidateMode: AutovalidateMode.onUserInteraction,
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  ThemedSectionHeader(
                    title: l10n.ownerConfigHeader,
                    subtitle: l10n.ownerConfigHeaderSub,
                  ),
                  const SizedBox(height: AppSpacing.md),
                  if (_fetchError != null) ...[
                    ThemedErrorBanner(
                      key: const Key('owner_config_fetch_error_banner'),
                      message: _fetchError!,
                      onRetry: _loadAndPrepopulate,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  if (_errorMessage != null) ...[
                    ThemedErrorBanner(
                      key: const Key('owner_config_error_banner'),
                      message: _errorMessage!,
                      onRetry: _submitForm,
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  if (user != null && !isKycApproved) ...[
                    _buildKycBanner(context, l10n, user),
                    const SizedBox(height: AppSpacing.md),
                  ],

                  // Section 1: Business Identity Card (Stitch Reference)
                  _buildBusinessIdentityCard(l10n, user),
                  const SizedBox(height: AppSpacing.lg),

                  // Section 2: Location & Operations Card (Stitch Reference)
                  _buildLocationOperationsCard(l10n),
                  const SizedBox(height: AppSpacing.lg),

                  // Section 3: Weekly Schedule Card (ADR-0025)
                  _buildScheduleCard(l10n),
                  const SizedBox(height: AppSpacing.lg),

                  // Section 4: Pricing Structure Card (Stitch Reference)
                  _buildPricingStructureCard(l10n),
                  const SizedBox(height: AppSpacing.xl),

                  // Section 5: Primary Save Action Button
                  _buildSaveButton(l10n),
                ],
              ),
            ),
    );
  }

  Widget _buildKycBanner(
      BuildContext context, AppLocalizations l10n, UserProfile user) {
    final isRejected = user.kycStatus == 'rejected';
    final isPending = user.kycStatus == 'pending_super_admin_approval';

    String subtitle = l10n.settingsKycSubtitleDefault;
    IconData icon = Icons.verified_user_outlined;
    Color iconColor = Theme.of(context).colorScheme.onSurfaceVariant;

    if (isRejected) {
      subtitle = l10n.settingsKycSubtitleRejected;
      icon = Icons.gavel_outlined;
      iconColor = context.semanticColors.danger;
    } else if (isPending) {
      subtitle = l10n.settingsKycSubtitlePending;
      icon = Icons.hourglass_empty_rounded;
      iconColor = context.semanticColors.warning;
    }

    return InkWell(
      key: const Key('owner_config_kyc_banner'),
      borderRadius: BorderRadius.circular(AppRadius.md),
      onTap: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => const KycDocumentUploadScreen(),
          ),
        );
      },
      child: ThemedPanel(
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(AppRadius.md),
        border: Border.all(
          color: AppColors.outlineVariant.withValues(alpha: 0.5),
        ),
        padding: const EdgeInsets.all(AppSpacing.md),
        child: Row(
          children: [
            Icon(
              icon,
              color: iconColor,
              size: 22,
            ),
            const SizedBox(width: AppSpacing.md),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    context.l10n.settingsKycRowTitle,
                    style: AppTypography.titleMd.copyWith(
                      fontWeight: FontWeight.bold,
                      color: Theme.of(context).colorScheme.onSurface,
                    ),
                  ),
                  const SizedBox(height: AppSpacing.xxs),
                  Text(
                    subtitle,
                    style: AppTypography.bodyMd.copyWith(
                      color: Theme.of(context).colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBusinessIdentityCard(AppLocalizations l10n, UserProfile? user) {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThemedPanel(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  width: 36,
                  height: 36,
                  child: const Center(
                    child: Icon(
                      Icons.storefront_outlined,
                      color: AppColors.secondary,
                      size: AppIconSize.smMd,
                    ),
                  )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.sectionBusinessIdentity,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      context.l10n.sectionBusinessIdentitySub,
                      style: AppTypography.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              if (user != null) ...[
                const SizedBox(width: AppSpacing.xs),
                StatusBadge(
                  key: const Key('owner_config_kyc_status_badge'),
                  status: user.kycStatus ?? 'unverified',
                ),
              ],
            ],
          ),
          const Divider(
            height: AppSpacing.lg,
            color: AppColors.outlineVariant,
          ),
          // Logo Upload / Picker Area
          Row(
            children: [
              ThemedPanel(
                  color: Theme.of(context).colorScheme.surfaceContainerHigh,
                  borderRadius: BorderRadius.circular(AppRadius.full),
                  border: Border.all(
                    color: AppColors.outlineVariant,
                  ),
                  width: 64,
                  height: 64,
                  clipBehavior: Clip.antiAlias,
                  child: _photoUrlController.text.isNotEmpty
                      ? (_photoUrlController.text.startsWith('http')
                          ? Image.network(
                              _photoUrlController.text,
                              fit: BoxFit.cover,
                              errorBuilder: (_, __, ___) => Icon(
                                Icons.business_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: AppIconSize.lg,
                              ),
                            )
                          : Icon(
                              Icons.image_outlined,
                              color: Theme.of(context).colorScheme.primary,
                              size: AppIconSize.lg,
                            ))
                      : Icon(
                          Icons.add_a_photo_outlined,
                          color: Theme.of(context).colorScheme.onSurfaceVariant,
                          size: AppIconSize.lg,
                        )),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _photoUrlController.text.isNotEmpty
                          ? _photoUrlController.text
                          : l10n.ownerConfigPhotoUrlHint,
                      key: const Key('owner_config_photo_url_field'),
                      maxLines: 2,
                      overflow: TextOverflow.ellipsis,
                      style: AppTypography.bodyMd.copyWith(
                        color: _photoUrlController.text.isNotEmpty
                            ? Theme.of(context).colorScheme.onSurface
                            : AppColors.outline,
                      ),
                    ),
                    const SizedBox(height: AppSpacing.xs),
                    SecondaryButton(
                      key: const Key('owner_config_pick_image_button'),
                      icon: Icons.upload_file_outlined,
                      text: l10n.tooltipPickImage,
                      isOutlined: true,
                      isFullWidth: false,
                      onPressed: _pickImage,
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          ThemedTextField(
            key: const Key('owner_config_name_field'),
            labelText: l10n.ownerConfigNameLabel,
            hintText: l10n.ownerConfigNameHint,
            controller: _nameController,
            validator: (v) =>
                v == null || v.trim().isEmpty ? l10n.ownerConfigNameReq : null,
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.ownerConfigCategoryLabel,
            style: AppTypography.labelMd.copyWith(
              fontWeight: FontWeight.bold,
              color: Theme.of(context).colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          DropdownButtonFormField<String>(
            key: const Key('owner_config_category_dropdown'),
            initialValue: serviceCategoryLabels.containsKey(_selectedCategory)
                ? _selectedCategory
                : 'delivery',
            decoration: InputDecoration(
              filled: true,
              fillColor: Theme.of(context).colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(
                horizontal: AppSpacing.md,
                vertical: AppSpacing.sm,
              ),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(AppRadius.md),
                borderSide: const BorderSide(color: AppColors.outlineVariant),
              ),
            ),
            items: serviceCategoryLabels.entries.map((e) {
              return DropdownMenuItem<String>(
                value: e.key,
                child: Text(e.value),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                setState(() {
                  _selectedCategory = val;
                });
              }
            },
          ),
        ],
      ),
    );
  }

  Widget _buildLocationOperationsCard(AppLocalizations l10n) {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThemedPanel(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  width: 36,
                  height: 36,
                  child: const Center(
                    child: Icon(
                      Icons.location_on_outlined,
                      color: AppColors.secondary,
                      size: AppIconSize.smMd,
                    ),
                  )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.sectionLocationOperations,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      context.l10n.sectionLocationOperationsSub,
                      style: AppTypography.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(
            height: AppSpacing.lg,
            color: AppColors.outlineVariant,
          ),
          ThemedTextField(
            key: const Key('owner_config_address_field'),
            labelText: l10n.ownerConfigAddressLabel,
            hintText: l10n.ownerConfigAddressHint,
            controller: _addressController,
            validator: (v) {
              if (v != null && v.trim().isNotEmpty && v.trim().length < 3) {
                return l10n.ownerConfigAddressInvalid;
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          Text(
            l10n.ownerConfigLocationLabel,
            style: AppTypography.labelLg.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: AppSpacing.xs),
          ThemedPanel(
              color: Theme.of(context).colorScheme.surfaceContainerLow,
              borderRadius: BorderRadius.circular(AppRadius.md),
              border: Border.all(
                color: _locationError != null
                    ? context.semanticColors.danger
                    : AppColors.outlineVariant.withValues(alpha: 0.4),
              ),
              padding: const EdgeInsets.all(AppSpacing.md),
              child: LayoutBuilder(builder: (context, constraints) {
                final wide = constraints.maxWidth > 420;
                final coordinateText = Text(
                  (_latitude != null && _longitude != null)
                      ? "Lat: ${_latitude!.toStringAsFixed(4)}, Lon: ${_longitude!.toStringAsFixed(4)}"
                      : l10n.noLocationSelectedLabel,
                  key: const Key('owner_config_location_text'),
                  style: AppTypography.bodyMd.copyWith(
                    color: (_latitude != null && _longitude != null)
                        ? Theme.of(context).colorScheme.onSurface
                        : Theme.of(context).colorScheme.onSurfaceVariant,
                  ),
                );
                final pickerButton = SecondaryButton(
                  key: const Key('owner_config_location_picker_button'),
                  icon: Icons.map_outlined,
                  text: l10n.customerMarketplaceChooseMap,
                  isOutlined: true,
                  isFullWidth: !wide,
                  onPressed: () => _openLocationPickerDialog(context),
                );
                return wide
                    ? Row(
                        children: [
                          Icon(
                            Icons.location_on_outlined,
                            color: Theme.of(context).colorScheme.primary,
                            size: AppIconSize.md,
                          ),
                          const SizedBox(width: AppSpacing.sm),
                          Expanded(child: coordinateText),
                          const SizedBox(width: AppSpacing.sm),
                          pickerButton,
                        ],
                      )
                    : Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Icon(
                                Icons.location_on_outlined,
                                color: Theme.of(context).colorScheme.primary,
                                size: AppIconSize.md,
                              ),
                              const SizedBox(width: AppSpacing.sm),
                              Expanded(child: coordinateText),
                            ],
                          ),
                          const SizedBox(height: AppSpacing.sm),
                          pickerButton,
                        ],
                      );
              })),
          if (_locationError != null) ...[
            const SizedBox(height: AppSpacing.xs),
            Text(
              _locationError!,
              key: const Key('owner_config_location_inline_error'),
              style: AppTypography.caption.copyWith(
                color: context.semanticColors.danger,
              ),
            ),
          ],
          const SizedBox(height: AppSpacing.md),
          ThemedTextField(
            key: const Key('owner_config_working_hours_field'),
            labelText: l10n.ownerConfigHoursLabel,
            hintText: l10n.ownerConfigHoursHint,
            controller: _workingHoursController,
            validator: (v) {
              if (v != null && v.trim().isNotEmpty && v.trim().length < 3) {
                return l10n.ownerConfigHoursInvalid;
              }
              return null;
            },
          ),
          const SizedBox(height: AppSpacing.md),
          ThemedTextField(
            key: const Key('owner_config_radius_field'),
            labelText: l10n.ownerConfigRadiusLabel,
            hintText: l10n.ownerConfigRadiusHint,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            controller: _radiusController,
            validator: (v) {
              if (v == null || v.trim().isEmpty) {
                return l10n.ownerConfigRadiusReq;
              }
              final parsed = double.tryParse(v.trim());
              if (parsed == null || parsed <= 0) {
                return l10n.ownerConfigRadiusReq;
              }
              return null;
            },
          ),
        ],
      ),
    );
  }

  String _dayLabel(AppLocalizations l10n, String day) {
    switch (day) {
      case 'mon':
        return l10n.scheduleDayMon;
      case 'tue':
        return l10n.scheduleDayTue;
      case 'wed':
        return l10n.scheduleDayWed;
      case 'thu':
        return l10n.scheduleDayThu;
      case 'fri':
        return l10n.scheduleDayFri;
      case 'sat':
        return l10n.scheduleDaySat;
      case 'sun':
      default:
        return l10n.scheduleDaySun;
    }
  }

  Future<void> _pickScheduleTime({
    required TimeOfDay initial,
    required ValueChanged<TimeOfDay> onPicked,
  }) async {
    final picked = await showTimePicker(
      context: context,
      initialTime: initial,
    );
    if (picked != null && mounted) {
      setState(() {
        _scheduleTouched = true;
        onPicked(picked);
      });
    }
  }

  String _timeText(TimeOfDay? t, String fallback) =>
      t == null ? fallback : toHHmm(t);

  Widget _buildScheduleCard(AppLocalizations l10n) {
    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThemedPanel(
                  color: AppColors.primaryContainer,
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  width: 36,
                  height: 36,
                  child: const Center(
                    child: Icon(
                      Icons.schedule_outlined,
                      color: AppColors.secondary,
                      size: AppIconSize.smMd,
                    ),
                  )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      l10n.scheduleTitle,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      l10n.scheduleSubtitle,
                      style: AppTypography.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(
            height: AppSpacing.lg,
            color: AppColors.outlineVariant,
          ),
          if (_scheduleMode == null)
            SecondaryButton(
              key: const Key('schedule_set_hours_button'),
              icon: Icons.schedule_outlined,
              text: l10n.scheduleSetBtn,
              isOutlined: true,
              isFullWidth: false,
              onPressed: () {
                setState(() {
                  _scheduleTouched = true;
                  _scheduleMode = 'same_daily';
                  _sameOpen ??= const TimeOfDay(hour: 9, minute: 0);
                  _sameClose ??= const TimeOfDay(hour: 17, minute: 0);
                });
              },
            )
          else ...[
            SegmentedButton<String>(
              key: const Key('schedule_mode_toggle'),
              segments: [
                ButtonSegment(
                  value: 'same_daily',
                  label: Text(
                    l10n.scheduleModeSameDaily,
                    key: const Key('schedule_mode_same_daily_button'),
                    style: AppTypography.labelLg.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                ButtonSegment(
                  value: 'per_day',
                  label: Text(
                    l10n.scheduleModePerDay,
                    key: const Key('schedule_mode_per_day_button'),
                    style: AppTypography.labelLg.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
              selected: {_scheduleMode!},
              onSelectionChanged: (selection) {
                setState(() {
                  _scheduleTouched = true;
                  _scheduleMode = selection.first;
                  if (_scheduleMode == 'same_daily') {
                    _sameOpen ??= const TimeOfDay(hour: 9, minute: 0);
                    _sameClose ??= const TimeOfDay(hour: 17, minute: 0);
                  } else {
                    if (_dayRows.isEmpty) {
                      _dayRows = _weekdayKeys
                          .map((d) => _ScheduleDayRow(
                                day: d,
                                open: const TimeOfDay(hour: 9, minute: 0),
                                close: const TimeOfDay(hour: 17, minute: 0),
                              ))
                          .toList();
                    }
                  }
                });
              },
            ),
            const SizedBox(height: AppSpacing.md),
            if (_scheduleMode == 'same_daily') ...[
              Row(
                children: [
                  Expanded(
                    child: SecondaryButton(
                      key: const Key('schedule_open_time_button'),
                      icon: Icons.access_time,
                      text:
                          '${l10n.scheduleOpenLabel}: ${_timeText(_sameOpen, '--:--')}',
                      isOutlined: true,
                      isFullWidth: true,
                      onPressed: () => _pickScheduleTime(
                        initial:
                            _sameOpen ?? const TimeOfDay(hour: 9, minute: 0),
                        onPicked: (t) => _sameOpen = t,
                      ),
                    ),
                  ),
                  const SizedBox(width: AppSpacing.sm),
                  Expanded(
                    child: SecondaryButton(
                      key: const Key('schedule_close_time_button'),
                      icon: Icons.access_time,
                      text:
                          '${l10n.scheduleCloseLabel}: ${_timeText(_sameClose, '--:--')}',
                      isOutlined: true,
                      isFullWidth: true,
                      onPressed: () => _pickScheduleTime(
                        initial:
                            _sameClose ?? const TimeOfDay(hour: 17, minute: 0),
                        onPicked: (t) => _sameClose = t,
                      ),
                    ),
                  ),
                ],
              ),
            ] else ...[
              Theme(
                data: Theme.of(context)
                    .copyWith(dividerColor: Colors.transparent),
                child: Material(
                  color: Colors.transparent,
                  child: ExpansionTile(
                    key: const Key('schedule_per_day_expansion_tile'),
                    initiallyExpanded: true,
                    tilePadding: EdgeInsets.zero,
                    title: Text(
                      l10n.scheduleModePerDay,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    children: [
                      for (final row in _dayRows) ...[
                        Padding(
                          padding: const EdgeInsets.only(bottom: AppSpacing.xs),
                          child: Row(
                            children: [
                              Expanded(
                                flex: 2,
                                child: Text(
                                  _dayLabel(l10n, row.day),
                                  style: AppTypography.bodyMd.copyWith(
                                    color:
                                        Theme.of(context).colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              Expanded(
                                flex: 3,
                                child: SecondaryButton(
                                  key: Key(
                                      'schedule_day_${row.day}_open_button'),
                                  text: _timeText(row.open, '--:--'),
                                  isOutlined: true,
                                  isFullWidth: true,
                                  onPressed: row.isOff
                                      ? null
                                      : () => _pickScheduleTime(
                                            initial: row.open ??
                                                const TimeOfDay(
                                                    hour: 9, minute: 0),
                                            onPicked: (t) => row.open = t,
                                          ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Expanded(
                                flex: 3,
                                child: SecondaryButton(
                                  key: Key(
                                      'schedule_day_${row.day}_close_button'),
                                  text: _timeText(row.close, '--:--'),
                                  isOutlined: true,
                                  isFullWidth: true,
                                  onPressed: row.isOff
                                      ? null
                                      : () => _pickScheduleTime(
                                            initial: row.close ??
                                                const TimeOfDay(
                                                    hour: 17, minute: 0),
                                            onPicked: (t) => row.close = t,
                                          ),
                                ),
                              ),
                              const SizedBox(width: AppSpacing.xs),
                              Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Text(
                                    l10n.scheduleOffLabel,
                                    style: AppTypography.labelMd.copyWith(
                                      color: Theme.of(context)
                                          .colorScheme
                                          .onSurfaceVariant,
                                    ),
                                  ),
                                  Switch(
                                    key: Key(
                                        'schedule_day_${row.day}_off_switch'),
                                    value: row.isOff,
                                    onChanged: (v) {
                                      setState(() {
                                        _scheduleTouched = true;
                                        row.isOff = v;
                                      });
                                    },
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ],
            const SizedBox(height: AppSpacing.sm),
            Align(
              alignment: AlignmentDirectional.centerEnd,
              child: SecondaryButton(
                key: const Key('schedule_remove_button'),
                text: l10n.scheduleRemoveBtn,
                isOutlined: true,
                isFullWidth: false,
                onPressed: () {
                  setState(() {
                    // Touched stays true: submit sends schedule_mode:""
                    // (explicit clear) rather than sending nothing.
                    _scheduleMode = null;
                  });
                },
              ),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildPricingStructureCard(AppLocalizations l10n) {
    final basePriceVal = double.tryParse(_basePriceController.text) ?? 0.0;
    final pricePerKmVal = double.tryParse(_pricePerKmController.text) ?? 0.0;
    final est10km = basePriceVal + (pricePerKmVal * 10);

    return ThemedCard(
      borderRadius: AppRadius.md,
      padding: AppSpacing.lg,
      borderSide: BorderSide(
        color: context.semanticColors.success.withValues(alpha: 0.35),
      ),
      topAccentColor: context.semanticColors.success,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              ThemedPanel(
                  color: context.semanticColors.success.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(AppRadius.sm),
                  width: 36,
                  height: 36,
                  child: Center(
                    child: Icon(
                      Icons.payments_outlined,
                      color: context.semanticColors.success,
                      size: AppIconSize.smMd,
                    ),
                  )),
              const SizedBox(width: AppSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      context.l10n.sectionPricingStructure,
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: Theme.of(context).colorScheme.onSurface,
                      ),
                    ),
                    Text(
                      context.l10n.sectionPricingStructureSub,
                      style: AppTypography.caption.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const Divider(
            height: AppSpacing.lg,
            color: AppColors.outlineVariant,
          ),
          Row(
            children: [
              Expanded(
                child: ThemedTextField(
                  key: const Key('owner_config_base_price_field'),
                  labelText: l10n.ownerConfigBasePriceLabel,
                  hintText: l10n.ownerConfigBasePriceHint,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  controller: _basePriceController,
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.ownerConfigBasePriceReq;
                    }
                    final parsed = double.tryParse(v.trim());
                    if (parsed == null || parsed < 0) {
                      return l10n.ownerConfigBasePriceReq;
                    }
                    return null;
                  },
                ),
              ),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: ThemedTextField(
                  key: const Key('owner_config_price_per_km_field'),
                  labelText: l10n.ownerConfigPricePerKmLabel,
                  hintText: l10n.ownerConfigPricePerKmHint,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  controller: _pricePerKmController,
                  onChanged: (_) => setState(() {}),
                  validator: (v) {
                    if (v == null || v.trim().isEmpty) {
                      return l10n.ownerConfigPricePerKmReq;
                    }
                    final parsed = double.tryParse(v.trim());
                    if (parsed == null || parsed < 0) {
                      return l10n.ownerConfigPricePerKmReq;
                    }
                    return null;
                  },
                ),
              ),
            ],
          ),
          if (est10km > 0) ...[
            const SizedBox(height: AppSpacing.md),
            ThemedPanel(
                color: Theme.of(context).colorScheme.surfaceContainerLow,
                borderRadius: BorderRadius.circular(AppRadius.sm),
                padding: const EdgeInsets.symmetric(
                  horizontal: AppSpacing.md,
                  vertical: AppSpacing.sm,
                ),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    Text(
                      context.l10n.estDelivery10kmLabel,
                      style: AppTypography.labelMd.copyWith(
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                    ),
                    Text(
                      "\$${est10km.toStringAsFixed(2)}",
                      style: AppTypography.titleMd.copyWith(
                        fontWeight: FontWeight.bold,
                        color: AppColors.secondary,
                      ),
                    ),
                  ],
                )),
          ],
        ],
      ),
    );
  }

  Widget _buildSaveButton(AppLocalizations l10n) {
    return ThemedPanel(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(AppRadius.md),
      padding: const EdgeInsets.all(AppSpacing.md),
      border: Border.all(
        color: AppColors.outlineVariant.withValues(alpha: 0.4),
      ),
      child: PrimaryButton(
        key: const Key('owner_config_save_button'),
        text: l10n.ownerConfigSaveButton,
        trailingIcon: Icons.arrow_forward,
        isLoading: _isSubmitting,
        onPressed: _submitForm,
      ),
    );
  }
}
