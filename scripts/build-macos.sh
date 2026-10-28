#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
build_args=(--package-path "$project_root/macos" -c release)
if [[ -n "${VAANI_ARCH:-}" ]]; then
  [[ "$VAANI_ARCH" == arm64 || "$VAANI_ARCH" == x86_64 ]] || { print -u2 'VAANI_ARCH must be arm64 or x86_64'; exit 1; }
  build_args+=(--arch "$VAANI_ARCH")
fi
swift build "${build_args[@]}"
bin_path=$(swift build "${build_args[@]}" --show-bin-path)
app_path="$project_root/build/Vaani.app"
mkdir -p "$app_path/Contents/MacOS"
cp "$bin_path/Vaani" "$app_path/Contents/MacOS/Vaani"
cp "$project_root/macos/Info.plist" "$app_path/Contents/Info.plist"
mkdir -p "$app_path/Contents/Resources/Licenses"
ditto "$bin_path/Vaani_VaaniCore.bundle" "$app_path/Contents/Resources/Vaani_VaaniCore.bundle"
cp "$project_root/macos/ThirdParty/rnnoise/COPYING" "$app_path/Contents/Resources/Licenses/RNNoise.txt"
if [[ -n "${VAANI_VERSION:-}" ]]; then
  python3 "$project_root/scripts/release-version.py" "v$VAANI_VERSION" >/dev/null
  /usr/libexec/PlistBuddy -c "Set :CFBundleShortVersionString $VAANI_VERSION" "$app_path/Contents/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleVersion ${VAANI_VERSION_CODE:?VAANI_VERSION_CODE is required}" "$app_path/Contents/Info.plist"
fi
codesign --force --sign "${VAANI_SIGN_IDENTITY:--}" --identifier dev.vaani.mac "$app_path"
printf '%s\n' "$app_path"
