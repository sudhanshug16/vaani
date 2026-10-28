#!/bin/zsh
# Install an already-built app over SSH. Does not quit or launch the user's app.
set -euo pipefail
project_root="${0:A:h:h}"
host="${1:?Usage: scripts/deploy-macos.sh ssh-host}"
app_path="$project_root/build/Vaani.app"
codesign --verify --deep --strict "$app_path"
archive=$(mktemp -t vaani-deploy)
trap 'rm -f "$archive"' EXIT
ditto -c -k --sequesterRsrc --keepParent "$app_path" "$archive"
scp -o BatchMode=yes -o ConnectTimeout=10 "$archive" "$host:Downloads/Vaani-install.zip"
ssh -o BatchMode=yes -o ConnectTimeout=10 "$host" /bin/zsh -s <<'REMOTE'
set -euo pipefail
stage=$(mktemp -d /Applications/.Vaani-install.XXXXXX)
trap 'rm -rf "$stage"' EXIT
ditto -x -k "$HOME/Downloads/Vaani-install.zip" "$stage"
codesign --verify --deep --strict "$stage/Vaani.app"
backup_root="$HOME/Library/Application Support/Vaani/backups"
mkdir -p "$backup_root"
backup="$backup_root/Vaani-$(date +%Y%m%d-%H%M%S)-$$.app"
if [[ -e /Applications/Vaani.app ]]; then
    mv /Applications/Vaani.app "$backup"
fi
if ! mv "$stage/Vaani.app" /Applications/Vaani.app; then
    if [[ -e "$backup" ]]; then mv "$backup" /Applications/Vaani.app; fi
    exit 1
fi
codesign --verify --deep --strict /Applications/Vaani.app
shasum -a 256 /Applications/Vaani.app/Contents/MacOS/Vaani
printf 'Installed: /Applications/Vaani.app\nOpen Vaani again to use the installed build.\n'
REMOTE
