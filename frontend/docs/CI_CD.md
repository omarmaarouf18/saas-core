# CI/CD Pipeline & Hot-Swap Sync Architecture

This document describes the automated synchronization and build pipeline linking the primary development repository ([omarmaarouf18/saas-core](https://github.com/omarmaarouf18/saas-core)) to the standalone mobile frontend repository ([omarmaarouf18/quick-delivery-mobile](https://github.com/omarmaarouf18/quick-delivery-mobile)).

---

## 1. Architecture Overview (Hot-Swap Sync Model)

To avoid manual copy-pasting between repositories while maintaining a clean, standalone repository for Flutter mobile development, the platform uses an automated two-stage pipeline:

```
[saas-core] (frontend/ directory)
     │
     │  Push to `main` touching `frontend/**`
     ▼
[.github/workflows/sync-mobile-frontend.yml] (in saas-core)
     │  1. `git subtree split --prefix=frontend`
     │  2. `git push ... quick-delivery-mobile main --force`
     ▼
[quick-delivery-mobile] (main branch updated)
     │
     │  Push to `main`
     ▼
[.github/workflows/build-apk.yml] (in quick-delivery-mobile)
     │  1. `subosito/flutter-action` (Flutter 3.44.6, pinned)
     │  2. `flutter build apk --release` (universal) and
     │     `flutter build apk --release --split-per-abi`, both with
     │     `--build-number=<run number>`, API_BASE_URL and APP_VERSION
     │  3. `actions/upload-artifact@v4` + GitHub release + app-release.json
     ▼
[Artifact app-release-<sha>: app-armeabi-v7a-release.apk,
 app-arm64-v8a-release.apk, app-x86_64-release.apk, app-release.apk (universal)]
```

---

## 2. Stage 1: Auto-Sync Pipeline (`saas-core` -> `quick-delivery-mobile`)

* **Source Workflow**: `.github/workflows/sync-mobile-frontend.yml` in `omarmaarouf18/saas-core`.
* **Triggers**:
  - `push` events to `main` only (as of commit fd545fc — previously also triggered on `logic-exploitation`, which allowed unreviewed feature-branch code to reach the public mobile app; this was a release-discipline bug, now fixed).
  - Manual trigger: `workflow_dispatch`.
  - Path-scoped filter: `paths: ["frontend/**"]` (only runs when files under `frontend/` change).

### Mechanics
1. **Subtree Extraction**: The workflow runs `git subtree split --prefix=frontend` to isolate commit history for the `frontend/` directory, rewriting commit paths so `frontend/` contents sit at the root of the resulting commit tree.
2. **Force-Push Mirror**: The isolated commit tree is force-pushed to the `main` branch of `omarmaarouf18/quick-delivery-mobile` using the `MOBILE_REPO_PAT` secret (Personal Access Token with `repo` scope on `quick-delivery-mobile`).
3. **Failure Isolation**: If either subtree extraction or git push fails, the workflow fails loudly with a non-zero exit code and clear diagnostic log entries.

> [!WARNING]
> Because `quick-delivery-mobile` is a downstream push mirror, any commits pushed directly to `quick-delivery-mobile`'s `main` branch will be overwritten during the next sync. All mobile app changes must originate in `saas-core`.

---

## 3. Stage 2: Auto-Build Pipeline (`quick-delivery-mobile`)

* **Target Workflow**: `.github/workflows/build-apk.yml` in `omarmaarouf18/quick-delivery-mobile`.
* **Triggers**:
  - `push` events to `main` (triggered automatically whenever Stage 1 lands a sync commit).
  - `workflow_dispatch` (manual trigger via GitHub Actions UI).

### Execution Steps
1. **Environment Setup**:
   - Checkout code via `actions/checkout@v4`.
   - Set up Java JDK 17 (Temurin distribution) via `actions/setup-java@v4`.
   - Set up Flutter **3.44.6** via `subosito/flutter-action@v2` (`flutter-version: '3.44.6'`, the same pin as saas-core CI in `.github/workflows/ci.yml`; bump both together, and regenerate goldens in the same change).
2. **Dependency Resolution**:
   - Executes `flutter pub get`.
   - **Firebase config (push)**: decodes the repository secret `GOOGLE_SERVICES_JSON_B64` into `android/app/google-services.json` (never committed) and checks it is the config for `com.saascore.frontend`. Without the secret the build still succeeds with push disabled, and the run summary says "push disabled in this build". See [PUSH.md](PUSH.md).
3. **Version** (ADR-0018):
   - `version` = the semver part of `pubspec.yaml` `version:` (2.0.0); `build_number` = `github.run_number`; `full_version` = `<version>+<build_number>` (e.g. `2.0.0+57`).
   - `full_version` is compiled in with `--dart-define=APP_VERSION=...` and sent by the app as `X-App-Version` (`lib/core/app_version.dart`). The api-gateway gate strips the `+build` part, so only the semver is compared with `minimum_supported_version`.
4. **Release Compilation** (both with `--build-number=${{ github.run_number }}`, `--dart-define=API_BASE_URL=...` and `--dart-define=APP_VERSION=...`):
   - `flutter build apk --release`: the **universal** APK (all three ABIs, ~60 MB), kept as `build/universal/app-release.apk`.
   - `flutter build apk --release --split-per-abi`: one APK per ABI, `app-armeabi-v7a-release.apk` (~19 MB), `app-arm64-v8a-release.apk` (~21 MB, most phones) and `app-x86_64-release.apk` (~23 MB, emulators / x86 Chromebooks).
   - `API_BASE_URL` defaults to `https://api.logiclinkeg.tech/api/v1` if the repository variable `vars.API_BASE_URL` is not set.
   - **Version-code rule**: the universal APK's Android version code is the build number `n`; Flutter gives each split APK an ABI offset (armeabi-v7a `1000 + n`, arm64-v8a `2000 + n`, x86_64 `4000 + n`). Android refuses to install a lower version code over a higher one ("App not installed"), so a phone that installed a split cannot take the universal APK of any earlier, current or (until `n` passes the offset) later run.
   - **One channel**: the default download (`apk_url` on the website) and the in-app update (api-gateway `download_url`, `releases/latest/download/app-release.apk`) are always the **universal** `app-release.apk`. Split APKs are for manual install only, and a phone that installed a split must keep installing splits of the same ABI. Guarded twice: the workflow's jq check refuses to publish an `app-release.json` whose `apk_url` is not the universal file, and saas-core `scripts/test_apk_channel.sh` (run by `make check`) checks `build-apk.yml` and the gateway default.
5. **Artifact Upload**: `actions/upload-artifact@v4` attaches the three split APKs and the universal `app-release.apk` as artifact `app-release-<short_sha>`.
6. **GitHub Release**: tag `app-release-<short_sha>` on `omarmaarouf18/quick-delivery-mobile` with all four APKs. `app-release.apk` keeps the pre-2.0 single-APK name, so `releases/latest/download/app-release.apk` (the api-gateway default `download_url` and the app's fallback link) always installs on any phone.
7. **Website** (`omarmaarouf18/logiclink`, GitHub App token): writes `app-release.json`:
   ```json
   {
     "version": "2.0.0",
     "full_version": "2.0.0+57",
     "build_number": "57",
     "build_sha": "<short_sha>",
     "apk_url": "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/download/app-release-<sha>/app-release.apk",
     "apk_urls": {
       "armeabi-v7a": ".../app-armeabi-v7a-release.apk",
       "arm64-v8a": ".../app-arm64-v8a-release.apk",
       "x86_64": ".../app-x86_64-release.apk",
       "universal": ".../app-release.apk"
     },
     "build_date": "<UTC ISO date>",
     "size_mb": "<universal APK size>"
   }
   ```
   `apk_url` is the universal `app-release.apk`, the same file as `apk_urls.universal` and the in-app update (see the version-code rule in step 4); the per-ABI `apk_urls` are optional smaller downloads for manual install. `apk_urls` and `full_version` / `build_number` are new in 2.0.0.
8. **Job Summary**: version, artifact name, short commit SHA, target API Base URL, and the one-channel note for the website team.

---

## 4. Downloading Build Artifacts

1. Navigate to [omarmaarouf18/quick-delivery-mobile/actions](https://github.com/omarmaarouf18/quick-delivery-mobile/actions), or the **Releases** page.
2. Select the latest **Build Android APK** workflow run.
3. Scroll down to the **Artifacts** section and download `app-release-<sha>`.
4. Install `app-release.apk` (universal): it is what the website and the in-app update hand out, so later updates install over it. Install a split (`app-arm64-v8a-release.apk` on a current phone, `app-armeabi-v7a-release.apk` on an old 32-bit phone) only on a phone that will keep getting split APKs of the same ABI by hand; it cannot take the universal update.

---

## 5. Manually Re-Triggering Builds & Syncs

* **Manually Re-Build APK**:
  Navigate to **Actions** -> **Build Android APK** -> click **Run workflow** -> select branch `main`.
* **Manually Sync Frontend**:
  Trigger a manual dispatch via `workflow_dispatch` (e.g. `gh workflow run sync-mobile-frontend.yml --ref logic-exploitation`) to manually sync from any feature branch for testing purposes, or push a commit to `main` touching any file in `frontend/` in `saas-core` for automatic production release sync.

---

## 6. Troubleshooting

Both stages fail fast (typically under 20 seconds) and print an explicit
`Error: ...` line rather than a stack trace, which makes the runs easy to
misread as "still starting" when they have actually already failed. Always
check the **last step** of the failed job first (`Push to quick-delivery-mobile`
for Stage 1, `Build Release APK` for Stage 2) before assuming a deeper issue.

### Stage 1 (`sync-mobile-frontend.yml`) failures

| Log line | Cause | Fix |
|---|---|---|
| `Error: MOBILE_REPO_PAT secret is missing or empty.` | The `MOBILE_REPO_PAT` repository secret was never added (or was deleted) in `saas-core` → Settings → Secrets and variables → Actions. | Create a fine-grained PAT scoped to `quick-delivery-mobile` with `Contents: Read and write` (or a classic token with `repo` scope), then add it as `MOBILE_REPO_PAT` under **Repository secrets** — not **Variables**. |
| `remote: Repository not found.` / `fatal: repository '...quick-delivery-mobile.git/' not found` | The `PAT` is valid, but the target repository `omarmaarouf18/quick-delivery-mobile` does not exist yet on GitHub. | Create an **empty** repository named exactly `quick-delivery-mobile` under the same account (do not initialize it with a README/.gitignore/license — the first sync force-pushes a full tree and an unrelated initial commit can conflict with that history). Then re-run the workflow. |
| `remote: Permission to ... denied` / `403` | The PAT exists and the target repo exists, but the token's scope/permissions don't include write access to that specific repository. | Regenerate the PAT with explicit write access to `quick-delivery-mobile` (fine-grained: `Contents: Read and write`; classic: `repo`), update the `MOBILE_REPO_PAT` secret value, re-run. |
| `Error: git subtree split produced an empty commit SHA.` | No commits touching `frontend/**` exist on the branch being split, or the checkout used `fetch-depth` that's too shallow. | Confirm the workflow uses `fetch-depth: 0` on checkout (already the default in this workflow) and that the triggering push actually modified files under `frontend/`. |
| `remote: Permission ... denied to github-actions[bot]` even after confirming the PAT has correct write permissions | The `actions/checkout@v4` step defaults to `persist-credentials: true`, which injects the job's ephemeral `GITHUB_TOKEN` as a global git credential (`http.https://github.com/.extraheader`) for all of `github.com`. This silently overrides the `MOBILE_REPO_PAT` embedded in the later `git push` URL — the PAT is never actually used, which is why regenerating it repeatedly does not help. | Add `persist-credentials: false` to the `Checkout Repository` step's `with:` block. |
| `fatal: could not read Password for 'https://***@github.com'` | After fixing `persist-credentials`, using a bare `https://${MOBILE_REPO_PAT}@github.com/...` URL is treated by git as a username with no password, which requires a TTY prompt that doesn't exist on a runner. | Use the `x-access-token` prefix: `https://x-access-token:${MOBILE_REPO_PAT}@github.com/...`. |
| `remote: Invalid username or token. Password authentication is not supported for Git operations.` | The PAT itself is invalid — expired, revoked, or corrupted at creation/copy time (confirm by calling `curl -H "Authorization: Bearer $TOKEN" https://api.github.com/user`; a real token returns your account JSON, an invalid one returns `{"message":"Bad credentials"}` with HTTP 401). This is unrelated to workflow configuration. | Generate a brand-new PAT (a classic token with the `repo` scope is simplest), verify it independently against `https://api.github.com/user` *before* setting it as a secret, then update `MOBILE_REPO_PAT`. Never paste a raw token into a chat, ticket, or log — treat any token that was ever displayed in plaintext as compromised and revoke it immediately at https://github.com/settings/tokens. |

### Stage 2 (`build-apk.yml`) failures

| Symptom | Cause | Fix |
|---|---|---|
| Workflow never starts on `quick-delivery-mobile` after a successful sync | `push` trigger only fires on `main`; confirm Stage 1 actually force-pushed to `main` and not a differently-named branch. | Check `quick-delivery-mobile`'s default branch is `main`, and re-run Stage 1 if it pushed elsewhere. |
| Build fails during `flutter build apk --release` with a network/dependency error | Transient Flutter/pub.dev outage, or a version mismatch introduced in `pubspec.yaml`. | Re-run the job (Actions -> failed run -> **Re-run failed jobs**); if it persists, reproduce locally with `flutter clean && flutter pub get && flutter build apk --release`. |
| App installs but can't reach the backend | `API_BASE_URL` (repo variable) isn't set, so the workflow silently falls back to the default `https://api.logiclinkeg.tech/api/v1` baked into `build-apk.yml`. This is only correct if that domain is actually pointed at the production server and Caddy has a valid certificate for it. | Set the `API_BASE_URL` repository variable in `quick-delivery-mobile` -> Settings -> Secrets and variables -> Actions -> Variables if a different backend target is needed, or confirm the default domain is live per `docs/DEPLOYMENT.md`. |

### Frontend build (Android compileSdk) failures

| Symptom | Cause | Fix |
|---|---|---|
| `Execution failed for task ':file_picker:checkReleaseAarMetadata'` / `:file_picker is currently compiled against android-34` | A Flutter plugin (e.g. `flutter_plugin_android_lifecycle`) requires `compileSdk 36+`, but another plugin (`file_picker`) in the dependency tree is compiled against an older API level. Naively bumping `file_picker` to a version that supports SDK 36 (e.g. `^11.0.2`) can trigger a *separate* pub version-solving conflict, because newer `file_picker` releases depend on `web: ^1.1.0`, which is incompatible with `web_socket_channel: ^2.4.5` and `firebase_messaging`'s transitive `web: ^0.5.x` constraint. | Keep `file_picker` pinned at `^8.0.7` (the last version pub resolves cleanly against the rest of the dependency tree) and instead force every Android Gradle subproject — including plugin modules — to compile against SDK 36 directly in `frontend/android/build.gradle.kts`:<br>`subprojects { afterEvaluate { extensions.findByType<com.android.build.gradle.BaseExtension>()?.let { it.compileSdkVersion(36) } } }`<br>This resolves the AAR metadata mismatch without touching the dependency tree at all. |

### General diagnostic steps
1. Open the failed run directly (`Actions` tab on the relevant repo) and read the last expanded step first — the failure message is almost always explicit, not buried in a stack trace.
2. If reading logs isn't convenient in-browser, download the log archive from the run page (`⚙ menu -> Download log archive`) and inspect the numbered step file matching the red ❌ step.
3. Re-run only after fixing the underlying secret/permission/repo issue — re-running without a fix reproduces the same failure.
