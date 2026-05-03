#!/usr/bin/env bash
# Builds an iOS IPA with compile-time Matrix + homeserver defines.
# Without --dart-define-from-file, MATRIX_PUSH_* are empty and TestFlight builds
# will not register a Sygnal pusher (Android local testing may still mislead).
set -euo pipefail
cd "$(dirname "$0")/.."
DEFINES_FILE="${1:-dart_defines/inve.json}"
if [[ ! -f "$DEFINES_FILE" ]]; then
  echo "Missing defines file: $DEFINES_FILE" >&2
  echo "Copy dart_defines/inve.example.json and pass the path, e.g.:" >&2
  echo "  tool/build_ipa.sh dart_defines/inve.json" >&2
  exit 1
fi
exec flutter build ipa --dart-define-from-file="$DEFINES_FILE"
