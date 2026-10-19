import 'package:flutter/material.dart';

import '../../l10n/l10n.dart';
import '../qd_ui.dart';

/// Debug-only catalog of every redesign A component in every state
/// (FE-DS). Reached through the `/qd-gallery` route, which `main.dart`
/// registers only when `kDebugMode`. Section goldens:
/// test/ui/qd_gallery_golden_test.dart.
///
/// Sample content is demo data in both languages, picked by the ambient
/// locale; component strings themselves (status labels, retry, ...) come
/// from the ARB files.
class QdGalleryScreen extends StatefulWidget {
  const QdGalleryScreen({super.key, this.now = DateTime.now});

  /// Clock for the countdown samples (fixed in goldens).
  final DateTime Function() now;

  static const String routeName = '/qd-gallery';

  @override
  State<QdGalleryScreen> createState() => _QdGalleryScreenState();
}

class _QdGalleryScreenState extends State<QdGalleryScreen> {
  bool _dark = false;
  Locale? _locale;

  @override
  Widget build(BuildContext context) {
    final locale = _locale ?? Localizations.localeOf(context);
    final sections = qdGallerySections(now: widget.now);
    return Localizations.override(
      context: context,
      locale: locale,
      child: Theme(
        data: _dark ? qdDarkTheme : qdLightTheme,
        child: Builder(builder: (context) {
          final c = QdColors.of(context);
          return Scaffold(
            backgroundColor: c.surface,
            appBar: AppBar(
              title: const Text('Design system'),
              actions: [
                TextButton(
                  onPressed: () => setState(() => _locale =
                      locale.languageCode == 'ar'
                          ? const Locale('en')
                          : const Locale('ar')),
                  child: Text(locale.languageCode == 'ar' ? 'EN' : 'ع'),
                ),
                IconButton(
                  tooltip: 'Dark',
                  onPressed: () => setState(() => _dark = !_dark),
                  icon: Icon(_dark ? Icons.light_mode : Icons.dark_mode),
                ),
              ],
            ),
            body: ListView.separated(
              padding: const EdgeInsets.fromLTRB(
                  QdSpace.gutter, QdSpace.x2, QdSpace.gutter, QdSpace.x6 * 2),
              itemCount: sections.length,
              separatorBuilder: (_, __) => const SizedBox(height: QdSpace.x6),
              itemBuilder: (context, i) => QdGallerySectionView(sections[i]),
            ),
          );
        }),
      ),
    );
  }
}

/// One gallery section: a stable id (golden file name) and its content.
class QdGallerySection {
  const QdGallerySection(this.id, this.title, this.builder);

  final String id;
  final String title;
  final WidgetBuilder builder;
}

/// A section with its header, as rendered in the gallery and the goldens.
class QdGallerySectionView extends StatelessWidget {
  const QdGallerySectionView(this.section, {super.key});

  final QdGallerySection section;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        QdSectionHeader(title: section.title),
        const SizedBox(height: QdSpace.x2),
        section.builder(context),
      ],
    );
  }
}

String _t(BuildContext context, String en, String ar) =>
    Localizations.localeOf(context).languageCode == 'ar' ? ar : en;

void _noop() {}

Widget _col(List<Widget> children, [double gap = QdSpace.x3]) => Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      mainAxisSize: MainAxisSize.min,
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) SizedBox(height: gap),
          children[i],
        ],
      ],
    );

List<QdGallerySection> qdGallerySections({
  DateTime Function() now = DateTime.now,
}) {
  return [
    QdGallerySection('buttons', 'QdButton', (context) {
      return _col([
        QdButton(
            label: _t(context, 'Order now', 'اطلب دلوقتي'),
            onPressed: _noop,
            fullWidth: true),
        QdButton(
            label: _t(context, 'Log in', 'دخول'),
            onPressed: _noop,
            loading: true,
            fullWidth: true),
        QdButton(
            label: _t(
                context, 'Pick the drop-off first', 'اختار مكان التسليم الأول'),
            onPressed: null,
            fullWidth: true),
        Row(children: [
          Expanded(
              child: QdButton.secondary(
                  label: _t(context, 'Decline', 'رفض'), onPressed: _noop)),
          const SizedBox(width: 10),
          Expanded(
              flex: 2,
              child: QdButton.secondary(
                  label: _t(context, 'Disabled', 'مقفول'), onPressed: null)),
        ]),
        Row(children: [
          QdButton(
              label: _t(context, 'Reply', 'رد عليه'),
              onPressed: _noop,
              small: true),
          const SizedBox(width: QdSpace.x2),
          QdButton.secondary(
              label: _t(context, 'Review', 'راجع'),
              onPressed: _noop,
              small: true),
          const Spacer(),
          QdButton.text(
              label: _t(context, 'Forgot password?', 'نسيت كلمة السر؟'),
              onPressed: _noop),
        ]),
        QdButton.destructive(
            label: _t(context, 'Cancel order', 'إلغاء الطلب'),
            onPressed: _noop,
            fullWidth: true),
        QdButton.secondary(
            label: _t(context, 'Open in maps', 'افتح في الخرائط'),
            icon: Icons.map_outlined,
            onPressed: _noop,
            fullWidth: true),
      ]);
    }),
    QdGallerySection('fields', 'QdTextField', (context) {
      return _col([
        QdTextField(
          label: _t(context, 'Email', 'الإيميل'),
          hint: 'name@example.com',
          ltr: true,
          keyboardType: TextInputType.emailAddress,
        ),
        QdTextField(
          label: _t(context, 'Password', 'كلمة السر'),
          obscure: true,
          controller: TextEditingController(text: 'secret-pass'),
        ),
        QdTextField(
          label: _t(context, 'Phone', 'الموبايل'),
          ltr: true,
          controller: TextEditingController(text: '+20 100 000 0000'),
          errorText: _t(
              context, 'Enter a valid Egyptian number', 'اكتب رقم مصري صحيح'),
        ),
        QdTextField(
          label: _t(context, 'Company name', 'اسم الشركة'),
          enabled: false,
          controller: TextEditingController(
              text: _t(context, 'Quick Delivery', 'كويك دليفري')),
          helperText: _t(context, 'Only the owner can change this',
              'صاحب الشغل بس يقدر يغيّره'),
        ),
      ], QdSpace.x4);
    }),
    QdGallerySection('lists', 'QdCard · QdListGroup', (context) {
      final c = QdColors.of(context);
      return _col([
        QdCard(
          subtle: true,
          onTap: _noop,
          child: _col([
            Row(children: [
              Expanded(
                child: Text(_t(context, 'Delivery · #A12', 'توصيل طلب · #A12'),
                    style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
              ),
              const QdJobStatusChips(status: 'active'),
            ]),
            const QdStepProgress(total: 4, current: 2),
            QdRouteLines(
              pickup: _t(context, 'Next to the kiosk', 'جنب الكشك'),
              dropoff: _t(context, 'Building 4, gate 2', 'عمارة 4، البوابة 2'),
              compact: true,
            ),
            Row(children: [
              Expanded(
                  child: Text(
                      _t(context, 'Cash on delivery', 'كاش عند الاستلام'),
                      style:
                          QdText.secondary.copyWith(color: c.textSecondary))),
              Text(QdMoney.of(context, 85),
                  style: QdText.rowTitleSm.copyWith(
                      color: c.textPrimary, fontWeight: FontWeight.w700)),
            ]),
          ]),
        ),
        QdListGroup(children: [
          QdListTile(
              icon: Icons.place_outlined,
              title: _t(context, 'Saved addresses', 'العناوين المحفوظة'),
              chevron: true,
              onTap: _noop),
          QdListTile(
              icon: Icons.lock_outline,
              title: _t(context, 'Security', 'الأمان'),
              value: _t(context, '2FA on', 'التحقق بخطوتين شغال'),
              chevron: true,
              onTap: _noop),
          QdListTile(
              icon: Icons.notifications_none,
              title: _t(context, 'Notifications', 'الإشعارات'),
              switchValue: true,
              onSwitchChanged: (_) {}),
          QdListTile(
              icon: Icons.account_balance_wallet_outlined,
              title: _t(context, 'Wallet', 'المحفظة'),
              enabled: false,
              badge: QdStatusChip(
                  label: context.l10n.qdComingSoon, tone: QdTone.neutral)),
        ]),
        QdListGroup(children: [
          QdListTile(
            leading: QdAvatarInitial(
                name: _t(context, 'Mona', 'منى'), size: 40, emphasis: false),
            title: _t(context, 'Mona Adel', 'منى عادل'),
            subtitle: _t(context, 'On a job · #A12', 'في مهمة · #A12'),
            badge: QdStatusChip(
                label: _t(context, 'On a job', 'في مهمة'),
                tone: QdTone.warning),
            onTap: _noop,
          ),
          QdListTile(
            leading: QdAvatarInitial(
                name: _t(context, 'Karim', 'كريم'), size: 40, emphasis: false),
            title: _t(context, 'Karim Samy', 'كريم سامي'),
            subtitle: _t(context, 'Documents missing', 'مستندات التحقق ناقصة'),
            subtitleColor: c.warning,
            badge: QdStatusChip(
                label: _t(context, 'Unavailable', 'مش متاح'),
                tone: QdTone.neutral),
            onTap: _noop,
          ),
          QdListTile(
            leading: QdAvatarInitial(
                name: _t(context, 'Hany', 'هاني'),
                size: 40,
                emphasis: false,
                dimmed: true),
            title: _t(context, 'Hany Fawzy', 'هاني فوزي'),
            subtitle: _t(context, 'Frozen 12 Oct', 'اتجمد 12 أكتوبر'),
            badge: QdStatusChip(
                label: _t(context, 'Frozen', 'متجمد'), tone: QdTone.danger),
            onTap: _noop,
          ),
        ]),
      ]);
    }),
    QdGallerySection('chips', 'QdStatusChip · job statuses', (context) {
      final l10n = context.l10n;
      const statuses = [
        'pending',
        'pending_dispatch',
        'unavailable',
        'awaiting_price_response',
        'assigned',
        'active',
        'completed',
        'cancelled',
        'escrow_reconciliation_required',
        'something_new',
      ];
      final c = QdColors.of(context);
      return _col([
        for (final s in statuses)
          Row(children: [
            Expanded(
              child: Text(s,
                  style: QdText.caption.copyWith(color: c.textSecondary)),
            ),
            QdStatusChip(
                label: QdJobStatus.fromBackend(s).label(l10n),
                tone: QdJobStatus.fromBackend(s).tone),
          ]),
        Row(children: [
          Expanded(
            child: Text('active + cancellation pending',
                style: QdText.caption.copyWith(color: c.textSecondary)),
          ),
          const QdJobStatusChips(
              status: 'active', cancellationRequestStatus: 'pending'),
        ]),
      ], QdSpace.x2);
    }),
    QdGallerySection('navigation', 'QdSegmented · QdBottomNav', (context) {
      return _col([
        QdSegmented<int>(
          segments: [
            QdSegment(value: 0, label: _t(context, 'Current 1', 'الجارية 1')),
            QdSegment(value: 1, label: _t(context, 'Past', 'السابقة')),
          ],
          selected: 0,
          onChanged: (_) {},
        ),
        QdSegmented<int>(
          segments: [
            QdSegment(value: 0, label: _t(context, 'All 12', 'الكل 12')),
            QdSegment(
                value: 1,
                label: _t(context, 'Working right now', 'شغالين دلوقتي')),
            QdSegment(
                value: 2,
                label: _t(context, 'Frozen accounts', 'الحسابات المتجمدة')),
          ],
          selected: 1,
          onChanged: (_) {},
        ),
        QdBottomNav(
          items: [
            QdNavItem(
                icon: Icons.home_outlined,
                activeIcon: Icons.home,
                label: _t(context, 'Home', 'الرئيسية')),
            QdNavItem(
                icon: Icons.receipt_long_outlined,
                label: _t(context, 'My orders', 'طلباتي')),
            QdNavItem(
                icon: Icons.person_outline,
                label: _t(context, 'Account', 'حسابي')),
          ],
          currentIndex: 0,
          onTap: (_) {},
        ),
        QdBottomNav(
          items: [
            QdNavItem(
                icon: Icons.today_outlined,
                label: _t(context, 'Today', 'النهارده')),
            QdNavItem(
                icon: Icons.inventory_2_outlined,
                label: _t(context, 'Orders', 'الطلبات')),
            QdNavItem(
                icon: Icons.groups_outlined,
                label: _t(context, 'Team', 'الفريق')),
            QdNavItem(
                icon: Icons.settings_outlined,
                label: _t(context, 'Settings', 'الإعدادات')),
          ],
          currentIndex: 2,
          onTap: (_) {},
        ),
      ], QdSpace.x4);
    }),
    QdGallerySection('route', 'QdRouteLines · QdStepProgress · QdTimeline',
        (context) {
      return _col([
        QdRouteLines(
          pickup: _t(context, 'Next to the kiosk', 'جنب الكشك'),
          dropoff: _t(context, 'Building 4, gate 2', 'عمارة 4، البوابة 2'),
          pickupCaption:
              _t(context, 'Pickup · 1.2 km from you', 'استلام · 1.2 كم منك'),
          dropoffCaption:
              _t(context, 'Drop-off · 4 km trip', 'تسليم · المشوار 4 كم'),
        ),
        QdRouteLines(
          pickup: _t(context, 'Next to the kiosk', 'جنب الكشك'),
          dropoff: _t(context, 'Building 4, gate 2', 'عمارة 4، البوابة 2'),
          compact: true,
        ),
        for (var i = 0; i < 4; i++) QdStepProgress(total: 4, current: i),
        QdTimeline(steps: [
          QdTimelineStep(
              label: _t(context, 'Ordered', 'طلبت'),
              state: QdTimelineState.done,
              time: '2:10'),
          QdTimelineStep(
              label: _t(context, 'Mona accepted', 'منى قبلت الطلب'),
              state: QdTimelineState.done),
          QdTimelineStep(
              label: _t(context, 'On the way', 'شغال عليه'),
              state: QdTimelineState.current,
              time: _t(context, 'Now', 'دلوقتي')),
          QdTimelineStep(
              label: _t(context, 'Delivered', 'اتسلم'),
              state: QdTimelineState.upcoming),
        ]),
      ], QdSpace.x4);
    }),
    QdGallerySection('people', 'QdAvatarInitial · QdSectionHeader · QdBanner',
        (context) {
      return _col([
        Row(children: [
          QdAvatarInitial(name: _t(context, 'Omar', 'عمر'), size: 56),
          const SizedBox(width: QdSpace.x3),
          QdAvatarInitial(name: _t(context, 'mona', 'منى')),
          const SizedBox(width: QdSpace.x3),
          QdAvatarInitial(
              name: _t(context, 'Karim', 'كريم'), size: 40, emphasis: false),
          const SizedBox(width: QdSpace.x3),
          const QdAvatarInitial(
              name: 'Hany', size: 36, emphasis: false, dimmed: true),
          const SizedBox(width: QdSpace.x3),
          const QdAvatarInitial(name: '', size: 36, emphasis: false),
        ]),
        QdSectionHeader(
            title: _t(context, 'Team now', 'الفريق دلوقتي'),
            actionLabel: _t(context, 'All', 'الكل'),
            onAction: _noop),
        QdSectionHeader(title: _t(context, 'Account', 'الحساب'), small: true),
        QdBanner(
          tone: QdBannerTone.info,
          message: _t(
              context,
              'You are offline. We will refresh when you are back.',
              'إنت مش متصل. هنحدّث أول ما النت يرجع.'),
          icon: Icons.wifi_off,
        ),
        QdBanner(
          tone: QdBannerTone.warning,
          message: _t(context, 'Your account is waiting for document review.',
              'حسابك مستني مراجعة المستندات.'),
          actionLabel: _t(context, 'Finish upload', 'كمّل الرفع'),
          onAction: _noop,
        ),
        QdBanner(
          tone: QdBannerTone.danger,
          title: _t(context, 'Account suspended', 'الحساب متوقف'),
          message: _t(context, 'You cannot take jobs. Contact your company.',
              'مش هتقدر تاخد مهام. كلّم الشركة.'),
        ),
        QdBanner(
          tone: QdBannerTone.warning,
          icon: Icons.location_off_outlined,
          message: _t(context, 'Location is off, so we cannot track the trip.',
              'اللوكيشن مقفول، مش هنقدر نتابع المشوار.'),
          actionLabel: _t(context, 'Turn on', 'شغّله'),
          onAction: _noop,
        ),
      ]);
    }),
    QdGallerySection('states', 'QdEmptyState · QdErrorState', (context) {
      return _col([
        QdEmptyState(
          icon: Icons.support_agent,
          title: _t(context, 'No tickets yet', 'مفيش شكاوى لسه'),
          body: _t(context, 'Need help? Open a new ticket.',
              'محتاج مساعدة؟ افتح شكوى جديدة.'),
          actionLabel: _t(context, 'New ticket', 'شكوى جديدة'),
          onAction: _noop,
        ),
        const QdErrorState(onRetry: _noop),
      ]);
    }),
    QdGallerySection('countdown', 'QdCountdown · QdMoney', (context) {
      final t0 = now();
      final c = QdColors.of(context);
      return _col([
        Row(children: [
          QdCountdown(
            expiresAt: t0.add(const Duration(seconds: 25)),
            total: const Duration(seconds: 30),
            now: now,
          ),
          const SizedBox(width: QdSpace.x4),
          QdCountdown(
            expiresAt: t0.subtract(const Duration(seconds: 1)),
            total: const Duration(seconds: 30),
            now: now,
          ),
        ]),
        QdCountdown(
          expiresAt: t0.add(const Duration(minutes: 2, seconds: 41)),
          total: const Duration(minutes: 5),
          style: QdCountdownStyle.bar,
          label: _t(context, 'Offer ends in', 'العرض بيخلص بعد'),
          now: now,
        ),
        for (final v in [45, 1250, 37.5])
          Row(children: [
            Expanded(
              child: Text('$v',
                  style: QdText.caption.copyWith(color: c.textSecondary)),
            ),
            Text(QdMoney.of(context, v),
                style: QdText.rowTitleSm.copyWith(color: c.textPrimary)),
          ]),
      ], QdSpace.x4);
    }),
    QdGallerySection('sheet', 'QdBottomSheet', (context) {
      final c = QdColors.of(context);
      return DecoratedBox(
        decoration: BoxDecoration(
          color: c.scrim,
          borderRadius: BorderRadius.circular(QdRadius.card),
        ),
        child: Padding(
          padding: const EdgeInsets.only(top: 48),
          child: QdBottomSheet(
            title: _t(context, 'Add courier', 'إضافة مندوب'),
            subtitle: _t(context, 'They get an email to set a password',
                'هيوصله إيميل يعمل منه كلمة سر'),
            primaryLabel: _t(context, 'Add', 'إضافة'),
            onPrimary: _noop,
            child: _col([
              QdTextField(label: _t(context, 'Name', 'الاسم')),
              QdTextField(
                  label: _t(context, 'Email', 'الإيميل'),
                  ltr: true,
                  hint: 'name@example.com'),
            ]),
          ),
        ),
      );
    }),
  ];
}
