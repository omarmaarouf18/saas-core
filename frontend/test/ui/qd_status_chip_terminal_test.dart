import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/ui/components/qd_status_chip.dart';

void main() {
  test('completed or cancelled jobs never get the cancellation chip', () {
    for (final terminal in [
      'completed',
      'cancelled',
      'canceled',
      'COMPLETED'
    ]) {
      expect(qdJobStatusChips(terminal, cancellationRequestStatus: 'pending'),
          [QdJobStatus.fromBackend(terminal)],
          reason: terminal);
    }
  });

  test('ongoing jobs still get the cancellation chip', () {
    for (final ongoing in [
      'pending',
      'pending_dispatch',
      'awaiting_price_response',
      'assigned',
      'active',
      'escrow_reconciliation_required',
      'unavailable',
    ]) {
      expect(qdJobStatusChips(ongoing, cancellationRequestStatus: 'pending'),
          [QdJobStatus.fromBackend(ongoing), QdJobStatus.cancellationRequested],
          reason: ongoing);
    }
  });
}
