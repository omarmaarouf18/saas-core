import 'package:flutter/material.dart';

import '../../../l10n/l10n.dart';
import '../../../models/job.dart';
import '../../../ui/qd_ui.dart';
import '../booking_rules.dart';
import '../customer_format.dart';
import 'job_timeline.dart';

/// Localized views of the job model v2 fields (FE-V2-CONSUME), shared by
/// the customer order page and the owner order pages: the history
/// timeline, the phase text, the ETA line and the recipient / package
/// rows. Wording follows the service category (ADR-0028 §2.9.3): rides
/// say driver / passenger.

/// Timeline rows for [steps]. [owner] words the first steps for the owner
/// ("Customer ordered", "Karim accepted").
List<QdTimelineStep> jobTimelineSteps(
  BuildContext context,
  List<JobStep> steps, {
  required DateTime now,
  bool ride = false,
  bool owner = false,
  String? courierName,
}) {
  final l10n = context.l10n;
  String label(JobStepKind k) => switch (k) {
        JobStepKind.requested =>
          owner ? l10n.tlOwnRequested : l10n.ordStepOrdered,
        JobStepKind.accepted => courierName == null
            ? l10n.ordStepAcceptedNoName
            : owner
                ? l10n.tlOwnAccepted(courierName)
                : l10n.ordStepAccepted(courierName),
        JobStepKind.pickedUp => !ride
            ? l10n.tlPickedUp
            : owner
                ? l10n.tlPickedUpRideOwner
                : l10n.tlPickedUpRide,
        JobStepKind.delivered => ride ? l10n.tlArrived : l10n.ordStepDelivered,
        JobStepKind.cancelled => l10n.tlCancelled,
        JobStepKind.unavailable => l10n.tlUnavailable,
      };
  return [
    for (final s in steps)
      QdTimelineStep(
        label: label(s.kind),
        state: switch (s.state) {
          JobStepState.done => QdTimelineState.done,
          JobStepState.current => QdTimelineState.current,
          JobStepState.upcoming => QdTimelineState.upcoming,
        },
        time: s.at == null ? null : formatWhen(context, s.at!, now: now),
      ),
  ];
}

/// The history timeline of [job], or null for a legacy job (no history).
Widget? jobHistoryTimeline(
  BuildContext context,
  Job job, {
  required DateTime now,
  bool ride = false,
  bool owner = false,
  String? courierName,
  Key? key,
}) {
  final steps = buildJobTimeline(job);
  if (steps == null) return null;
  return Semantics(
    label: context.l10n.ordSteps,
    container: true,
    child: QdTimeline(
      key: key,
      steps: jobTimelineSteps(context, steps,
          now: now, ride: ride, owner: owner, courierName: courierName),
    ),
  );
}

/// Customer sentence for the phase ("On the way to you"); null when the
/// job is not active or its phase is unknown (legacy: plain "active").
String? jobPhaseText(AppLocalizations l10n, Job job, {bool ride = false}) =>
    switch (jobPhase(job)) {
      JobPhase.headingToPickup =>
        ride ? l10n.phaseToPickupRide : l10n.phaseToPickup,
      JobPhase.pickedUp => ride ? l10n.phasePickedUpRide : l10n.phasePickedUp,
      JobPhase.unknown || null => null,
    };

/// Short chip text for the phase (owner lists and detail).
String? jobPhaseChip(AppLocalizations l10n, Job job, {bool ride = false}) =>
    switch (jobPhase(job)) {
      JobPhase.headingToPickup =>
        ride ? l10n.phaseChipToPickupRide : l10n.phaseChipToPickup,
      JobPhase.pickedUp =>
        ride ? l10n.phaseChipPickedUpRide : l10n.phaseChipPickedUp,
      JobPhase.unknown || null => null,
    };

/// "Arrives around 14:35" from [jobEta]; "any minute" once that time has
/// passed; null when there is no estimate.
String? jobEtaText(BuildContext context, Job job,
    {required DateTime now, bool ride = false}) {
  final eta = jobEta(job);
  if (eta == null) return null;
  final l10n = context.l10n;
  final toPickup = jobPhase(job) == JobPhase.headingToPickup;
  if (!eta.isAfter(now)) return toPickup ? l10n.etaPickupSoon : l10n.etaSoon;
  // The device's 12 / 24-hour setting decides "2:35 PM" or "14:35".
  final time = MaterialLocalizations.of(context).formatTimeOfDay(
      TimeOfDay.fromDateTime(eta.toLocal()),
      alwaysUse24HourFormat: MediaQuery.alwaysUse24HourFormatOf(context));
  if (!toPickup) return l10n.etaAround(time);
  return ride ? l10n.etaPickupAroundRide(time) : l10n.etaPickupAround(time);
}

/// The recipient (or passenger) and the package of [job], as label /
/// value rows; empty when the job has neither (legacy, or nothing given).
class JobRecipientPackageRows extends StatelessWidget {
  const JobRecipientPackageRows(
      {super.key, required this.job, this.ride = false});

  final Job job;
  final bool ride;

  static bool hasAny(Job job) =>
      job.recipient != null || job.packageDetails != null;

  @override
  Widget build(BuildContext context) {
    final l10n = context.l10n;
    final c = QdColors.of(context);
    final r = job.recipient;
    final p = job.packageDetails;
    Widget row(Key key, String label, String value, String? note) => Padding(
          key: key,
          padding: const EdgeInsets.only(top: QdSpace.x2),
          child: MergeSemantics(
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Text(label,
                      style: QdText.body.copyWith(color: c.textSecondary)),
                ),
                const SizedBox(width: QdSpace.x3),
                Flexible(
                  flex: 2,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.end,
                    children: [
                      Text(value,
                          textAlign: TextAlign.end,
                          style:
                              QdText.bodyStrong.copyWith(color: c.textPrimary)),
                      if (note != null)
                        Text(note,
                            textAlign: TextAlign.end,
                            style: QdText.caption
                                .copyWith(color: c.textSecondary)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        );

    final rows = <Widget>[
      if (r != null)
        () {
          final who = [
            if (r.name != null) r.name!,
            // Left-to-right isolate keeps "+20…" in order inside Arabic.
            if (r.phone != null) '\u2066${r.phone!}\u2069',
          ].join(' · ');
          return row(
            const Key('job_recipient'),
            ride ? l10n.ordPassenger : l10n.ordRecipient,
            who.isEmpty ? r.notes ?? '' : who,
            who.isEmpty ? null : r.notes,
          );
        }(),
      if (p != null && !ride)
        row(
          const Key('job_package'),
          l10n.ordPackage,
          packageSizeLabel(l10n, p.size),
          p.notes,
        ),
    ];
    if (rows.isEmpty) return const SizedBox.shrink();
    return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch, children: rows);
  }
}

/// Calls [phone]; copies it with a notice through [notice] when no phone
/// app opens.
Future<void> callPhone(BuildContext context, String phone,
    {required void Function(String message) notice}) {
  final l10n = context.l10n;
  return openOrCopy(
    context,
    [phoneCallUri(phone)],
    copyText: phone,
    onCopied: () {
      if (context.mounted) notice(l10n.lnchPhoneCopied(phone));
    },
  );
}
