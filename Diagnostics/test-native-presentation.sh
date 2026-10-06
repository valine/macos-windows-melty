#!/bin/zsh
set -euo pipefail
project_dir="${0:A:h:h}"
python_executable="${1:?Pass the absolute path to a MeltyGUI Python executable}"
output_dir="${2:?Pass an output directory for captures and isolated app state}"
mkdir -p "$output_dir"
output_dir="${output_dir:A}"
xcrun clang -O2 -fobjc-arc -dynamiclib -framework AppKit -framework ScreenCaptureKit \
    -framework CoreMedia -framework CoreVideo "$project_dir/Diagnostics/PresentationCapture.m" \
    -o "$output_dir/PresentationCapture.dylib"
export XDG_STATE_HOME="$output_dir/state" XDG_CACHE_HOME="$output_dir/cache"
export XDG_CONFIG_HOME="$output_dir/config" MELTY_FILE_META="$output_dir/meta"
candidate=()
if [[ -n "${3:-}" ]]; then candidate=("$3"); fi
"$python_executable" "$project_dir/Diagnostics/native-presentation.py" \
    "$output_dir/PresentationCapture.dylib" "$output_dir/captures.jsonl" "${candidate[@]}"
