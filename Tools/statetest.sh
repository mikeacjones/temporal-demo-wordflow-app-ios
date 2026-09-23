#!/bin/bash
# Compiles the shipping Core layer (including AppStore) for macOS and drives a
# complete play session against a live Wordflow server.
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"
OUT="${TMPDIR:-/tmp}/wordflow-statetest"

swiftc -O \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -swift-version 5 \
  -o "$OUT" \
  TemporalWordflow/Core/*.swift \
  Tools/StateTest/main.swift

"$OUT" "$@"
