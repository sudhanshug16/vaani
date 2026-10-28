#!/bin/zsh
set -euo pipefail
project_root="${0:A:h:h}"
cd "$project_root/android"
if [[ -x ./gradlew ]]; then
  ./gradlew assembleDebug
elif command -v gradle >/dev/null; then
  gradle assembleDebug
else
  print -u2 'Open android/ in Android Studio, or install Gradle 8.13 and run gradle wrapper first.'
  exit 1
fi
