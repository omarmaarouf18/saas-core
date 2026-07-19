# Documentation Changelog

This file tracks historical entries for the primary category: **Documentation Changelog**.

---

## Complaint Routing Stage 7: Documentation

- **Implementation Detail**: Documented complaint routing design and atomic assignment decisions in DESIGN.md and AI_CONTEXT.md.
- **Commit SHA**: ``46849ac88483819acc6069944c5b69a6cbaa213b``
- **Verification**: Verified via review. ✅

## Application Map

- **Implementation Detail**: Created a comprehensive reference document (docs/APPLICATION_MAP.md) detailing ports, databases, actor lifecycles, and connection flows.
- **Commit SHA**: ``ed34020c6be346ba39bd0c1fafdd09e95e9b87b2``
- **Verification**: Verified via document generation. ✅

## Document Client-Submitted Coordinates Pricing Risk

- **Implementation Detail**: Documented the risk associated with client-submitted coordinates for distance-based pricing and escrow calculations in AI_CONTEXT.md.
- **Commit SHA**: ``c7189a85c31edfafd5fd6b8fdf993584f7e01197``
- **Verification**: Verified via review of AI_CONTEXT.md. ✅

## Documentation Audit Correction

- **Implementation Detail**: Fixed six mismatches between documentation and implementation (corrected `/auth/documents/view` path and added missing `/auth/kye/upload` in `APPLICATION_MAP.md`, updated location update throttle constant in map, added target architecture disclaimer and corrected `flutter_client_sse` version in `DESIGN.md`, and consolidated `GEMINI.md` to point to `CLAUDE.md` to prevent drift).
- **Commit SHA**: ``39099f89c4d6f1673d46690976cce1559eaec622``
- **Verification**: Verified via visual review and shared/infra validation test suite. ✅

## Self-Enforcing Auto-Documentation System

- **Implementation Detail**: Built a Go-based AST parser and code generator to automatically maintain the HTTP endpoint table in `APPLICATION_MAP.md` based on `RegisterRoutes` handlers. Added automated structural checks verifying that all Dart frontend files are listed in `STATUS.md` and dependency version quotes in `DESIGN.md` match `pubspec.yaml`. Configured Makefile targets (`make docs` and `make docs-check`) and wired them into the shared unit test suite.
- **Commit SHA**: ``5d6411b500d0e5f094d6b956f75dbcb74c821643``
- **Verification**: Verified via test suite (`TestDocgenFreshness`, `TestDocgenDriftCatching`, `TestDartFilesMentionedInStatus`, and `TestPubspecDependenciesInDesignDoc`). ✅

## DESIGN.md Link Alignment

- **Implementation Detail**: Fixed stale/drifted code line-number references in DESIGN.md for Go source handlers and helper functions to prevent documentation drift and align with actual locations.
- **Commit SHA**: ``ab02e2e8d127edd4ce58bcc888ee032d763315c0``
- **Verification**: Verified via visual review and checked that docgen/structural checks pass cleanly. ✅

## Audit Report Refresh (2026-07-19)

- **Implementation Detail**: Refreshed the codebase audit documentation in `docs/audit/shared-module-review.md` and `AUDIT_REPORT.md` to reflect gosec fixes (unchecked errors, server timeouts, local storage directory traversal checks), pre-push hooks, flaky test mitigations, and new features like username validation and point-in-time chat snapshots. Verified all known open items and open risks against HEAD.
- **Commit SHA**: ``3dae5df21adc6bd1ea9e2644990248c17d1aea5b``
- **Verification**: Verified that docgen tests and changelog SHA validation tests pass cleanly. ✅





