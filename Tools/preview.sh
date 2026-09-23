#!/bin/bash
# Renders the shipping SwiftUI screens to PNG off-screen, driving the real
# AppStore against a live Wordflow server. Stands in for a simulator on a
# machine that has no Xcode.
#
# Usage: ./Tools/preview.sh [output-directory]
set -euo pipefail
cd "$(dirname "$0")/.."

SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"
OUT_BIN="${TMPDIR:-/tmp}/wordflow-preview"
OUT_DIR="${1:-$PWD/preview}"

# TemporalWordflowApp.swift carries @main, which would collide with the tool's
# own top-level entry point.
SOURCES=$(find TemporalWordflow -name '*.swift' ! -name 'TemporalWordflowApp.swift' | sort)

swiftc \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -swift-version 5 \
  -o "$OUT_BIN" \
  $SOURCES \
  Tools/Preview/main.swift

"$OUT_BIN" "$OUT_DIR"
