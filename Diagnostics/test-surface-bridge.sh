#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
if [[ $# != 1 ]]; then
    print -u2 'Usage: Diagnostics/test-surface-bridge.sh /absolute/path/to/meltygui/python'
    exit 2
fi
probe_dir=$(mktemp -d /tmp/melty-probe.XXXXXX)
trap 'rm -rf "$probe_dir"' EXIT
# Compile the same registry and server sources into an isolated diagnostic.
xcrun swiftc -emit-library -emit-module -module-name WindowBehavior \
    Sources/WindowBehavior/SurfaceClaims.swift -o "$probe_dir/libWindowBehavior.dylib" \
    -emit-module-path "$probe_dir/WindowBehavior.swiftmodule"
xcrun swiftc -I "$probe_dir" -L "$probe_dir" -lWindowBehavior \
    -Xlinker -rpath -Xlinker "$probe_dir" \
    Sources/MeltyWindows/SurfaceBridge.swift Sources/MeltyWindows/Trace.swift \
    Diagnostics/SurfaceBridgeProbe.swift -o "$probe_dir/SurfaceBridgeProbe"
"$1" Diagnostics/test-surface-bridge.py "$probe_dir/SurfaceBridgeProbe"
