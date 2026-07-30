# ADR-0003: Employee Assignment Tenant Binding Check

- **Status**: Accepted
- **Date**: 2026-07-13
- **Related Commit SHA**: `logic-exploitation`
- **Related audit finding**: Unchecked employee assignment in TrackJob / cross-tenant employee hijacking

## Context
In `services/user-service/internal/handlers/handlers.go`, the private utility function `isEmployeeActive(employeeID string)` was responsible for verifying that an assigned employee was valid. However, this helper only checked that the user's status (`is_active`) was `true`, completely ignoring the user's role and tenant binding returned from `auth-service` (`GET /auth/user`). 

As a result, `TrackJob` (`POST /users/jobs/track`) would accept any active user ID as `employee_id`—including another owner's account, a different tenant's employee, or a plain customer account—since all accounts default to active at signup. This created a cross-tenant security gap where jobs could be assigned to arbitrary users or hijacked by unauthorized employees.

## Decision
We decided to enforce role validation and tenant-binding checks during job tracking:
1. **Rename and Extend Helper**: Renamed `isEmployeeActive` to `verifyEmployeeAssignment(employeeID, ownerID string) (bool, error)`.
2. **Retrieve and Validate Tenant / Role**: Updated the helper to decode `tenant_id` and `role` fields from the auth-service response.
3. **Assert Criteria**: Enforce that:
   - `user.Role == "employee"` (must be a valid employee)
   - `user.TenantID == ownerID` (must belong to the requesting owner's tenant)
   - `user.IsActive == true` (must not be frozen or deactivated)
4. **Reject on Failure**: Update `TrackJob` to return a `400 Bad Request` with a clear message: `"employee is not active, not an employee, or does not belong to this owner's tenant"` when any criterion fails.
5. **Update Mock Auth Service in Tests**: Updated the test suite's mock auth server to support `tenant_id` and role propagation.
6. **Comprehensive Test Suite**: Added test coverage validating:
   - Assigning another owner as `employee_id` is rejected.
   - Assigning a customer role as `employee_id` is rejected.
   - Assigning an employee belonging to a different tenant is rejected.
   - Assigning a valid active employee belonging to the same tenant succeeds.

## Consequences
- **Security Posture**: Closes the cross-tenant employee assignment gap.
- **Data Integrity**: Job assignments are restricted strictly to authorized employees under the same tenant as the service owner.
- **Client Impact**: Clients attempting to assign incorrect or cross-tenant identities will receive a clean `400 Bad Request`.

## Alternatives Considered
- **Doing checks at the API Gateway level**: Rejected because the gateway doesn't hold service-to-owner maps or job context required to perform the tenant-matching validation. 
- **Enforcing checks on Job Completion/Cancellation instead of TrackJob**: Rejected because preventing invalid assignments at the time of booking is the most secure and fail-closed approach.
