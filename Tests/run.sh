#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
build_dir="$(mktemp -d "${TMPDIR:-/tmp}/touch-up-tests.XXXXXX")"
trap 'rm -rf "$build_dir"' EXIT
xcrun clang -fobjc-arc -fmodules -I . -I TouchUpCore \
  -framework AppKit -framework CoreGraphics \
  Tests/DrawingModeTests.m TouchUpCore/TUCTouchInputManager.m \
  TouchUpCore/TUCCursorUtilities.m TouchUpCore/TUCTouch.m TouchUpCore/TUCScreen.m \
  -o "$build_dir/drawing-mode-tests"
"$build_dir/drawing-mode-tests"
xcrun clang -I TouchUpCore -framework IOKit -framework CoreFoundation -framework CoreGraphics \
  Tests/HIDQueueFailureTests.c -o "$build_dir/hid-queue-failure-tests"
"$build_dir/hid-queue-failure-tests"
xcrun swiftc 'Touch Up/PermissionController.swift' Tests/PermissionTests.swift -o "$build_dir/permission-tests"
"$build_dir/permission-tests"

xcrun swiftc 'Touch Up/RestartController.swift' Tests/RestartTests.swift -o "$build_dir/restart-tests"
"$build_dir/restart-tests"

xcrun clang -fsanitize=address,undefined -g -I TouchUpCore \
  -framework IOKit -framework CoreFoundation -framework CoreGraphics \
  Tests/HIDParserTests.c -o "$build_dir/hid-parser-tests"
"$build_dir/hid-parser-tests"
