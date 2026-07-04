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
