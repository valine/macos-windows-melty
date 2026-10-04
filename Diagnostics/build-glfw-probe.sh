#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
probe_dir="$project_dir/dist/GLFW Resize Probe.app"
glfw_lib="/Users/lukas/Desktop/testapp/.venv/lib/python3.12/site-packages/glfw/libglfw.3.dylib"
mkdir -p "$probe_dir/Contents/MacOS" "$probe_dir/Contents/Frameworks"
cp "$glfw_lib" "$probe_dir/Contents/Frameworks/libglfw.3.dylib"
clang -fobjc-arc -framework AppKit -framework OpenGL "$project_dir/Diagnostics/GLFWResizeProbe.m" "$glfw_lib" -Wl,-rpath,@executable_path/../Frameworks -o "$probe_dir/Contents/MacOS/GLFWResizeProbe"
cat > "$probe_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?><!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd"><plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.melty.windows.glfw-probe</string>
<key>CFBundleName</key><string>GLFW Resize Probe</string>
<key>CFBundleExecutable</key><string>GLFWResizeProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
codesign --force --sign - "$probe_dir/Contents/Frameworks/libglfw.3.dylib"
codesign --force --sign - "$probe_dir"
