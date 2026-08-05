# ADR-0014: Unified Account Settings and Role Home Redesign

- **Status**: Implemented
- **Date**: 2026-08-04
- **Related Commit SHAs**: `8afbc4c` (Employee Audit), `ebdbf1a` (Customer 4-Tab Redesign & Employee Capabilities Redesign)
- **Related audit finding**: UX Restructuring & Navigation Duplication Audit

## Context

- The current Flutter frontend contains scattered and duplicated UI elements. Most concretely, a "Logout" action is independently duplicated across three separate screens ([home_screen.dart](../../frontend/lib/screens/home_screen.dart), [customer_marketplace_screen.dart](../../frontend/lib/screens/customer_marketplace_screen.dart), and [employee_jobs_screen.dart](../../frontend/lib/screens/employee_jobs_screen.dart)) rather than living in a single centralized location. Additionally, there is no centralized place for app-wide preferences (such as dark/light theme toggles or language selection) or support access.
- [customer_marketplace_screen.dart](../../frontend/lib/screens/customer_marketplace_screen.dart) currently requires the customer to manually type raw Latitude/Longitude values into two text fields (lines ~178, ~187) to search for nearby services. This presents a poor, error-prone user experience with no visual map affordance, despite `flutter_map` already being an active dependency used elsewhere in the application (such as map tracking screens).
- [employee_jobs_screen.dart](../../frontend/lib/screens/employee_jobs_screen.dart)'s current feature set does not reflect the full set of actions actually available to the employee role per the backend API contract (e.g. job completion, cancellation restrictions, live location sharing, chat, and action logging). It requires a complete audit against backend endpoints before any visual redesign, rather than just a cosmetic UI refresh.

## Decision

1. **Unified Settings Screen (Account Action Center)**: Introduce a single unified "Settings" screen accessible across all three roles (owner, employee, user/customer). This screen consolidates:
   - Dark Mode / Light Mode toggle
   - Language selection
   - Centralized Logout action (removing the 3 duplicated instances from individual screens)
   - Customer Service / Support access (wiring to `POST /chat/tickets` once built)
2. **Owner Role Configuration Section**: For the Owner role, the Settings screen includes an "Owner Configuration" section.
   - **STATUS**: **NOT YET SPECIFIED / PLANNED** — This ADR formally registers it as an upcoming addition. Its detailed content (which existing owner-management features from `employee_screen.dart` migrate here, and what new features are added) is explicitly **DEFERRED** to a future decision and not decided in this ADR.
3. **User (Customer) Role "My Account" Section**: For the User (customer) role, the exact same underlying Settings screen/logic is reused, but the owner-configuration-equivalent section is labeled "My Account" in the customer UI. Its detailed content is likewise deferred and TBD, to be scoped later.
4. **Customer Home Redesign**: Redesign the Customer home experience to feature a friendly layout with 4 distributed category tiles, a search bar, and a home page the user can navigate from.
   - **STATUS**: The exact 4 categories are **TBD** — to be finalized in a follow-up scoping conversation before implementation. Note this explicitly as an open question.
5. **Interactive Map Location Picker**: Remove the manual Latitude/Longitude text-input fields from `customer_marketplace_screen.dart` entirely. Replace them with an interactive map picker leveraging the existing `flutter_map` dependency, allowing customers to visually pick their location and filter/sort nearby services based on the selected coordinates.
6. **Employee Capability Audit & Screen Redesign**: Full redesign of the Employee-facing screen(s). Before any visual redesign work begins, a complete audit must be performed of every backend capability available to the employee role (cross-referencing `services/user-service`, `services/auth-service`, and `services/chat-service` handlers restricted to employee auth) to ensure the redesigned UI surfaces all backend capabilities. This audit is a prerequisite task to be completed prior to the employee screen redesign, not simultaneously.

## Consequences

- This is a multi-phase initiative. This ADR establishes directional goals and scope boundaries but does not commit to a single monolithic implementation task. Follow-up ADRs or `STATUS.md` phase entries will be added as each piece (Settings/Account Center, Customer home redesign, Map picker, Employee audit + redesign) is scoped and built individually.
- The "Owner Configuration" content, "My Account" content, and the exact 4 customer home categories are explicitly **open questions** requiring follow-up scoping conversations before implementation. No future session should invent or assume this scope without explicit user alignment.

## Alternatives Considered

- **Keeping Logout/Support/Preferences Scattered Per-Screen (Status Quo)**: Rejected due to the code duplication already found across 3 separate screens and the ongoing maintenance burden of keeping multiple copies in sync.
- **Building Owner Configuration Content Speculatively Now**: Rejected because the specific requirements have not yet been specified by the user. Registering the placeholder now and scoping it properly later prevents speculative over-engineering.
