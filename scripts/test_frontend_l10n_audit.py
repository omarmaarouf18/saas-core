#!/usr/bin/env python3
"""Regression tests for frontend_l10n_audit.py.

Verifies that the audit scanner detects hardcoded English strings returned
from getters, methods, and arrow functions in models/providers/services,
closing the blind spot where display strings were smuggled into non-widget layers.
"""
import sys
import unittest
from pathlib import Path

# Add repo root to sys.path
REPO_ROOT = Path(__file__).resolve().parent.parent
sys.path.insert(0, str(REPO_ROOT))

from scripts.frontend_l10n_audit import audit_source, is_accepted_exception


class TestFrontendL10nAudit(unittest.TestCase):
    def test_catches_getter_returning_hardcoded_english(self):
        """Proves the scanner catches the exact pattern from reconciliation_job.dart."""
        fixture = """
        class ReconciliationJob {
          final String escrowFailureReason;
          ReconciliationJob(this.escrowFailureReason);

          String get humanReadableFailureReason {
            switch (escrowFailureReason) {
              case 'under_distance_mismatch':
                return 'Distance mismatch — under 70% of booked distance';
              case 'escrow_amount_unrecorded':
                return 'Unrecorded escrow balance failure';
              case 'implausible_speed':
                return 'Implausible movement speed detected';
              default:
                return 'Escrow reconciliation required for manual review';
            }
          }
        }
        """
        total, findings = audit_source(fixture, Path("frontend/lib/models/reconciliation_job.dart"))
        flagged_literals = [lit for _, _, lit in findings]

        self.assertIn("Distance mismatch — under 70% of booked distance", flagged_literals)
        self.assertIn("Unrecorded escrow balance failure", flagged_literals)
        self.assertIn("Implausible movement speed detected", flagged_literals)
        self.assertIn("Escrow reconciliation required for manual review", flagged_literals)
        self.assertEqual(len(flagged_literals), 4)

        # None of these should be classified as accepted exceptions
        for lit in flagged_literals:
            self.assertFalse(is_accepted_exception("frontend/lib/models/reconciliation_job.dart", lit))

    def test_catches_arrow_getter_returning_hardcoded_english(self):
        """Proves arrow getters returning English display strings are caught."""
        fixture = """
        class NotificationModel {
          String get displayTag => 'Critical Job Alert';
        }
        """
        total, findings = audit_source(fixture, Path("frontend/lib/models/notification_model.dart"))
        flagged_literals = [lit for _, _, lit in findings]

        self.assertIn("Critical Job Alert", flagged_literals)
        self.assertEqual(len(flagged_literals), 1)

    def test_allows_machine_codes_and_enums(self):
        """Proves machine-level identifiers (snake_case) returned from getters are permitted."""
        fixture = """
        class JobModel {
          String get status => 'under_distance_mismatch';
          String get fallbackReason => 'escrow_amount_unrecorded';
          String get state => 'pending';
        }
        """
        total, findings = audit_source(fixture, Path("frontend/lib/models/job_model.dart"))
        self.assertEqual(len(findings), 0)

    def test_allows_routes_and_auth_headers(self):
        """Proves route strings, asset paths, and technical auth templates are permitted."""
        fixture = """
        class ApiService {
          String get cancelRoute => '/users/jobs/cancel';
          String get authHeader => 'Bearer $token';
          String get logoPath => 'assets/icons/logo.svg';
        }
        """
        total, findings = audit_source(fixture, Path("frontend/lib/services/api_service.dart"))
        self.assertEqual(len(findings), 0)

    def test_allows_l10n_references(self):
        """Proves references properly routed through l10n are not flagged."""
        fixture = """
        class UserBanner extends StatelessWidget {
          @override
          Widget build(BuildContext context) {
            return Text(context.l10n.welcomeMessage);
          }
        }
        """
        total, findings = audit_source(fixture, Path("frontend/lib/widgets/user_banner.dart"))
        self.assertEqual(len(findings), 0)


if __name__ == "__main__":
    unittest.main()
