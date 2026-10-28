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
# Prefer the maintainer's permanent local identity. Never silently fall back to
# ad-hoc when this keychain exists: failure must stop deployment.
local_keychain="$HOME/Library/Application Support/Vaani/release-signing/macos-build.keychain-db"
if [[ -z "${VAANI_SIGN_IDENTITY:-}" && -f "$local_keychain" ]]; then
  VAANI_SIGN_IDENTITY='Vaani Release Signing'
  VAANI_SIGN_KEYCHAIN="$local_keychain"
fi
sign_args=(--force --sign "${VAANI_SIGN_IDENTITY:--}" --identifier dev.vaani.mac)
if [[ -n "${VAANI_SIGN_KEYCHAIN:-}" ]]; then
  sign_args+=(--keychain "$VAANI_SIGN_KEYCHAIN")
fi
codesign "${sign_args[@]}" "$app_path"
codesign --verify --deep --strict "$app_path"
printf '%s\n' "$app_path"
