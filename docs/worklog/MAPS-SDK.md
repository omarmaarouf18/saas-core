# Worklog: MAPS-SDK — Move all three Waddify client apps to Google Maps SDK

## Task and scope
- Task ID: `MAPS-SDK` (GitHub issue #49; 1 of 4: `MAPS-SDK` -> `ADDR-GEO` -> `MAPS-QA`, with `ROAD-DISTANCE` in parallel to `MAPS-QA`)
- Item IDs covered: Items 1–4 (ADR-0032, `AppMap` wrapper, migrate the four map screens and remove `flutter_map`/OSM tile dependencies, Android/iOS build wiring and release documentation)
- Allowed paths (lane from the task prompt):
  - `frontend/lib/**`, `frontend/test/**`, `frontend/docs/**`
  - `frontend/android/app/src/main/AndroidManifest.xml` (only `com.google.android.geo.API_KEY` meta-data from placeholder)
  - `frontend/android/app/build.gradle.kts` (only `manifestPlaceholders` entry read from Gradle property or `MAPS_API_KEY` env var, empty by default)
  - `frontend/ios/Runner/AppDelegate.swift` and `frontend/ios/Runner/Info.plist` (`GMSServices.provideAPIKey` from build setting, empty by default)
  - Hot path granted: `frontend/pubspec.yaml`, `frontend/pubspec.lock` (add `google_maps_flutter` + federated packages; remove `flutter_map`; retain `latlong2` for existing coordinate users)
  - `docs/adr/0032-google-maps-platform.md` (new)
  - `docs/worklog/MAPS-SDK.md` (new)
- Agent branch: `agent/MAPS-SDK-google-maps-sdk`, created from `logic-exploitation` (`de8cd0d7`)

## Decisions taken
- Recorded architectural decision in `docs/adr/0032-google-maps-platform.md` (Status `Accepted`, Date `2026-11-27`): Google Maps Platform across all three client apps (`customer`, `console`, `employees`), strict key split (app key restricted to bundle/package IDs and Android/iOS Maps SDKs only; Geocoding/Places/Routes server key kept out of apps and called through `user-service`), per-SKU free allowance + quotas + Cloud Billing alerts, and four-task plan.
- Wrapped `google_maps_flutter: ^2.18.1` inside `frontend/lib/core/maps/` (`app_map.dart`, `app_map_types.dart`, `map_marker_renderer.dart`, `waddify_map_style.dart`) so feature screens never import `google_maps_flutter` directly.
- Applied Redesign A tokens (`QdColors`) to shared bitmap/widget marker icons (`pickupRing`, `dropoffSquare`, `selfDot`, `courierPin`, `fleetCourier`) and added optional light/dark Google Maps JSON styles in `waddify_map_style.dart`.
- Provided a test fake seam via `AppMapScope(builder: ..., hasApiKey: ...)` (plus per-widget overrides `AppMap.mapBuilder` and `AppMap.hasApiKey`) backed by `FakeAppMap` in `frontend/test/helpers/fake_app_map.dart`.
- Detected missing compile-time key via `const String kMapsApiKey = String.fromEnvironment('MAPS_API_KEY')` (`defaultHasMapsApiKey => kMapsApiKey.isNotEmpty`). Because `MainActivity.kt` and `Runner.xcodeproj/project.pbxproj` are out of lane, Dart cannot read native Android manifest / iOS `Info.plist` keys without a native channel or Xcode project change; mobile release workflows must pass BOTH the native key (`MAPS_API_KEY`) and `--dart-define=MAPS_API_KEY=...`. When empty, `AppMap` renders `Key('app_map_unavailable')` (`mapUnavailableTitle` / `mapUnavailableBody` in EN and AR) and leaves the rest of the screen interactive.
- Migrated all four map screens (`features/courier/courier_map.dart`, `features/customer/order/track_map.dart`, `features/customer/picker_page.dart`, `features/owner/fleet_map_page.dart`), preserving live updates, bounds fitting (`initialBounds` + safe single-point/zero-span zoom fallback), bottom padding clearances for overlays/sheets, and picker drag/saved/device location priority.
- Removed `flutter_map` from `frontend/pubspec.yaml`, removed `mapTileUrlTemplate`/`mapTileUserAgent` from `frontend/lib/core/constants.dart`, removed `CustomerMapTilesScope`/`BlankTileProvider` from test helpers, and deleted `frontend/test/helpers/stub_tile_http.dart`. Retained `latlong2` because `active_job_page.dart`, `offer_page.dart`, and `courier_map.dart`'s public parameter still use `latlong2.LatLng`.
- Fixed lazy `late` camera state initialization in both `_GoogleMapHostState` and `FakeAppMapState` so `initialCenter` and `initialZoom` are captured eagerly inside `initState()`, matching Frame-1 map initialization before async fleet hydration updates markers.
- Wired native `MAPS_API_KEY` injection with empty defaults:
  - Android: `defaultConfig.manifestPlaceholders["MAPS_API_KEY"]` in `frontend/android/app/build.gradle.kts` reads `-PMAPS_API_KEY` (if non-blank) else `System.getenv("MAPS_API_KEY")` else `""`; `frontend/android/app/src/main/AndroidManifest.xml` adds `<meta-data android:name="com.google.android.geo.API_KEY" android:value="${MAPS_API_KEY}" />`.
  - iOS: `frontend/ios/Runner/Info.plist` maps `MAPS_API_KEY` -> `$(MAPS_API_KEY)`; `frontend/ios/Runner/AppDelegate.swift` imports `GoogleMaps` and calls `GMSServices.provideAPIKey(...)` only when the trimmed `Info.plist` string is non-empty and does not begin with `"$("`.

## New and removed files
- New files:
  - `docs/adr/0032-google-maps-platform.md`
  - `docs/worklog/MAPS-SDK.md`
  - `frontend/lib/core/maps/app_map.dart`
  - `frontend/lib/core/maps/app_map_types.dart`
  - `frontend/lib/core/maps/map_marker_renderer.dart`
  - `frontend/lib/core/maps/waddify_map_style.dart`
  - `frontend/test/core/maps/app_map_test.dart`
  - `frontend/test/helpers/fake_app_map.dart`
- Removed files:
  - `frontend/test/helpers/stub_tile_http.dart`

## Changes per commit (message only — NO SHAs)
1. `docs(adr): adopt Google Maps Platform (ADR-0032, MAPS-SDK)`
2. `feat(frontend): add google_maps_flutter behind AppMap wrapper (MAPS-SDK)`
3. `feat(frontend): migrate map screens to AppMap and drop flutter_map (MAPS-SDK)`
4. `build(frontend): wire MAPS_API_KEY for Android/iOS and record MAPS-SDK worklog (MAPS-SDK)`

## Verification
- Commit 1: `make check` — PASS (`scope: docs infra-tests`)
- Commit 2: `make check` — PASS (`scope: docs infra-tests docgen frontend`; `flutter analyze` 0 issues; `flutter test` 1,478 passed)
- Commit 3:
  - `grep -rn "tile\.openstreetmap\.org\|flutter_map" frontend/lib` — empty (0 matches)
  - `grep -rn "tile\.openstreetmap\.org\|flutter_map" frontend/test` — empty (0 matches)
  - `make check` — PASS (`scope: docs infra-tests docgen frontend`; `flutter analyze` 0 issues; `flutter test` 1,487 passed, including new widget tests for all 4 migrated screens with `FakeAppMap` + markers, picker selected coordinate updates, `hasMapsKey: false` "Map unavailable" tests across all 4 screens, and Arabic RTL tests)
- Item 4 (before commit):
  - `xmllint --noout frontend/android/app/src/main/AndroidManifest.xml frontend/ios/Runner/Info.plist` — PASS (`xmllint OK`)
  - `flutter build apk --config-only --flavor customer --dart-define=APP_CLIENT=customer` — exit 0
  - `make check` runs immediately before committing Item 4 and `git diff --name-only logic-exploitation..HEAD` verifies only lane files were touched.

## Unverified
- Native iOS build (`Runner` + CocoaPods `GoogleMaps` + `AppDelegate.swift` + `$(MAPS_API_KEY)` `Info.plist` substitution): not built locally because this host is Fedora Linux without Xcode/`swiftc`/`plutil`. Must be exercised on `macos-15` in `frontend/.github/workflows/store-testing.yml`.
- Full Android Gradle APK/AAB compile (`./gradlew` / `flutter build apk --release`): not run locally because `flutter doctor` reports unaccepted Android SDK licenses on this workstation; only XML well-formedness (`xmllint`) and `--config-only` ran locally.
- Live Google Maps SDK rendering on physical devices (tiles, dark/light custom styles, bitmap markers, camera idle behavior, and GCP key restrictions): deferred to `MAPS-QA`.

## Follow-ups / out-of-lane findings

### Mobile release workflow & Fastlane changes required (out of lane — do not modify here)
Before shipping store or APK builds that display real Google Maps, update the three out-of-lane files below for all three flavors (`customer`, `console`, `employees`):

1. `frontend/.github/workflows/build-apk.yml` (step `Build Release APKs (3 apps, universal + one per ABI)`):
   - Add `MAPS_API_KEY: ${{ secrets.MAPS_API_KEY }}` to `env:`.
   - Pass `--dart-define=MAPS_API_KEY="${MAPS_API_KEY:-}"` inside `DEFINES=(...)` for every `CLIENT in customer console employees` so both the Gradle manifest placeholder and Dart `kMapsApiKey` receive the key.
2. `frontend/.github/workflows/store-testing.yml`:
   - In `android` -> `Build AABs and upload to the internal track`, add `MAPS_API_KEY: ${{ secrets.MAPS_API_KEY }}` to `env:`.
   - In `ios` -> `Build IPAs and upload to TestFlight`, add `MAPS_API_KEY: ${{ secrets.MAPS_API_KEY }}` to `env:`.
3. `frontend/fastlane/Fastfile`:
   - In `flutter_args(app)`, include `"--dart-define=MAPS_API_KEY=#{ENV['MAPS_API_KEY'].to_s}"` (used by both `android internal` and `ios internal` across all three flavors `customer`, `console`, `employees`).
   - On Android, Gradle already inherits `ENV["MAPS_API_KEY"]` via `build.gradle.kts` `manifestPlaceholders`.
   - On iOS, in `platform :ios` -> `lane :internal` -> `build_app(...)`, pass `xcargs: "MAPS_API_KEY=#{ENV['MAPS_API_KEY'].to_s}"` (or omit when empty) so Xcode expands `$(MAPS_API_KEY)` in `Info.plist` across `Release-customer`, `Release-console`, and `Release-employees`.

### Owner actions (required before release / `MAPS-QA`)
1. Create or select the Google Cloud project with billing enabled, and enable **Maps SDK for Android** and **Maps SDK for iOS**.
2. Create the restricted mobile app API key:
   - Restrict Android apps to `app.waddify`, `app.waddify.console`, `app.waddify.employees` with release signing SHA-1s (plus debug SHA-1s if testing debug builds).
   - Restrict iOS apps to bundle IDs `app.waddify`, `app.waddify.console`, `app.waddify.employees`.
   - Restrict the key to **Maps SDK for Android** and **Maps SDK for iOS** only (never enable Geocoding, Places, Routes, or server APIs on the app key).
3. Add `MAPS_API_KEY` to the mobile release repository secrets in GitHub.
4. Set a Cloud Billing budget alert and API quotas in Google Cloud Console.

### Deploy note
- No backend changes are part of `MAPS-SDK` and no backend deployment is required.
- Client apps (`customer`, `console`, `employees`) need a fresh mobile release built with `MAPS_API_KEY`.
- Older installed app versions continue loading OSM tiles until users update to the new release.

### Docs to fold on merge (out of lane)
- Add ADR-0032 to `docs/adr/README.md` and mark ADR-0008's OSM tile server choice as superseded by ADR-0032.
- Update `docs/frontend/STATUS.md`, `AI_CONTEXT.md`, and `docs/changelog/**` from this worklog.

## Open questions
- none
