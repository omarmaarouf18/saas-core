import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/account/notifications/notification_rules.dart';
import 'package:frontend/l10n/app_localizations_ar.dart';
import 'package:frontend/l10n/app_localizations_en.dart';
import 'package:frontend/models/notification_model.dart';

void main() {
  final en = AppLocalizationsEn();
  final ar = AppLocalizationsAr();

  NotificationModel n({
    required String type,
    String title = 'Sender English Title',
    String body = 'Sender English Body',
    Map<String, String>? params,
    Map<String, NotificationLocalizedText>? texts,
  }) {
    return NotificationModel(
      id: 'n-1',
      type: type,
      tenantId: 't-1',
      title: title,
      body: body,
      timestamp: DateTime(2026, 10, 1),
      params: params,
      texts: texts,
    );
  }

  group('notificationCopy - server texts first', () {
    test('uses texts[<app language>] when present and non-empty (beats local l10n)', () {
      final model = n(
        type: 'job_accepted',
        title: 'Server Sender Title',
        body: 'Server Sender Body',
        texts: {
          'en': const NotificationLocalizedText(
            title: 'Custom Server English Title',
            body: 'Custom Server English Body',
          ),
          'ar': const NotificationLocalizedText(
            title: 'عنوان مخصص من السيرفر',
            body: 'تفاصيل مخصصة من السيرفر',
          ),
        },
      );

      // In EN: returns server texts['en']
      expect(
        notificationCopy(en, model),
        ('Custom Server English Title', 'Custom Server English Body'),
      );

      // In AR: returns server texts['ar']
      expect(
        notificationCopy(ar, model),
        ('عنوان مخصص من السيرفر', 'تفاصيل مخصصة من السيرفر'),
      );
    });

    test('falls back to local l10n when server texts for that language is absent', () {
      // Model only has texts for Arabic, missing English
      final onlyAr = n(
        type: 'job_accepted',
        texts: {
          'ar': const NotificationLocalizedText(
            title: 'عنوان عربي',
            body: 'تفاصيل عربي',
          ),
        },
      );

      // In AR: uses texts['ar']
      expect(notificationCopy(ar, onlyAr), ('عنوان عربي', 'تفاصيل عربي'));
      // In EN: falls back to existing local l10n
      expect(
        notificationCopy(en, onlyAr),
        ('A courier accepted your order', 'Follow it from the order page.'),
      );

      // Model only has texts for English, missing Arabic
      final onlyEn = n(
        type: 'job_accepted',
        texts: {
          'en': const NotificationLocalizedText(
            title: 'English Server Title',
            body: 'English Server Body',
          ),
        },
      );
      // In EN: uses texts['en']
      expect(notificationCopy(en, onlyEn), ('English Server Title', 'English Server Body'));
      // In AR: falls back to local l10n
      expect(notificationCopy(ar, onlyEn).$1, 'مندوب قبل طلبك');
    });

    test('falls back to server title/body when neither server text nor local l10n exists', () {
      final unknownModel = n(
        type: 'unknown_custom_event',
        title: 'Original Title',
        body: 'Original Body',
      );

      expect(notificationCopy(en, unknownModel), ('Original Title', 'Original Body'));
      expect(notificationCopy(ar, unknownModel), ('Original Title', 'Original Body'));
    });
  });

  group('notificationCopy - admin_announcement localization', () {
    test('uses params title_ar/body_ar or title_en/body_en by app language', () {
      final model = n(
        type: 'admin_announcement',
        title: 'Fallback English Title',
        body: 'Fallback English Body',
        params: {
          'title_en': 'Maintenance Tonight',
          'body_en': 'System will be down for 10 minutes.',
          'title_ar': 'صيانة الليلة',
          'body_ar': 'النظام سيتوقف لمدة 10 دقائق.',
        },
      );

      // In EN: returns English announcement
      expect(
        notificationCopy(en, model),
        ('Maintenance Tonight', 'System will be down for 10 minutes.'),
      );

      // In AR: returns Arabic announcement
      expect(
        notificationCopy(ar, model),
        ('صيانة الليلة', 'النظام سيتوقف لمدة 10 دقائق.'),
      );
    });

    test('uses texts for admin_announcement when present', () {
      final model = n(
        type: 'admin_announcement',
        texts: {
          'en': const NotificationLocalizedText(
            title: 'Announce EN',
            body: 'Details EN',
          ),
          'ar': const NotificationLocalizedText(
            title: 'إعلان عربي',
            body: 'تفاصيل عربي',
          ),
        },
      );

      expect(notificationCopy(en, model), ('Announce EN', 'Details EN'));
      expect(notificationCopy(ar, model), ('إعلان عربي', 'تفاصيل عربي'));
    });

    test('falls back to the other language when requested language is missing', () {
      // Arabic only announcement
      final arOnly = n(
        type: 'admin_announcement',
        title: 'English Raw Sender Title',
        body: 'English Raw Sender Body',
        params: {
          'title_ar': 'إعلان خاص',
          'body_ar': 'محتوى الإعلان',
        },
      );
      // In AR: gets Arabic
      expect(notificationCopy(ar, arOnly), ('إعلان خاص', 'محتوى الإعلان'));
      // In EN: falls back to Arabic rather than English raw sender text
      expect(notificationCopy(en, arOnly), ('إعلان خاص', 'محتوى الإعلان'));

      // English only announcement
      final enOnly = n(
        type: 'admin_announcement',
        title: 'Raw Sender Title',
        body: 'Raw Sender Body',
        params: {
          'title_en': 'Special Announcement',
          'body_en': 'Details here',
        },
      );
      // In EN: gets English
      expect(notificationCopy(en, enOnly), ('Special Announcement', 'Details here'));
      // In AR: falls back to English
      expect(notificationCopy(ar, enOnly), ('Special Announcement', 'Details here'));
    });

    test('falls back to server title/body if neither AR nor EN announcement text exists', () {
      final bare = n(
        type: 'admin_announcement',
        title: 'Raw Sender Title',
        body: 'Raw Sender Body',
      );
      expect(notificationCopy(en, bare), ('Raw Sender Title', 'Raw Sender Body'));
      expect(notificationCopy(ar, bare), ('Raw Sender Title', 'Raw Sender Body'));
    });
  });
}
