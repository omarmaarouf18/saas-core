import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/models/notification_model.dart';

void main() {
  group('NotificationLocalizedText', () {
    test('parses from valid JSON and serializes back', () {
      final json = {'title': 'العنوان', 'body': 'المحتوى'};
      final text = NotificationLocalizedText.fromJson(json);
      expect(text.title, 'العنوان');
      expect(text.body, 'المحتوى');
      expect(text.toJson(), json);
    });

    test('tolerates malformed input and nulls', () {
      expect(NotificationLocalizedText.fromJson(null).title, isEmpty);
      expect(NotificationLocalizedText.fromJson('not a map').body, isEmpty);
      expect(
          NotificationLocalizedText.fromJson({'title': null, 'body': 123}).body,
          '123');
    });

    test('equality and hashCode', () {
      const a = NotificationLocalizedText(title: 'T', body: 'B');
      const b = NotificationLocalizedText(title: 'T', body: 'B');
      const c = NotificationLocalizedText(title: 'T2', body: 'B');
      expect(a, equals(b));
      expect(a.hashCode, equals(b.hashCode));
      expect(a, isNot(equals(c)));
      expect(a.toString(), contains('title: T'));
    });
  });

  group('NotificationModel params and texts', () {
    test('parses params and texts from JSON', () {
      final json = {
        'id': 'n-1',
        'type': 'admin_announcement',
        'tenant_id': 'tenant-1',
        'title': 'Default title',
        'body': 'Default body',
        'timestamp': '2026-10-01T12:00:00.000Z',
        'params': {
          'ticket_id': 'tkt-99',
          'variant': 'accept',
          'deep_link': '/orders/ord-1',
          'numeric_val': 42,
        },
        'texts': {
          'ar': {'title': 'عنوان عربي', 'body': 'تفاصيل بالعربي'},
          'en': {'title': 'English title', 'body': 'English body'},
        },
      };

      final model = NotificationModel.fromJson(json);
      expect(model.id, 'n-1');
      expect(model.type, 'admin_announcement');
      expect(model.params['ticket_id'], 'tkt-99');
      expect(model.params['variant'], 'accept');
      expect(model.params['deep_link'], '/orders/ord-1');
      expect(model.params['numeric_val'], '42');
      expect(model.texts['ar']?.title, 'عنوان عربي');
      expect(model.texts['ar']?.body, 'تفاصيل بالعربي');
      expect(model.texts['en']?.title, 'English title');
      expect(model.texts['en']?.body, 'English body');

      // Roundtrip toJson -> fromJson
      final exported = model.toJson();
      expect(exported['params'], isA<Map<String, dynamic>>());
      expect(exported['texts'], isA<Map<String, dynamic>>());
      final reloaded = NotificationModel.fromJson(exported);
      expect(reloaded.params, equals(model.params));
      expect(reloaded.texts, equals(model.texts));
    });

    test('tolerates missing or malformed params and texts in JSON', () {
      // Missing fields (old history items)
      final bareJson = {
        'id': 'n-old',
        'type': 'job_booked',
        'tenant_id': 't-1',
        'title': 'Job booked',
        'body': 'A job was booked',
      };
      final oldModel = NotificationModel.fromJson(bareJson);
      expect(oldModel.params, isEmpty);
      expect(oldModel.texts, isEmpty);
      expect(oldModel.toJson().containsKey('params'), isFalse);
      expect(oldModel.toJson().containsKey('texts'), isFalse);

      // Malformed: non-map or null
      final malformed = NotificationModel.fromJson({
        'id': 'n-bad',
        'type': 'system',
        'tenant_id': 't-1',
        'params': 'not-a-map',
        'texts': 12345,
      });
      expect(malformed.params, isEmpty);
      expect(malformed.texts, isEmpty);

      // Stringified JSON map in params and texts
      final stringified = NotificationModel.fromJson({
        'id': 'n-str',
        'type': 'system',
        'tenant_id': 't-1',
        'params': jsonEncode({'key': 'val'}),
        'texts': jsonEncode({
          'en': {'title': 'T', 'body': 'B'}
        }),
      });
      expect(stringified.params['key'], 'val');
      expect(stringified.texts['en']?.title, 'T');
    });

    test('parses deep_link and params from push data', () {
      // 1. Direct deep_link key in FCM data
      final pushData = {
        'id': 'push-1',
        'event_type': 'admin_announcement',
        'tenant_id': 't-1',
        'deep_link': '/orders/ord-456',
      };
      final pushModel = NotificationModel.fromPushData(pushData,
          title: 'Push Title', body: 'Push Body');
      expect(pushModel.id, 'push-1');
      expect(pushModel.type, 'admin_announcement');
      expect(pushModel.title, 'Push Title');
      expect(pushModel.body, 'Push Body');
      expect(pushModel.params['deep_link'], '/orders/ord-456');

      // 2. Both params and deep_link present
      final combined = NotificationModel.fromPushData({
        'id': 'push-2',
        'params': {'extra': 'value'},
        'deep_link': '/plan',
      });
      expect(combined.params['extra'], 'value');
      expect(combined.params['deep_link'], '/plan');

      // 3. No deep_link or params
      final simplePush = NotificationModel.fromPushData({
        'id': 'push-3',
        'type': 'job_offer',
        'job_id': 'j-1',
      });
      expect(simplePush.params, isEmpty);
      expect(simplePush.jobId, 'j-1');
    });
  });
}
