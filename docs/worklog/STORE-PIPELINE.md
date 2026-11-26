# Worklog: STORE-PIPELINE — Google Play internal/closed testing + TestFlight pipeline

## Task and scope
- Task ID: STORE-PIPELINE
- Item IDs covered: none (owner request: store pipeline for internal and closed testing on both stores, no production release)
- Allowed paths (lane, granted by the owner in chat, including the hot paths listed): `frontend/.github/workflows/**`, `frontend/android/**`, `frontend/ios/**`, `frontend/fastlane/**`, `frontend/Gemfile`, `frontend/Gemfile.lock`, `frontend/.gitignore`, store-testing runbook, `docs/worklog/STORE-PIPELINE.md`
- Agent branch: agent/STORE-PIPELINE-store-testing-pipeline, created from logic-exploitation @ c5b3faeb

## Decisions taken
- Fastlane inside GitHub Actions (owner choice after explanation). Workflows live in `frontend/.github/workflows/` and run in the mobile repo after the subtree sync, like `build-apk.yml`.
- Triggers (owner choice): every push to mobile `main` → Play internal + TestFlight internal; closed testing only through the manual `store-promote.yml`. No lane can target the Play `production` track or submit for App Store review.
- Runbook placed at `frontend/docs/STORE_TESTING.md` (next to `PUSH.md`, synced to the mobile repo with the workflows) instead of `docs/frontend/STORE_TESTING.md` as first announced in chat.
- Android: release signing uses the upload key only when configured (`key.properties` or `ANDROID_*` env); otherwise the debug key as before, so the APK channel (`build-apk.yml`) is unchanged. Store builds set `WADDIFY_REQUIRE_UPLOAD_KEY=true` and fail without the key.
- iOS flavors: 9 new build configurations `Debug-/Release-/Profile-<flavor>` (copies of the existing ones in the project and both targets), shared schemes `customer`/`console`/`employees`, bundle IDs `app.waddify`/`.console`/`.employees`, display name from `APP_DISPLAY_NAME`. Base xcconfigs unchanged (Flutter's documented flavor setup). Legacy `Debug/Release/Profile` now use `app.waddify` (was `com.saascore.frontend`; no iOS users, ADR-0030 §5). The edit was done by a script (text edit of `project.pbxproj`), not by Xcode.
- iOS deployment target 13.0 → 15.0 (Xcode 26, required by App Store Connect since 2026-04-28, supports iOS 15 as minimum).
- Info.plist: `CFBundleDisplayName = $(APP_DISPLAY_NAME)`, `ITSAppUsesNonExemptEncryption = false` (HTTPS only), camera/photo library purpose strings (image_picker, file_picker), `NSAppleMusicUsageDescription` (file_picker links the media library API; a missing string fails upload validation).
- iOS signing: fastlane match (git storage, private repo, token from the existing GitHub App) and a manual `store-ios-signing.yml` so certificates can be created without a Mac.
- Build number: `STORE_BUILD_NUMBER_OFFSET + run_number*10 + run_attempt`, shared by all apps and both stores in a run.
- No Podfile committed: the project uses Flutter's Swift Package Manager integration; Flutter generates a Podfile only if a plugin needs CocoaPods.

- Apple setup done in the owner's browser (2026-11-25, with owner approval per step): explicit App IDs `app.waddify`, `app.waddify.console`, `app.waddify.employees` with Push Notifications enabled; three App Store Connect apps (English (U.S.), SKUs `waddify-customer`, `waddify-console`, `waddify-employees`); team API key `waddify-ci` with role Admin (needed so match can create the distribution certificate from CI); its private key was pasted into the chat by mistake, so it was revoked the same day and replaced by `waddify-ci-2` (Admin). The account already had one Distribution certificate from another project; match will create its own. Private repo `omarmaarouf18/waddify-ios-certificates` created and added to the `quick-delivery-automation` GitHub App installation. TestFlight: internal group "Internal team" (automatic distribution on, account holder added) in all three apps. App Store Connect offers no external-group option before the first build exists, so the external group (`TESTFLIGHT_EXTERNAL_GROUPS`) is created after the first TestFlight upload; `ios promote` fails until then.

## Changes per commit (message only — NO SHAs)
Not committed by the agent (no Flutter/Go in its shells); the owner runs `make check && make commit` on the host, as three commits:
1. `feat(android): release signing with the Play upload key (STORE-PIPELINE)`
2. `feat(ios): customer/console/employees flavors and app.waddify bundle IDs (STORE-PIPELINE)`
3. `ci(mobile): Fastlane store testing pipeline, Play internal/closed + TestFlight (STORE-PIPELINE)`

The three workflow files could not be written by the agent's tools (`.github/workflows` is write-protected for remote tools); the owner placed the files the agent produced.

## Verification
Where: the agent's shells (desktop VM and cloud container). No Flutter, Go, Xcode or Fastlane available there.
- `actionlint` 1.7.12 (with shellcheck) on `store-testing.yml`, `store-promote.yml`, `store-ios-signing.yml` — clean after fixing SC2129/SC2155.
- `ruby -c fastlane/Fastfile`, `ruby -c Gemfile` — Syntax OK.
- `project.pbxproj`: custom structural check — balanced braces/parens, 87 unique object IDs, each of the 3 configuration lists has 12 entries, all referenced IDs defined; bundle IDs `app.waddify`, `app.waddify.RunnerTests`, `app.waddify.console`, `app.waddify.employees`; deployment target only 15.0. Script refuses a second run.
- `Info.plist`: parses with Python `plistlib`.
- `make check` / `make commit`: NOT run by the agent (no Flutter/Go in its shells).

## Unverified
- Any Android build with the new signing block (`flutter build appbundle`): no Flutter/Gradle in the agent's shells.
- Xcode opening the edited project, `flutter build ios --config-only --flavor X`, archive, export, TestFlight upload: no macOS.
- Fastlane behaviour (action parameters checked against documentation from memory, not run): `upload_to_play_store` promote with `version_code`, `latest_testflight_build_number(version:)`, `upload_to_testflight(distribute_only: true)`.
- That `macos-15` runners resolve `latest-stable` to Xcode 26+ (the workflow fails fast if not).
- That all iOS plugins resolve through SPM without CocoaPods.

## Follow-ups / out-of-lane findings
- Commit `Gemfile.lock` from the first CI run's artifact to pin Fastlane.
- iOS push (APNs key, `GoogleService-Info.plist` for three bundle IDs, push entitlement) — not in this task.
- iOS per-flavor app icons and Arabic `InfoPlist.strings`.
- Version gate `download_url` sends store testers (and iOS users) to the Android APK; per-client gate (ADR-0030) should also know the store links.
- ADR-0030 §5 says "iOS: no iOS release yet": the owner may want an ADR addendum for the iOS flavors and store channels.
- `AI_CONTEXT.md` feature table: add the store-testing pipeline row at fold time.

## Open questions
- none

## Follow-up: first CI runs (2026-11-25)
- `store-ios-signing.yml` succeeded (match created the distribution certificate and three App Store profiles).
- `store-testing.yml` iOS run failed at `flutter build ios --release --config-only` with "No development certificates available to code sign app for device deployment" (match itself succeeded). Fix: pass `--no-codesign` to the config-only step; `build_app` signs with the match profile.
- Verified on the macOS runner up to that point: Xcode 26 check, Flutter 3.44.6, Ruby 3.3 / fastlane 2.242.0, `flutter pub get`, GitHub App token for the certificates repo, App Store Connect API key, match readonly fetch.
- Next run (with `--no-codesign`): match installed the certificate and all three profiles; `flutter build ios --config-only` then failed because `flutter_secure_storage` has no Swift Package Manager support, so Flutter needs CocoaPods, and the runner's CocoaPods is "installed but broken" under `bundle exec` (different Ruby). Fix: `gem "cocoapods"` in `frontend/Gemfile`.

