# Frontend Localization & Egyptian Arabic Support

## Overview
Added full internationalization (i18n) infrastructure and Egyptian Colloquial Arabic (`ar_EG`) localization for the Quick Delivery Flutter client per ADR-0014 specifications.

## Key Changes
- **Infrastructure**: Configured `flutter_localizations` (SDK) and `intl` (`^0.20.2`) with ARB codegen (`l10n.yaml`).
- **ARB Translations**: Created `app_en.arb` (source-of-truth English) and `app_ar.arb` (Egyptian Colloquial Arabic - عامية مصرية) covering ~30 screens and reusable widgets.
- **Locale Auto-Detection & Preferences**: Configured `MaterialApp` with `localeResolutionCallback` defaulting to `ar` for Arabic device settings. Added `LocaleProvider` (persisted via `FlutterSecureStorage` key `'language_code'`) and interactive language selector in `SettingsScreen`.
- **RTL Layout Audit**: Verified `Directionality.of(context)` handling and updated hardcoded `Alignment.centerRight` to `AlignmentDirectional.centerEnd` across screens.
- **Verification**: Created `frontend/test/localization_test.dart` asserting RTL directionality and ARB resolution.
