#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
swift build --package-path "$project_root/macos" -c release
app_path="$project_root/build/Vaani.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$project_root/macos/.build/release/Vaani" "$app_path/Contents/MacOS/Vaani"
cp "$project_root/macos/Info.plist" "$app_path/Contents/Info.plist"
codesign --force --sign "${VAANI_SIGN_IDENTITY:--}" --identifier dev.vaani.mac "$app_path"
printf '%s\n' "$app_path"
