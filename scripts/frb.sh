#!/usr/bin/env bash
# Regenerate flutter_rust_bridge bindings.
#
# Run this after EVERY change under rust/src/api/** — the generated Dart/Rust
# glue files are committed and must stay in sync with the hand-written API.
set -euo pipefail

cd "$(dirname "$0")/.."

flutter_rust_bridge_codegen generate
