#!/usr/bin/env bash
set -euo pipefail

APP_NAME="${APP_NAME:-Snipzy}"
CONFIGURATION="${CONFIGURATION:-release}"
SCRIPT_DIR="$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd -P)"
ROOT_DIR="$(CDPATH= cd -- "$SCRIPT_DIR/.." && pwd -P)"
DIST_DIR="${DIST_DIR:-$ROOT_DIR/dist}"
APP_PATH="${APP_PATH:-$DIST_DIR/$APP_NAME.app}"
INFO_PLIST="$ROOT_DIR/Resources/Info.plist"
ICON_PNG="$ROOT_DIR/Resources/AppIcon.png"
ARCH_FLAGS=()
for arch in ${ARCHS:-}; do
    ARCH_FLAGS+=(--arch "$arch")
done

if ! command -v swift >/dev/null 2>&1; then
    printf 'error: swift executable not found\n' >&2
    exit 127
fi

if [[ ! -f "$INFO_PLIST" ]]; then
    printf 'error: missing bundle metadata: %s\n' "$INFO_PLIST" >&2
    exit 1
fi

if [[ ! -f "$ICON_PNG" ]]; then
    printf 'error: missing app icon: %s\n' "$ICON_PNG" >&2
    exit 1
fi

BIN_DIR="$(swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --show-bin-path "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}")"
swift build --package-path "$ROOT_DIR" -c "$CONFIGURATION" --product "$APP_NAME" "${ARCH_FLAGS[@]+"${ARCH_FLAGS[@]}"}"
BIN_PATH="$BIN_DIR/$APP_NAME"

if [[ ! -x "$BIN_PATH" ]]; then
    printf 'error: built executable not found: %s\n' "$BIN_PATH" >&2
    exit 1
fi

/bin/rm -rf "$APP_PATH"
/bin/mkdir -p "$APP_PATH/Contents/MacOS" "$APP_PATH/Contents/Resources"
/usr/bin/install -m 755 "$BIN_PATH" "$APP_PATH/Contents/MacOS/$APP_NAME"
/bin/cp "$INFO_PLIST" "$APP_PATH/Contents/Info.plist"
if [[ -n ${APP_VERSION:-} ]]; then
    /usr/bin/plutil -replace CFBundleShortVersionString -string "$APP_VERSION" "$APP_PATH/Contents/Info.plist"
fi
if [[ -n ${BUILD_NUMBER:-} ]]; then
    /usr/bin/plutil -replace CFBundleVersion -string "$BUILD_NUMBER" "$APP_PATH/Contents/Info.plist"
fi
/usr/bin/plutil -insert CFBundleExecutable -string "$APP_NAME" "$APP_PATH/Contents/Info.plist"
ICONSET_DIR="$(/usr/bin/mktemp -d)/AppIcon.iconset"
trap '/bin/rm -rf "$(dirname "$ICONSET_DIR")"' EXIT
/bin/mkdir -p "$ICONSET_DIR"
for size in 16 32 128 256 512; do
    /usr/bin/sips -z "$size" "$size" "$ICON_PNG" --out "$ICONSET_DIR/icon_${size}x${size}.png" >/dev/null
    /usr/bin/sips -z "$((size * 2))" "$((size * 2))" "$ICON_PNG" --out "$ICONSET_DIR/icon_${size}x${size}@2x.png" >/dev/null
done
/usr/bin/iconutil -c icns "$ICONSET_DIR" -o "$APP_PATH/Contents/Resources/AppIcon.icns"
/usr/bin/codesign --force --deep --sign - "$APP_PATH"

printf 'Created %s\n' "$APP_PATH"
