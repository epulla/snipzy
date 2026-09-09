#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-Snipzy}"
CONFIGURATION="${CONFIGURATION:-release}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_PATH="${APP_PATH:-$DIST_DIR/$APP_NAME.app}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"

if ! command -v swift >/dev/null 2>&1; then
    printf 'error: swift executable not found\n' >&2
    exit 127
fi

if [[ ! -f "$INFO_PLIST" ]]; then
    printf 'error: missing bundle metadata: %s\n' "$INFO_PLIST" >&2
    exit 1
fi

BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --show-bin-path)"
swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --product "$APP_NAME"
BIN_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
    printf 'error: built executable not found: %s\n' "$BIN_PATH" >&2
    exit 1
fi

/bin/rm -rf "$APP_PATH"
/bin/mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
/usr/bin/install -m 755 "$BIN_PATH" "$APP_PATH/Contents/MacOS/$APP_NAME"
/bin/cp "$INFO_PLIST" "$APP_PATH/Contents/Info.plist"
/usr/bin/plutil -insert CFBundleExecutable -string "$APP_NAME" "$APP_PATH/Contents/Info.plist"
/usr/bin/codesign --force --deep --sign - "$APP_PATH"

printf 'Created %s\n' "$APP_PATH"
