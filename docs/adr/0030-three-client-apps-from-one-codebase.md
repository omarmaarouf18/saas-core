# ADR-0030: Three client apps from one Flutter codebase

- **Status**: Accepted (owner decision, 2026-11-24). Implemented in SPLIT-APPS.
- **Date**: 2026-11-24
- **Priority**: P0. Ships in the same release as the rebrand (ADR-0029), app version 3.0.0.
- **Related**: ADR-0001 (owners provision their employees), ADR-0018 (client version gate), ADR-0029 (rebrand to Waddify; §3 brand architecture names "Waddify" for customers and "Waddify Console" for owners and staff tools).

---

## Context

Until now one Android app (`com.saascore.frontend`) served all three roles: customers (`user`), business owners (`owner`) and their staff (`employee`). The login page decided which shell a user got, and the signup page offered a customer/owner role picker.

ADR-0029 §3 gives customers and businesses different names. One app for everybody also means:

- a store listing that has to speak to customers, business owners and couriers at once;
- every role carries the code, permissions and screens of the other two;
- the owner has no way to send a courier a link to "the staff app".

There are no production users yet (internal testers only), so changing the Android application ID costs nothing.

## Decision

### 1. One codebase, three builds

The code stays one Flutter project (`frontend/`). Nothing moves into packages or new repos. Only the build produces three apps, from Android product flavors (dimension `client`):

| Flavor | Store / launcher name | Application ID | Roles it accepts | Account creation |
| :--- | :--- | :--- | :--- | :--- |
| `customer` | Waddify | `app.waddify` | `user` | sign up as customer |
| `console` | Waddify Console | `app.waddify.console` | `owner` | sign up as owner |
| `employees` | Waddify Employees | `app.waddify.employees` | `employee` | login only (owners add their staff, ADR-0001) |

- The Gradle `namespace` (and the Kotlin package `com.saascore.frontend`) does not change.
- The launcher name comes from `src/<flavor>/res/values/strings.xml` (`app_name`); the manifest label is `@string/app_name`.
- Each flavor has its own launcher icon: the same mark, a different tile colour (customer Ink, console Nile, employees Sun) so testers can tell the apps apart. The native splash stays shared.

### 2. Client identity in Dart

`frontend/lib/core/app_client.dart` defines `AppClient { customer, console, employees }`, read from `--dart-define=APP_CLIENT=<customer|console|employees>`. When the define is missing the app uses the Flutter build flavor (`appFlavor`) when it names a client, else `customer` (tests and a plain `flutter run`). A define that names no client, or a define that disagrees with the build flavor, stops the app at start-up instead of building the wrong app silently.

Release builds pass both: `flutter build apk --flavor X --dart-define=APP_CLIENT=X`.

`AppClient` exposes `allowedRoles`, `canSignUp`, `signupRole` and `displayName`, and every API request carries `X-App-Client: <client>`.

### 3. Gating rules

- After sign-in, a user whose role is not in the app's `allowedRoles` sees a "wrong app" page that names the right app (customers → Waddify, owners → Waddify Console, employees → Waddify Employees) with a sign-out button. The app never routes a user into another role's shell.
- Roles that have no app (admin, reviewer) keep the existing unsupported-role page (they use the web console).
- Signup: the customer app creates a `user`, the console app an `owner`; neither has a role picker. The employees app has no signup link or page; its sign-in page says that staff accounts are created by their company.
- The server stays the authority on roles. The gate is a client-side routing rule, not a security boundary.

### 4. One version for all three

All three apps always share one version number, `3.0.0+1` for this release (it carries the rebrand; 2.2.0 was never released). They send the same `X-App-Version`, so the existing global version gate (ADR-0018) keeps working with no backend change.

### 5. Not in this decision

- iOS: no iOS release yet; schemes for the three apps come later. `frontend/ios/**` is unchanged.
- No migration from `com.saascore.frontend`: there are no production users, so the three apps are new installs.

## Consequences

- Every Android build needs `--flavor <customer|console|employees>` (`flutter run`, `flutter build apk`, `flutter build appbundle`); a build without it fails with an ambiguous-variant error.
- The mobile release workflow (`frontend/.github/workflows/build-apk.yml`, run in the mobile repo) must build and publish three APKs with `--flavor X --dart-define=APP_CLIENT=X`. Until it does, the release workflow fails.
- Firebase: FCM needs the three package names registered. The owner adds `app.waddify`, `app.waddify.console` and `app.waddify.employees` as Android apps in the same Firebase project and replaces `google-services.json` (and the CI secret) with the downloaded file, which lists all three. Push does not work in the new apps until then.
- The ops console (`kyc-reviewer-console`) needs one download link per app.
- A later per-client version gate (different minimum versions, a different `download_url` per app) can key on `X-App-Client` at the gateway. Today the gateway ignores the header.
