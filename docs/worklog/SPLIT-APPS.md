# Worklog: SPLIT-APPS — three Waddify apps from the one Flutter codebase

## Task and scope
- Task ID: SPLIT-APPS (P0, ships with the rebrand in one release, 3.0.0)
- Item IDs covered: none
- Allowed paths (lane): `frontend/android/app/build.gradle.kts` (product flavors only),
  `frontend/android/app/src/main/AndroidManifest.xml` (label only),
  `frontend/android/app/src/{customer,console,employees}/**`, `frontend/lib/core/app_client.dart` (new),
  `frontend/lib/core/api_client.dart` (X-App-Client only), `frontend/lib/features/auth/**`,
  `frontend/lib/l10n/app_{en,ar}.arb` + regenerated `app_localizations*.dart` (new strings only),
  `frontend/test/**`; hot path granted: `frontend/pubspec.yaml` (version line only),
  `frontend/lib/core/app_version.dart` (default only); `docs/adr/0030-*.md`, `docs/adr/README.md`,
  `frontend/README.md` (build/run section), this worklog.
- Agent branch: agent/SPLIT-APPS-three-clients, created from logic-exploitation @ baab789d

## Decisions taken
- Owner decisions (table, IDs, 3.0.0+1, no migration, iOS out, no backend change) applied as given; not reopened.
- `AppClient` resolution: `APP_CLIENT` define first; when the define is missing, the Flutter build flavor
  (`appFlavor`) when it names a client; else `customer` (tests, plain `flutter run`). An unknown define, or a
  define that disagrees with `--flavor`, throws a `StateError` at start-up (the first `ApiClient` is built
  in `main.dart`). Reason: a release built with `--flavor console` but without the define would otherwise be a
  console-branded app that only lets customers in. Release builds still pass both (README, ADR-0030).
- `ApiClient` takes an optional `appClient` (default `AppClient.current`) and sends `X-App-Client: <name>`
  from `_getHeaders`, which every request path uses.
- Wrong-app page: `UnsupportedRolePage` extended with an optional `rightApp`. With it: key `wrong_app_page`,
  title "This account is for another app", body naming the right app's `displayName` (the Latin store name in
  both locales, ADR-0029: the brand is never translated), sign-out button. Without it: unchanged staff-role page
  (admin, reviewer). `RoleHome` checks `AppClient.current.allows(role)` before the role switch, so no role ever
  reaches another role's shell. `AuthGate` needs no change: it only routes to `RoleHome`/`LoginPage`.
- Signup: role picker removed; the role is `AppClient.current.signupRole`. Customer app shows a hint pointing
  businesses to Waddify Console; console app says couriers sign in with Waddify Employees once added. Employees
  app: the login footer replaces the sign-up link with "Staff accounts are created by your company…"; `SignupPage`
  asserts `canSignUp` and `_submit` refuses a null role.
- Icons: customer keeps the main icon (Ink tile, allowed by the prompt). Console and employees get legacy
  `mipmap-*/ic_launcher.png` rendered with `rsvg-convert` from `app-icon.svg` geometry with swapped colours
  (speed lines take the beak colour, so they stay visible on the Sun tile), an adaptive foreground vector
  (`drawable/ic_launcher_foreground.xml`, main geometry with swapped fills) and `ic_launcher_background`.
  The adaptive XML (`mipmap-anydpi-v26/ic_launcher.xml`) and the monochrome layer are inherited from main
  (identical for all three), so they are not copied into the flavors. Native splash unchanged.
- Old role-picker strings (`authRoleQuestion`, `authRoleCustomer`, `authRoleCustomerHint`, `authRoleOwner`,
  `authRoleOwnerHint`, `authCourierNote`) are now unused; left in place (lane: new strings only).
- `frontend/ios/**` untouched (iOS out of scope).
- `google-services.json` not touched: it is not in the repo (CI secret) and none exists locally, so the debug
  builds below ran with push disabled.

## Changes per commit (message only — NO SHAs)
1. `SPLIT-APPS: ADR-0030 three client apps from one Flutter codebase`
2. `SPLIT-APPS: Android flavors customer/console/employees with per-flavor app names`
3. `SPLIT-APPS: per-flavor launcher icons (console Nile tile, employees Sun tile)`
4. `SPLIT-APPS: AppClient (APP_CLIENT define) and X-App-Client header`
5. `SPLIT-APPS: role gating, signup per app, wrong-app page, l10n and tests`
6. `SPLIT-APPS: version 3.0.0+1 for all three apps`
7. `SPLIT-APPS: README build and run commands for the three apps`
8. `SPLIT-APPS: ADR-0030 states the real error of a build without --flavor`
9. `SPLIT-APPS: worklog`

## Verification (all local)
- `make check` before every commit — PASS (scope `docs infra-tests docgen frontend` from commit 2 on):
  `flutter analyze` "No issues found!", `flutter test` "+1474: All tests passed!" (was +1451 at base).
- New tests: `test/core/app_client_test.dart` (resolution, typo/mismatch fail, roles/signup/names, X-App-Client
  for each client on GET and POST); `test/features/auth/split_apps_test.dart` (each app: allowed role → its shell;
  each other role → wrong-app page naming the right app, sign-out works; Arabic; admin keeps the staff page;
  employees: no sign-up link + staff note; customer/console: sign-up creates `user`/`owner`, no role picker).
  Updated: `role_home_test.dart` (owner/courier run as console/employees), `login_signup_test.dart`,
  `test/core/app_version_test.dart` (3.0.0).
- Goldens: only `auth_signup_{ar_rtl,en_ltr}_360x800.png` changed (role picker removed, hint added), re-rendered
  locally with Flutter 3.44.6 (the CI pin); every other golden byte-identical.
- `flutter build apk --debug --flavor X --dart-define=APP_CLIENT=X` for customer, console, employees — built.
  `aapt dump badging`: `app.waddify` / 'Waddify', `app.waddify.console` / 'Waddify Console',
  `app.waddify.employees` / 'Waddify Employees', all versionName 3.0.0 versionCode 1.
  `aapt dump --values resources`: `ic_launcher_background` = 0xff10233f / 0xff0e7c7b / 0xfff2a541.
- `flutter build apk --debug` without `--flavor`: "Gradle build failed to produce an .apk file" (expected).
- `file` on the 10 new PNGs: 48/72/96/144/192 px, 8-bit RGB, for console and employees.

## Unverified
- Owner device check: install the three apps side by side and log in with one account of each role in each app
  (needs a device and real accounts).
- Push in the new apps: cannot work until Firebase lists the three package names (open question 1).
- Release builds and the mobile repo workflow: not run (the workflow is out of lane and fails today, see below).
- `StateError` on a mismatched define/flavor: covered by unit tests of `AppClient.resolve`, not observed in a
  real app start.
- iOS: not built (out of scope).

## Follow-ups / out-of-lane findings
- Mobile repo release workflow (`frontend/.github/workflows/build-apk.yml`): it runs `flutter build apk --release`
  without `--flavor` and **fails from this change on**. Build and publish three APKs with
  `--flavor X --dart-define=APP_CLIENT=X` (and update the gateway `download_url` / website links).
  `test/core/app_version_test.dart` asserts strings in that workflow and must follow it.
- `frontend/lib/main.dart` (out of lane): `MaterialApp(title: 'Waddify')` is the Android recents label for all
  three apps; it should be `AppClient.current.displayName`.
- `frontend/lib/main.dart` (out of lane): SSE subscription (and push token sync) start for any authenticated user,
  so a user on the wrong-app page still has a notification stream until they sign out. Gate on
  `AppClient.current.allows(role)`.
- Remove the six now-unused role-picker ARB keys (listed above).
- Ops console (`kyc-reviewer-console`): one download link per app.
- Per-client version gate and `download_url` on the gateway keyed by `X-App-Client`, when the apps need
  different minimum versions. The gateway CORS allow-list does not include `X-App-Version` or `X-App-Client`
  (only relevant if a web client ever calls the API cross-origin).
- iOS schemes for the three apps.
- Shared docs to fold: AI_CONTEXT (ADR range now 0001–0030, client is three apps, version 3.0.0, the rebrand row),
  `docs/frontend/STATUS.md` (new file `lib/core/app_client.dart`; `make check` passed without a STATUS entry —
  whether `make docs-check` covers `lib/core/` was not checked).

## Open questions
1. Firebase (owner action): add `app.waddify`, `app.waddify.console` and `app.waddify.employees` as Android apps in
   the same Firebase project, download the new `google-services.json` (it lists all three), and replace
   `frontend/android/app/google-services.json` locally and the CI secret `GOOGLE_SERVICES_JSON_B64`. Until then
   push does not work in the new apps. Expected but not verified here (no json locally): the google-services
   plugin fails the Gradle build when the json has no client for the build's package name ("No matching client
   found"), so the CI secret likely has to be replaced before the first flavored release build.
