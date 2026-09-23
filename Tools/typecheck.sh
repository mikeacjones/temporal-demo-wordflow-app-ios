#!/bin/bash
# Whole-app compile gate, standing in for an Xcode build.
#
# Only the Command Line Tools are installed on this machine, so there is no iOS
# SDK. Every source file is written to compile on macOS as well (iOS-only API
# sits behind the shims in Design/PlatformCompat.swift), which lets the real
# compiler — not just a parser — check the app. This compiles AND links,
# including the @main entry point, so it catches code-generation errors a
# `-typecheck` pass would miss. Warnings are errors.
set -euo pipefail
cd "$(dirname "$0")/.."

# NOTE: the newest CLT SDK (MacOSX27) ships SwiftUI's @State/@Binding as macros
# whose plugin (libSwiftUIMacros) only exists inside Xcode, which is not
# installed. MacOSX26.5 still declares them as property wrappers, so it is the
# SDK that can actually type-check SwiftUI here.
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"

FILES=$(find TemporalWordflow -name '*.swift' | sort)
OUT="${TMPDIR:-/tmp}/wordflow-appcheck"

echo "Building $(echo "$FILES" | wc -l | tr -d ' ') files against ${SDK##*/} …"
swiftc -parse-as-library \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -swift-version 5 \
  -warnings-as-errors \
  -o "$OUT" \
  $FILES
echo "OK"
