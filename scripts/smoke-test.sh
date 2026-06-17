#!/usr/bin/env bash
# Build, assemble, sign, and smoke-test WhatBattery.app.
#
# This is the day-to-day verification script. It assembles a real .app bundle
# (which the menu bar app and notifications need: UNUserNotificationCenter
# aborts when run as a bare binary), embeds the widget, ad-hoc signs, and runs
# an alive-after-2s check plus CLI checks.
#
# It does NOT notarise or touch any Homebrew tap; that is the distribution
# phase. For local "eyes on" testing, run this then `open dist/WhatBattery.app`.
#
# Modes:
#   - No DEVELOPER_ID set: ad-hoc signed (runs locally; widget App Group data
#     sharing won't work, but the app and notifications do).
#   - DEVELOPER_ID set:    Developer ID signed + hardened runtime (real App
#     Group sharing; ready for notarisation later).
#
# Configure via .env if you have one.
set -euo pipefail

cd "$(dirname "$0")/.."

# Load .env if present
if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a; source .env; set +a
fi

APP_NAME="WhatBattery"
BUNDLE_ID="app.whatbattery.whatbattery"
VERSION="0.1.0"
BUILD_NUMBER="1"
MIN_OS="14.0"
CLI_PRODUCT="whatbattery-cli"
CLI_BIN_NAME="whatbattery"

DEVELOPER_ID="${DEVELOPER_ID:-}"

DIST_DIR="dist"
APP_DIR="${DIST_DIR}/${APP_NAME}.app"
CONTENTS_DIR="${APP_DIR}/Contents"
MACOS_DIR="${CONTENTS_DIR}/MacOS"
HELPERS_DIR="${CONTENTS_DIR}/Helpers"
RESOURCES_DIR="${CONTENTS_DIR}/Resources"
PLUGINS_DIR="${CONTENTS_DIR}/PlugIns"
ENTITLEMENTS="scripts/${APP_NAME}.entitlements"
WIDGET_ENTITLEMENTS="scripts/WhatBatteryWidget.entitlements"
WIDGET_APPEX="WhatBatteryWidget.appex"

echo "==> Running tests"
swift test

echo "==> Cleaning previous build"
rm -rf "${DIST_DIR}"
mkdir -p "${MACOS_DIR}" "${HELPERS_DIR}" "${RESOURCES_DIR}" "${PLUGINS_DIR}"

# Apple Silicon only (see SPEC), so a single arm64 slice, not universal.
echo "==> Building release binaries (arm64)"
swift build -c release --product "${APP_NAME}" --arch arm64
swift build -c release --product "${CLI_PRODUCT}" --arch arm64

BIN_PATH=$(swift build -c release --product "${APP_NAME}" --arch arm64 --show-bin-path)
cp "${BIN_PATH}/${APP_NAME}" "${MACOS_DIR}/${APP_NAME}"
# The CLI lives in Helpers/, not MacOS/. macOS filesystems are case-insensitive
# by default, so "whatbattery" next to "WhatBattery" would silently overwrite
# the menu bar binary. Helpers/ avoids the collision and is where Apple expects
# bundled non-launch executables to live.
cp "${BIN_PATH}/${CLI_PRODUCT}" "${HELPERS_DIR}/${CLI_BIN_NAME}"

echo "==> Building widget extension (xcodebuild)"
if command -v xcodegen &>/dev/null; then
    xcodegen generate --quiet
elif [[ ! -d "WhatBatteryWidget.xcodeproj" ]]; then
    echo "    ERROR: xcodegen not installed and WhatBatteryWidget.xcodeproj not found." >&2
    echo "    Install with: brew install xcodegen" >&2
    exit 1
fi

xcodebuild build -project WhatBatteryWidget.xcodeproj -scheme WhatBatteryWidget \
    -configuration Release \
    -destination 'platform=macOS' \
    CODE_SIGNING_ALLOWED=NO \
    ARCHS="arm64" ONLY_ACTIVE_ARCH=NO \
    MARKETING_VERSION="${VERSION}" \
    CURRENT_PROJECT_VERSION="${BUILD_NUMBER}" \
    -quiet

WIDGET_BUILD_DIR=$(xcodebuild -project WhatBatteryWidget.xcodeproj -scheme WhatBatteryWidget \
    -configuration Release -showBuildSettings 2>/dev/null \
    | grep ' BUILD_DIR = ' | awk '{print $NF}')
cp -R "${WIDGET_BUILD_DIR}/Release/${WIDGET_APPEX}" "${PLUGINS_DIR}/${WIDGET_APPEX}"
echo "    Widget embedded at ${PLUGINS_DIR}/${WIDGET_APPEX}"

echo "==> Verifying binaries"
lipo -archs "${MACOS_DIR}/${APP_NAME}" | sed 's/^/    app: /'
lipo -archs "${HELPERS_DIR}/${CLI_BIN_NAME}" | sed 's/^/    cli: /'
lipo -archs "${PLUGINS_DIR}/${WIDGET_APPEX}/Contents/MacOS/WhatBatteryWidget" | sed 's/^/    widget: /'

echo "==> Copying app icon"
if [[ -f "scripts/AppIcon.icns" ]]; then
    cp "scripts/AppIcon.icns" "${RESOURCES_DIR}/AppIcon.icns"
    ICON_KEY='    <key>CFBundleIconFile</key>
    <string>AppIcon</string>'
else
    echo "    no scripts/AppIcon.icns yet - bundling without an icon"
    ICON_KEY=''
fi

echo "==> Writing Info.plist"
# LSUIElement=true: a menu bar / accessory app with no Dock icon.
cat > "${CONTENTS_DIR}/Info.plist" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDevelopmentRegion</key>
    <string>en</string>
    <key>CFBundleExecutable</key>
    <string>${APP_NAME}</string>
${ICON_KEY}
    <key>CFBundleIdentifier</key>
    <string>${BUNDLE_ID}</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>${APP_NAME}</string>
    <key>CFBundleDisplayName</key>
    <string>${APP_NAME}</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>${VERSION}</string>
    <key>CFBundleVersion</key>
    <string>${BUILD_NUMBER}</string>
    <key>LSApplicationCategoryType</key>
    <string>public.app-category.utilities</string>
    <key>LSMinimumSystemVersion</key>
    <string>${MIN_OS}</string>
    <key>LSUIElement</key>
    <true/>
    <key>NSHumanReadableCopyright</key>
    <string>© $(date +%Y) Darryl Morley</string>
    <key>NSHighResolutionCapable</key>
    <true/>
</dict>
</plist>
PLIST

printf "APPL????" > "${CONTENTS_DIR}/PkgInfo"

# Strip macOS metadata sidecars before signing. AppleDouble (._*) and .DS_Store
# files can appear any time the OS touches the bundle; if present at sign time
# they get sealed into the manifest and later trip codesign --verify --strict.
echo "==> Stripping macOS metadata sidecars (._* and .DS_Store)"
find "${APP_DIR}" -name "._*" -delete 2>/dev/null || true
find "${APP_DIR}" -name ".DS_Store" -delete 2>/dev/null || true

# Sign inner bundles before the outer app: signing the outer first then touching
# a nested bundle invalidates the outer signature.
if [[ -n "${DEVELOPER_ID}" ]]; then
    echo "==> Signing with Developer ID + hardened runtime"
    codesign --force --options runtime --timestamp --sign "${DEVELOPER_ID}" \
        "${HELPERS_DIR}/${CLI_BIN_NAME}"
    codesign --force --options runtime --timestamp \
        --entitlements "${WIDGET_ENTITLEMENTS}" --sign "${DEVELOPER_ID}" \
        "${PLUGINS_DIR}/${WIDGET_APPEX}"
    codesign --force --options runtime --timestamp \
        --entitlements "${ENTITLEMENTS}" --sign "${DEVELOPER_ID}" \
        "${APP_DIR}"
else
    echo "==> Ad-hoc signing (no DEVELOPER_ID set)"
    codesign --force --sign - "${HELPERS_DIR}/${CLI_BIN_NAME}"
    codesign --force --entitlements "${WIDGET_ENTITLEMENTS}" --sign - \
        "${PLUGINS_DIR}/${WIDGET_APPEX}"
    codesign --force --entitlements "${ENTITLEMENTS}" --sign - \
        "${APP_DIR}"
fi

echo "==> Verifying signature"
codesign --verify --deep --strict --verbose=2 "${APP_DIR}" 2>&1 | sed 's/^/    /'

echo "==> Smoke-testing main binary (must stay alive as a GUI app, not exit immediately)"
"${MACOS_DIR}/${APP_NAME}" >/dev/null 2>&1 &
SMOKE_PID=$!
sleep 2
if kill -0 "${SMOKE_PID}" 2>/dev/null; then
    echo "    main binary alive after 2s - looks like a GUI app"
    kill "${SMOKE_PID}" 2>/dev/null || true
    wait "${SMOKE_PID}" 2>/dev/null || true
else
    echo "    ERROR: ${MACOS_DIR}/${APP_NAME} exited within 2s. The menu bar binary" >&2
    echo "    should stay running. Check for a case-insensitive FS collision that" >&2
    echo "    overwrote it with the CLI, or a crash on launch." >&2
    exit 1
fi

echo "==> Smoke-testing CLI binary (--version)"
CLI_VERSION_OUTPUT=$("${HELPERS_DIR}/${CLI_BIN_NAME}" --version 2>&1 | tr -d '[:space:]')
if [[ -z "${CLI_VERSION_OUTPUT}" ]]; then
    echo "    ERROR: CLI --version printed nothing." >&2
    exit 1
fi
echo "    CLI reports ${CLI_VERSION_OUTPUT}"

# Exercise the JSON path: it hits the IOKit / SMC read end to end, so a crash
# here catches a deployed-context regression the unit tests can't.
if ! "${HELPERS_DIR}/${CLI_BIN_NAME}" --json >/dev/null 2>&1; then
    echo "    ERROR: CLI --json exited non-zero." >&2
    exit 1
fi
echo "    CLI --json runs cleanly"

echo "==> Creating zip"
( cd "${DIST_DIR}" && ditto --norsrc -c -k --keepParent "${APP_NAME}.app" "${APP_NAME}.zip" )

echo
echo "Done."
echo "  App:     ${APP_DIR}"
echo "  CLI:     ${HELPERS_DIR}/${CLI_BIN_NAME} (inside the bundle)"
echo "  App zip: ${DIST_DIR}/${APP_NAME}.zip"
echo
echo "For eyes-on testing, launch the bundle so notifications work:"
echo "  open ${APP_DIR}"
