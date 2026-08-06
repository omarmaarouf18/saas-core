# Frontend Localization & Egyptian Arabic Support

## Overview
Added full internationalization (i18n) infrastructure and Egyptian Colloquial Arabic (`ar_EG`) localization for the Quick Delivery Flutter client per ADR-0014 specifications.

## Key Changes
- **Infrastructure**: Configured `flutter_localizations` (SDK) and `intl` (`^0.20.2`) with ARB codegen (`l10n.yaml`).
- **ARB Translations**: Created `app_en.arb` (source-of-truth English) and `app_ar.arb` (Egyptian Colloquial Arabic - عامية مصرية) covering ~30 screens and reusable widgets.
- **Locale Auto-Detection & Preferences**: Configured `MaterialApp` with `localeResolutionCallback` defaulting to `ar` for Arabic device settings. Added `LocaleProvider` (persisted via `FlutterSecureStorage` key `'language_code'`) and interactive language selector in `SettingsScreen`.
- **RTL Layout Audit**: Verified `Directionality.of(context)` handling and updated hardcoded `Alignment.centerRight` to `AlignmentDirectional.centerEnd` across screens.
- **Verification**: Created `frontend/test/localization_test.dart` asserting RTL directionality and ARB resolution.

## Follow-up Audit Pass & Egyptian Arabic Correction Pass
- **Original Commit**: `7c216d98ef023e3813be83115a46a27508e6df57`
- **Audit Correction**: Re-audited all screens and widgets across `frontend/lib/screens/` and `frontend/lib/widgets/`. Extracted 13 remaining hardcoded strings across `customer_job_map_screen.dart`, `subscription_screen.dart`, `owner_fleet_map_screen.dart`, `kyb_kye_review_screen.dart`, `owner_reconciliation_queue_screen.dart`, `document_viewer_dialog.dart`, and other UI files into ARB bundles using natural Egyptian logistics terminology ("تتبع المندوب مباشر", "خطط الاشتراك", "خريطة الأسطول الحية", "مراجعة تسوية الضمان", "بطاقة الرقم القومي (وجه)", "إثبات النشاط التجاري").
- **Documentation Audit Alignment**: Corrected `docs/frontend/LOCALIZATION_AUDIT.md` table filename error (`reconciliation_queue_screen.dart` -> `owner_reconciliation_queue_screen.dart`) and added missing `document_viewer_dialog.dart` row with exact audit metrics.
- **Verification**: Verified zero hardcoded `Text('` or `Text("` strings remain via `grep -rn` checks. Passed all 155 Flutter unit and widget tests (`make ci`).
