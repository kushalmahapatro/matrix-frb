#!/usr/bin/env bash
# Regenerates Dart + Rust FRB glue from sdk/rust (run after changing api/ or bridge types).
set -euo pipefail
cd "$(dirname "$0")/../rust"
exec flutter_rust_bridge_codegen generate
