/// Rules for the redesigned activity log (FE-OWNER-2): the audit log
/// (`GET /auth/audit-log`: id, employee_id, tenant_id, action, timestamp)
/// and the money ledger (`GET /users/ledger`: job_id, type, amount,
/// balance_before, balance_after, description, timestamp).
library;

DateTime? _time(Object? raw) =>
    raw is String ? DateTime.tryParse(raw)?.toLocal() : null;

class AuditItem {
  const AuditItem(
      {required this.id, required this.action, this.employeeId, this.at});

  final String id;
  final String action;
  final String? employeeId;
  final DateTime? at;

  factory AuditItem.fromJson(Map<dynamic, dynamic> j) {
    final emp = j['employee_id']?.toString().trim() ?? '';
    return AuditItem(
      id: j['id']?.toString() ?? '',
      action: j['action']?.toString() ?? '',
      employeeId: emp.isEmpty ? null : emp,
      at: _time(j['timestamp']),
    );
  }

  static List<AuditItem> listFrom(Iterable<dynamic> raw) => [
        for (final e in raw)
          if (e is Map) AuditItem.fromJson(e),
      ];
}

/// Types that add money to the owner when the entry has no balances.
const Set<String> _inTypes = {
  'deposit',
  'refund',
  'escrow_release',
  'payout_refund',
  // Without balances, a payout entry is the owner's share written with an
  // escrow release; a payout request always carries balances.
  'payout',
};

class LedgerItem {
  const LedgerItem({
    required this.id,
    required this.type,
    required this.amount,
    this.jobId,
    this.balanceBefore = 0,
    this.balanceAfter = 0,
    this.at,
  });

  final String id;
  final String type;
  final double amount;
  final String? jobId;
  final double balanceBefore;
  final double balanceAfter;
  final DateTime? at;

  factory LedgerItem.fromJson(Map<dynamic, dynamic> j) {
    final job = j['job_id']?.toString().trim() ?? '';
    double n(Object? v) => (v as num?)?.toDouble() ?? 0;
    return LedgerItem(
      id: j['id']?.toString() ?? '',
      type: j['type']?.toString().trim().toLowerCase() ?? '',
      amount: n(j['amount']).abs(),
      jobId: job.isEmpty ? null : job,
      balanceBefore: n(j['balance_before']),
      balanceAfter: n(j['balance_after']),
      at: _time(j['timestamp']),
    );
  }

  static List<LedgerItem> listFrom(Iterable<dynamic> raw) => [
        for (final e in raw)
          if (e is Map) LedgerItem.fromJson(e),
      ];

  /// The server recorded the balance around this entry.
  bool get hasBalance => balanceBefore != 0 || balanceAfter != 0;

  /// Money in: by the balance change when there is one, else by type.
  bool get incoming => balanceBefore != balanceAfter
      ? balanceAfter > balanceBefore
      : _inTypes.contains(type);
}

enum LogPeriod { all, today, week }

bool inPeriod(LogPeriod p, DateTime? at, DateTime now) {
  if (p == LogPeriod.all) return true;
  if (at == null) return false;
  final local = at.toLocal(), today = now.toLocal();
  final startOfToday = DateTime(today.year, today.month, today.day);
  return switch (p) {
    LogPeriod.all => true,
    LogPeriod.today => !local.isBefore(startOfToday),
    LogPeriod.week =>
      !local.isBefore(startOfToday.subtract(const Duration(days: 6))),
  };
}

/// "#QD-" and the first 8 characters of a job id, as the order pages show
/// it, in a left-to-right isolate.
String jobIdRefIsolated(String jobId) {
  final s = jobId.length > 8 ? jobId.substring(0, 8) : jobId;
  return '\u2066#QD-${s.toUpperCase()}\u2069';
}
