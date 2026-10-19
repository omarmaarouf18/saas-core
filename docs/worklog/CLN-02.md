# Worklog: CLN-02 — Repo Tidy (Files and Docs Only)

## Overview & Scope
- **Worktree**: `../saas-core-wt/CLN-02`
- **Branch**: `agent/CLN-02-repo-tidy` branched from `75367b5` (`logic-exploitation` base)
- **Goal**: Execute repo tidy items 1–8 per `docs/CLEANUP_INVENTORY.md` and owner instructions with zero behavior/code logic changes.
- **Allowed lane**: `design/**`, `docs/**` (link-only edits in changelog without changing text/SHAs), `README.md`, `index.html`, `IMPLEMENTATION.md`, `QA-COVERAGE.md`, `infrastructure/docker-compose.yml`, `infrastructure/Caddyfile`, and in `shared/infra/docgen/generator.go` ONLY the version-config "Targets" strings. Link-only edits in `AI_CONTEXT.md` explicitly granted.

---

## Execution Summary (Items 1–8)

### Item 1: design/ cleanup (inventory items 1a, 1b, 1c)
- **Status**: Done (commit `9c6435c`)
- **Action**: Deleted 12 superseded stitch-export variant folders:
  - `design/stitch-export/logistics_core_unified/job_status_1`
  - `design/stitch-export/logistics_core_unified/job_status_2`
  - `design/stitch-export/logistics_core_unified/customer_job_map`
  - `design/stitch-export/logistics_core_unified/reconciliation_queue_1`
  - `design/stitch-export/logistics_core_unified/reconciliation_queue_2`
  - `design/stitch-export/quick_delivery_ui_brief/fleet_map`
  - `design/stitch-export/quick_delivery_ui_brief/kyc_kyb_upload`
  - `design/stitch-export/quick_delivery_ui_brief/signup`
  - `design/stitch-export/quick_delivery_ui_brief/velocity_logistics`
  - `design/stitch-export/quick_delivery_ui_brief/` (14 screen folders)
  - `design/stitch-export/kinetic_logistics-light`
  - `design/stitch-export/nocturne_amber-dark`
- **Disk size**: Reduced from 13,308 KiB (~13 MiB) to 5,364 KiB (~5.3 MiB), freeing ~7.76 MiB.
- **Grep Before**: Zero references in `services/**`, `frontend/**`, `tests/**`, or `scripts/**`. Only historical mentions in `docs/history/frontend/STITCH_VISUAL_AUDIT.md`.
- **Grep After**: Zero folders remaining on disk.

### Item 2: Root index.html ("Logic Vetting Interface")
- **Status**: Done (commit `ceb650c`)
- **Action**: Deleted obsolete root `index.html`.
- **Grep Before**: No references in Go or Dart code; only historical mentions in `docs/adr/0001-...` and KYC console changelog.
- **Grep After**: `index.html` removed from repository root.

### Item 3: Historical docs → docs/history/ (14 docs + IMPLEMENTATION.md)
- **Status**: Done (commit `9679444`)
- **Action**: Moved 14 historical documents and `IMPLEMENTATION.md` via `git mv`:
  - `docs/BUSINESS_LOGIC_AUDIT.md` -> `docs/history/BUSINESS_LOGIC_AUDIT.md`
  - `docs/FRONTEND_CONSISTENCY_AUDIT.md` -> `docs/history/FRONTEND_CONSISTENCY_AUDIT.md`
  - `docs/FRONTEND_INTEGRATION_SCOPE.md` -> `docs/history/FRONTEND_INTEGRATION_SCOPE.md`
  - `IMPLEMENTATION.md` -> `docs/history/IMPLEMENTATION.md`
  - `docs/audit/shared-module-review.md` -> `docs/history/audit/shared-module-review.md`
  - `docs/reports/P1_DARK_THEME_UNIFICATION_REPORT.md` -> `docs/history/reports/P1_DARK_THEME_UNIFICATION_REPORT.md`
  - `docs/reports/P2_SCREEN_MIGRATION_REPORT.md` -> `docs/history/reports/P2_SCREEN_MIGRATION_REPORT.md`
  - `docs/frontend/EMPLOYEE_CAPABILITY_AUDIT.md` -> `docs/history/frontend/EMPLOYEE_CAPABILITY_AUDIT.md`
  - `docs/frontend/EMPLOYEE_FUNCTIONALITY_AUDIT.md` -> `docs/history/frontend/EMPLOYEE_FUNCTIONALITY_AUDIT.md`
  - `docs/frontend/STITCH_VISUAL_AUDIT.md` -> `docs/history/frontend/STITCH_VISUAL_AUDIT.md`
  - `docs/frontend/STITCH_VISUAL_AUDIT_V2.md` -> `docs/history/frontend/STITCH_VISUAL_AUDIT_V2.md`
  - `docs/frontend/UI_UX_AUDIT.md` -> `docs/history/frontend/UI_UX_AUDIT.md`
  - `docs/frontend/UI_UX_ENTERPRISE_ROADMAP.md` -> `docs/history/frontend/UI_UX_ENTERPRISE_ROADMAP.md`
  - `docs/frontend/UI_VISUAL_AUDIT_2026-09.md` -> `docs/history/frontend/UI_VISUAL_AUDIT_2026-09.md`
- Added "Historical — superseded by ..." headers to the 5 files with designated successors (`IMPLEMENTATION.md`, `FRONTEND_INTEGRATION_SCOPE.md`, `UI_UX_ENTERPRISE_ROADMAP.md`, `STITCH_VISUAL_AUDIT.md`, `EMPLOYEE_CAPABILITY_AUDIT.md`).
- Updated relative inbound links in `AI_CONTEXT.md`, `README.md`, `docs/frontend/STATUS.md`, `docs/frontend/UI_UX_BEHAVIOR_AUDIT.md`, `docs/changelog/infrastructure.md`, and `docs/README.md`.

### Item 4: QA-COVERAGE.md → docs/qa/QA-COVERAGE.md
- **Status**: Done (commit `81ac0b9`)
- **Action**: Verified docgen does not hard-code `QA-COVERAGE.md` (only `DESIGN.md` is hard-coded). Moved via `git mv QA-COVERAGE.md docs/qa/QA-COVERAGE.md`.
- Updated Section 6 relative links inside `docs/qa/QA-COVERAGE.md` (`docs/...` -> `../...`, fixed ADR 0021 filename to `0021-kyc-kyb-kye-reviewer-console.md`).
- Updated link in `docs/README.md`.

### Item 5: docs/README.md as Single Index Table
- **Status**: Done (commit `acfce5c`)
- **Action**: Consolidated multiple separate tables into one comprehensive index table with columns `| Path | Purpose | Class | Modified | In-links | Superseded by |`.
- Included `docs/runbooks/`, `docs/worklog/` (single row for the folder), `docs/audit/REBASELINE-2026-10.md`, and `docs/history/`. Removed stale `history/AI_CONTEXT.proposed.md` row.
- Verified cross-linking between `docs/WORKFLOW.md` and `docs/CI_CD_AND_HOOKS.md`.

### Item 6: Deployment Docs & APPLICATION_MAP Match OPS-HARDEN
- **Status**: Done (commit `7ebaf1a`)
- **Action**:
  - `docs/DEPLOYMENT.md`: Documented compose-managed `saas-caddy` service (`infrastructure/deploy/Caddyfile`, external `caddy_data` volume); removed `Allow-API-Gateway-Direct` from NSG table; updated all host health check instructions from `curl https://localhost:8080/health` to `docker exec saas-api-gateway curl -sk https://localhost:8080/health`; updated admin API / version-config documentation to reflect edge 404 and execution via `docker exec saas-api-gateway` with `X-Admin-Token`; removed manual Caddy startup instructions.
  - `docs/REPOSITORY_MAP.md`: Updated Section 4 to reflect compose Caddy, gateway internal health check, admin API isolation, and fixed broken `file:///mnt/windows_data/...` links to relative links.
  - `shared/infra/docgen/generator.go`: Updated the two "Targets" strings for `/api/v1/admin/version-config` (in `KnownEndpoints` and `endpoints = append(...)`) from `Reads/Updates platform_versions collection` to `Reads/Updates in-memory version store.`.
  - Ran `make docs` to regenerate `docs/APPLICATION_MAP.md`.

### Item 7: README.md Sample Tokens Sanitization
- **Status**: Done (commit `0251b99`)
- **Action**: Replaced literal hex sample token prefixes in `README.md` lines 135 and 169 with `<64-hex-token-shown-once>` to prevent gitleaks false alarms.

### Item 8: Local Compose Caddyfile
- **Status**: Done (commit `70396e2`)
- **Choice**: (a) Add minimal local `infrastructure/Caddyfile`.
- **Justification**: Providing a minimal local `infrastructure/Caddyfile` (HTTP only `:80`, reverse proxy to `https://api-gateway:8080`, `@admin` path 404) prevents Docker Compose from creating `./Caddyfile` as an empty directory on the host when starting `infrastructure/docker-compose.yml`, while maintaining architectural parity with staging and production.
- **Validation**: Passed `caddy validate` via container and `scripts/compose-validate.sh` (`compose config OK: local`).

---

## Verification & Literal Outputs

### 1. Grep Commands (Items 1–4)
```bash
# Item 1: Grep variant folder references across repo
git grep -E "kinetic_logistics-light|nocturne_amber-dark|logistics_core_unified/job_status_1" || echo "0 code references"
# Output:
# 0 code references

# Item 2: Grep root index.html references
git grep -F "index.html" -- ':!docs/adr/0001*' ':!docs/worklog/*' || echo "0 active references"
# Output:
# 0 active references

# Item 4: Grep QA-COVERAGE in docgen/scripts
git grep "QA-COVERAGE" shared/infra/ scripts/ Makefile || echo "0 hardcoded paths"
# Output:
# 0 hardcoded paths
```

### 2. Relative Link Check Across All *.md
```bash
python3 -c '
import os, re, subprocess

tracked_md = subprocess.check_output(["git", "ls-files", "*.md"]).decode().strip().split("\n")
active_md = [f for f in tracked_md if not f.startswith("docs/history/")]
broken = []
total_links = 0

for file_path in active_md:
    if not os.path.isfile(file_path):
        continue
    file_dir = os.path.dirname(file_path)
    with open(file_path, "r", encoding="utf-8", errors="ignore") as f:
        in_code_block = False
        for line_no, line in enumerate(f, 1):
            if line.strip().startswith("```"):
                in_code_block = not in_code_block
                continue
            if in_code_block:
                continue
            for m in re.finditer(r"\[([^\]]+)\]\(([^)]+)\)", line):
                target = m.group(2).strip()
                if re.match(r"^(https?://|file://|mailto:|#)", target):
                    continue
                clean_target = target.split("#")[0].split("?")[0]
                if not clean_target:
                    continue
                total_links += 1
                resolved = os.path.normpath(os.path.join(file_dir, clean_target))
                if not os.path.exists(resolved):
                    broken.append((file_path, line_no, m.group(1), target, resolved))

print(f"Total active internal relative links checked: {total_links}")
if broken:
    print(f"Found {len(broken)} broken links")
    exit(1)
else:
    print("0 broken")
'
```
Literal output:
```text
Total active internal relative links checked: 394
0 broken
```

### 3. Shared Infra Tests & Changelog Validation
```bash
go test ./shared/infra/...
```
Literal output:
```text
ok  	github.com/project/shared/infra	(cached)
ok  	github.com/project/shared/infra/docgen	0.024s
ok  	github.com/project/shared/infra/handlerutil	(cached)
ok  	github.com/project/shared/infra/jwtutil	(cached)
ok  	github.com/project/shared/infra/passwordpolicy	(cached)
ok  	github.com/project/shared/infra/ratelimit	(cached)
ok  	github.com/project/shared/infra/redact	(cached)
ok  	github.com/project/shared/infra/resilience	(cached)
ok  	github.com/project/shared/infra/storage	(cached)
ok  	github.com/project/shared/infra/testutil	(cached)
ok  	github.com/project/shared/infra/tlsutil	(cached)
```

### 4. Markdown Commit SHA Check
```bash
FAILED_SHA=0
for file in $(find . -type f -name "*.md" -not -path "*/node_modules/*" -not -path "*/vendor/*" -not -path "*/.git/*"); do
  for sha in $(grep -oE "[0-9a-f]{40}" "$file" || true); do
    if ! git cat-file -e "$sha^{commit}" 2>/dev/null; then
      echo "BLOCKED: fabricated/non-existent SHA $sha in $file"
      FAILED_SHA=1
    elif ! git merge-base --is-ancestor "$sha" HEAD 2>/dev/null; then
      echo "BLOCKED: SHA $sha in $file is not reachable from current branch history"
      FAILED_SHA=1
    fi
  done
done
[ "$FAILED_SHA" -eq 0 ] && echo "Markdown SHA check PASSED! 0 violations."
```
Literal output:
```text
Markdown SHA check PASSED! 0 violations.
```

### 5. Git Log (Items 1–8)
```bash
git log --oneline 75367b5..HEAD
```
Literal output:
```text
70396e2 CLN-02: add local dev Caddyfile for compose reverse proxy (item 8)
0251b99 CLN-02: sanitize sample token hex strings in README.md (item 7)
7ebaf1a CLN-02: update deployment docs and APPLICATION_MAP for OPS-HARDEN (item 6)
acfce5c CLN-02: consolidate docs/README.md into single index table (item 5)
81ac0b9 CLN-02: move QA-COVERAGE.md to docs/qa/ (item 4)
9679444 CLN-02: archive 14 historical docs to docs/history/ and update inbound links (item 3)
ceb650c CLN-02: delete obsolete root index.html logic vetting interface (item 2)
9c6435c CLN-02: remove superseded stitch-export variant folders from design/ (items 1a-1c)
```

### 6. Git Diff Stat (Branch Base 75367b5 to HEAD)
```bash
git diff --stat 75367b5..HEAD | tail -5
```
Literal output:
```text
 index.html                                         | 363 ---------------
 infrastructure/Caddyfile                           |  15 +
 shared/infra/docgen/generator.go                   |   8 +-
 106 files changed, 317 insertions(+), 12935 deletions(-)
```

---

## Verification & Follow-ups
- **Unverified**: None. All automated test suites, pre-push quality gates (`make check`), gitleaks, compose syntax validation, and markdown link verification passed.
- **Follow-ups**:
  1. Staging compose Caddyfile (`infrastructure/staging/Caddyfile`) currently has no `@admin` 404 matcher; consider aligning staging with prod/local if staging ever exposes admin routes.
  2. Future cleanup can optionally archive the per-test historical narratives inside `docs/qa/QA-COVERAGE.md` sections 3 and 4 once new QA framework replaces them.
- **Questions**: None.
