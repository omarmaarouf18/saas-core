# ADR-0012: Single Source of Truth for Production `.env` (Self-Hosted Runner Workspace vs. Persistent Backup)

- **Status**: Accepted
- **Date**: 2026-08-01
- **Related Commit SHA**: `15f6f2896a62e1b5b5a8578e8af973c3effe8139`
- **Related audit finding**: Production OTP Dispatcher Silent Reversion & MongoDB SCRAM Authentication Mismatch Incident

## Context

During production operations on `quickdelivery-vm`, two silent operational failure modes were observed:

1. **OTP Dispatcher Reversion**: The `auth-service` OTP delivery mechanism silently flipped from `Resend` (`Resend API active`) back to `MockSMS` (mock logger) whenever the self-hosted CD pipeline auto-triggered on pushes to `main`.
2. **MongoDB SCRAM Authentication Mismatch**: Container redeployments periodically failed with `AuthenticationFailed: SCRAM authentication failed, storedKey mismatch` on `saas-mongo`.

Investigation revealed the root cause: **two independent, out-of-sync `.env` files on the production host**:

1. **Operator Manual Directory**: An operator SSH'd into the VM as `azureuser` and manually edited `~/azureuser/saas-core-deploy/.env` (or `/opt/saas-platform/.env`), adding `RESEND_API_KEY`, `RESEND_FROM_EMAIL`, and correcting `ALLOWED_ORIGIN`. The operator manually executed `docker compose up -d --force-recreate auth-service`, temporarily enabling Resend.
2. **CD Runner Workspace**: The self-hosted GitHub Actions runner (`saas-vm-runner`) executes under system user `deploybot` at `/home/deploybot/actions-runner/_work/saas-core-deploy/saas-core-deploy/`. Its workflow (`.github/workflows/deploy.yml`) restores its working `.env` from `/home/deploybot/.env` (a cross-run persistent backup).

Because `/home/deploybot/.env` lacked `RESEND_API_KEY` and `RESEND_FROM_EMAIL`, every automated CD run (triggered by any push to `main`) restored `/home/deploybot/.env` into the runner workspace and executed `docker compose up -d --force-recreate`. This silently re-created `saas-auth-service` without the Resend credentials, overriding the operator's manual host changes without emitting an error or warning.

Additionally, the two `.env` files contained differing `MONGO_INITDB_ROOT_PASSWORD` values, causing database authentication failures when containers were recreated under the wrong `.env` context against the persistent `mongo_data` volume.

## Decision

We establish `/home/deploybot/.env` as the **sole canonical source of truth** for production environment variables on `quickdelivery-vm`:

1. **Single Source of Truth**: All manual production environment updates (adding API keys, updating secrets, or changing domains) MUST be performed directly in `/home/deploybot/.env`.
2. **CD Runner Persistence**: The CD pipeline (`deploy.yml`) will continue to persist and restore from `/home/deploybot/.env`. Manual edits to secondary directories (`~/azureuser/saas-core-deploy/.env` or `/opt/saas-platform/.env`) are strictly prohibited as they will be overwritten on the next automated deployment.
3. **Workspace Cleanup**: Stale `.env` files in runner workspace directories must be deleted when updating `/home/deploybot/.env` so that the CD pipeline immediately reads the updated persistent backup.

## Consequences

### Positive
- **Deterministic Deployments**: Eliminates silent environment drift between manual SSH operator commands and automated CD runs.
- **Persistent Secrets**: Critical environment variables (`RESEND_API_KEY`, `RESEND_FROM_EMAIL`, `ALLOWED_ORIGIN`, `MONGO_INITDB_ROOT_PASSWORD`) remain stable across automated pipeline executions.
- **Consistent Database Auth**: Eliminates `SCRAM authentication failed` errors caused by conflicting root password definitions.

### Negative / Flagged Follow-Up Recommendation
- **Manual `.env` Edits Remain Unchecked**: If a required key is omitted from `/home/deploybot/.env`, services will still fall back to mock implementations silently.
- **Recommended Follow-Up Safeguard**: We recommend adding a `Verify Critical Secrets Present` step to `.github/workflows/deploy.yml` in `saas-core-deploy` that checks for required keys (e.g. `RESEND_API_KEY`) and fails loudly (`::error::RESEND_API_KEY is missing from /home/deploybot/.env — halting deployment`) instead of permitting silent fallback.

## Alternatives Considered

- **Syncing `.env` from GitHub Secrets**: Rejected because the single-VM deployment architecture deliberately avoids storing long-lived production infrastructure secrets inside GitHub repository settings (per ADR-0010).
- **Symlinking Runner `.env` to `/opt/saas-platform/.env`**: Rejected because `deploybot` user permissions and runner workspace isolation make cross-user symlinks fragile during runner workspace cleanups.
