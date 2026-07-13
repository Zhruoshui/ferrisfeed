# Fix Flutter emulator run failure

## Goal

Make `fvm flutter run -d emulator-5554` build and launch the app on the Android emulator, preserving existing project behavior.

## What I already know

* The failing command is `fvm flutter run -d emulator-5554`.
* This is a Flutter project using FVM.
* The likely scope is build/runtime configuration or code reached during Android startup.

## Assumptions (temporary)

* The emulator `emulator-5554` is available from this environment.
* The desired fix should be local to this repository unless the error proves to be an external SDK/emulator setup issue.
* Existing uncommitted user changes must be preserved.

## Open Questions

* None currently; reproduce the failure first.

## Requirements

* Reproduce the reported failure from the requested command.
* Identify the root cause from logs rather than guessing.
* Apply the smallest repository change needed to make the command succeed, if the failure is in repo code/config.
* If the failure is environmental, report the exact external action needed instead of changing unrelated files.

## Acceptance Criteria

* [ ] `fvm flutter run -d emulator-5554` no longer fails for the original error, or the remaining blocker is clearly external and documented.
* [ ] `fvm flutter analyze` is run when code/config changes are made.
* [ ] Existing user work is not reverted.

## Definition of Done

* Lint/typecheck passes where applicable.
* The fix is scoped to the failing command.
* Any relevant project convention learned during debugging is considered for spec updates.

## Out of Scope

* Broad UI changes.
* Refactoring unrelated startup, Rust bridge, or platform registration code.
* Fixing unrelated pre-existing warnings unless they block the run command.

## Technical Notes

* Initial command to reproduce: `fvm flutter run -d emulator-5554`.
