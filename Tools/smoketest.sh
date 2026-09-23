#!/bin/bash
# Compiles the shipping Core layer for macOS and runs it against a live
# Wordflow server (default http://localhost:8099), verifying the request
# bodies, response decoding, and Go timestamp parsing end to end.
set -euo pipefail
cd "$(dirname "$0")/.."

# NOTE: the newest CLT SDK (MacOSX27) ships SwiftUI's @State/@Binding as macros
# whose plugin (libSwiftUIMacros) only exists inside Xcode, which is not
# installed. MacOSX26.5 still declares them as property wrappers, so it is the
# SDK that can actually type-check SwiftUI here.
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"
OUT="${TMPDIR:-/tmp}/wordflow-smoketest"

swiftc -O \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -swift-version 5 \
  -o "$OUT" \
  TemporalWordflow/Core/*.swift \
  Tools/SmokeTest/main.swift

"$OUT" "$@"
