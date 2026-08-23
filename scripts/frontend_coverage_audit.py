#!/usr/bin/env python3
"""A3 audit: per-file line coverage from frontend/coverage/lcov.info.

Run AFTER:  cd frontend && flutter test --coverage
Then:       python3 scripts/frontend_coverage_audit.py

Flags:
  0%      — file never executed by any test
  LOW     — below risk-tier floor: money/auth/job-state files <60%,
            other UI files <40% (presentational bar)
"""
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
LCOV = REPO / "frontend" / "coverage" / "lcov.info"

RISK = {
    # money (P1)
    "screens/wallet_screen.dart": "money",
    "widgets/deposit_funds_dialog.dart": "money",
    "widgets/payout_request_dialog.dart": "money",
    # auth (P2)
    "screens/login_screen.dart": "auth",
    "screens/signup_screen.dart": "auth",
    "screens/otp_screen.dart": "auth",
    "screens/forgot_password_screen.dart": "auth",
    "providers/auth_provider.dart": "auth",
    "utils/logout_helper.dart": "auth",
    "services/push_notification_service.dart": "auth",
    # job-state (P3)
    "screens/job_status_screen.dart": "jobstate",
    "screens/rating_screen.dart": "jobstate",
    "screens/employee_jobs_screen.dart": "jobstate",
    "widgets/cancel_job_dialog.dart": "jobstate",
    "providers/marketplace_provider.dart": "jobstate",
    "providers/reconciliation_provider.dart": "jobstate",
    "providers/map_tracking_provider.dart": "jobstate",
    "providers/employee_jobs_provider.dart": "jobstate",
}

FLOOR_RISK = 60
FLOOR_OTHER = 40


def parse():
    records = []
    current = None
    for raw in LCOV.read_text().splitlines():
        if raw.startswith("SF:"):
            current = {"path": raw[3:], "found": 0, "hit": 0}
        elif raw.startswith("LF:") and current is not None:
            current["found"] = int(raw[3:])
        elif raw.startswith("LH:") and current is not None:
            current["hit"] = int(raw[3:])
        elif raw == "end_of_record" and current is not None:
            pct = 100.0 if current["found"] == 0 else round(current["hit"] * 100.0 / current["found"], 1)
            current["pct"] = pct
            records.append(current)
            current = None
    return records


def rel_class(path: str) -> str | None:
    p = path.replace("\\", "/")
    marker = "lib/"
    i = p.find(marker)
    if i == -1:
        return None
    return p[i + len(marker):]


def main() -> int:
    groups = {"screens": [], "providers": [], "widgets": [], "services": [], "other-lib": []}
    for rec in parse():
        r = rel_class(rec["path"])
        if r is None:
            continue
        top = r.split("/")[0]
        key = top if top in groups else "other-lib"
        rec["rel"] = r
        groups[key].append(rec)

    print("=== A3 Coverage Audit (frontend/coverage/lcov.info) ===")
    zero, low = [], []
    for key in ("screens", "providers", "widgets", "services", "other-lib"):
        rows = sorted(groups[key], key=lambda x: x["pct"])
        if not rows:
            continue
        print(f"\n--- lib/{key} ---")
        for rec in rows:
            tier = RISK.get(rec["rel"], "ui")
            flag = ""
            if rec["pct"] == 0.0:
                flag = " ** 0% **"
                zero.append(rec)
            else:
                floor = FLOOR_RISK if tier in ("money", "auth", "jobstate") else FLOOR_OTHER
                if rec["pct"] < floor:
                    flag = f" LOW (<{floor} {tier if tier!='ui' else 'ui'})"
                    low.append(rec)
            print(f"{rec['pct']:6.1f}%  [{tier:8s}] {rec['rel']}{flag}")

    total_found = sum(r["found"] for r in sum(groups.values(), []))
    total_hit = sum(r["hit"] for r in sum(groups.values(), []))
    print(f"\n=== Overall (audited dirs): {total_hit}/{total_found} = {round(total_hit*100.0/total_found,1)}% ===")
    print(f"\nZERO-COVERAGE ({len(zero)}):")
    for r in zero:
        print(f"  {r['rel']}  [{RISK.get(r['rel'],'ui')}]")
    print(f"\nBELOW-FLOOR ({len(low)}):")
    for r in low:
        tier = RISK.get(r["rel"], "ui")
        floor = FLOOR_RISK if tier in ("money", "auth", "jobstate") else FLOOR_OTHER
        print(f"  {r['pct']:5.1f}%  [{tier:8s}] {r['rel']}  floor={floor}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
