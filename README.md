# SaaS Prototype Platform

## Manual KYC Approval Process (Ops Runbook)

To maintain security and avoid exposing administrative endpoints that could be targeted by attackers, Know Your Customer (KYC) approval for tenant owners is deliberately **not** automated or exposed via in-app API endpoints. Instead, approvals must be handled manually by an operations engineer directly in the database.

### MongoDB Configuration Details
* **Database**: `saas_platform`
* **Collection**: `users`
* **KYC Status Field**: `kyc_status`
* **Approved Value**: `"approved"`
* **Pending Value**: `"pending_super_admin_approval"`

---

### Step-by-Step Approval Instructions

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

