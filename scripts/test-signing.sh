#!/bin/zsh
# Exercise macOS's actual requirement evaluator across different binaries.
set -euo pipefail
project_dir="${0:A:h:h}"
mkdir -p "$project_dir/.build"
test_dir="$(mktemp -d "$project_dir/.build/signing-test.XXXXXX")"
trap 'rm -rf -- "$test_dir"' EXIT
trap 'exit 130' INT
trap 'exit 143' TERM
app_dir="$test_dir/Signing Probe.app"
mkdir -p "$app_dir/Contents/MacOS"
cat > "$app_dir/Contents/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleIdentifier</key><string>org.melty.signing-probe</string>
<key>CFBundleExecutable</key><string>SigningProbe</string>
<key>CFBundlePackageType</key><string>APPL</string>
</dict></plist>
PLIST

build_variant() {
    cat > "$test_dir/main.c" <<SOURCE
#include <stdio.h>
int main(void) { puts("build $1"); return 0; }
SOURCE
    /usr/bin/clang "$test_dir/main.c" -o "$app_dir/Contents/MacOS/SigningProbe"
    "$project_dir/scripts/sign-dev.sh" "$app_dir"
}

build_variant 1
first_hash="$(/usr/bin/shasum -a 256 "$app_dir/Contents/MacOS/SigningProbe")"
first_requirement="$(/usr/bin/codesign -d -r- "$app_dir" 2>/dev/null)"
requirement="${first_requirement#designated => }"
if [[ "$requirement" != *'certificate leaf = H"'* || "$requirement" == *cdhash* ]]; then
    print -u2 -- "Expected a certificate-bound identity, got: $requirement"
    exit 1
fi

build_variant 2
second_hash="$(/usr/bin/shasum -a 256 "$app_dir/Contents/MacOS/SigningProbe")"
second_requirement="$(/usr/bin/codesign -d -r- "$app_dir" 2>/dev/null)"
[[ "$first_hash" != "$second_hash" ]]
[[ "$first_requirement" == "$second_requirement" ]]
/usr/bin/codesign --verify --deep --strict -R "=$requirement" "$app_dir"
print -- "PASS: different binaries share the same certificate-bound identity."

/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier org.melty.signing-probe.other' "$app_dir/Contents/Info.plist"
"$project_dir/scripts/sign-dev.sh" "$app_dir"
if /usr/bin/codesign --verify -R "=$requirement" "$app_dir" 2>/dev/null; then
    print -u2 -- "FAIL: a different app matched the original app's identity."
    exit 1
fi
print -- "PASS: another app signed with the same certificate cannot inherit its identity."

/usr/libexec/PlistBuddy -c 'Set :CFBundleIdentifier org.melty.signing-probe' "$app_dir/Contents/Info.plist"
/usr/bin/codesign --force --sign - "$app_dir"
if /usr/bin/codesign --verify -R "=$requirement" "$app_dir" 2>/dev/null; then
    print -u2 -- "FAIL: ad-hoc code matched the certificate-bound identity."
    exit 1
fi
print -- "PASS: an ad-hoc binary with the same bundle ID cannot impersonate the signed app."
