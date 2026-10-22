import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../../core/error_messages.dart';
import '../../l10n/l10n.dart';
import '../../providers/auth_provider.dart';
import '../../providers/owner_provider.dart';
import '../../ui/qd_ui.dart';
import '../customer/customer_location.dart';
import '../customer/picker_page.dart';
import 'owner_nav.dart';
import 'owner_sheets.dart';
import 'owner_widgets.dart';
import 'service_rules.dart';

typedef ServicePlacePicker = Future<PickedPlace?> Function(
    BuildContext context, PickedPlace? initial);
typedef ServiceTimePicker = Future<TimeOfDay?> Function(
    BuildContext context, TimeOfDay initial);

/// Service setup (O-Service): business, place and coverage, working hours
/// and pricing, with one save button.
///
/// Behaviour kept from OwnerConfigurationScreen: the profile (KYB status)
/// and the services list are fetched on open, the owner's service is the
/// one whose `tenant_id` / `owner_id` is theirs, the fields and the weekly
/// schedule are prefilled, an untouched schedule is not sent (ADR-0025),
/// the same field rules, a KYB banner while not approved, and on success
/// the profile is re-read, a notice is shown and the page closes.
/// Changed: no photo picker (there is no upload endpoint, `photo_url`
/// stored a local path), the initial-letter tile instead and `photo_url` is
/// never sent; the free-text working hours field is gone (its stored value
/// is kept); a first save is POST + PUT (see [saveService]).
class OwnerServicePage extends StatefulWidget {
  const OwnerServicePage({super.key, this.pickPlace, this.pickTime});

  /// Location picker (tests); default: the redesigned picker (A-Picker).
  final ServicePlacePicker? pickPlace;

  /// Time picker (tests); default: [showTimePicker].
  final ServiceTimePicker? pickTime;

  static Future<void> open(BuildContext context) => Navigator.of(context)
      .push<void>(qdPageRoute((_) => const OwnerServicePage()));

  @override
  State<OwnerServicePage> createState() => _OwnerServicePageState();
}

class _OwnerServicePageState extends State<OwnerServicePage> {
  final _name = TextEditingController();
  final _address = TextEditingController();
  final _radius = TextEditingController();
  final _baseFee = TextEditingController();
  final _perKm = TextEditingController();

  bool _loading = true;
  String? _loadError;
  String? _serviceId;
  String _category = kServiceCategories.first;
  double? _lat;
  double? _lon;
  ServiceHours _hours = ServiceHours();

  /// Field problems are shown once a save was tried, then kept live.
  bool _tried = false;
  bool _saving = false;
  String? _saveError;

  @override
  void initState() {
    super.initState();
    for (final c in [_name, _radius, _baseFee, _perKm, _address]) {
      c.addListener(_changed);
    }
    WidgetsBinding.instance.addPostFrameCallback((_) => _load());
  }

  void _changed() {
    if (mounted) setState(() {});
  }

  @override
  void dispose() {
    for (final c in [_name, _address, _radius, _baseFee, _perKm]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _load() async {
    final auth = context.read<AuthProvider>();
    final owner = context.read<OwnerProvider>();
    setState(() {
      _loading = true;
      _loadError = null;
    });
    try {
      await auth.fetchUserProfile();
    } catch (_) {
      // The KYB banner keeps the last known status.
    }
    await owner.fetchServices();
    if (!mounted) return;
    if (owner.servicesError != null && owner.services.isEmpty) {
      setState(() {
        _loading = false;
        _loadError = owner.servicesError;
      });
      return;
    }
    final svc = ownServiceOf(owner.services, auth.user?.id);
    setState(() {
      _loading = false;
      if (svc != null) _fill(svc);
    });
  }

  void _fill(Map<String, dynamic> svc) {
    _serviceId = serviceIdOf(svc);
    _name.text = svc['name']?.toString() ?? '';
    final cat = svc['category']?.toString() ?? '';
    _category =
        kServiceCategories.contains(cat) ? cat : kServiceCategories.first;
    _address.text = svc['address']?.toString() ?? '';
    _radius.text = amountText(svc['coverage_radius_km']);
    _baseFee.text = amountText(svc['tenant_base_price']);
    _perKm.text = amountText(svc['tenant_price_per_km']);
    final lat = (svc['latitude'] as num?)?.toDouble();
    final lon = (svc['longitude'] as num?)?.toDouble();
    if (lat != null && lon != null) {
      _lat = lat;
      _lon = lon;
    }
    _hours = ServiceHours.fromService(svc);
  }

  bool get _hasPlace => _lat != null && _lon != null;

  ServiceFormProblems get _problems => validateServiceForm(
        name: _name.text,
        hasPlace: _hasPlace,
        address: _address.text,
        radius: _radius.text,
        baseFee: _baseFee.text,
        perKm: _perKm.text,
        hours: _hours,
      );

  Future<void> _pickPlace() async {
    final initial =
        _hasPlace ? PickedPlace(latitude: _lat!, longitude: _lon!) : null;
    final pick = widget.pickPlace ??
        (ctx, init) => Navigator.of(ctx).push<PickedPlace>(qdPageRoute(
              (_) => CustomerPickerPage(
                title: ctx.l10n.ownSvcPickerTitle,
                initial: init,
                showNote: false,
              ),
            ));
    final place = await pick(context, initial);
    if (place == null || !mounted) return;
    setState(() {
      _lat = place.latitude;
      _lon = place.longitude;
    });
  }

  Future<void> _pickTime(
      TimeOfDay? current, ValueChanged<TimeOfDay> set) async {
    final initial = current ?? kDefaultOpen;
    final pick = widget.pickTime ??
        (ctx, init) => showTimePicker(context: ctx, initialTime: init);
    final t = await pick(context, initial);
    if (t == null || !mounted) return;
    setState(() {
      _hours.touched = true;
      set(t);
    });
  }

  Future<void> _save() async {
    if (_saving) return;
    final l10n = context.l10n;
    setState(() {
      _tried = true;
      _saveError = null;
    });
    if (_problems.any) {
      showOwnerNotice(context, l10n.ownSvcFixErrors);
      return;
    }
    final auth = context.read<AuthProvider>();
    final owner = context.read<OwnerProvider>();
    final ownerId = auth.user?.id;
    if (ownerId == null) {
      setState(() => _saveError = l10n.userNotAuthenticatedError);
      return;
    }
    final draft = ServiceDraft(
      name: _name.text.trim(),
      category: _category,
      latitude: _lat!,
      longitude: _lon!,
      address: _address.text.trim(),
      radiusKm: parseAmount(_radius.text)!,
      baseFee: parseAmount(_baseFee.text)!,
      perKm: parseAmount(_perKm.text)!,
      schedule: scheduleFieldsOf(_hours),
    );
    setState(() => _saving = true);
    try {
      _serviceId = await saveService(owner,
          ownerId: ownerId, serviceId: _serviceId, d: draft);
      try {
        await auth.fetchUserProfile();
      } catch (_) {}
      if (!mounted) return;
      setState(() => _saving = false);
      showOwnerNotice(context, l10n.ownSvcSaved);
      final nav = Navigator.of(context);
      if (nav.canPop()) nav.pop();
    } on ServiceSaveIncomplete catch (e) {
      // The service exists now: the next save must update it, not create
      // a second one.
      var id = e.serviceId;
      if (id == null) {
        await owner.fetchServices();
        id = serviceIdOf(ownServiceOf(owner.services, ownerId));
      }
      if (!mounted) return;
      setState(() {
        _serviceId = id ?? _serviceId;
        _saving = false;
        _saveError = l10n.ownSvcErrPartial;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _saveError = switch (serviceSaveFailureOf(e)) {
          ServiceSaveFailure.kybNotApproved => l10n.ownSvcErrKyb,
          ServiceSaveFailure.paidPlanRequired => l10n.ownSvcErrPlan,
          ServiceSaveFailure.unavailable => l10n.ownSvcErrUnavailable,
          ServiceSaveFailure.other => friendlyErrorMessage(e),
        };
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    return Scaffold(
      key: const Key('own_service_page'),
      backgroundColor: c.surface,
      appBar: ownerAppBar(context, title: l10n.ownSvcTitle),
      body: _loading
          ? const Center(
              key: Key('own_service_loading'),
              child: CircularProgressIndicator())
          : _loadError != null
              ? OwnerScrollableCenter(
                  key: const Key('own_service_error'),
                  child: QdErrorState(
                    title: l10n.ownSvcLoadError,
                    onRetry: _load,
                  ),
                )
              : _form(context),
      bottomNavigationBar: _loading || _loadError != null
          ? null
          : QdFooterBar(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  if (_saveError != null) ...[
                    QdBanner(
                      key: const Key('own_service_save_error'),
                      tone: QdBannerTone.danger,
                      icon: Icons.error_outline,
                      message: _saveError!,
                    ),
                    const SizedBox(height: QdSpace.x3),
                  ],
                  QdButton(
                    key: const Key('own_service_save'),
                    label: l10n.ownSvcSave,
                    loading: _saving,
                    fullWidth: true,
                    onPressed: _save,
                  ),
                ],
              ),
            ),
    );
  }

  Widget _form(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final user = context.watch<AuthProvider>().user;
    final kyb = user?.kycStatus?.trim() ?? '';
    final p = _tried ? _problems : const ServiceFormProblems();
    final example = examplePrice(_baseFee.text, _perKm.text);
    const gap = SizedBox(height: QdSpace.x3);
    const sectionGap = SizedBox(height: 28);

    return SingleChildScrollView(
      key: const Key('own_service_form'),
      padding: const EdgeInsetsDirectional.fromSTEB(
          QdSpace.gutter, QdSpace.x1, QdSpace.gutter, QdSpace.x4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (user != null && kyb != 'approved') ...[
            OwnerKybBanner(
              status: kyb,
              reason: user.rejectionReason,
              onOpen: () => OwnerNavScope.of(context).openKyb(context),
            ),
            const SizedBox(height: QdSpace.x5),
          ],

          // Business.
          QdSectionHeader(title: l10n.ownSvcSectionBusiness),
          gap,
          Row(
            children: [
              QdIconTile.initialOf(_name.text,
                  key: const Key('own_service_letter'),
                  size: 56,
                  tone: QdIconTileTone.gold),
              const SizedBox(width: QdSpace.x3),
              Expanded(
                child: Text(l10n.ownSvcPhotoNote,
                    style: QdText.secondary.copyWith(color: c.textSecondary)),
              ),
            ],
          ),
          gap,
          QdTextField(
            key: const Key('own_service_name'),
            label: l10n.ownSvcName,
            controller: _name,
            textInputAction: TextInputAction.next,
            errorText: p.name ? l10n.ownSvcNameRequired : null,
          ),
          gap,
          Text(l10n.ownSvcKind,
              style: QdText.body
                  .copyWith(color: c.textPrimary, fontWeight: FontWeight.w500)),
          const SizedBox(height: QdSpace.x2),
          Row(
            children: [
              for (var i = 0; i < kServiceCategories.length; i++) ...[
                if (i > 0) const SizedBox(width: QdSpace.x2),
                Expanded(
                  child: _KindOption(
                    key: Key('own_service_kind_${kServiceCategories[i]}'),
                    label: _kindLabel(l10n, kServiceCategories[i]),
                    selected: _category == kServiceCategories[i],
                    onTap: () =>
                        setState(() => _category = kServiceCategories[i]),
                  ),
                ),
              ],
            ],
          ),
          sectionGap,

          // Place and coverage.
          QdSectionHeader(title: l10n.ownSvcSectionPlace),
          gap,
          _PlaceRow(
            lat: _lat,
            lon: _lon,
            error: p.place,
            onTap: _pickPlace,
          ),
          gap,
          QdTextField(
            key: const Key('own_service_address'),
            label: l10n.ownSvcAddress,
            controller: _address,
            textInputAction: TextInputAction.next,
            errorText: p.address ? l10n.ownSvcAddressShort : null,
          ),
          gap,
          QdTextField(
            key: const Key('own_service_radius'),
            label: l10n.ownSvcRadius,
            controller: _radius,
            suffixText: l10n.ownSvcKm,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            errorText: p.radius ? l10n.ownSvcRadiusInvalid : null,
          ),
          sectionGap,

          // Working hours.
          QdSectionHeader(title: l10n.ownSvcSectionHours),
          gap,
          ..._hoursEditor(context, p.hours),
          sectionGap,

          // Pricing.
          QdSectionHeader(title: l10n.ownSvcSectionPricing),
          gap,
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: QdTextField(
                  key: const Key('own_service_base_fee'),
                  label: l10n.ownSvcBaseFee,
                  controller: _baseFee,
                  suffixText: l10n.ownSvcCurrency,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  errorText: p.baseFee ? l10n.ownSvcPriceInvalid : null,
                ),
              ),
              const SizedBox(width: QdSpace.x2),
              Expanded(
                child: QdTextField(
                  key: const Key('own_service_per_km'),
                  label: l10n.ownSvcPerKm,
                  controller: _perKm,
                  suffixText: l10n.ownSvcCurrency,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  errorText: p.perKm ? l10n.ownSvcPriceInvalid : null,
                ),
              ),
            ],
          ),
          gap,
          Container(
            key: const Key('own_service_example'),
            padding: const EdgeInsetsDirectional.symmetric(
                horizontal: 14, vertical: QdSpace.x3),
            decoration: BoxDecoration(
              color: c.fillSubtle,
              borderRadius: BorderRadius.circular(QdRadius.sm),
            ),
            child: Text(
              example == null
                  ? l10n.ownSvcExampleEmpty
                  : l10n.ownSvcExample(
                      kPriceExampleKm, QdMoney.format(l10n, example)),
              style: QdText.secondary.copyWith(color: c.neutral, height: 1.6),
            ),
          ),
        ],
      ),
    );
  }

  List<Widget> _hoursEditor(
      BuildContext context, Map<String, HoursProblem> problems) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    String? problemText(HoursProblem? p) => switch (p) {
          null => null,
          HoursProblem.missingTime => l10n.ownSvcHoursMissing,
          HoursProblem.sameTime => l10n.ownSvcHoursSameTime,
        };

    if (_hours.mode == null) {
      return [
        Text(l10n.ownSvcHoursNone,
            key: const Key('own_service_hours_none'),
            style: QdText.secondary.copyWith(color: c.textSecondary)),
        const SizedBox(height: QdSpace.x3),
        Align(
          alignment: AlignmentDirectional.centerStart,
          child: QdButton.secondary(
            key: const Key('own_service_hours_set'),
            label: l10n.ownSvcHoursSet,
            icon: Icons.schedule_outlined,
            onPressed: () => setState(_hours.start),
          ),
        ),
      ];
    }

    final same = _hours.mode == ScheduleMode.sameDaily;
    return [
      Semantics(
        container: true,
        label: l10n.ownSvcSectionHours,
        child: QdSegmented<ScheduleMode>(
          key: const Key('own_service_hours_mode'),
          selected: _hours.mode!,
          onChanged: (m) => setState(() => _hours.setMode(m)),
          segments: [
            QdSegment(
                value: ScheduleMode.sameDaily, label: l10n.ownSvcHoursSame),
            QdSegment(
                value: ScheduleMode.perDay, label: l10n.ownSvcHoursPerDay),
          ],
        ),
      ),
      const SizedBox(height: QdSpace.x3),
      if (same) ...[
        _TimePair(
          keyPrefix: 'own_service_same',
          open: _hours.open,
          close: _hours.close,
          error: problems.containsKey('same'),
          onOpen: () => _pickTime(_hours.open, (t) => _hours.open = t),
          onClose: () => _pickTime(_hours.close, (t) => _hours.close = t),
        ),
        if (problemText(problems['same']) != null) ...[
          const SizedBox(height: 6),
          _ErrorLine(problemText(problems['same'])!),
        ],
      ] else
        OwnerBorderedColumn(children: [
          for (final d in _hours.days)
            Padding(
              key: Key('own_service_day_${d.day}'),
              padding: const EdgeInsetsDirectional.fromSTEB(
                  14, QdSpace.x2, QdSpace.x2, QdSpace.x3),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(_dayLabel(l10n, d.day),
                            style: QdText.rowTitleSm
                                .copyWith(color: c.textPrimary)),
                      ),
                      Text(l10n.ownSvcDayOff,
                          style: QdText.secondary
                              .copyWith(color: c.textSecondary)),
                      Switch(
                        key: Key('own_service_day_${d.day}_off'),
                        value: d.off,
                        activeTrackColor: c.navy,
                        activeThumbColor: c.surface,
                        inactiveTrackColor: c.fillMuted,
                        inactiveThumbColor: c.textSecondary,
                        onChanged: (v) => setState(() {
                          _hours.touched = true;
                          d.off = v;
                        }),
                      ),
                    ],
                  ),
                  if (!d.off) ...[
                    const SizedBox(height: QdSpace.x1),
                    Padding(
                      padding:
                          const EdgeInsetsDirectional.only(end: QdSpace.x2),
                      child: _TimePair(
                        keyPrefix: 'own_service_day_${d.day}',
                        open: d.open,
                        close: d.close,
                        error: problems.containsKey(d.day),
                        onOpen: () => _pickTime(d.open, (t) => d.open = t),
                        onClose: () => _pickTime(d.close, (t) => d.close = t),
                      ),
                    ),
                    if (problemText(problems[d.day]) != null) ...[
                      const SizedBox(height: 6),
                      _ErrorLine(problemText(problems[d.day])!),
                    ],
                  ],
                ],
              ),
            ),
        ]),
      const SizedBox(height: QdSpace.x1),
      Align(
        alignment: AlignmentDirectional.centerStart,
        child: QdButton.text(
          key: const Key('own_service_hours_remove'),
          label: l10n.ownSvcHoursRemove,
          onPressed: () => setState(_hours.clear),
        ),
      ),
    ];
  }

  static String _kindLabel(AppLocalizations l10n, String category) =>
      switch (category) {
        'transport' => l10n.ownSvcKindTransport,
        'shipping' => l10n.ownSvcKindShipping,
        _ => l10n.ownSvcKindDelivery,
      };

  static String _dayLabel(AppLocalizations l10n, String day) => switch (day) {
        'mon' => l10n.scheduleDayMon,
        'tue' => l10n.scheduleDayTue,
        'wed' => l10n.scheduleDayWed,
        'thu' => l10n.scheduleDayThu,
        'fri' => l10n.scheduleDayFri,
        'sat' => l10n.scheduleDaySat,
        _ => l10n.scheduleDaySun,
      };
}

/// One of the three service types (O-Service radio tiles).
class _KindOption extends StatelessWidget {
  const _KindOption(
      {super.key,
      required this.label,
      required this.selected,
      required this.onTap});

  final String label;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Semantics(
      button: true,
      selected: selected,
      inMutuallyExclusiveGroup: true,
      label: label,
      excludeSemantics: true,
      onTap: selected ? null : onTap,
      child: Material(
        color: selected ? c.goldTint : c.surface,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(QdRadius.sm),
          side: BorderSide(
              color: selected ? c.navy : c.borderInput,
              width: selected ? 2 : 1),
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: selected ? null : onTap,
          child: ConstrainedBox(
            constraints: const BoxConstraints(minHeight: QdSize.minTouch),
            child: Center(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: QdSpace.x1),
                child: FittedBox(
                  fit: BoxFit.scaleDown,
                  child: Text(
                    label,
                    maxLines: 1,
                    style: QdText.body.copyWith(
                      color: c.textPrimary,
                      fontWeight: selected ? FontWeight.w600 : FontWeight.w400,
                    ),
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// "Business location on the map" row: "Required" until set, then the
/// coordinates; opens the picker.
class _PlaceRow extends StatelessWidget {
  const _PlaceRow(
      {required this.lat,
      required this.lon,
      required this.error,
      required this.onTap});

  final double? lat;
  final double? lon;
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final set = lat != null && lon != null;
    final subtitle = set
        ? '${lat!.toStringAsFixed(4)}, ${lon!.toStringAsFixed(4)}'
        : l10n.ownSvcPlaceMissing;
    return Semantics(
      button: true,
      label: '${l10n.ownSvcPlace}, '
          '${set ? l10n.ownSvcPlaceSet : l10n.ownSvcPlaceMissing}',
      excludeSemantics: true,
      onTap: onTap,
      child: Material(
        key: const Key('own_service_place'),
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
                  Icon(Icons.location_on_outlined,
                      size: QdSize.icon, color: c.textPrimary),
                  const SizedBox(width: QdSpace.x3),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(l10n.ownSvcPlace,
                            style: QdText.body.copyWith(
                                fontSize: 15,
                                color: c.textPrimary,
                                fontWeight: FontWeight.w500)),
                        Text(
                          subtitle,
                          key: const Key('own_service_place_value'),
                          textDirection: set ? TextDirection.ltr : null,
                          style: QdText.caption.copyWith(
                              color: set
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

/// Opens / closes time boxes side by side.
class _TimePair extends StatelessWidget {
  const _TimePair({
    required this.keyPrefix,
    required this.open,
    required this.close,
    required this.error,
    required this.onOpen,
    required this.onClose,
  });

  final String keyPrefix;
  final TimeOfDay? open;
  final TimeOfDay? close;
  final bool error;
  final VoidCallback onOpen;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    return Row(
      children: [
        Expanded(
          child: _TimeBox(
            key: Key('${keyPrefix}_open'),
            label: l10n.ownSvcOpens,
            value: open,
            error: error,
            onTap: onOpen,
          ),
        ),
        const SizedBox(width: QdSpace.x2),
        Expanded(
          child: _TimeBox(
            key: Key('${keyPrefix}_close'),
            label: l10n.ownSvcCloses,
            value: close,
            error: error,
            onTap: onClose,
          ),
        ),
      ],
    );
  }
}

class _TimeBox extends StatelessWidget {
  const _TimeBox({
    super.key,
    required this.label,
    required this.value,
    required this.error,
    required this.onTap,
  });

  final String label;
  final TimeOfDay? value;
  final bool error;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    final text = value == null ? '--:--' : toHHmm(value!);
    return Semantics(
      button: true,
      label: '$label, $text',
      excludeSemantics: true,
      onTap: onTap,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(label, style: QdText.secondary.copyWith(color: c.textSecondary)),
          const SizedBox(height: 6),
          Material(
            color: c.surface,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(QdRadius.sm),
              side: BorderSide(color: error ? c.danger : c.borderInput),
            ),
            clipBehavior: Clip.antiAlias,
            child: InkWell(
              onTap: onTap,
              child: Container(
                height: 50,
                padding: const EdgeInsetsDirectional.symmetric(horizontal: 12),
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  text,
                  textDirection: TextDirection.ltr,
                  style:
                      QdText.body.copyWith(fontSize: 15, color: c.textPrimary),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorLine extends StatelessWidget {
  const _ErrorLine(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final c = QdColors.of(context);
    return Semantics(
      liveRegion: true,
      child: Text(text,
          style: QdText.caption
              .copyWith(color: c.danger, fontWeight: FontWeight.w500)),
    );
  }
}
