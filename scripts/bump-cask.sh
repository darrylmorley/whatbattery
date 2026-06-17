#!/usr/bin/env bash
# Bump the Homebrew cask in the homebrew-whatbattery tap to a new release.
#
# Usage:
#   scripts/bump-cask.sh <version> <zip-path>
#
# Configuration (via env or .env):
#   TAP_DIR              Path to the homebrew-whatbattery repo. Required.
#   CASK_AUTOPUSH        If "1", run `git push` after committing. Default: 0.
#   CASK_VERIFY_REMOTE   If "1", download the asset the cask points at and verify
#                        its sha256 matches the local zip before committing.
#   CASK_VERIFY_STRICT   If "1" and CASK_VERIFY_REMOTE=1, treat a 404 (asset not
#                        yet uploaded) as a hard error rather than a warning.
#
# Skipped silently if TAP_DIR is unset, so build-app.sh can call it always.
set -euo pipefail

VERSION="${1:-}"
ZIP_PATH="${2:-}"

if [[ -z "${VERSION}" || -z "${ZIP_PATH}" ]]; then
    echo "usage: $0 <version> <zip-path>" >&2
    exit 1
fi

if [[ -z "${TAP_DIR:-}" ]]; then
    echo "==> TAP_DIR not set, skipping cask bump"
    echo "    Set TAP_DIR in .env (e.g. TAP_DIR=\$HOME/Projects/personal/homebrew-whatbattery)"
    exit 0
fi

if [[ ! -d "${TAP_DIR}" ]]; then
    echo "==> TAP_DIR=${TAP_DIR} does not exist, skipping cask bump" >&2
    exit 0
fi

CASK_FILE="${TAP_DIR}/Casks/whatbattery.rb"
if [[ ! -f "${CASK_FILE}" ]]; then
    echo "==> Cask file ${CASK_FILE} not found, skipping cask bump" >&2
    exit 0
fi

if [[ ! -f "${ZIP_PATH}" ]]; then
    echo "==> Zip ${ZIP_PATH} not found, cannot compute sha256" >&2
    exit 1
fi

NEW_SHA=$(shasum -a 256 "${ZIP_PATH}" | awk '{print $1}')

echo "==> Bumping cask to ${VERSION}"
echo "    sha256: ${NEW_SHA}"

if [[ "${CASK_VERIFY_REMOTE:-0}" == "1" ]]; then
    REMOTE_URL="https://github.com/darrylmorley/whatbattery/releases/download/v${VERSION}/WhatBattery.zip"
    echo "==> Verifying remote asset at ${REMOTE_URL}"
    HTTP_CODE=$(curl -sLI -o /dev/null -w "%{http_code}" "${REMOTE_URL}" || echo "000")
    if [[ "${HTTP_CODE}" != "200" ]]; then
        if [[ "${CASK_VERIFY_STRICT:-0}" == "1" ]]; then
            echo "    ERROR: remote asset returned HTTP ${HTTP_CODE}" >&2
            exit 1
        fi
        echo "    Remote returned HTTP ${HTTP_CODE}, release likely not published yet. Skipping verify."
    else
        TMP_ZIP=$(mktemp -t whatbattery-cask-verify.XXXXXX).zip
        trap 'rm -f "${TMP_ZIP}"' EXIT
        curl -sL -o "${TMP_ZIP}" "${REMOTE_URL}"
        REMOTE_SHA=$(shasum -a 256 "${TMP_ZIP}" | awk '{print $1}')
        if [[ "${REMOTE_SHA}" != "${NEW_SHA}" ]]; then
            echo "    ERROR: sha mismatch between local zip and uploaded asset" >&2
            echo "      local:  ${NEW_SHA}" >&2
            echo "      remote: ${REMOTE_SHA}" >&2
            exit 1
        fi
        echo "    Remote sha matches local. Proceeding."
    fi
fi

if sed --version >/dev/null 2>&1; then
    SED_INPLACE=(sed -i)
else
    SED_INPLACE=(sed -i '')
fi

"${SED_INPLACE[@]}" -E "s/^  version \".*\"/  version \"${VERSION}\"/" "${CASK_FILE}"
"${SED_INPLACE[@]}" -E "s/^  sha256 \".*\"/  sha256 \"${NEW_SHA}\"/" "${CASK_FILE}"

cd "${TAP_DIR}"
if git diff --quiet -- Casks/whatbattery.rb; then
    echo "==> Cask already at ${VERSION} with this sha256, nothing to commit"
    exit 0
fi

git add Casks/whatbattery.rb
git commit -m "WhatBattery ${VERSION}"
echo "==> Committed cask bump in ${TAP_DIR}"

if [[ "${CASK_AUTOPUSH:-0}" == "1" ]]; then
    echo "==> Pushing tap"
    git push
else
    echo "    (set CASK_AUTOPUSH=1 in .env to push automatically)"
fi
