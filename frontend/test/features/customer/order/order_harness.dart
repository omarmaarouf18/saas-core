import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/order/order_deps.dart';
import 'package:frontend/features/customer/order/order_detail_page.dart';
import 'package:frontend/models/job.dart';

import '../customer_harness.dart';

/// Courier names without the network.
class FakeCourierLookup extends CourierLookup {
  FakeCourierLookup([this.names = const {}]);

  final Map<String, String?> names;
  final List<String> calls = [];

  @override
  Future<String?> nameOf(BuildContext context, String userId) async {
    calls.add(userId);
    return names[userId];
  }
}

/// Pumps the order page for [job]. The first fetch returns
/// `deps.marketplace.nextStatus` (default: [job] itself). The clock is
/// [now] (default [fixedNow]); timers run on the test's fake clock.
Future<void> pumpOrder(
  WidgetTester tester,
  CustomerTestDeps deps,
  Job job, {
  Locale locale = en,
  DateTime Function()? now,
  FakeCourierLookup? lookup,
  bool settle = true,
  ThemeMode themeMode = ThemeMode.light,
}) async {
  usePhone(tester);
  deps.marketplace.nextStatus ??= job;
  await tester.pumpWidget(CourierLookupScope(
    lookup: lookup ?? FakeCourierLookup(),
    child: customerApp(
      deps,
      OrderDetailPage(
          jobId: job.id, initialJob: job, now: now ?? () => fixedNow),
      locale: locale,
      themeMode: themeMode,
    ),
  ));
  if (settle) {
    await tester.pump();
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 400));
  }
}

/// Unmounts the page so its polling timer stops before the test ends.
Future<void> unmountOrder(WidgetTester tester, CustomerTestDeps deps) async {
  await tester.pumpWidget(customerApp(deps, const SizedBox()));
  await tester.pump();
}
