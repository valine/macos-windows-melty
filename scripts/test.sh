#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
swift_compiler="$(xcrun --find swiftc)"
testing_macros="${swift_compiler:h:h}/lib/swift/host/plugins/testing/libTestingMacros.dylib"
test_args=(--disable-xctest)
# The macOS 27 CLT Swift build system can omit TestingMacros on incremental
# builds. Load the toolchain's own plugin explicitly when it is available.
if [[ -f "$testing_macros" ]]; then
    test_args+=(-Xswiftc -load-plugin-library -Xswiftc "$testing_macros")
fi
swift test "${test_args[@]}"
