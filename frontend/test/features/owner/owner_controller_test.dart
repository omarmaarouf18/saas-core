import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/owner/owner_controller.dart';

import 'owner_harness.dart';

void main() {
  test('refresh: profile, jobs then employees; per-call errors kept', () async {
    final deps = OwnerTestDeps();
    deps.owner.nextJobs = [ownerJob()];
    deps.owner.nextEmployeesError = 'db down';
    final data = deps.data;
    expect(data.loaded, isFalse);

    await data.refresh();
    expect(deps.auth.profileCalls, 1);
    expect(data.loaded, isTrue);
    expect(data.loading, isFalse);
    expect(data.jobs.single.id, 'a1b2c3d4e5f6');
    expect(data.jobsError, isNull);
    // The employees call failed after the jobs call succeeded: the shared
    // provider error would say "no error" for jobs, "db down" overall.
    expect(data.employeesError, 'db down');
  });

  test('a refresh while one runs joins it', () async {
    final deps = OwnerTestDeps();
    deps.owner.jobsGate = Completer<void>();
    final a = deps.data.refresh();
    final b = deps.data.refresh();
    expect(deps.data.loading, isTrue);
    deps.owner.jobsGate!.complete();
    await Future.wait([a, b]);
    expect(deps.owner.jobCalls, 1);
    await deps.data.refresh();
    expect(deps.owner.jobCalls, 2);
  });

  test('no token: errors, no requests', () async {
    final deps = OwnerTestDeps();
    deps.auth.token = null;
    await deps.data.refresh();
    expect(deps.owner.jobCalls, 0);
    expect(deps.data.jobsError, isNotNull);
    expect(deps.data.employeesError, isNotNull);
  });

  test('employees parsed once per list; lookups by id', () async {
    final deps = OwnerTestDeps();
    deps.owner.nextEmployees = [staff('emp-1', 'Karim')];
    await deps.data.refresh();
    final first = deps.data.employees;
    expect(identical(first, deps.data.employees), isTrue);
    expect(deps.data.employeeById('emp-1')?.displayName, 'Karim');
    expect(deps.data.employeeById(null), isNull);
    expect(deps.data.employeeById('nope'), isNull);

    deps.owner.nextEmployees = [staff('emp-2', 'Sara')];
    await deps.data.refreshEmployees();
    expect(deps.data.employeeById('emp-1'), isNull);
    expect(deps.data.employeeById('emp-2')?.displayName, 'Sara');
  });

  test('extras come from the provider\'s raw job JSON', () async {
    final deps = OwnerTestDeps();
    deps.owner.nextJobs = [ownerJob()];
    deps.owner.nextJobJson = {
      'a1b2c3d4e5f6': {'actual_cash_amount': 12.5},
    };
    await deps.data.refresh();
    expect(deps.data.extrasOf('a1b2c3d4e5f6').actualCashAmount, 12.5);
    expect(deps.data.extrasOf('other').actualCashAmount, isNull);
    expect(deps.data.jobById('a1b2c3d4e5f6'), isNotNull);
  });

  test('provider changes notify; dispose stops listening', () async {
    final deps = OwnerTestDeps();
    final data = OwnerDataController(deps.owner, deps.auth);
    var n = 0;
    data.addListener(() => n++);
    deps.owner.notifyListeners();
    expect(n, 1);
    data.dispose();
    deps.owner.notifyListeners(); // no throw on a disposed controller
  });
}
