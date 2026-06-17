#!/usr/bin/env bash
# Generates scripts/AppIcon.icns from the battery.100percent.circle SF Symbol.
# Run this any time the icon design changes; the resulting .icns is checked in
# so smoke-test.sh can copy it without needing Swift at build time.
set -euo pipefail

cd "$(dirname "$0")/.."

ICONSET="dist/AppIcon.iconset"
OUT="scripts/AppIcon.icns"

rm -rf "${ICONSET}"
mkdir -p "${ICONSET}"

# size_on_disk : filename
declare -a SIZES=(
    "16:icon_16x16.png"
    "32:icon_16x16@2x.png"
    "32:icon_32x32.png"
    "64:icon_32x32@2x.png"
    "128:icon_128x128.png"
    "256:icon_128x128@2x.png"
    "256:icon_256x256.png"
    "512:icon_256x256@2x.png"
    "512:icon_512x512.png"
    "1024:icon_512x512@2x.png"
)

for entry in "${SIZES[@]}"; do
    size="${entry%%:*}"
    name="${entry##*:}"
    swift scripts/generate-icon.swift "${size}" "${ICONSET}/${name}"
done

iconutil -c icns "${ICONSET}" -o "${OUT}"
rm -rf "${ICONSET}"

echo "Wrote ${OUT}"
