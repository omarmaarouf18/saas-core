# Worklog: REBRAND-NAME — Waddify brand name across app and server

## Task and scope
- Task ID: REBRAND-NAME
- Item IDs covered: GitHub #56 (tracker #54), priority P0
- Allowed paths (lane from the task prompt):
  - frontend/lib/l10n/app_en.arb, frontend/lib/l10n/app_ar.arb and the generated frontend/lib/l10n/app_localizations*.dart
  - frontend/lib/core/constants.dart (the app-name value and the file comment only), frontend/lib/main.dart (MaterialApp.title only), frontend/lib/ui/gallery/qd_gallery_screen.dart (the brand text only)
  - frontend/android/app/src/main/AndroidManifest.xml (android:label only), frontend/ios/Runner/Info.plist (CFBundleDisplayName, CFBundleName only)
  - tests under frontend/test/** that assert the old name, and only the golden PNGs that change because of this text
  - services/api-gateway/internal/middleware/version_gate.go and its tests; services/auth-service/internal/otp/resend_dispatcher.go and its tests
  - docs/worklog/REBRAND-NAME.md
- Agent branch: agent/REBRAND-NAME-app-name, created from logic-exploitation (b28bca6a)

## Decisions taken
- Replaced version gate update message in api-gateway with "... to continue using Waddify."
- Replaced OTP email subject in auth-service resend dispatcher with "Your Waddify verification code".
- Updated version gate and resend dispatcher tests to assert on Waddify text.
- Replaced brand name across ARB localization files in EN (Quick Delivery -> Waddify) and Egyptian Arabic (Quick Delivery / كويك ديليفري -> ودّيفاي) for all 6 branding keys:
  - `otpFooterBrand`
  - `updBody`
  - `courBlockedPaused`
  - `ownPlanPendingNote`
  - `ownPlanChangeBody`
  - `ownPlanUpgradeBody`
- Regenerated `frontend/lib/l10n/app_localizations*.dart` with `flutter gen-l10n`.
- Updated `MaterialApp.title` in `main.dart` to 'Waddify'.
- Updated `quickDeliveryAppName` constant value in `constants.dart` to 'Waddify' and updated top-level comment.
- Updated gallery brand text in `qd_gallery_screen.dart` to Waddify / ودّيفاي.
- Updated Android `android:label` in `AndroidManifest.xml` to "Waddify".
- Updated iOS `CFBundleDisplayName` and `CFBundleName` in `Info.plist` to "Waddify".
- Updated widget test assertion in `launch_and_role_test.dart` to assert 'Waddify'.
- Regenerated and verified the 10 golden image baselines affected by the brand name text changes:
  - `frontend/test/features/auth/goldens/auth_update_ar_rtl_360x800.png`
  - `frontend/test/features/auth/goldens/auth_update_en_ltr_360x800.png`
  - `frontend/test/features/owner/goldens/own_plan_free_ar_rtl_360x800.png`
  - `frontend/test/features/owner/goldens/own_plan_free_en_ltr_360x800.png`
  - `frontend/test/features/owner/goldens/own_plan_paid_ar_rtl_360x800.png`
  - `frontend/test/features/owner/goldens/own_plan_paid_en_ltr_360x800.png`
  - `frontend/test/features/owner/goldens/own_plan_review_ar_rtl_360x800.png`
  - `frontend/test/features/owner/goldens/own_plan_review_en_ltr_360x800.png`
  - `frontend/test/ui/goldens/qd_gallery_fields_ar_rtl_360x800.png`
  - `frontend/test/ui/goldens/qd_gallery_fields_en_ltr_360x800.png`
- Preserved internal identifiers per ADR-0029 §7 and task instructions:
  - `quickDeliveryAppName` variable identifier unchanged.
  - `mapTileUserAgent` default value `QuickDeliveryApp/1.0` unchanged.
  - `RESEND_FROM_EMAIL` test fixtures in `config_test.go` unchanged.
  - All `Qd*` prefixes and package names unchanged.

## Changes per commit (message only — NO SHAs)
1. REBRAND-NAME: brand name in version-gate update message and OTP email subject
2. REBRAND-NAME: brand name in l10n, platform manifests, and updated goldens
3. REBRAND-NAME: worklog

## Verification
- `grep -rIn "Quick Delivery\|QuickDelivery\|كويك" frontend/lib frontend/android/app/src/main frontend/ios/Runner frontend/test services --include=*.dart --include=*.arb --include=*.xml --include=*.plist --include=*.go`
  Output:
  - `frontend/lib/core/constants.dart:32:  defaultValue: 'QuickDeliveryApp/1.0',` -> Tile User-Agent header policy default, preserved per ADR-0029 §7.
  - `services/auth-service/internal/config/config_test.go:119,124: "Quick Delivery <onboarding@resend.dev>"` -> Resend config test fixture, preserved per ADR-0029 §7 (production sender is VM env configuration, owner action #59).
- `flutter analyze` — No issues found! (ran in 3.1s)
- `flutter test` — All 1445 tests passed!
- `python3 scripts/frontend_l10n_audit.py` — not clean: "Flagged as likely-unlocalized human copy: 19", "Documented accepted exceptions: 1", "Non-exempt unlocalized violations: 18", including the new `frontend/lib/main.dart:139: 'Waddify'` because the script's brand exceptions listed only "Quick Delivery" and "QD" (corrected by the owner at merge; see Follow-ups).
- `make check` — PASS (scope: go=services/api-gateway,services/auth-service contracts docgen frontend)
- `gofmt -l .` — empty
- `go vet ./...` — PASS for services/api-gateway and services/auth-service
- `go test ./...` — PASS for services/api-gateway and services/auth-service

## Unverified
- On-device visual display of Android/iOS launcher labels and push notifications (requires physical device deployment).

## Follow-ups / out-of-lane findings
- `scripts/frontend_l10n_audit.py:90` accepts `"Quick Delivery"` and `"QD"` as brand exceptions, but not yet `"Waddify"`. An owner update can add `"Waddify"` to the accepted exceptions list in `scripts/frontend_l10n_audit.py`.

## Open questions
- none
