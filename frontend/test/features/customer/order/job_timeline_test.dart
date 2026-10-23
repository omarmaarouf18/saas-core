import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:frontend/features/customer/order/job_timeline.dart';
import 'package:frontend/features/customer/order/job_v2_sections.dart';
import 'package:frontend/l10n/app_localizations.dart';
import 'package:frontend/models/job.dart';

// FE-V2-CONSUME item 3: timeline, phase and ETA from status_history.

final t0 = DateTime.utc(2026, 10, 19, 12, 0);
DateTime at(int minutes) => t0.add(Duration(minutes: minutes));

JobStatusHistoryEntry h(String status, int minutes, [String? sub]) =>
    JobStatusHistoryEntry(status: status, at: at(minutes), subStatus: sub);

Job v2(String status,
        {String? sub,
        List<JobStatusHistoryEntry> history = const [],
        int? eta}) =>
    Job(
      id: 'j1',
      ownerId: 'o',
      userId: 'u',
      serviceId: 's',
      status: status,
      subStatus: sub,
      location: JobLocation(latitude: 1, longitude: 1),
      paymentMethod: 'cod',
      statusHistory: history,
      estimatedDurationMinutes: eta,
    );

const d = JobStepState.done,
    c = JobStepState.current,
    u = JobStepState.upcoming;

void main() {
  group('buildJobTimeline', () {
    test('legacy: no history -> null (page keeps created_at timeline)', () {
      expect(buildJobTimeline(v2('active')), isNull);
      expect(buildJobTimeline(v2('completed')), isNull);
    });

    test('full history, completed', () {
      final job = v2('completed', history: [
        h('pending_dispatch', 0),
        h('active', 1, 'heading_to_pickup'),
        h('active', 15, 'picked_up'),
        h('completed', 32),
      ]);
      expect(buildJobTimeline(job), [
        JobStep(JobStepKind.requested, d, at(0)),
        JobStep(JobStepKind.accepted, d, at(1)),
        JobStep(JobStepKind.pickedUp, d, at(15)),
        JobStep(JobStepKind.delivered, d, at(32)),
      ]);
      expect(jobCompletedAt(job), at(32));
    });

    test('history out of order is sorted', () {
      final job = v2('active', sub: 'picked_up', history: [
        h('active', 15, 'picked_up'),
        h('pending_dispatch', 0),
        h('active', 1, 'heading_to_pickup'),
      ]);
      expect(buildJobTimeline(job)!.map((s) => s.state), [d, d, d, c]);
    });

    test('partial: dispatching', () {
      expect(
          buildJobTimeline(
              v2('pending_dispatch', history: [h('pending_dispatch', 0)])),
          [
            JobStep(JobStepKind.requested, d, at(0)),
            const JobStep(JobStepKind.accepted, c),
            const JobStep(JobStepKind.pickedUp, u),
            const JobStep(JobStepKind.delivered, u),
          ]);
    });

    test('partial: heading to pickup', () {
      final steps = buildJobTimeline(v2('active',
          sub: 'heading_to_pickup',
          history: [
            h('pending_dispatch', 0),
            h('active', 2, 'heading_to_pickup')
          ]))!;
      expect(steps.map((s) => s.state), [d, d, c, u]);
      expect(steps[1].at, at(2));
      expect(steps[2].at, isNull);
    });

    test('partial: status says completed but the entry is missing', () {
      final steps = buildJobTimeline(v2('completed', history: [
        h('pending_dispatch', 0),
        h('active', 2, 'heading_to_pickup')
      ]))!;
      expect(steps.map((s) => s.state), [d, d, d, d]);
      expect(steps[2].at, isNull);
      expect(steps[3].at, isNull);
    });

    test('re-dispatch: accepted restarts from the new courier', () {
      final steps =
          buildJobTimeline(v2('active', sub: 'heading_to_pickup', history: [
        h('pending_dispatch', 0),
        h('active', 1, 'heading_to_pickup'),
        h('pending_dispatch', 20),
        h('active', 25, 'heading_to_pickup'),
      ]))!;
      expect(steps[0].at, at(0));
      expect(steps[1].at, at(25));
    });

    test('cancelled before a courier', () {
      expect(
          buildJobTimeline(v2('cancelled',
              history: [h('pending_dispatch', 0), h('cancelled', 3)])),
          [
            JobStep(JobStepKind.requested, d, at(0)),
            JobStep(JobStepKind.cancelled, d, at(3)),
          ]);
    });

    test('cancelled after acceptance keeps the reached steps', () {
      expect(
          buildJobTimeline(v2('cancelled', history: [
            h('pending_dispatch', 0),
            h('active', 1, 'heading_to_pickup'),
            h('cancelled', 9),
          ])),
          [
            JobStep(JobStepKind.requested, d, at(0)),
            JobStep(JobStepKind.accepted, d, at(1)),
            JobStep(JobStepKind.cancelled, d, at(9)),
          ]);
    });

    test('cancelled without its entry: no time on the last step', () {
      expect(
          buildJobTimeline(v2('cancelled', history: [h('pending', 0)]))!.last,
          const JobStep(JobStepKind.cancelled, d));
    });

    test('unavailable', () {
      expect(
          buildJobTimeline(v2('unavailable',
                  history: [h('pending_dispatch', 0), h('unavailable', 4)]))!
              .last,
          JobStep(JobStepKind.unavailable, d, at(4)));
    });

    test('ride: accepted at the price step', () {
      final steps = buildJobTimeline(v2('awaiting_price_response', history: [
        h('pending_dispatch', 0),
        h('awaiting_price_response', 2)
      ]))!;
      expect(steps[1], JobStep(JobStepKind.accepted, d, at(2)));
      expect(steps[2].state, c);
    });
  });

  group('jobPhase', () {
    test('by sub_status, only while active', () {
      expect(jobPhase(v2('active', sub: 'heading_to_pickup')),
          JobPhase.headingToPickup);
      expect(jobPhase(v2('active', sub: 'picked_up')), JobPhase.pickedUp);
      expect(jobPhase(v2('active')), JobPhase.unknown);
      expect(jobPhase(v2('active', sub: 'teleporting')), JobPhase.unknown);
      expect(jobPhase(v2('completed', sub: 'picked_up')), isNull);
    });
  });

  group('jobEta', () {
    test('absent: no minutes, no phase, or no entry for the phase', () {
      expect(
          jobEta(v2('active',
              sub: 'picked_up', history: [h('active', 5, 'picked_up')])),
          isNull);
      expect(
          jobEta(v2('active', eta: 10, history: [h('active', 5, 'picked_up')])),
          isNull);
      expect(jobEta(v2('active', sub: 'picked_up', eta: 10)), isNull);
      expect(jobEta(v2('completed', eta: 10, history: [h('completed', 5)])),
          isNull);
    });

    test('from the entry of the current phase (latest one)', () {
      final job = v2('active', sub: 'picked_up', eta: 12, history: [
        h('active', 1, 'heading_to_pickup'),
        h('active', 15, 'picked_up'),
      ]);
      expect(jobEta(job), at(27));
      final toPickup = v2('active', sub: 'heading_to_pickup', eta: 8, history: [
        h('active', 1, 'heading_to_pickup'),
        h('pending_dispatch', 3),
        h('active', 4, 'heading_to_pickup'),
      ]);
      expect(jobEta(toPickup), at(12));
    });
  });

  group('jobEtaText', () {
    final job = v2('active', sub: 'picked_up', eta: 12, history: [
      h('active', 15, 'picked_up'),
    ]);
    final pickupJob = v2('active', sub: 'heading_to_pickup', eta: 5, history: [
      h('active', 1, 'heading_to_pickup'),
    ]);

    Future<String?> text(WidgetTester tester, Job j, DateTime now,
        {Locale locale = const Locale('en'), bool ride = false}) async {
      String? out;
      await tester.pumpWidget(MaterialApp(
        locale: locale,
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: MediaQuery(
          data: const MediaQueryData(alwaysUse24HourFormat: true),
          child: Builder(builder: (context) {
            out = jobEtaText(context, j, now: now, ride: ride);
            return const SizedBox();
          }),
        ),
      ));
      return out;
    }

    String hhmm(DateTime t) {
      final l = t.toLocal();
      return '${l.hour.toString().padLeft(2, '0')}:'
          '${l.minute.toString().padLeft(2, '0')}';
    }

    testWidgets('absent', (tester) async {
      expect(await text(tester, v2('active', sub: 'picked_up'), at(0)), isNull);
    });

    testWidgets('EN, to the drop-off and to the pickup', (tester) async {
      expect(await text(tester, job, at(20)), 'Arrives around ${hhmm(at(27))}');
      expect(await text(tester, pickupJob, at(2)),
          'At the pickup around ${hhmm(at(6))}');
      expect(await text(tester, pickupJob, at(2), ride: true),
          'Picks you up around ${hhmm(at(6))}');
    });

    testWidgets('AR', (tester) async {
      final s = await text(tester, job, at(20), locale: const Locale('ar'));
      expect(s, startsWith('هيوصل حوالي '));
    });

    testWidgets('past: any minute', (tester) async {
      expect(await text(tester, job, at(27)), 'Should arrive any minute');
      expect(await text(tester, pickupJob, at(30)),
          'Should reach the pickup any minute');
      expect(await text(tester, job, at(40), locale: const Locale('ar')),
          'هيوصل في أي لحظة');
    });
  });
}
