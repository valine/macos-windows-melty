#!/bin/zsh
set -euo pipefail
cd "${0:A:h:h}"
probe_dir=$(mktemp -d /tmp/melty-frame-test.XXXXXX)
trap 'rm -rf "$probe_dir"' EXIT
xcrun clang -fobjc-arc -framework AppKit Native/MeltySurfaceFrame.m \
    Diagnostics/SurfaceFrameTests.m -o "$probe_dir/SurfaceFrameTests"
"$probe_dir/SurfaceFrameTests"
