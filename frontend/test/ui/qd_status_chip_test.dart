import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/ui/components/qd_status_chip.dart';
import 'package:frontend/ui/tokens.dart';

import 'qd_harness.dart';

void main() {
  /// Every job status the models / backend emit (user-service
  /// models.JobStatus*, plus the frontend-only `assigned` and the
  /// `reconciliation_required` / `canceled` aliases from enum_labels.dart).
  const table = <String, (QdJobStatus, QdTone)>{
    'pending': (QdJobStatus.pending, QdTone.warning),
    'pending_dispatch': (QdJobStatus.pendingDispatch, QdTone.warning),
    'unavailable': (QdJobStatus.unavailable, QdTone.danger),
    'awaiting_price_response': (QdJobStatus.awaitingPrice, QdTone.warning),
    'assigned': (QdJobStatus.assigned, QdTone.success),
    'active': (QdJobStatus.active, QdTone.success),
    'completed': (QdJobStatus.completed, QdTone.neutral),
    'cancelled': (QdJobStatus.cancelled, QdTone.danger),
    'canceled': (QdJobStatus.cancelled, QdTone.danger),
    'escrow_reconciliation_required': (QdJobStatus.underReview, QdTone.warning),
    'reconciliation_required': (QdJobStatus.underReview, QdTone.warning),
  };

  test('every backend status maps to its chip and tone', () {
    table.forEach((status, expected) {
      final s = QdJobStatus.fromBackend(status);
      expect(s, expected.$1, reason: status);
      expect(s.tone, expected.$2, reason: status);
    });
  });

  test('case and whitespace are ignored', () {
    expect(QdJobStatus.fromBackend(' ACTIVE '), QdJobStatus.active);
    expect(QdJobStatus.fromBackend('Pending_Dispatch'),
        QdJobStatus.pendingDispatch);
  });

  test('unknown, empty and null are a neutral chip, never a throw', () {
    for (final s in ['teleported', '', '   ', null]) {
      final r = QdJobStatus.fromBackend(s);
      expect(r, QdJobStatus.unknown, reason: '$s');
      expect(r.tone, QdTone.neutral);
    }
  });

  test('pending cancellation request adds its own warning chip', () {
    expect(qdJobStatusChips('active', cancellationRequestStatus: 'pending'),
        [QdJobStatus.active, QdJobStatus.cancellationRequested]);
    expect(QdJobStatus.cancellationRequested.tone, QdTone.warning);
    for (final other in [null, '', 'approved', 'rejected']) {
      expect(qdJobStatusChips('active', cancellationRequestStatus: other),
          [QdJobStatus.active],
          reason: '$other');
    }
  });

  test('every chip has a distinct, non-empty label in EN and AR', () {
    for (final locale in bothLocales) {
      final l10n = lookupAppLocalizations(locale);
      final labels = QdJobStatus.values.map((s) => s.label(l10n)).toList();
      expect(labels.every((l) => l.trim().isNotEmpty), isTrue);
      expect(labels.toSet().length, labels.length, reason: '$labels');
      if (locale == en) {
        // Sentence case: no Title Case, no ALL CAPS.
        for (final l in labels) {
          final words = l.split(' ');
          expect(words.skip(1).every((w) => w == w.toLowerCase()), isTrue,
              reason: l);
        }
      }
    }
  });

  testWidgets('chips render tone colors and both chips', (tester) async {
    await tester.pumpWidget(qdApp(const QdJobStatusChips(
        status: 'active', cancellationRequestStatus: 'pending')));
    expect(find.text('في الطريق'), findsOneWidget);
    expect(find.text('طلب إلغاء'), findsOneWidget);
    expect(tester.widget<Text>(find.text('في الطريق')).style?.color,
        QdColors.light.success);
    expect(tester.widget<Text>(find.text('طلب إلغاء')).style?.color,
        QdColors.light.warning);
  });

  testWidgets('unknown status renders a neutral chip', (tester) async {
    await tester.pumpWidget(
        qdApp(const QdJobStatusChips(status: 'warp_speed'), locale: en));
    expect(find.text('Unknown status'), findsOneWidget);
    expect(tester.widget<Text>(find.text('Unknown status')).style?.color,
        QdColors.light.neutral);
  });

  testWidgets('chip never wraps', (tester) async {
    await tester.pumpWidget(qdApp(const SizedBox(
        width: 60,
        child: QdStatusChip(
            label: 'Cancellation requested', tone: QdTone.warning))));
    final text = tester.widget<Text>(find.text('Cancellation requested'));
    expect(text.maxLines, 1);
    expect(text.softWrap, isFalse);
    expect(tester.takeException(), isNull);
  });
}
