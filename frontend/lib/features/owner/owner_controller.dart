import 'package:flutter/foundation.dart';

import '../../models/job.dart';
import '../../providers/auth_provider.dart';
import '../../providers/owner_provider.dart';
import 'owner_rules.dart';

/// Loading state for the redesigned owner pages (FE-OWNER-1), shared by the
/// shell's tabs and the pages pushed from them.
///
/// [OwnerProvider] has one `isLoading` / `error` for every call, so this
/// controller keeps its own state: it runs the jobs and employees fetches
/// one after the other and reads their per-call errors
/// ([OwnerProvider.ownerJobsError], [OwnerProvider.employeesError]).
class OwnerDataController extends ChangeNotifier {
  OwnerDataController(this.owner, this.auth, {DateTime Function()? now})
      : now = now ?? DateTime.now {
    owner.addListener(_onOwnerChanged);
  }

  final OwnerProvider owner;
  final AuthProvider auth;

  /// Clock for "today" and relative times (tests).
  final DateTime Function() now;

  bool _loading = false;
  bool _loaded = false;
  String? _jobsError;
  String? _employeesError;
  Future<void>? _inFlight;
  bool _disposed = false;

  List<OwnerEmployee> _employees = const [];
  Map<String, OwnerEmployee> _byId = const {};
  List<dynamic>? _employeesSource;

  bool get loading => _loading;

  /// True once a refresh has finished (successfully or not).
  bool get loaded => _loaded;
  String? get jobsError => _jobsError;
  String? get employeesError => _employeesError;

  List<Job> get jobs => owner.ownerJobs;

  List<OwnerEmployee> get employees {
    _syncEmployees();
    return _employees;
  }

  OwnerEmployee? employeeById(String? id) {
    if (id == null || id.isEmpty) return null;
    _syncEmployees();
    return _byId[id];
  }

  Job? jobById(String id) => jobs.where((j) => j.id == id).firstOrNull;

  OwnerJobExtras extrasOf(String jobId) =>
      OwnerJobExtras.fromJson(owner.ownerJobJson(jobId));

  void _syncEmployees() {
    final src = owner.employees;
    if (identical(src, _employeesSource)) return;
    _employeesSource = src;
    _employees = OwnerEmployee.listFrom(src);
    _byId = {for (final e in _employees) e.id: e};
  }

  void _onOwnerChanged() {
    if (!_disposed) notifyListeners();
  }

  /// Reloads the profile (KYB status), the owner jobs and the employees.
  /// A call while one is running joins it.
  Future<void> refresh() => _inFlight ??= _run().whenComplete(() {
        _inFlight = null;
      });

  Future<void> _run() async {
    _loading = true;
    _notify();
    final token = auth.token;
    if (token == null) {
      _jobsError = _employeesError = 'not signed in';
    } else {
      try {
        await auth.fetchUserProfile();
      } catch (_) {
        // The KYB banner keeps the last known status.
      }
      await owner.fetchOwnerJobs(token);
      _jobsError = owner.ownerJobsError;
      await owner.fetchEmployees(token);
      _employeesError = owner.employeesError;
    }
    _loading = false;
    _loaded = true;
    _notify();
  }

  /// Reloads the owner jobs only (after an action on one order).
  Future<void> refreshJobs() async {
    final token = auth.token;
    if (token == null) return;
    await owner.fetchOwnerJobs(token);
    _jobsError = owner.ownerJobsError;
    _notify();
  }

  /// Reloads the employees only (after adding, freezing or unfreezing).
  Future<void> refreshEmployees() async {
    final token = auth.token;
    if (token == null) return;
    await owner.fetchEmployees(token);
    _employeesError = owner.employeesError;
    _notify();
  }

  void _notify() {
    if (!_disposed) notifyListeners();
  }

  @override
  void dispose() {
    _disposed = true;
    owner.removeListener(_onOwnerChanged);
    super.dispose();
  }
}
