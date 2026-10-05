#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
cd "$project_dir"
# Create/reuse the identity before building; never fall back to ad-hoc signing.
"$project_dir/scripts/sign-dev.sh" --setup
swift build -c release
binary_dir="$(swift build -c release --show-bin-path)"
app_dir="$project_dir/dist/Melty Windows.app"
mkdir -p "$app_dir/Contents/MacOS"
cp "$binary_dir/MeltyWindows" "$app_dir/Contents/MacOS/MeltyWindows"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Melty Windows</string>
<key>CFBundleDisplayName</key><string>Melty Windows</string>
<key>CFBundleIdentifier</key><string>org.melty.windows</string>
<key>CFBundleExecutable</key><string>MeltyWindows</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>CFBundleShortVersionString</key><string>0.1.14</string>
<key>CFBundleVersion</key><string>15</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>LSUIElement</key><true/>
<key>NSHighResolutionCapable</key><true/>
<key>NSScreenCaptureUsageDescription</key><string>Check a small patch around a left click so dragging an empty background can move its window. Images are never saved.</string>
</dict></plist>
PLIST
fixture_dir="$app_dir/Contents/Helpers/Gesture Test.app"
mkdir -p "$fixture_dir/Contents/MacOS"
cp "$binary_dir/MeltyWindows" "$fixture_dir/Contents/MacOS/MeltyWindows"
cat > "$fixture_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>Melty Window Test</string>
<key>CFBundleIdentifier</key><string>org.melty.windows.fixture</string>
<key>CFBundleExecutable</key><string>MeltyWindows</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>26.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
"$project_dir/scripts/sign-dev.sh" "$fixture_dir" "$app_dir"
print -r -- "$app_dir"
