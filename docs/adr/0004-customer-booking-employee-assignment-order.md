# ADR-0004: Customer Booking Employee Assignment Ordering Correctness

- **Status**: Accepted
- **Date**: 2026-07-17
- **Related Commit SHA**: `bb405d3dea2c8f4464433e4635a7e4db563adc08`
- **Related audit finding**: Regression in customer-initiated booking pre-assignment / empty owner ID verification

## Context
In ADR-0003, `verifyEmployeeAssignment(employeeID, ownerID)` was introduced to validate that pre-assigned employees hold the correct role and belong to the correct tenant (matching `ownerID`). 

Later, a customer-initiated booking flow (where no `owner_id` token is passed in the request body) was added. In this customer flow, the owner ID is not provided in the request but is instead resolved server-side from `svc.TenantID` after looking up the service record. 

However, in the original implementation of the handler `TrackJob` (`POST /users/jobs/track`), the `verifyEmployeeAssignment` check was executed *before* the service record was retrieved and the owner ID resolved for customer bookings. Because of this incorrect ordering, when a customer initiated a booking with an `employee_id` to pre-assign an employee, the helper was called with `resolvedOwnerID == ""` (which was not yet resolved). As a result, the tenant-binding check (`user.TenantID != ownerID`) always failed, causing legitimate employee pre-assignments to be rejected with `400 Bad Request` in customer-initiated bookings.

## Decision
We decided to reorder the transaction validation steps inside `TrackJob` to ensure the owner ID is fully resolved before performing the employee verification check:
1. **Move Service Lookup and Owner Resolution Earlier**: Retrieve the service record `svc` and set `resolvedOwnerID = svc.TenantID` early in the execution path if the request does not provide an owner token (`!hasOwnerToken`).
2. **Execute Employee Verification after Resolution**: Call `verifyEmployeeAssignment` only after `resolvedOwnerID` is set to either the validated owner token's identity (for owner/employee-initiated bookings) or the service record's tenant ID (for customer-initiated bookings).
3. **Preserve Lazy Loading for Owner Bookings**: If an owner token is provided, defer service lookup to the original step (only if `svc` is nil) and verify that the token's owner matches the service tenant, preserving the original behavior and error flows.
4. **Ensure Robust Testing**: Add regression test cases validating that customer-initiated bookings with valid active employees of the matching tenant succeed, and those with deactivated employees, wrong tenants, or invalid roles fail.

## Consequences
- **Correctness**: Resolves the regression, restoring full support for customer-initiated bookings with pre-assigned employees.
- **Security Posture**: Retains the strong tenant-binding and role protections of ADR-0003 under all booking flows.
- **Consistency**: Client-facing error messages and behaviors for existing flows remain unchanged.

## Alternatives Considered
- **Relaxing tenant binding for customer bookings**: Rejected because it would re-introduce the cross-tenant employee hijacking vulnerability closed by ADR-0003.
- **Passing raw owner_id in customer requests**: Rejected because allowing the client to specify the owner ID directly on customer-initiated bookings bypasses the server-side resolution verification and could lead to spoofing.
