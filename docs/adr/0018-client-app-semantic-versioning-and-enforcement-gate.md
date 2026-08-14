# ADR-0018: Client Application Semantic Versioning & Version-Gating Middleware

* **Status**: Accepted
* **Date**: 2026-08-14
* **Deciders**: Architecture Team, Mobile Lead, Security Lead
* **Technical Area**: Cross-cutting / Mobile Version Control & API Gateway Middleware

---

## 1. Context & Problem Statement

Prior to this architectural addition, zero app version control or compatibility enforcement existed across the platform:
1. `frontend/pubspec.yaml` retained a static, never-bumped `version: 1.0.0+1`.
2. Mobile APK releases published via `build-apk.yml` to `logiclinc` used short git commit SHAs in the `"version"` field rather than semantic versioning (`MAJOR.MINOR.PATCH`).
3. Microservices across the backend had zero visibility into which client versions were communicating with the API.
4. When breaking API changes or database migrations occurred, legacy installed clients could crash or transmit corrupt payloads without any mechanism to force users to upgrade.

A unified version management architecture was required to establish semantic versioning discipline, track live releases, enforce minimum supported version gating at the API Gateway level, and provide a seamless client upgrade flow.

---

## 2. Decision Outcome & Architecture

We adopted an end-to-end version control architecture spanning CI/CD pipelines, MongoDB persistence, API Gateway middleware enforcement, and Flutter client interception.

```
┌─────────────────────────┐          ┌──────────────────────────┐          ┌──────────────────────────┐
│  pubspec.yaml (semver)  │ ───────► │ build-apk.yml (workflow) │ ───────► │ app-release.json (site) │
└─────────────────────────┘          └──────────────────────────┘          └──────────────────────────┘
             │                                                                           │
             ▼                                                                           │
┌─────────────────────────┐          ┌──────────────────────────┐                        │
│   Flutter ApiClient     │ ───────► │   api-gateway            │                        │
│ (X-App-Version: 1.0.0)  │          │   VersionGate Middleware │                        │
└─────────────────────────┘          └──────────────────────────┘                        │
             │                                    │                                      │
             │                                    ▼                                      │
             │                      ┌──────────────────────────┐                         │
             │                      │ platform_versions (Mongo)│                         │
             │                      └──────────────────────────┘                         │
             │                                    │                                      │
             │ HTTP 426 (if semver < min)        │                                      │
             └────────────────────────────────────┘                                      │
             │                                                                           │
             ▼                                                                           ▼
┌─────────────────────────┐                                                ┌──────────────────────────┐
│ UpdateRequiredScreen    │ ─────────────────────────────────────────────► │ APK Download URL         │
└─────────────────────────┘                                                └──────────────────────────┘
```

### 2.1 Real Semantic Versioning (CI/CD Pipeline)
* `frontend/pubspec.yaml`'s `version: MAJOR.MINOR.PATCH+build` is established as the single canonical source of truth for the client application.
* Bumps follow semver rules:
  * **MAJOR**: Breaking API payload changes or schema migrations requiring mandatory client upgrade.
  * **MINOR**: New features, new screens, or backwards-compatible API additions.
  * **PATCH**: Bug fixes, styling updates, and performance optimizations.
* The `.github/workflows/build-apk.yml` build script extracts `version` from `pubspec.yaml` and publishes `app-release.json` containing:
  ```json
  {
    "version": "1.0.0",
    "build_sha": "ed2afc4",
    "apk_url": "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/download/app-release-ed2afc4/app-release.apk",
    "build_date": "2026-08-14T10:36:00Z",
    "size_mb": "42"
  }
  ```

### 2.2 Version Registry & MongoDB Persistence
* Created MongoDB collection `platform_versions` (document `_id: "global"`) managed by `api-gateway`:
  * `latest_version`: The newest released client version (e.g. `"1.2.0"`).
  * `minimum_supported_version`: The lowest client version permitted to communicate with backend APIs (e.g. `"1.0.0"`).
  * `enforce_minimum_version`: Boolean flag enabling or disabling version enforcement.
  * `download_url`: Canonical download link for updated APKs.
* Admin Management Endpoints:
  * `GET /api/v1/admin/version-config`: Fetches current version configuration.
  * `PUT /api/v1/admin/version-config`: Authenticated admin endpoint (`X-Internal-Token`) to dynamically update minimum/latest version bounds without restarting microservices.

### 2.3 API Gateway `VersionGate` Middleware & Safe Rollout Path
* `middleware.VersionGate` intercepts incoming HTTP requests at `api-gateway`:
  1. **Bypass Paths**: Bypasses `/health`, `/health/internal`, `/api/v1/admin/version-config`, and root `/`.
  2. **Header Ingestion**: Reads `X-App-Version` header from incoming requests.
  3. **Safe Rollout Policy**:
     * If `X-App-Version` header is missing and `enforce_minimum_version == false` (rollout grace period mode): Request is allowed through without blocking.
     * If `X-App-Version` header is missing and `enforce_minimum_version == true`: Request is rejected with `426 Upgrade Required`.
  4. **Semver Evaluation**: Parses client version using zero-dependency semver logic (`version.ParseSemVer`) stripping build metadata (e.g. `1.0.0+1` → `1.0.0`).
  5. **Enforcement Block**: If `clientSemver < minimumSupportedSemver` AND `enforce_minimum_version == true`:
     Responds immediately with HTTP `426 Upgrade Required` and JSON:
     ```json
     {
       "error": "app_update_required",
       "message": "A required app update is available. Please update to continue using Quick Delivery.",
       "minimum_version": "1.1.0",
       "latest_version": "1.2.0",
       "current_version": "1.0.0",
       "download_url": "https://github.com/omarmaarouf18/quick-delivery-mobile/releases/latest/download/app-release.apk"
     }
     ```

### 2.4 Flutter Client Header & Global Interception
* `ApiClient` in `frontend/lib/core/api_client.dart`:
  * Automatically injects `X-App-Version` header into all HTTP requests (`get`, `post`, `put`, `patch`, `postMultipart`, `getBytes`).
  * Intercepts HTTP `426 Upgrade Required` responses globally in `_handleResponse()`.
  * Triggers `onUpdateRequired` callback, displaying `UpdateRequiredScreen` (`frontend/lib/screens/update_required_screen.dart`).
* `UpdateRequiredScreen`:
  * Non-dismissible UI (`PopScope(canPop: false)`) displaying installed vs minimum required version details and a direct "Update Now" action button pointing to `download_url`.

---

## 3. Verification & Compliance

1. **Go Unit Tests (`api-gateway`)**:
   * `version.ParseSemVer` unit tests (`semver_test.go`) covering semver parsing, build metadata stripping, and version comparison logic (`1.0.0 < 1.0.1 < 1.1.0 < 2.0.0`).
   * `middleware.VersionGate` integration tests (`version_gate_test.go`) verifying missing header grace period, enforcement rejection (426), semver comparison, and bypass paths.
2. **Flutter Widget & Unit Tests**:
   * `api_client_version_test.dart`: Verifies `X-App-Version` header management.
   * `update_required_screen_test.dart`: Verifies `UpdateRequiredScreen` rendering and button interactions.
3. **Automated Pipeline Checks**:
   * `make ci` exit code 0 across all Go microservices.
   * `flutter analyze` 0 issues and `flutter test` 100% pass (191/191 tests).
