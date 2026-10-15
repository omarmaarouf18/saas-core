# Cleanup inventory (CLN-01)

Proposals only. CLN-01 moved, deleted and edited nothing listed here. Each section gives the evidence: the command,
then its literal output, captured when this file was generated on branch `agent/CLN-01-repo-diet` (based on
`logic-exploitation` at `1e7692ab...`). Each recommendation carries an action (keep / archive-move / delete /
move-to-other-repo) and a risk.

Executing these moves and deletions is a separate task (CLN-02).

## Summary

| # | Item | Recommended action | Risk | Value |
| :--- | :--- | :--- | :--- | :--- |
| 1a | 12 superseded variant folders in `design/stitch-export/logistics_core_unified/` (about 4.5 MiB) | delete | Low | Medium |
| 1b | `design/stitch-export/quick_delivery_ui_brief/` (V1 brief, about 1.7 MiB) | delete (or archive-move with 1c) | Low | Medium |
| 1c | `kinetic_logistics-light/` and `nocturne_amber-dark/` (about 1.6 MiB) | delete | Low | Low |
| 1d | All of `design/` | move-to-other-repo (a design-assets repo), only if the owner wants a lean code repo | Medium | Medium |
| 2 | Root `index.html` ("Logic Vetting Interface") | delete | Low | Low |
| 2b | `infrastructure/docker-compose.yml` and the staging compose mount a `./Caddyfile`. Only the staging one exists | keep; fix in its own task | n/a | Medium (finding, not cleanup) |
| 3 | 15 historical docs | archive-move to `docs/history/` and update links mechanically | Low–Medium | Medium |
| 4 | `IMPLEMENTATION.md` | archive-move to `docs/history/` | Low | Low |
| 4b | `DESIGN.md` | keep in place (docgen code hard-codes the path) and trim its stale Section 1 | Medium if moved | Low |
| 4c | `QA-COVERAGE.md` | keep; optionally move under `docs/qa/` | Low | Low |
| 5 | `frontend/{macos,windows,linux,web}` | keep for now; remove after checking `quick-delivery-mobile` CI | Medium | Low |
| 6 | 4 stashes, 4 merged branches, `frontend-split`, 5 old worktrees registered at the pre-move path | delete merged branches; owner reviews stashes; keep `frontend-split` until owner confirms; repair or deliberately remove the 5 worktrees, never blind-prune | Low (merged) / Medium (stashes) | Low |
| 7 | Dead Go code (U1000) | not run (staticcheck is not installed) | n/a | n/a |

## 1. `design/stitch-export`

```bash
du -sh design;
git ls-files design | wc -l
```

Output (literal):

```text
13M	design
136
```

Per folder: size in KiB, tracked file count, the number of `*.md` files outside `docs/history/` that name the folder
with a path context, and the number of non-Markdown tracked files (code, tests, workflows) that mention `stitch-export`
or `design/` at all. For subfolders the path-context pattern is `<parent>/<name>`, `` `<name>/` `` or `/<name>/`.
Names shared between exports (`login`, `signup`, `customer_home`) inflate the subfolder counts, so treat them as an
upper bound.

```bash
printf 'folder\tKiB\tfiles\tmd-files-with-path-ref\tnon-md-refs\n';
md=$(git grep -l -F 'stitch-export' -- '*.md' ':!docs/history' ':!docs/CLEANUP_INVENTORY.md');
for d in design/stitch-export/*/ design/stitch-export/*/*/;
do
    d=${d%/};
    sub=$(basename "$d");
    par=$(basename "$(dirname "$d")");
    k=$(du -s --block-size=1K "$d" | cut -f1);
    f=$(git ls-files "$d" | wc -l);
    if [ "$par" = "stitch-export" ]; then
        pat="stitch-export/${sub}";
    else
        pat="(${par}/${sub}|\`${sub}/?\`|/${sub}/)";
    fi;
    m=$(grep -lE "$pat" $md 2> /dev/null | wc -l);
    c=$(git grep -l -E "stitch-export|design/" -- ':!*.md' ':!design' | wc -l);
    printf '%s\t%s\t%s\t%s\t%s\n' "${d#design/stitch-export/}" "$k" "$f" "$m" "$c";
done
```

Output (literal):

```text
folder	KiB	files	md-files-with-path-ref	non-md-refs
kinetic_logistics-light	900	9	0	0
logistics_core_unified	9984	81	4	0
nocturne_amber-dark	696	9	0	0
quick_delivery_ui_brief	1728	37	4	0
kinetic_logistics-light/notifications_alerts	224	2	0	0
kinetic_logistics-light/rate_your_experience	216	2	0	0
kinetic_logistics-light/rating_summary_overview	312	2	0	0
kinetic_logistics-light/subscription_plans	140	2	2	0
logistics_core_unified/business_configuration	156	2	2	0
logistics_core_unified/chat	96	2	4	0
logistics_core_unified/customer_home	168	2	3	0
logistics_core_unified/customer_job_map	532	2	2	0
logistics_core_unified/customer_job_map_final_fidelity	612	2	3	0
logistics_core_unified/customer_job_map_unified	536	2	1	0
logistics_core_unified/customer_rating	68	2	2	0
logistics_core_unified/employee_history	224	2	2	0
logistics_core_unified/employee_history_final_fidelity	220	2	3	0
logistics_core_unified/employee_home	92	2	2	0
logistics_core_unified/employee_jobs	384	2	3	0
logistics_core_unified/employee_jobs_final_fidelity	224	2	3	0
logistics_core_unified/employee_management	236	2	2	0
logistics_core_unified/fleet_tracking_map	736	2	2	0
logistics_core_unified/forgot_password	44	2	3	0
logistics_core_unified/job_status_1	212	2	1	0
logistics_core_unified/job_status_2	424	2	1	0
logistics_core_unified/job_status_final_fidelity	200	2	3	0
logistics_core_unified/job_status_unified	428	2	1	0
logistics_core_unified/job_tracking_map	1092	2	1	0
logistics_core_unified/kyc_verification	216	2	2	0
logistics_core_unified/login	44	2	3	0
logistics_core_unified/logistics_core	8	1	1	0
logistics_core_unified/marketplace	236	2	2	0
logistics_core_unified/my_account	148	2	2	0
logistics_core_unified/my_jobs	116	2	2	0
logistics_core_unified/notifications	120	2	4	0
logistics_core_unified/otp_verification	68	2	2	0
logistics_core_unified/owner_dashboard	232	2	3	0
logistics_core_unified/owner_history	220	2	2	0
logistics_core_unified/owner_reconciliation_queue_unified	184	2	2	0
logistics_core_unified/owner_service_management	228	2	2	0
logistics_core_unified/owner_service_management_final_fidelity	256	2	3	0
logistics_core_unified/reconciliation_queue_1	192	2	1	0
logistics_core_unified/reconciliation_queue_2	184	2	1	0
logistics_core_unified/reconciliation_queue_final_fidelity	188	2	3	0
logistics_core_unified/settings	68	2	2	0
logistics_core_unified/signup	68	2	4	0
logistics_core_unified/subscription_plans	188	2	2	0
logistics_core_unified/update_required	120	2	2	0
logistics_core_unified/wallet_transactions	216	2	2	0
nocturne_amber-dark/notifications_alerts	200	2	0	0
nocturne_amber-dark/rate_your_experience	184	2	0	0
nocturne_amber-dark/rating_summary_overview	152	2	0	0
nocturne_amber-dark/subscription_plans	152	2	2	0
quick_delivery_ui_brief/courier_profile	136	2	1	0
quick_delivery_ui_brief/customer_home	140	2	3	0
quick_delivery_ui_brief/employee_jobs	104	2	2	0
quick_delivery_ui_brief/fleet_history	112	2	1	0
quick_delivery_ui_brief/fleet_map	28	2	1	0
quick_delivery_ui_brief/forgot_password	76	2	3	0
quick_delivery_ui_brief/job_details	232	2	1	0
quick_delivery_ui_brief/kyc_kyb_upload	16	2	1	0
quick_delivery_ui_brief/login	48	2	3	0
quick_delivery_ui_brief/manage_employees	84	2	1	0
quick_delivery_ui_brief/orders_history	92	2	1	0
quick_delivery_ui_brief/owner_configuration	200	2	2	0
quick_delivery_ui_brief/owner_dashboard	96	2	3	0
quick_delivery_ui_brief/owner_subscription	108	2	1	0
quick_delivery_ui_brief/settings_owner	84	2	1	0
quick_delivery_ui_brief/signup	20	2	4	0
quick_delivery_ui_brief/velocity_logistics	8	1	1	0
quick_delivery_ui_brief/verify_otp	52	2	1	0
quick_delivery_ui_brief/wallet_owner	92	2	1	0
```

No code, test, workflow or script references any design folder (last column is 0 everywhere). Only Markdown
audit docs do.

What the docs say is authoritative:

```bash
grep -n -E '^\| - \|' docs/frontend/STITCH_VISUAL_AUDIT_V2.md | cut -d'|' -f3-5;
grep -n -E 'single authoritative visual ground truth|Authoritative Reference' docs/frontend/STITCH_VISUAL_AUDIT_V2.md | cut -c1-220;
grep -n 'stitch-export exclusion' docs/frontend/UI_VISUAL_AUDIT_2026-09.md | cut -c1-220;
grep -n 'SUPERSEDED DOCUMENT' -A1 docs/frontend/STITCH_VISUAL_AUDIT.md | cut -c1-220
```

Output (literal):

```text
 `job_status_1` | Iteration 1 | Superseded by final 
 `job_status_2` | Iteration 2 | Superseded by final 
 `job_status_unified` | Unified draft | Superseded by final 
 `customer_job_map` | Iteration 1 | Superseded by final 
 `customer_job_map_unified` | Unified draft | Superseded by final 
 `job_tracking_map` | Alias variant | Superseded by final 
 `owner_service_management` | Iteration 1 | Superseded by final 
 `reconciliation_queue_1` | Iteration 1 | Superseded by final 
 `reconciliation_queue_2` | Iteration 2 | Superseded by final 
 `owner_reconciliation_queue_unified` | Unified draft | Superseded by final 
 `employee_jobs` | Iteration 1 | Superseded by final 
 `employee_history` | Iteration 1 | Superseded by final 
6:> **Authoritative Reference**: `design/stitch-export/logistics_core_unified/` (`logistics_core/DESIGN.md` + 40 Screen Folders)  
19:2. **Authoritative Fidelity Resolution**: For screens with multiple iterations (e.g. `_1`, `_2`, `_unified`, `_final_fidelity`), the `_final_fidelity` folder serves as the single authoritative visual ground truth.
8:> **stitch-export exclusion**: `design/stitch-export/` (nocturne_amber-dark, kinetic_logistics-light, etc.) contains exploratory concepts, NOT the shipped identity — ignored throughout; nothing was borrowed from it.
4:> **SUPERSEDED DOCUMENT**: This V1 audit evaluated `quick_delivery_ui_brief` (18 screens, `velocity_logistics/DESIGN.md`), which was an incomplete prototype export.  
5-> It has been superseded by [`STITCH_VISUAL_AUDIT_V2.md`](STITCH_VISUAL_AUDIT_V2.md), audited against the authoritative `logistics_core_unified` export containing all 40 screen folders and `logistics_core/DESIGN.md`.
```

Reading this:
- **Authoritative set** (per `STITCH_VISUAL_AUDIT_V2.md`): `logistics_core_unified/` minus the 12 rows marked
  "Superseded by final" above. That leaves 28 screen folders: the `_final_fidelity` ones for screens with iterations,
  the "Standard" ones for the rest, plus `logistics_core/` (`DESIGN.md`).
- **Superseded variants** (12 folders, 4,620 KiB by the table above): `job_status_1`, `job_status_2`,
  `job_status_unified`, `customer_job_map`, `customer_job_map_unified`, `job_tracking_map`, `owner_service_management`,
  `reconciliation_queue_1`, `reconciliation_queue_2`, `owner_reconciliation_queue_unified`, `employee_jobs`,
  `employee_history`.
- **`quick_delivery_ui_brief/`** (1,728 KiB) is the V1 brief. `STITCH_VISUAL_AUDIT.md` calls it an "incomplete
  prototype export", superseded by V2.
- **`kinetic_logistics-light/`, `nocturne_amber-dark/`** (900 + 696 KiB): `UI_VISUAL_AUDIT_2026-09.md` calls them
  "exploratory concepts, NOT the shipped identity".

**Recommendation**
- 1a: delete the 12 superseded variant folders. Risk is low: no code refs, and V2 already names the replacement for each.
  `STITCH_VISUAL_AUDIT_V2.md` rows for them stay valid as history. Two docs with path-qualified links
  (`UI_UX_AUDIT.md`, `STITCH_VISUAL_AUDIT_V2.md`) would then link to removed folders. Acceptable for Historical docs,
  or add a one-line note.
- 1b: delete `quick_delivery_ui_brief/`, or keep it only if V1-audit reproducibility matters. Low risk.
- 1c: delete the two exploratory theme exports. Low risk.
- Together, 1a–1c cut the working tree from 13 MiB to about 5.2 MiB.
- 1d (optional): move the authoritative set to a separate design-assets repo and leave a pointer README. Medium risk:
  several Current docs link into `design/`.

**Git history:** none of this shrinks the clone. The blobs stay reachable from every existing commit:

```bash
git log --format='%as %h %s' -- design;
git count-objects -vH 2> /dev/null | grep -E 'size-pack|in-pack';
git rev-list --objects --all -- design | git cat-file --batch-check='%(objecttype) %(objectsize) %(rest)' | awk '$1=="blob"{s+=$2;n++} END{printf "design blobs reachable from all refs: %d blobs, %.1f MiB uncompressed\n", n, s/1048576}'
```

Output (literal):

```text
2026-08-17 b5c8a909 docs(frontend): add STITCH_VISUAL_AUDIT_V2 and logistics_core_unified reference export
2026-08-17 8874af4a docs(frontend): add Stitch visual design brief comparison audit
2026-07-18 8a692fc8 docs: add Stitch light/dark UI design reference exports
in-pack: 16997
size-pack: 35.67 MiB
design blobs reachable from all refs: 133 blobs, 12.3 MiB uncompressed
```

Design blobs are about 12.3 MiB of a 35.7 MiB pack. Only rewriting history removes them, for example
`git filter-repo --path design --invert-paths` on every branch followed by a force-push of `logic-exploitation` and
`main`. That breaks every clone and fork, and every cited full SHA in `docs/changelog/` and `AI_CONTEXT.md` (the
pre-push SHA check would then fail repo-wide). Recommendation: **do not rewrite history.** Accept the one-time cost.
If future design exports are expected, put them in a separate repo or Git LFS from the start.

## 2. Root `index.html` and web UIs

```bash
git log -1 --format='%as %h %s' -- index.html;
wc -c index.html;
grep -o '<title>[^<]*' index.html;
grep -n 'BASE_URL =' index.html;
ls -d web 2>&1
```

Output (literal):

```text
2026-07-13 a6eef07e fix(auth-service): enforce owner-authenticated employee signup
13400 index.html
<title>Logic Vetting Interface
245:        const BASE_URL = "http://localhost:8000";
ls: cannot access 'web': No such file or directory
```

```bash
git grep -n -I 'index\.html' -- ':!design' ':!docs/history' ':!docs/CLEANUP_INVENTORY.md' ':!docs/worklog' | cut -c1-170;
echo '-- tracked Caddyfiles:';
git ls-files | grep -i caddyfile;
echo '-- Caddyfile mounts in compose files:';
git grep -n 'Caddyfile' -- 'infrastructure/*.yml' 'infrastructure/**/*.yml';
echo '-- index.html / root static file served by any Caddyfile or compose (file_server|root|index.html):';
git grep -n -E 'file_server|root \*|index\.html' -- 'infrastructure' || echo '(no matches)';
echo '-- infrastructure/Caddyfile in history:';
git log --oneline --all -- infrastructure/Caddyfile | head -3;
echo '(end)'
```

Output (literal):

```text
AI_CONTEXT.md:972:  - `web/index.html`, `web/style.css`, `web/app.js`:
docs/adr/0001-owner-authenticated-employee-provisioning.md:28:- **Client Changes**: Updated `index.html` to automatically save the JWT token returned on login/verificatio
docs/adr/0022-account-suspension-and-reviewer-directory.md:80:- **Web UI (`web/index.html`, `web/app.js`, `web/style.css`)**:
docs/changelog/new-features.md:143:    - `web/index.html`, `web/app.js`, `web/style.css`: Added User Documents modal dialog with mandatory audit reason and refresh action
docs/changelog/new-features.md:195:    - `web/index.html`, `web/app.js`, `web/style.css`: Added "Subscriptions" and "Support Tickets" tabs, tables, toolbars, pagination c
docs/changelog/new-features.md:214:    - `web/index.html`, `web/app.js`, `web/style.css`: Added tabbed navigation for Pending Queue vs Accounts Directory, accounts search
-- tracked Caddyfiles:
infrastructure/staging/Caddyfile
-- Caddyfile mounts in compose files:
infrastructure/docker-compose.yml:288:      - ./Caddyfile:/etc/caddy/Caddyfile:ro
infrastructure/staging/docker-compose.staging.yml:300:      - ./Caddyfile:/etc/caddy/Caddyfile:ro
-- index.html / root static file served by any Caddyfile or compose (file_server|root|index.html):
(no matches)
-- infrastructure/Caddyfile in history:
(end)
```

Reading this:
- `index.html` was last changed on 2026-07-13 by the ADR-0001 commit. It is a standalone page calling
  `http://localhost:8000`. No service listens on 8000: the gateway default is 8080 per `infrastructure/.env.example`.
- The ADR-0001 mention is historical ("Updated `index.html`…"). The other `web/index.html` hits refer to the
  `kyc-reviewer-console` repo (its `web/` folder), not this repo. There is no `web/` here.
- No Caddyfile or compose file serves it.

**Recommendation:** delete root `index.html`. Risk is low. ADR-0001 keeps its sentence as history, with no link to fix
(it is plain text, not a link).

**Side finding, not cleanup:** `infrastructure/docker-compose.yml:288` mounts `./Caddyfile`, but no
`infrastructure/Caddyfile` is tracked, ignored or in history (output above). Unless the developer creates one by hand,
Docker would create an empty directory at that path and Caddy would fail to load its config (unverified: I did not
start the stack). Raise it as its own small task. Do not fold it into CLN-02.

## 3. Historical docs: proposed targets and link-update list

Classification comes from `docs/README.md`. The proposed target keeps the relative layout under `docs/history/`.

| Current path | Proposed target |
| :--- | :--- |
| `IMPLEMENTATION.md` | `docs/history/IMPLEMENTATION.md` |
| `docs/BUSINESS_LOGIC_AUDIT.md` | `docs/history/BUSINESS_LOGIC_AUDIT.md` |
| `docs/FRONTEND_CONSISTENCY_AUDIT.md` | `docs/history/FRONTEND_CONSISTENCY_AUDIT.md` |
| `docs/FRONTEND_INTEGRATION_SCOPE.md` | `docs/history/FRONTEND_INTEGRATION_SCOPE.md` |
| `docs/audit/shared-module-review.md` | `docs/history/audit/shared-module-review.md` |
| `docs/reports/P1_DARK_THEME_UNIFICATION_REPORT.md` | `docs/history/reports/P1_DARK_THEME_UNIFICATION_REPORT.md` |
| `docs/reports/P2_SCREEN_MIGRATION_REPORT.md` | `docs/history/reports/P2_SCREEN_MIGRATION_REPORT.md` |
| `docs/frontend/UI_UX_AUDIT.md` | `docs/history/frontend/UI_UX_AUDIT.md` |
| `docs/frontend/UI_UX_AUDIT_2026-09.md` | `docs/history/frontend/UI_UX_AUDIT_2026-09.md` |
| `docs/frontend/UI_VISUAL_AUDIT_2026-09.md` | `docs/history/frontend/UI_VISUAL_AUDIT_2026-09.md` |
| `docs/frontend/UI_UX_ENTERPRISE_ROADMAP.md` | `docs/history/frontend/UI_UX_ENTERPRISE_ROADMAP.md` |
| `docs/frontend/STITCH_VISUAL_AUDIT.md` | `docs/history/frontend/STITCH_VISUAL_AUDIT.md` |
| `docs/frontend/STITCH_VISUAL_AUDIT_V2.md` | `docs/history/frontend/STITCH_VISUAL_AUDIT_V2.md` |
| `docs/frontend/EMPLOYEE_CAPABILITY_AUDIT.md` | `docs/history/frontend/EMPLOYEE_CAPABILITY_AUDIT.md` |
| `docs/frontend/EMPLOYEE_FUNCTIONALITY_AUDIT.md` | `docs/history/frontend/EMPLOYEE_FUNCTIONALITY_AUDIT.md` |

Files that mention each doc by basename, with the match count per file (`docs/history/`, this file and the worklog
excluded). These are the files whose links need updating:

```bash
for p in IMPLEMENTATION.md docs/BUSINESS_LOGIC_AUDIT.md docs/FRONTEND_CONSISTENCY_AUDIT.md docs/FRONTEND_INTEGRATION_SCOPE.md docs/audit/shared-module-review.md docs/reports/P1_DARK_THEME_UNIFICATION_REPORT.md docs/reports/P2_SCREEN_MIGRATION_REPORT.md docs/frontend/UI_UX_AUDIT.md docs/frontend/UI_UX_AUDIT_2026-09.md docs/frontend/UI_VISUAL_AUDIT_2026-09.md docs/frontend/UI_UX_ENTERPRISE_ROADMAP.md docs/frontend/STITCH_VISUAL_AUDIT.md docs/frontend/STITCH_VISUAL_AUDIT_V2.md docs/frontend/EMPLOYEE_CAPABILITY_AUDIT.md docs/frontend/EMPLOYEE_FUNCTIONALITY_AUDIT.md;
do
    b=$(basename "$p");
    echo "### $p";
    git grep -c -F "$b" -- '*.md' ':!docs/history' ':!docs/CLEANUP_INVENTORY.md' ':!docs/worklog' ":!$p" | sed 's/^/    /';
    git grep -l -F "$b" -- ':!*.md' ':!design' | sed 's/^/    NON-MD: /';
done
```

Output (literal):

```text
### IMPLEMENTATION.md
    README.md:1
    docs/README.md:2
    docs/changelog/documentation.md:2
    docs/frontend/STATUS.md:2
### docs/BUSINESS_LOGIC_AUDIT.md
    AI_CONTEXT.md:1
    README.md:1
    docs/README.md:1
    docs/adr/0017-zero-commission-subscription-only-revenue-model.md:2
    docs/changelog/bug-fixes.md:1
    docs/changelog/documentation.md:5
### docs/FRONTEND_CONSISTENCY_AUDIT.md
    docs/README.md:1
    docs/changelog/documentation.md:1
    docs/frontend/STATUS.md:1
    docs/frontend/UI_UX_BEHAVIOR_AUDIT.md:1
### docs/FRONTEND_INTEGRATION_SCOPE.md
    docs/README.md:1
    docs/changelog/documentation.md:2
    docs/changelog/new-features.md:1
### docs/audit/shared-module-review.md
    AI_CONTEXT.md:1
    docs/README.md:1
    docs/changelog/documentation.md:2
    docs/changelog/security-fixes.md:1
### docs/reports/P1_DARK_THEME_UNIFICATION_REPORT.md
    docs/README.md:1
### docs/reports/P2_SCREEN_MIGRATION_REPORT.md
    AI_CONTEXT.md:1
    docs/README.md:1
### docs/frontend/UI_UX_AUDIT.md
    AI_CONTEXT.md:1
    docs/README.md:1
    docs/frontend/STATUS.md:3
    docs/frontend/UI_UX_AUDIT_2026-09.md:1
    NON-MD: frontend/test/a8_uiux_remediation_test.dart
### docs/frontend/UI_UX_AUDIT_2026-09.md
    AI_CONTEXT.md:1
    docs/README.md:2
    docs/changelog/bug-fixes.md:25
    docs/changelog/documentation.md:4
    docs/frontend/STATUS.md:1
    docs/frontend/UI_VISUAL_AUDIT_2026-09.md:1
    docs/frontend/UX_PATTERNS.md:1
    NON-MD: frontend/test/auth_inline_error_banner_test.dart
    NON-MD: frontend/test/customer_failure_states_test.dart
### docs/frontend/UI_VISUAL_AUDIT_2026-09.md
    AI_CONTEXT.md:1
    docs/README.md:1
    docs/changelog/bug-fixes.md:2
    docs/changelog/documentation.md:1
    docs/frontend/EMPLOYEE_FUNCTIONAL_FINDINGS_2026-09.md:1
### docs/frontend/UI_UX_ENTERPRISE_ROADMAP.md
    AI_CONTEXT.md:3
    README.md:1
    docs/README.md:1
    docs/changelog/documentation.md:6
    docs/frontend/STATUS.md:1
    docs/frontend/UI_UX_AUDIT_2026-09.md:1
### docs/frontend/STITCH_VISUAL_AUDIT.md
    AI_CONTEXT.md:1
    docs/README.md:1
    docs/frontend/STATUS.md:1
    docs/frontend/STITCH_VISUAL_AUDIT_V2.md:1
### docs/frontend/STITCH_VISUAL_AUDIT_V2.md
    docs/README.md:2
    docs/changelog/documentation.md:1
    docs/frontend/STATUS.md:1
    docs/frontend/STITCH_VISUAL_AUDIT.md:2
    docs/frontend/UI_UX_AUDIT.md:1
    docs/frontend/UI_UX_BEHAVIOR_AUDIT.md:1
### docs/frontend/EMPLOYEE_CAPABILITY_AUDIT.md
    docs/README.md:1
    docs/changelog/new-features.md:1
    docs/frontend/STATUS.md:1
### docs/frontend/EMPLOYEE_FUNCTIONALITY_AUDIT.md
    AI_CONTEXT.md:2
    docs/README.md:2
    docs/frontend/STATUS.md:1
    docs/frontend/UI_UX_BEHAVIOR_AUDIT.md:1
```

Notes for doing the move mechanically:
- After any move, relative links inside the moved file change depth (for example `../../frontend/lib/...` in
  `STITCH_VISUAL_AUDIT_V2.md` and `UI_UX_AUDIT.md`). Re-check them with a link checker, or with
  `grep -o '](\.\./[^)]*)'`.
- `docs/changelog/*.md` is append-only history. Updating link targets there changes no SHA, but confirm the
  changelog policy allows link-only edits. Otherwise leave changelog mentions as plain historical text.
- NON-MD hits are comments in Flutter tests (`frontend/test/*.dart`) that cite audit finding IDs by doc name. Update
  the path in the comment or leave it. Nothing parses them.
- `AI_CONTEXT.md` mentions disappear when it is replaced by the slim file, which links only `docs/README.md`.
- `UI_UX_AUDIT_2026-09.md` has open §5 questions Q1–Q11. If the owner treats them as live, keep that file in place
  (class Current) and move only the others.

## 4. Root docs: overlap

```bash
sed -n '3,6p' IMPLEMENTATION.md | cut -c1-220;
sed -n '3,6p' DESIGN.md | cut -c1-220;
grep -n -E 'DESIGN\.md|DESIGN_SYSTEM\.md' shared/infra/docgen/*.go | grep -v '^\s*//' | cut -c1-170;
grep -n '^## ' QA-COVERAGE.md DESIGN.md docs/frontend/DESIGN_SYSTEM.md docs/RELEASE-GATE.md | cut -c1-110;
wc -lc QA-COVERAGE.md
```

Output (literal):

```text
This document details the historical step-by-step implementation plan for the Flutter frontend client (Phases 1–7).

> [!NOTE]
> **Canonical Implementation Status**:
This document outlines the architectural and user interface design for the Flutter frontend client of the Quick Delivery marketplace services platform. The frontend coordinates with the Go microservices backend exposed v

> [!NOTE]
> **Planned vs. Current Architecture**: The directory structure and provider file tree detailed in Section 1 (such as `screens/shared/`, `screens/owner/`, `screens/employee/`, `screens/user/`, and `chat_provider.dart` / 
shared/infra/docgen/counts.go:185:	// 3. Check DESIGN.md widget count
shared/infra/docgen/counts.go:186:	designPath := filepath.Clean(filepath.Join(repoRoot, "DESIGN.md"))
shared/infra/docgen/counts.go:194:				errs = append(errs, fmt.Errorf("DESIGN.md claims %d reusable widgets, but frontend/lib/widgets/ has %d files", wCount, counts.Widget
shared/infra/docgen/counts.go:199:	// 4. Check docs/frontend/DESIGN_SYSTEM.md widget count
shared/infra/docgen/counts.go:200:	designSystemPath := filepath.Clean(filepath.Join(repoRoot, "docs", "frontend", "DESIGN_SYSTEM.md"))
shared/infra/docgen/counts.go:208:				errs = append(errs, fmt.Errorf("docs/frontend/DESIGN_SYSTEM.md claims %d shared widgets, but frontend/lib/widgets/ has %d files", wC
shared/infra/docgen/structural_drift_test.go:57:	designPath := filepath.Join(repoRoot, "DESIGN.md")
shared/infra/docgen/structural_drift_test.go:101:	// Regex to find `pkg` (`version`) in DESIGN.md
shared/infra/docgen/structural_drift_test.go:107:		t.Log("No dependency version strings found in DESIGN.md to validate")
shared/infra/docgen/structural_drift_test.go:118:				t.Errorf("Dependency version mismatch for %q: DESIGN.md quotes %q but frontend/pubspec.yaml specifies %q. Please alig
QA-COVERAGE.md:3:## 1. Executive Summary & Phase Ordering Notice
QA-COVERAGE.md:17:## 2. Comprehensive Master Coverage Gap Matrix
QA-COVERAGE.md:61:## 3. Section A: Pre-Existing Coverage (Baseline, Audited Retroactively)
QA-COVERAGE.md:313:## 4. Section B: New Coverage Added by QA Strategy Initiative (Net-New)
QA-COVERAGE.md:652:## 5. QA Backlog & Future Roadmap
QA-COVERAGE.md:688:## 6. Living Reference Links
DESIGN.md:11:## 1. Core Architecture
DESIGN.md:52:## 2. Visual Design & Theme System
DESIGN.md:66:## 3. Screen Flows by Role
DESIGN.md:100:## 4. API Integration Details
DESIGN.md:130:## 5. Security & Rate Limiting
DESIGN.md:149:## 6. Customer Service Outbound Chat Routing
docs/frontend/DESIGN_SYSTEM.md:8:## 1. Overview & Usage Guidelines
docs/frontend/DESIGN_SYSTEM.md:19:## 2. Complete Design Token Reference
docs/frontend/DESIGN_SYSTEM.md:138:## 3. Shared Component Library Reference
docs/frontend/DESIGN_SYSTEM.md:187:## 4. Screen Composition Patterns
docs/frontend/DESIGN_SYSTEM.md:242:## 5. Tracked Design Debt Backlog
docs/frontend/DESIGN_SYSTEM.md:307:## 6. RTL & Localization Design Rules
docs/RELEASE-GATE.md:3:## 1. Purpose & Scope
docs/RELEASE-GATE.md:13:## 2. CI/CD Release Pipeline Topology
docs/RELEASE-GATE.md:56:## 3. Concrete Quality Gate Criteria
docs/RELEASE-GATE.md:74:## 4. Release Decision Matrix
docs/RELEASE-GATE.md:106:## 5. Emergency Hotfix Bypass Policy
  698 82106 QA-COVERAGE.md
```

- **`DESIGN.md` vs `docs/frontend/DESIGN_SYSTEM.md`**: little overlap. `DESIGN.md` is app architecture, flows, API
  and security notes for the frontend. `DESIGN_SYSTEM.md` is tokens, components and patterns. `DESIGN.md` admits its
  Section 1 tree is the planned layout, not the current one. `shared/infra/docgen` hard-codes `DESIGN.md` at the repo
  root, for its dependency-pin drift test and widget-count check. **Recommendation:** keep it in place (moving it
  needs a docgen change). Replace Section 1 with a pointer to `docs/frontend/ARCHITECTURE.md`. Low risk; a separate
  doc task.
- **`IMPLEMENTATION.md`**: describes itself as the historical Phase 1–7 plan and points to `STATUS.md` as canonical.
  **Recommendation:** archive-move with section 3. Three inbound mentions. Low risk.
- **`QA-COVERAGE.md` (82 KB, 698 lines)**: a living coverage matrix plus QA backlog. It overlaps `docs/RELEASE-GATE.md`
  only on gate criteria. One inbound mention. **Recommendation:** keep. Optionally move to `docs/qa/QA-COVERAGE.md`
  so the root holds only README, CLAUDE, AI_CONTEXT and DESIGN. Low risk, low value. Its §3/§4 per-test narratives
  could later be archived the way AI_CONTEXT was.

## 5. Frontend platform folders

```bash
for d in android ios macos windows linux web;
do
    printf '%s tracked-files=%s size=%s\n' "$d" "$(git ls-files frontend/$d | wc -l)" "$(du -sh frontend/$d | cut -f1)";
done;
echo '-- flutter build/test/analyze steps in workflows:';
grep -n -E 'flutter (build|test|analyze|create)' .github/workflows/*.yml;
echo '-- references to desktop/web builds (workflows, scripts, Makefile, docs):';
git grep -n -I -E 'flutter build (macos|windows|linux|web)|frontend/(macos|windows|linux|web)/|-d (chrome|linux|macos|windows)\b' -- .github scripts Makefile '*.md' ':!docs/history' ':!docs/CLEANUP_INVENTORY.md' ':!docs/worklog' || echo '(no matches)';
echo '-- mobile sync workflow:';
grep -n -E 'subtree split|repositories:' .github/workflows/sync-mobile-frontend.yml
```

Output (literal):

```text
android tracked-files=19 size=92K
ios tracked-files=40 size=252K
macos tracked-files=28 size=308K
windows tracked-files=18 size=116K
linux tracked-files=10 size=48K
web tracked-files=7 size=64K
-- flutter build/test/analyze steps in workflows:
.github/workflows/ci.yml:205:        run: flutter analyze
.github/workflows/ci.yml:209:        run: flutter test
.github/workflows/regen-goldens.yml:39:        run: flutter test --update-goldens test/golden_screens_test.dart
-- references to desktop/web builds (workflows, scripts, Makefile, docs):
(no matches)
-- mobile sync workflow:
37:          SPLIT_SHA=$(git subtree split --prefix=frontend)
39:            echo "Error: git subtree split produced an empty commit SHA."
52:          repositories: quick-delivery-mobile
```

No workflow, script, Makefile target or doc builds macOS, Windows, Linux or web. CI here runs `flutter analyze`
and `flutter test` only. The whole `frontend/` tree is subtree-split to `quick-delivery-mobile`, where the release
APK is built. I did not inspect that repo's workflows (unverified), so it could still build web or desktop.
**Recommendation:** keep for now. Removing them saves about 0.5 MiB and four folders of noise but is not free: it
changes what `quick-delivery-mobile` receives on the next sync. Delete `macos/`, `windows/`, `linux/` (and `web/`
if no web target is planned) once `quick-delivery-mobile` CI is confirmed not to use them. Risk is medium until
that check is done.

## 6. Stashes and stale local branches (report only, nothing deleted)

```bash
git stash list;
for s in 0 1 2 3;
do
    echo "stash@{$s}: $(git stash show --stat "stash@{$s}" 2> /dev/null | tail -1) | base commit date $(git log -1 --format=%as "stash@{$s}^" 2> /dev/null)";
done
```

Output (literal):

```text
stash@{0}: On logic-exploitation: superseded duplicate Q23 guard edits (landed properly via q5-24-fixes a032760) - do not apply
stash@{1}: On q5-24-fixes: mid-flight unverified Q24 revert (G704 claim unsubstantiated)
stash@{2}: WIP on logic-exploitation: 53ccd06 feat(ui): implement Stitch Unified UI Batch E employee experience screens and final verification
stash@{3}: WIP on main: 205466e baseline: operational microservices architecture
stash@{0}:  3 files changed, 12 insertions(+), 6 deletions(-) | base commit date 2026-08-22
stash@{1}:  2 files changed, 6 insertions(+), 50 deletions(-) | base commit date 2026-08-22
stash@{2}:  9 files changed, 1010 insertions(+), 584 deletions(-) | base commit date 2026-08-17
stash@{3}:  8 files changed, 261 insertions(+), 45 deletions(-) | base commit date 2026-06-22
```

```bash
for b in a8-uiux-remediation visual-fixes qa-audit-dispatch-order frontend-visual-fixes frontend-split;
do
    echo "$ git rev-list --left-right --count logic-exploitation...$b";
    git rev-list --left-right --count "logic-exploitation...$b";
    echo "  last commit: $(git log -1 --format='%as %h' "$b"); ancestor of logic-exploitation: $(git merge-base --is-ancestor "$b" logic-exploitation && echo yes || echo no)";
done;
echo '-- frontend-split shared history check:';
git merge-base logic-exploitation frontend-split;
echo "merge-base exit=$?";
echo "root commit of frontend-split: $(git rev-list --max-parents=0 frontend-split | cut -c1-10)";
echo "root commit of logic-exploitation: $(git rev-list --max-parents=0 logic-exploitation | cut -c1-10)";
echo '-- worktrees:';
git worktree list | sed 's#/home/omarmaarouf#~#'
```

Output (literal):

```text
$ git rev-list --left-right --count logic-exploitation...a8-uiux-remediation
345	0
  last commit: 2026-08-23 8eca05a4; ancestor of logic-exploitation: yes
$ git rev-list --left-right --count logic-exploitation...visual-fixes
336	0
  last commit: 2026-08-24 cc18afe7; ancestor of logic-exploitation: yes
$ git rev-list --left-right --count logic-exploitation...qa-audit-dispatch-order
225	0
  last commit: 2026-09-05 f4f60e6b; ancestor of logic-exploitation: yes
$ git rev-list --left-right --count logic-exploitation...frontend-visual-fixes
345	0
  last commit: 2026-08-23 8eca05a4; ancestor of logic-exploitation: yes
$ git rev-list --left-right --count logic-exploitation...frontend-split
1391	60
  last commit: 2026-07-31 3e3973b5; ancestor of logic-exploitation: no
-- frontend-split shared history check:
merge-base exit=1
root commit of frontend-split: 82d752bc2a
root commit of logic-exploitation: 205466ec7c
-- worktrees:
~/CS tools/Antigravity/SaaS prototype                  1e7692ab [logic-exploitation]
~/CS tools/Antigravity/saas-core-wt/CLN-01             5f10080e [agent/CLN-01-repo-diet]
/mnt/windows_data/CS tools/Antigravity/saas-core-final-cleanup         47981460 (detached HEAD) prunable
/mnt/windows_data/CS tools/Antigravity/saas-core-frontend-a8           8eca05a4 [a8-uiux-remediation] prunable
/mnt/windows_data/CS tools/Antigravity/saas-core-frontend-visual-fixes cc18afe7 [visual-fixes] prunable
/mnt/windows_data/CS tools/Antigravity/saas-core-qa-audit-dispatch     f4f60e6b [qa-audit-dispatch-order] prunable
/mnt/windows_data/CS tools/Antigravity/saas-core-ux-review             69df526c (detached HEAD) prunable
```

| Item | Finding | Recommendation |
| :--- | :--- | :--- |
| `a8-uiux-remediation` | 0 commits not in `logic-exploitation`; ancestor. Checked out in worktree `saas-core-frontend-a8` (registered at the old path, see below) | delete the branch after that worktree is repaired-and-removed or deleted-and-pruned (git refuses to delete a branch checked out in a registered worktree) |
| `frontend-visual-fixes` | same tip as `a8-uiux-remediation`; 0 unique commits; not checked out anywhere | delete |
| `visual-fixes` | 0 unique commits; ancestor. Checked out in worktree `saas-core-frontend-visual-fixes` | delete the branch after its worktree is handled (see below) |
| `qa-audit-dispatch-order` | 0 unique commits; ancestor. Checked out in worktree `saas-core-qa-audit-dispatch` | delete the branch after its worktree is handled (see below) |
| `frontend-split` | 60 commits, **no common history** with `logic-exploitation` (different root). It looks like an old frontend-only subtree split (last commit 2026-07-31, "add standalone quick-delivery-mobile frontend repo") | keep until the owner confirms `quick-delivery-mobile` has these commits, then delete |
| `stash@{0}` | its own message says "superseded … do not apply" | drop (owner) |
| `stash@{1}` | "mid-flight unverified Q24 revert"; Q24 was fixed later on `logic-exploitation` | drop after a glance (owner) |
| `stash@{2}` | WIP on the Stitch Batch E commit `53ccd06`, 9 files, +1010/−584; that batch has landed | owner reviews, then drop |
| `stash@{3}` | WIP on the initial `main` baseline `205466e` (2026-06-22) | drop (owner) |
| 5 old worktrees registered at `/mnt/windows_data/...` | `git worktree list` says "prunable", but the folders still exist: the repo moved to `/home/omarmaarouf/CS tools/Antigravity/` and they moved with it. Git only sees the stale registered path | see "Old worktrees" below. Do **not** run `git worktree prune` blindly |

Risk: deleting merged branches is low risk (the commits are in `logic-exploitation`). Dropping stashes cannot be undone
easily, so leave that to the owner.

### Old worktrees (moved, not gone)

The repo was moved from `/mnt/windows_data/CS tools/Antigravity/` to `/home/omarmaarouf/CS tools/Antigravity/`, and
the five worktree folders moved with it. Their `.git` files still point at the old repo path, so plain
`git -C "<new path>"` fails. The script below reads HEAD from the registered gitdir inside the main repo and runs
`status` by passing `--git-dir`/`--work-tree` explicitly with `GIT_OPTIONAL_LOCKS=0` (read-only, no repair).
Detached HEADs are truncated to 10 characters inside the script.

```bash
M="/home/omarmaarouf/CS tools/Antigravity/SaaS prototype/.git"
for n in saas-core-final-cleanup saas-core-frontend-a8 saas-core-frontend-visual-fixes saas-core-qa-audit-dispatch saas-core-ux-review; do
  p="/home/omarmaarouf/CS tools/Antigravity/$n"
  echo "== $n"
  ls -d "$p" 2>&1
  h=$(cat "$M/worktrees/$n/HEAD"); case "$h" in ref:*) ;; *) h="${h:0:10}... (detached; truncated)";; esac; echo "registered gitdir HEAD: $h"
  echo "plain git -C status: $(git -C "$p" status --short 2>&1 | head -1)"
  echo "status --short line count (via registered gitdir, GIT_OPTIONAL_LOCKS=0): $(GIT_OPTIONAL_LOCKS=0 git --git-dir="$M/worktrees/$n" --work-tree="$p" status --short | wc -l)"
  GIT_OPTIONAL_LOCKS=0 git --git-dir="$M/worktrees/$n" --work-tree="$p" status --short | sed 's/^/    /'
done
for s in 47981460 69df526c; do echo "$s ancestor of logic-exploitation: $(git merge-base --is-ancestor $s logic-exploitation && echo yes || echo no)"; done
```

Output (literal):

```text
== saas-core-final-cleanup
/home/omarmaarouf/CS tools/Antigravity/saas-core-final-cleanup
registered gitdir HEAD: 4798146030... (detached; truncated)
plain git -C status: fatal: gitfile does not point to a valid repository: /home/omarmaarouf/CS tools/Antigravity/saas-core-final-cleanup/.git
status --short line count (via registered gitdir, GIT_OPTIONAL_LOCKS=0): 0
== saas-core-frontend-a8
/home/omarmaarouf/CS tools/Antigravity/saas-core-frontend-a8
registered gitdir HEAD: ref: refs/heads/a8-uiux-remediation
plain git -C status: fatal: gitfile does not point to a valid repository: /home/omarmaarouf/CS tools/Antigravity/saas-core-frontend-a8/.git
status --short line count (via registered gitdir, GIT_OPTIONAL_LOCKS=0): 0
== saas-core-frontend-visual-fixes
/home/omarmaarouf/CS tools/Antigravity/saas-core-frontend-visual-fixes
registered gitdir HEAD: ref: refs/heads/visual-fixes
plain git -C status: fatal: gitfile does not point to a valid repository: /home/omarmaarouf/CS tools/Antigravity/saas-core-frontend-visual-fixes/.git
status --short line count (via registered gitdir, GIT_OPTIONAL_LOCKS=0): 2
    ?? frontend/test/goldens_scratch/
    ?? frontend/test/scratch_evidence_test.dart
== saas-core-qa-audit-dispatch
/home/omarmaarouf/CS tools/Antigravity/saas-core-qa-audit-dispatch
registered gitdir HEAD: ref: refs/heads/qa-audit-dispatch-order
plain git -C status: fatal: gitfile does not point to a valid repository: /home/omarmaarouf/CS tools/Antigravity/saas-core-qa-audit-dispatch/.git
status --short line count (via registered gitdir, GIT_OPTIONAL_LOCKS=0): 2
    ?? services/notification-service/internal/handlers/qa_audit_notification_leak_test.go
    ?? services/user-service/internal/handlers/qa_audit_dispatch_flow_test.go
== saas-core-ux-review
/home/omarmaarouf/CS tools/Antigravity/saas-core-ux-review
registered gitdir HEAD: 69df526c54... (detached; truncated)
plain git -C status: fatal: gitfile does not point to a valid repository: /home/omarmaarouf/CS tools/Antigravity/saas-core-ux-review/.git
status --short line count (via registered gitdir, GIT_OPTIONAL_LOCKS=0): 4
     M frontend/pubspec.yaml
    ?? _ux_review_screenshots/
    ?? frontend/assets/fonts/NotoSansArabic-Regular.ttf
    ?? frontend/test/ux_review_dump_test.dart
47981460 ancestor of logic-exploitation: yes
69df526c ancestor of logic-exploitation: yes
```

| Worktree (new path) | Folder exists | HEAD | `status --short` lines | Notes |
| :--- | :--- | :--- | ---: | :--- |
| `saas-core-final-cleanup` | yes | detached `4798146030...` (in `logic-exploitation`) | 0 | clean |
| `saas-core-frontend-a8` | yes | `a8-uiux-remediation` | 0 | clean |
| `saas-core-frontend-visual-fixes` | yes | `visual-fixes` | 2 | untracked scratch goldens and a scratch test |
| `saas-core-qa-audit-dispatch` | yes | `qa-audit-dispatch-order` | 2 | two untracked QA audit test files |
| `saas-core-ux-review` | yes | detached `69df526c54...` (in `logic-exploitation`) | 4 | modified `frontend/pubspec.yaml`, untracked screenshots, font and test |

Options for each one (owner's choice, after looking at the uncommitted files above):

1. **Re-link and keep:** `git worktree repair "/home/omarmaarouf/CS tools/Antigravity/<name>"` from the main repo,
   for the paths you want to keep. It rewrites both the `.git` file and the registry. Then remove a worktree normally
   with `git worktree remove` once it is no longer needed.
2. **Discard:** inspect and save anything of value (for example the untracked QA test files in
   `saas-core-qa-audit-dispatch`), delete the folder, then run `git worktree prune`.

> [!WARNING]
> Never run `git worktree prune` from an environment that cannot see the real folders (a container, a sandbox, or a
> machine where `/home/omarmaarouf/CS tools/Antigravity/` is not mounted). Prune unregisters every worktree whose
> registered path is missing *from where it runs*, which would also unregister live worktrees such as
> `saas-core-wt/*`. Run it only after option 2 deletes the folders, on the machine that holds them.

The fully merged branches (`a8-uiux-remediation`, `frontend-visual-fixes`, `visual-fixes`, `qa-audit-dispatch-order`)
can still be deleted. Three of them can go only after their worktree is handled.

## 7. Dead Go code (U1000)

```bash
command -v staticcheck || echo "staticcheck: not found on PATH";
ls ~/go/bin | grep -x staticcheck || echo "staticcheck: not in ~/go/bin";
go version
```

Output (literal):

```text
staticcheck: not found on PATH
staticcheck: not in ~/go/bin
go version go1.26.9-X:nodwarf5 linux/amd64
```

staticcheck is not installed and installing it needs network access, which this task did not use. `go vet` has no
unused-identifier check, so it cannot stand in. **Skipped.** To run it later:
`go install honnef.co/go/tools/cmd/staticcheck@latest`, then
`staticcheck -checks U1000 ./...` in each of `services/*`, `shared/infra`, `tools/*`, `tests/*`.
