# Quick Delivery

## Developer Setup (Required After Cloning)

After cloning this repository, run the following command once to activate the
pre-push git hook that enforces formatting, changelog SHA validity, and
build/vet/test checks before every push:

```bash
make setup
```

This sets `core.hooksPath` to `.githooks/` in your local git config. The hook
lives at `.githooks/pre-push` and is tracked in the repo so it stays up to date
with pulls. You can also run the same checks manually at any time via `make ci`.

For instructions on connecting Flutter apps running on physical devices, Android emulators, or iOS simulators to the local Docker Compose backend, consult [frontend/CONNECTING_TO_BACKEND.md](frontend/CONNECTING_TO_BACKEND.md).

## Manual KYC Approval Process (Ops Runbook)

To maintain security and avoid exposing administrative endpoints that could be targeted by attackers, Know Your Customer (KYC) approval for tenant owners is deliberately **not** automated or exposed via in-app API endpoints.

### Method 1: Using the Ops CLI Tool (Recommended)
We provide a safe, validated CLI tool to manage owner KYC documents. The tool looks up the user by email, verifies that their role is owner, checks that their current KYC status is exactly `pending_super_admin_approval`, and prompts for confirmation before applying changes.

```bash
# To approve an owner's KYC status:
MONGO_URI=mongodb://localhost:27017 go run ./services/auth-service/cmd/approve-kyc --email=owner@example.com --action=approve

# To reject an owner's KYC status:
MONGO_URI=mongodb://localhost:27017 go run ./services/auth-service/cmd/approve-kyc --email=owner@example.com --action=reject --reason="Documents are blurry"

# Scripted/Non-interactive bypass (using --yes flag):
MONGO_URI=mongodb://localhost:27017 go run ./services/auth-service/cmd/approve-kyc --email=owner@example.com --action=approve --yes
```

### Method 2: Manual Database Updates (Fallback)
If the CLI tool is unavailable, approvals can be handled manually by an operations engineer directly in the database.

* **Database**: `saas_platform`
* **Collection**: `users`
* **KYC Status Field**: `kyc_status`
* **Approved Value**: `"approved"`
* **Pending Value**: `"pending_super_admin_approval"`

#### Step-by-Step Approval Instructions
1. **Access the MongoDB database instance** (e.g., via `mongosh` or your database admin tool).
2. **Switch to the platform database**:
   ```javascript
   use saas_platform;
   ```
3. **Locate the owner account** by their registration email (or ID) to verify they exist and their current status is `pending_super_admin_approval`:
   ```javascript
   db.users.find({ email: "owner@example.com" });
   ```
4. **Approve the owner** by updating the `kyc_status` field to `"approved"`:
   ```javascript
   db.users.updateOne(
     { email: "owner@example.com" },
     { $set: { kyc_status: "approved" } }
   );
   ```
5. **Verify the update** succeeded:
   ```javascript
   db.users.find({ email: "owner@example.com" });
   // Expected output includes: "kyc_status": "approved"
   ```

*Note: Once approved, the owner will be unblocked from creating services, posting/tracking jobs, and other restricted platform actions.*

---

## Manual Tenant Subscription Activation Process (Ops Runbook)

To prevent unverified upgrades and unauthorized access to premium features, transitioning a tenant's subscription to the `"paid"` tier is deliberately **not** automated or self-service via the API. Instead, upgrades must be requested via the app (which flags the subscription as `"pending_payment"`) and then manually activated by an operations engineer once out-of-band payment is confirmed.

### MongoDB Configuration Details
* **Database**: `saas_platform`
* **Collection**: `subscriptions`
* **Subscription Tier Field**: `tier`
* **Paid Value**: `"paid"`
* **Pending Payment Value**: `"pending_payment"`

---

### Step-by-Step Activation Instructions

1. **Access the MongoDB database instance** (e.g., via `mongosh` or your database admin tool).
2. **Switch to the platform database**:
   ```javascript
   use saas_platform;
   ```
3. **Locate the tenant subscription** by their tenant ID to verify their current status is `pending_payment`:
   ```javascript
   db.subscriptions.find({ tenant_id: "tenant_owner_id" });
   ```
4. **Activate the paid tier** by updating the `tier` field to `"paid"`:
   ```javascript
   db.subscriptions.updateOne(
     { tenant_id: "tenant_owner_id" },
     { $set: { tier: "paid" } }
   );
   ```
5. **Verify the update** succeeded:
   ```javascript
   db.subscriptions.find({ tenant_id: "tenant_owner_id" });
   // Expected output includes: "tier": "paid"
   ```

---

## Support Agent Onboarding Process (Ops Runbook)

To minimize the attack surface of the running services, onboarding a support agent is deliberately **not** exposed via any HTTP API endpoint. Instead, agents are created out-of-band using a standalone CLI tool that connects directly to MongoDB.

### Step-by-Step Onboarding Instructions

1. **Locate the CLI Tool**: The tool is located at `services/chat-service/cmd/onboard-agent`.
2. **Run the Onboarding Command**:
   Execute the tool with the agent ID as a parameter and point the `MONGO_URI` environment variable to the target MongoDB instance:
   ```bash
   MONGO_URI="mongodb://localhost:27017" go run ./services/chat-service/cmd/onboard-agent --id=agent_omar
   ```
3. **Confirm Onboarding**:
   If run interactively, the tool will prompt for confirmation:
   ```text
   Are you sure you want to onboard support agent "agent_omar"? (y/N):
   ```
   Type `y` or `yes` to proceed. (Use the `--yes` flag to bypass this confirmation in non-interactive pipelines).
4. **Retrieve the Token**:
   The tool will generate a cryptographically secure token and output it to stdout exactly once:
   ```text
   Successfully onboarded support agent "agent_omar"!
   ----------------------------------------------------------------------
   Generated Token: e82d7083abf3e9c402b8a0...
   ----------------------------------------------------------------------
   WARNING: This token is displayed ONLY ONCE. Copy it now.
   ```
5. **Secure the Token**: Hand this token over to the support agent out-of-band.

> [!WARNING]
> **Token Retrieval**: The generated token is displayed **only once** upon creation. It cannot be retrieved again from the database (it is a secret). If lost, the agent must be re-created with a new ID.

---

## KYB/KYE Reviewer Onboarding Process (Ops Runbook)

To minimize the attack surface of the running services, onboarding a KYB/KYE reviewer is deliberately **not** exposed via any HTTP API endpoint. Instead, reviewers are created out-of-band using a standalone CLI tool that connects directly to MongoDB.

### Step-by-Step Onboarding Instructions

1. **Locate the CLI Tool**: The tool is located at `services/auth-service/cmd/onboard-reviewer`.
2. **Run the Onboarding Command**:
   Execute the tool with the reviewer ID and display name as parameters and point the `MONGO_URI` environment variable to the target MongoDB instance:
   ```bash
   MONGO_URI="mongodb://localhost:27017" go run ./services/auth-service/cmd/onboard-reviewer --id=reviewer_omar --name="Omar Maarouf"
   ```
3. **Confirm Onboarding**:
   If run interactively, the tool will prompt for confirmation:
   ```text
   Are you sure you want to onboard reviewer "reviewer_omar" (Omar Maarouf)? (y/N):
   ```
   Type `y` or `yes` to proceed. (Use the `--yes` flag to bypass this confirmation in non-interactive pipelines).
4. **Retrieve the Token**:
   The tool will generate a cryptographically secure token and output it to stdout exactly once:
   ```text
   Successfully onboarded reviewer "reviewer_omar"!
   ----------------------------------------------------------------------
   Generated Reviewer Token: d8a958e932b7bc0f82...
   ----------------------------------------------------------------------
   WARNING: This token is displayed ONLY ONCE. Copy it now.
   ```
5. **Secure the Token**: Hand this token over to the reviewer out-of-band.

> [!WARNING]
> **Token Retrieval**: The generated token is displayed **only once** upon creation. It cannot be retrieved again from the database (it is a secret). If lost, the reviewer must be re-created with a new ID.

---

## Documentation Index

The following documentation resources map the Quick Delivery platform architecture and guidelines:

### Core & Backend
*   **[AI_CONTEXT.md](AI_CONTEXT.md)** — The primary source of truth detailing the current project state, implementation roadmap, and immediate next steps.
*   **[CLAUDE.md](CLAUDE.md)** — Core development policies and guides, including this project's auto-commit policy.
*   **[DESIGN.md](DESIGN.md)** — High-level system design, data schema models, and microservice communication patterns.
*   **[IMPLEMENTATION.md](IMPLEMENTATION.md)** — Tech stack specifications, checklists, and manual verification procedures.
*   **[docs/APPLICATION_MAP.md](docs/APPLICATION_MAP.md)** — Detailed API endpoints, inter-service HTTP routes, and user/system interaction flowcharts.
*   **[docs/changelog/README.md](docs/changelog/README.md)** — Index of categorized changelogs (Security Fixes, New Features, Infrastructure, Bug Fixes, and Documentation updates).

### Frontend (Flutter Client)
*   **[frontend/README.md](frontend/README.md)** — Practical developer-facing setup, run instructions, and target platform build scripts.
*   **[frontend/CONNECTING_TO_BACKEND.md](frontend/CONNECTING_TO_BACKEND.md)** — Per-platform network setup guide for connecting emulators and physical devices to the local backend.
*   **[docs/frontend/STATUS.md](docs/frontend/STATUS.md)** — Current frontend phase completion progress and verified client capabilities.
*   **[docs/frontend/ARCHITECTURE.md](docs/frontend/ARCHITECTURE.md)** — Technical design specifications of the client, state managers, directory layouts, and socket subscribers.



