# Package Deployment and GitHub Actions Builds

## Goal

Define a reliable local Docker packaging workflow for the Flutter + Rust Web MVP that does not regress the web platform.

## What I already know

* The project is a Flutter multi-platform app with a Rust core bridged through `flutter_rust_bridge`.
* Web builds depend on generated FRB Dart bindings and generated FRB web artifacts under `web/pkg/`.
* `web/pkg/*` is ignored by Git, so CI cannot rely on checked-in web artifacts.
* `README.md` already documents that Rust / FRB code changes require `./tools/rebuild-web` before web run/build.
* `doc/ref/web-platform-fix.md` records two separate web failure modes:
  * FRB worker initialization bug fixed by pinning both Rust and Dart FRB deps to git rev `254b193`
  * FRB content hash mismatch causing white screen when Dart/Rust generated code and `web/pkg` wasm/js artifacts drift out of sync
* `./tools/rebuild-web` runs:
  * `flutter_rust_bridge_codegen generate --config-file flutter_rust_bridge.yaml`
  * `flutter_rust_bridge_codegen build-web`
* `flutter_rust_bridge.yaml` sets `auto_upgrade_dependency: false` to prevent FRB codegen from rewriting the pinned dependency back to the broken crates.io version.
* `lib/main.dart` awaits `RustLib.init()` before `runApp()`, so FRB init failures surface as a blank page before Flutter mounts UI.

## Assumptions (temporary)

* The first implementation target is local Docker packaging for the Web app only.
* Deterministic rebuilds are preferable to path-based heuristics for FRB web artifacts.
* The deployment shape should control generated artifacts and required response headers in version-controlled config.

## Open Questions

* None for the local Docker MVP.

## Requirements (evolving)

* Document whether `./tools/rebuild-web` is mandatory and under what conditions.
* Define a local Docker build that always avoids FRB hash drift and the known FRB web regression.
* Support a containerized static runtime that serves `build/web` with COOP/COEP headers.
* Document local build and run commands for the Web container.
* Call out remaining browser-side feed CORS limitations that Docker does not solve.

## Acceptance Criteria (evolving)

* [ ] The team has a clear rule for when `./tools/rebuild-web` must run.
* [ ] The local Docker build includes the required FRB/Rust/web setup steps.
* [ ] Web build plan explicitly prevents white-screen failures caused by stale FRB wasm/js artifacts.
* [ ] Web deployment config serves required cross-origin isolation headers.
* [ ] README explains how to build and run the local Web image.

## Definition of Done (team quality bar)

* Tests added/updated where appropriate
* Lint / typecheck / CI green
* Docs/notes updated if behavior changes
* Rollout/rollback considered if risky

## Out of Scope (explicit)

* GitHub Actions automation in this iteration
* Non-Web platform packaging in this iteration
* Reworking FRB architecture beyond build/deploy reliability needs

## Technical Notes

* Relevant files:
  * `tools/rebuild-web`
  * `flutter_rust_bridge.yaml`
  * `README.md`
  * `doc/ref/web-platform-fix.md`
  * `lib/main.dart`
* `web/pkg/.gitignore` ignores generated wasm/js outputs, so CI must generate them inside the workflow.

## Research References

* [`research/web-deployment-options.md`](research/web-deployment-options.md) — compares Dockerized nginx, static hosting with custom headers, and artifact-only deployment for the Web MVP.

## Feasible Approaches

**Approach A: Dockerized nginx runtime** (recommended)

* CI builds a Docker image that runs the Flutter/Rust/FRB web build sequence, copies `build/web` into nginx, and ships nginx config for SPA fallback plus COOP/COEP headers.
* This is the best fit for a self-hosted MVP because it makes generated artifacts and server headers explicit.

**Approach B: Static hosting with custom headers**

* CI builds `build/web` and deploys to a static host that supports custom response headers.
* This is simpler operationally, but header and wasm behavior become hosting-platform-specific.

**Approach C: Build artifact only**

* CI uploads `build/web` as an artifact or release asset.
* Useful as an intermediate validation step, but it does not solve production serving headers.

## Decision (ADR-lite)

**Context**: Web white-screen regressions were caused by FRB/web artifact drift and runtime header requirements. The deployment shape needs to preserve generated assets and enforce the required browser isolation headers.

**Decision**: Use Dockerized nginx as the first local Web deployment target. The container build will run the Flutter/Rust/FRB web build sequence, assemble a runtime image, and ship nginx config that serves `build/web` with SPA fallback plus COOP/COEP headers.

**Consequences**: Local deployment becomes reproducible and easier to test, but the app still inherits browser-side RSS feed CORS limitations because feed fetching happens in the client. GitHub Actions and other platforms are deferred until the local container flow is stable.
