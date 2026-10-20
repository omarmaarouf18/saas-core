# Worklog: HOTFIX-LOGIN — the launch splash only covers session restore

## Task and scope
- Task ID: HOTFIX-LOGIN
- Item IDs covered: 1 (AuthProvider.isRestoringSession), 2 (old AuthGate + RedesignAuthGate), 3 (logout helper)
- Allowed paths (lane from the task prompt): frontend/lib/providers/auth_provider.dart, frontend/lib/main.dart (AuthGate), frontend/lib/features/auth/auth_gate.dart (RedesignAuthGate alignment), frontend/lib/utils/logout_helper.dart, their tests, docs/worklog/HOTFIX-LOGIN.md
- Agent branch: agent/HOTFIX-LOGIN-authgate-restore-only, created from logic-exploitation (11475037, FE-AUTH-ACCOUNT merged)

## Decisions taken
- `isRestoringSession` is set and cleared only in `_tryAutoLogin` (called from the constructor, so it is already true before the first frame). `isLoading` is unchanged: `_tryAutoLogin` still raises it, and so does every other call.
- RedesignAuthGate's `_restored` latch (first time `isLoading` was false) is replaced by `isRestoringSession`, so both gates use one flag. The widget is now stateless; its constructor is unchanged.
- `logoutAndClearProviders` gets an optional `{bool redesign = kRedesignAuth}` parameter, passed to `signedOutRootScreen(redesign:)`, so tests can check the flag both on and off. The call site (settings_screen.dart) is unchanged.
- Test fakes: `FakeAuthFlow` (test/features/auth/auth_harness.dart) gets an `isRestoringSession` field (it `implements AuthProvider`, so the new getter has to be there or it throws NoSuchMethodError). `GateAuthProvider` (test/auth_splash_gate_test.dart) gets `mockRestoring` and scripted `login`/`signup`. The scripted calls hold on a completer with `isLoading` true, the same way the real provider does.

## Changes per commit (message only — NO SHAs)
1. `HOTFIX-LOGIN: AuthProvider.isRestoringSession, true only during the launch session restore`
2. `HOTFIX-LOGIN: AuthGate shows the splash only while the session is restored`
3. `HOTFIX-LOGIN: logout opens signedOutRootScreen() so QD_REDESIGN_AUTH is respected`
4. `HOTFIX-LOGIN: worklog` (this file)

## Regression tests: does each one fail before the fix?
| Test | File | Fails before fix? |
| :--- | :--- | :--- |
| isRestoringSession true from construction until the restore ends | test/auth_provider_test.dart | yes (compile error: the getter does not exist) |
| isRestoringSession clears when no session is stored | test/auth_provider_test.dart | yes (compile error, same reason) |
| isRestoringSession stays false during login/signup/verifyOtp/resendOtp/forgotPassword while isLoading is true | test/auth_provider_test.dart | yes (compile error, same reason) |
| (a) UX-17 launch restore: splash, never a LoginScreen frame | test/auth_splash_gate_test.dart | no. This is the existing guard, updated to raise isRestoringSession; it passes before and after |
| (b) customer/owner login that needs a code pushes OtpScreen | test/auth_splash_gate_test.dart | **yes**. Run against the old gate, with the mid-request splash assertions also removed, it failed with `Found 0 widgets with type "OtpScreen"` (the production symptom) |
| (c) sign-up pushes OtpScreen | test/auth_splash_gate_test.dart | **no**, see the finding below |
| (d) employee login lands on HomeScreen | test/auth_splash_gate_test.dart | yes, but only on the mid-request "no splash" assertion. After the request the old gate also ends on HomeScreen |
| logout, flag off (default build) opens LoginScreen | test/logout_helper_test.dart | no. The default build behaves the same before and after |
| logout, flag off explicitly opens LoginScreen | test/logout_helper_test.dart | yes (compile error: no `redesign` parameter) |
| logout, flag on opens LoginPage, stack cleared | test/logout_helper_test.dart | yes (compile error). Behaviourally the old helper always pushed LoginScreen, which this test rejects. Not run as a behavioural pre-fix probe |
| RedesignAuthGate tests (existing, updated for the new flag) | test/features/auth/auth_gate_flag_test.dart | n/a, alignment only |

### Finding: (c) sign-up does not fail before the fix
The task prompt says (c) must fail before the fix. It does not, and I left it as a regression guard instead of building a contrived failure. SignupScreen is pushed as its own route above the root route (`LoginScreen._buildFooterLink`, `Navigator.push`). The old gate swaps only the root route's child (LoginScreen to splash), so SignupScreen stays mounted during `auth.signup`, and its `pushReplacement(OtpScreen)` still runs. The splash does appear under it, offstage. With the old gate, the test above passed before the fix (`00:01 +1: All tests passed!` for `--plain-name "sign-up pushes OtpScreen"`). So the production break this fix addresses is the login path (owners and customers with 2FA). If new sign-ups also fail in production, the cause is somewhere else, and the owner's manual check should cover sign-up too.

## Verification
- `make check` before each of the three code commits: PASS each time (scope: docgen frontend). Last lines from the item-3 run:
  ```
  00:47 +1314: All tests passed!
  [timing] flutter-analyze-test 52.6s
  [timing] total 53.4s
  == pre-push gate: all checks passed (scope: docgen frontend) ==
  ```
- `flutter analyze` (frontend/), last line: `No issues found! (ran in 0.9s)`
- `flutter test` (frontend/), last line: `00:47 +1314: All tests passed!`
- Goldens unchanged: `git diff --stat logic-exploitation..HEAD -- '*.png'` printed nothing, and `git status --short` was empty after the full test run.

## Unverified
- Manual check (owner): old app build, log out, then log in as a customer, and the code screen should appear. I did not run it; it needs a device or desktop build against a backend.
- I did not run the flag-on logout test as a behavioural pre-fix probe (see the table).

## Follow-ups / out-of-lane findings
- The old LoginScreen overflows by 32 px (Row at login_screen.dart:279) at a 360 px test surface with the test font. This was there before the change and was not fixed here; the new logout test uses the default surface for the old screen.
- The (c) finding above: if sign-up is still reported broken in production, it needs its own investigation.

## Open questions
- none for items 1–3.

## Follow-up: end-to-end integration test (stopped)
Asked for: a `frontend/integration_test/` test run on Linux against the local staging stack. It signs up a fresh customer, logs out, logs in again, checks that the code screen appears and that the dev OTP lands on the customer home. Then a seeded courier logs in and lands on home with no code. It runs twice: once with the AuthGate change reverted locally (must fail), once on HEAD (must pass).

Checked before stopping:
- Display/desktop session: available (`DISPLAY=:0`, `WAYLAND_DISPLAY=wayland-0`). `flutter devices` lists `Linux (desktop) • linux • linux-x64 • Fedora Linux 44 (Workstation Edition) 7.2.11-200.fc44.x86_64`.
- Linux build on this base: `flutter build linux --debug` ended with `✓ Built build/linux/x64/debug/bundle/frontend`. The FE-LINUX-BUILD CMake changes are not needed for this.
- Nothing was written and no test was run; the tree is unchanged.

Stopped on these decisions (no test written, nothing reverted):
1. **`integration_test` is not a dependency.** `frontend/pubspec.yaml` lists only `flutter_test` and `flutter_lints` under dev_dependencies. Adding `integration_test: sdk: flutter` changes `pubspec.yaml` and `pubspec.lock`, which are hot paths. This task's prompt does not grant ownership of them. Owner decision: grant HOTFIX-LOGIN ownership of `frontend/pubspec.yaml`/`pubspec.lock` for this one dev dependency (its own commit), or add it in a separate task first.
2. **No seeded courier in the staging stack.** `scripts/staging_up.sh` seeds no app users. The Go e2e suites create users with direct Mongo writes (`tests/e2e/e2e_helpers.go`, e.g. `db.SeedCustomer`), which a Dart integration test cannot call. Owner decision: (a) give the courier credentials, or a seed step to run before the test (e.g. a small Go helper or `mongosh` script under `scripts/`, which is outside this lane), or (b) have the test create the courier through the app's API (owner signup + OTP, then the owner creates an employee). Option (b) needs the employee-creation endpoint and its first-login flow confirmed, and makes the test much longer.
