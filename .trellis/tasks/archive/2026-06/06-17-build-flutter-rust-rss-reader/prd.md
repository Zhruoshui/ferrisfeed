# Build Flutter Rust RSS Reader

## Goal

Build a cross-platform RSS reader with Flutter UI and Rust core logic via flutter_rust_bridge.

## What I already know

* The repo is currently a flutter_rust_bridge sample: `lib/main.dart` only calls Rust `greet("Tom")`, and Rust only exposes `greet` plus `init_app`.
* The project already has Flutter platform folders and FRB-generated bindings.
* The README currently mentions Linux, Android, and Web support, plus the extra web headers needed for FRB.
* `doc/oksskolten` is a much richer RSS reader reference, but it is React + Node + SQLite, not the target stack.
* Oksskolten is still useful as a product reference for reader flows, article views, settings, and feed management.

## Assumptions

* The first version should be local-first unless the user wants remote sync or a server backend.
* Rust should own feed parsing, storage, and domain logic.
* Flutter should own navigation, layout, and interaction.
* v1 is explicitly an MVP and should prioritize reading and feed management over advanced features.

## Open Questions

* Which platforms must the MVP support on day one?

## Requirements

* Cross-platform Flutter app with Rust-backed domain logic.
* Manual feed add flow.
* Feed list, article list, article detail, and read-state actions.
* Bookmark or favorite action for saved reading.
* Local persistence for subscriptions and article state.
* Basic refresh / fetch flow.
* Scope stays local-first and offline-friendly where practical.

## Acceptance Criteria

* App launches and shows a working RSS reader UI for the agreed MVP platforms.
* Rust exposes real reader APIs through FRB instead of the sample `greet` API.
* A user can add a feed, fetch articles, open an article, and mark it read end to end.
* A user can save article state locally and see it after relaunch.

## Out of Scope

* Full Oksskolten parity.
* Remote account sync unless explicitly requested.
* AI summary / translation.
* Auth, remote backend, and cloud sync.
* Full-text extraction from arbitrary web pages beyond the feed payload, unless needed later.

## Technical Notes

* Current sample files:
  * `lib/main.dart`
  * `lib/src/rust/api/simple.dart`
  * `rust/src/lib.rs`
  * `rust/src/api/simple.rs`
* Reference project:
  * `doc/oksskolten/docs/spec/01_overview.md`
  * `doc/oksskolten/docs/spec/02_architecture.md`
  * `doc/oksskolten/docs/spec/50_frontend.md`
  * `doc/oksskolten/README.md`
* Relevant constraints:
  * FRB web requires COOP/COEP headers for Chrome/web usage.
  * The current codebase is still the FRB hello-world scaffold.
