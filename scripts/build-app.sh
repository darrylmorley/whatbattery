#!/usr/bin/env bash
# Full release build: smoke-test.sh (build, sign, notarise, staple, verify, zip)
# then bump the Homebrew cask. Called by scripts/release.sh.
#
# For day-to-day verification builds that should NOT touch the tap, run
# scripts/smoke-test.sh directly instead. Configure via .env.
set -euo pipefail

cd "$(dirname "$0")/.."

# smoke-test.sh handles: .env loading, tests, build, sign, notarise, staple,
# Gatekeeper verify, alive checks, and zip creation.
./scripts/smoke-test.sh

# Reload .env for TAP_DIR etc. in this shell.
if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a; source .env; set +a
fi

# Version constant set at the top of smoke-test.sh (patched by release.sh).
VERSION=$(grep -E '^VERSION=' scripts/smoke-test.sh | head -1 | sed -E 's/VERSION="(.*)"/\1/')

if [[ -x "scripts/bump-cask.sh" ]]; then
    echo "==> Bumping Homebrew cask (no-op unless TAP_DIR is set)"
    ./scripts/bump-cask.sh "${VERSION}" "dist/WhatBattery.zip" || \
        echo "    cask bump failed (non-fatal)"
fi
