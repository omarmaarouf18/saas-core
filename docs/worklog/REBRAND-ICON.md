# Worklog: REBRAND-ICON — launcher icons, notification icon and splash from the Waddify mark

## Task and scope
- Task ID: REBRAND-ICON
- Item IDs covered: #58 (tracker #54), priority P0
- Allowed paths (lane from the task prompt):
  frontend/android/app/src/main/res/mipmap-*/**
  frontend/android/app/src/main/res/drawable*/**
  frontend/android/app/src/main/res/values*/
  frontend/ios/Runner/Assets.xcassets/AppIcon.appiconset/**
  frontend/ios/Runner/Assets.xcassets/LaunchImage.imageset/**
  docs/worklog/REBRAND-ICON.md
- Agent branch: agent/REBRAND-ICON-launcher-icons, created from logic-exploitation (b28bca6a)

## Decisions taken
- Rendered PNGs from master vectors (`docs/design/waddify/app-icon.svg` and `docs/design/waddify/mark-mono.svg`) using `rsvg-convert` (v2.63.2).
- Android adaptive icon: configured `mipmap-anydpi-v26/ic_launcher.xml` with background color `#10233F` (`@color/ic_launcher_background` in `values/colors.xml`), foreground vector drawable in `drawable/ic_launcher_foreground.xml` (white bird + Nile Light `#2FB5B3` tail + Sun `#F2A541` beak, fitted within the 66 dp safe zone of the 108 dp canvas), and monochrome vector drawable in `drawable/ic_launcher_monochrome.xml` from `mark-mono.svg` for Android 13+ themed icons.
- Android legacy icons: rendered `app-icon.svg` to 48x48 (mdpi), 72x72 (hdpi), 96x96 (xhdpi), 144x144 (xxhdpi), and 192x192 (xxxhdpi) in `mipmap-*dpi/ic_launcher.png`.
- Android notification icon: created `drawable/ic_stat_notification.xml` as a 24x24 dp vector drawable silhouette from `mark-mono.svg` (wings + head, tail dropped for under 24 dp per ADR-0029 §5) in pure white `#FFFFFFFF` on transparent background.
- iOS app icons: rendered `app-icon.svg` to all 15 sizes specified in `Contents.json` (including 1024x1024 with no alpha channel in RGB mode).
- Splash screen: configured Ink (`#10233F`) background with centered white mark from `mark-mono.svg` in `drawable/launch_background.xml`, `drawable-v21/launch_background.xml` (pointing to `splash_mark` bitmap), generated `splash_mark.png` in drawable density buckets (mdpi..xxxhdpi), and updated `LaunchImage.imageset` (1x, 2x, 3x) with centered white mark on transparent background.

## Changes per commit (message only — NO SHAs)
1. `REBRAND-ICON: android adaptive and legacy launcher icons, notification icon`
2. `REBRAND-ICON: iOS app icons from 1024px master`
3. `REBRAND-ICON: Android and iOS splash with Ink background and white mark`

## Verification
- `file` on every generated PNG (verified sizes match the specification table).
- `flutter build apk --debug` — PASS (built successfully in 14.0s).
- `make check` — PASS (scoped gate stamped for commit).

## Unverified
- Owner device check: the icon on a light and a dark launcher, themed icon on Android 13+, notification icon in the status bar, splash on cold start (requires physical Android/iOS devices).

## Follow-ups / out-of-lane findings
- `LaunchScreen.storyboard` (iOS) has backgroundColor `#0D1321` (the old navy). It was left untouched as it is outside the task lane. `LaunchImage.imageset` renders a centered white mark seamlessly on dark background.

## Open questions
- none
