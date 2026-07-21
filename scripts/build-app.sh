#!/bin/zsh
# Build and optionally install MiControlApp.app
# Usage:
#   ./scripts/build-app.sh              # release + install to /Applications
#   ./scripts/build-app.sh --no-install # only write dist/MiControlApp.app
#   ./scripts/build-app.sh --universal  # arm64 + x86_64 fat binary
#   CONFIGURATION=debug ./scripts/build-app.sh
set -euo pipefail

ROOT="${0:A:h:h}"
CONFIGURATION="${CONFIGURATION:-release}"
APP_NAME="MiControlApp"
DISPLAY_NAME="MiControlApp"
BUNDLE_ID="com.jiamid.MiControlApp"
OUTPUT_DIR="$ROOT/dist"
APP_DIR="$OUTPUT_DIR/$DISPLAY_NAME.app"
INSTALL_DIR="/Applications/$DISPLAY_NAME.app"
INFO_PLIST="$ROOT/Resources/Info.plist"

UNIVERSAL=0
INSTALL=1
for arg in "$@"; do
  case "$arg" in
    --universal) UNIVERSAL=1 ;;
    --no-install) INSTALL=0 ;;
    -h|--help)
      sed -n '2,8p' "$0"
      exit 0
      ;;
    *) print -u2 "unknown argument: $arg"; exit 1 ;;
  esac
done

cd "$ROOT"

# --- sanity checks -----------------------------------------------------------
[[ -f "$INFO_PLIST" ]] || { print -u2 "missing $INFO_PLIST"; exit 1; }
[[ -f "$ROOT/Package.swift" ]] || { print -u2 "missing Package.swift"; exit 1; }

plist_exec="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleExecutable' "$INFO_PLIST" 2>/dev/null || true)"
plist_id="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleIdentifier' "$INFO_PLIST" 2>/dev/null || true)"
if [[ -n "$plist_exec" && "$plist_exec" != "$APP_NAME" ]]; then
  print -u2 "Info.plist CFBundleExecutable ($plist_exec) != APP_NAME ($APP_NAME)"
  exit 1
fi
if [[ -n "$plist_id" && "$plist_id" != "$BUNDLE_ID" ]]; then
  print -u2 "Info.plist CFBundleIdentifier ($plist_id) != expected ($BUNDLE_ID)"
  exit 1
fi

copy_resource() {
  local src="$1" dst="$2"
  if [[ -e "$src" ]]; then
    ditto --norsrc --noextattr --noqtn --noacl "$src" "$dst"
  else
    print -u2 "skip missing resource: $src"
  fi
}

# --- build -------------------------------------------------------------------
print "building $APP_NAME ($CONFIGURATION)…"
if [[ "$UNIVERSAL" -eq 1 ]]; then
  xcrun swift build -c "$CONFIGURATION" --triple arm64-apple-macosx11.0
  ARM64_BIN_DIR="$(xcrun swift build -c "$CONFIGURATION" --triple arm64-apple-macosx11.0 --show-bin-path)"
  xcrun swift build -c "$CONFIGURATION" --triple x86_64-apple-macosx11.0
  X86_64_BIN_DIR="$(xcrun swift build -c "$CONFIGURATION" --triple x86_64-apple-macosx11.0 --show-bin-path)"

  UNIVERSAL_BIN="$ROOT/.build/universal-$CONFIGURATION/$APP_NAME"
  mkdir -p "${UNIVERSAL_BIN:h}"
  lipo -create -output "$UNIVERSAL_BIN" \
    "$ARM64_BIN_DIR/$APP_NAME" \
    "$X86_64_BIN_DIR/$APP_NAME"
  BIN_PATH="$UNIVERSAL_BIN"
else
  xcrun swift build -c "$CONFIGURATION"
  BIN_PATH="$(xcrun swift build -c "$CONFIGURATION" --show-bin-path)/$APP_NAME"
fi

[[ -x "$BIN_PATH" ]] || { print -u2 "built binary missing: $BIN_PATH"; exit 1; }

# --- package .app ------------------------------------------------------------
case "$APP_DIR" in
  "$ROOT/dist/"*.app) ;;
  *) print -u2 "refusing to clean unexpected app path: $APP_DIR"; exit 1 ;;
esac
rm -rf -- "$APP_DIR"
mkdir -p "$APP_DIR/Contents/MacOS" "$APP_DIR/Contents/Resources"

ditto --norsrc --noextattr --noqtn --noacl \
  "$BIN_PATH" "$APP_DIR/Contents/MacOS/$APP_NAME"
strip -S -x "$APP_DIR/Contents/MacOS/$APP_NAME"

copy_resource "$INFO_PLIST" "$APP_DIR/Contents/Info.plist"
copy_resource "$ROOT/LICENSE" "$APP_DIR/Contents/Resources/LICENSE"
copy_resource "$ROOT/README.md" "$APP_DIR/Contents/Resources/README.md"
copy_resource "$ROOT/THIRD_PARTY_NOTICES.md" "$APP_DIR/Contents/Resources/THIRD_PARTY_NOTICES.md"
copy_resource "$ROOT/COPYRIGHT" "$APP_DIR/Contents/Resources/COPYRIGHT"
copy_resource "$ROOT/Resources/MiControlApp-remote.png" \
  "$APP_DIR/Contents/Resources/MiControlApp-remote.png"
copy_resource "$ROOT/Resources/AppIcon.icns" \
  "$APP_DIR/Contents/Resources/AppIcon.icns"

# --- codesign ----------------------------------------------------------------
# Prefer a stable local identity so Accessibility / Input Monitoring survive rebuilds.
# Ad-hoc (`-`) changes CDHash every build and resets TCC.
PREFERRED_IDENTITY="MiControlApp Local"
# Existing local codesign cert (by hash) — same CDHash family as prior installs.
LEGACY_LOCAL_CERT_HASH="8879DC8B78E4F8DACB67A80691A19E576E4E64C1"
SIGN_IDENTITY="-"
if security find-identity -v -p codesigning 2>/dev/null | grep -F "$PREFERRED_IDENTITY" | grep -vq CSSMERR; then
  SIGN_IDENTITY="$PREFERRED_IDENTITY"
elif security find-identity -v -p codesigning 2>/dev/null | grep -Fi "$LEGACY_LOCAL_CERT_HASH" | grep -vq CSSMERR; then
  SIGN_IDENTITY="$LEGACY_LOCAL_CERT_HASH"
fi
print "codesign identity: $SIGN_IDENTITY"
codesign --force --deep --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$APP_DIR"
codesign --verify --deep --strict "$APP_DIR"

# --- install -----------------------------------------------------------------
if [[ "$INSTALL" -eq 1 ]]; then
  if pgrep -f "/$DISPLAY_NAME.app/Contents/MacOS/$APP_NAME" >/dev/null 2>&1; then
    print "stopping running $DISPLAY_NAME…"
    pkill -f "/$DISPLAY_NAME.app/Contents/MacOS/$APP_NAME" 2>/dev/null || true
    sleep 0.5
  fi

  # Remove superseded installs that would leave a second menu-bar icon.
  rm -rf -- "$INSTALL_DIR"
  rm -rf -- "/Applications/小米遥控器桥接.app"

  ditto --norsrc --noextattr --noqtn --noacl "$APP_DIR" "$INSTALL_DIR"
  codesign --force --deep --sign "$SIGN_IDENTITY" --identifier "$BUNDLE_ID" "$INSTALL_DIR"
  codesign --verify --deep --strict "$INSTALL_DIR"
  print "installed: $INSTALL_DIR"
  print "bundle id: $BUNDLE_ID"
fi

print "$APP_DIR"
