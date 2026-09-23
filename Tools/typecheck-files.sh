#!/bin/bash
# Type-check the shared layers plus the files named on the command line.
# Useful while other files in the tree are mid-edit; Tools/typecheck.sh is the
# whole-app gate.
set -euo pipefail
cd "$(dirname "$0")/.."

# NOTE: the newest CLT SDK (MacOSX27) ships SwiftUI's @State/@Binding as macros
# whose plugin (libSwiftUIMacros) only exists inside Xcode, which is not
# installed. MacOSX26.5 still declares them as property wrappers, so it is the
# SDK that can actually type-check SwiftUI here.
SDK="/Library/Developer/CommandLineTools/SDKs/MacOSX26.5.sdk"
[ -d "$SDK" ] || SDK="$(xcrun --show-sdk-path)"
swiftc -typecheck \
  -sdk "$SDK" \
  -target arm64-apple-macos14.0 \
  -swift-version 5 \
  TemporalWordflow/Core/*.swift \
  TemporalWordflow/Design/*.swift \
  "$@"
echo "OK"
