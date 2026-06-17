#!/usr/bin/env bash
# Release WhatBattery end to end.
#
# Usage:
#   scripts/release.sh <version> [build-number]
#   scripts/release.sh --dry-run <version> [build-number]
#
# Steps:
#   1. Sanity checks: clean tree, on main, tag absent, gh present, release notes.
#   2. Patch VERSION / BUILD_NUMBER in scripts/smoke-test.sh; commit.
#   3. build-app.sh (build, sign, notarise, staple, verify, zip, local cask bump).
#   4. Tag v<version>, push main + tag to private.
#   5. Mirror to public (flattened commit on public main).
#   6. gh release create on the PUBLIC repo at the new public HEAD (this creates
#      the tag on public), with the zip + release notes.
#   7. Verify the uploaded asset sha matches local, then push the tap.
#   8. Close issues referenced by closing keywords since the previous tag.
#
# Differs from WhatCable's flow only in step 5: we run the manual mirror script
# rather than relying on an auto-mirror GitHub Action.
#
# --dry-run runs the sanity checks and prints each step, skipping commits, the
# build, the mirror, the release, and the tap push.
set -euo pipefail

cd "$(dirname "$0")/.."

PUBLIC_REPO="darrylmorley/whatbattery"

DRY_RUN=0
if [[ "${1:-}" == "--dry-run" ]]; then
    DRY_RUN=1
    shift
fi

VERSION="${1:-}"
BUILD_NUMBER="${2:-}"

if [[ -z "${VERSION}" ]]; then
    echo "usage: $0 [--dry-run] <version> [build-number]" >&2
    exit 1
fi

if [[ -z "${BUILD_NUMBER}" ]]; then
    CURRENT_BUILD=$(grep -E '^BUILD_NUMBER=' scripts/smoke-test.sh | head -1 | sed -E 's/.*"([0-9]+)".*/\1/')
    BUILD_NUMBER=$((CURRENT_BUILD + 1))
fi

if [[ ! "${VERSION}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
    echo "ERROR: version '${VERSION}' is not a dotted triple (e.g. 0.1.0)." >&2
    exit 1
fi

echo "==> Releasing WhatBattery v${VERSION} (build ${BUILD_NUMBER})"
[[ "${DRY_RUN}" == "1" ]] && echo "    DRY RUN: no commits, tags, builds, mirror, or release"

# ---- 1. Sanity checks ----------------------------------------------------
echo "==> Sanity checks"

if [[ -f ".env" ]]; then
    # shellcheck disable=SC1091
    set -a; source .env; set +a
fi

if ! git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    echo "ERROR: not inside a git checkout." >&2; exit 1
fi
BRANCH=$(git rev-parse --abbrev-ref HEAD)
if [[ "${BRANCH}" != "main" ]]; then
    echo "ERROR: on branch '${BRANCH}', expected 'main'." >&2; exit 1
fi
if ! git diff --quiet || ! git diff --cached --quiet; then
    echo "ERROR: working tree has uncommitted changes." >&2
    git status --short >&2; exit 1
fi
if git rev-parse "v${VERSION}" >/dev/null 2>&1; then
    echo "ERROR: tag v${VERSION} already exists locally." >&2; exit 1
fi
if git ls-remote --tags origin "v${VERSION}" | grep -q "v${VERSION}"; then
    echo "ERROR: tag v${VERSION} already exists on private origin." >&2; exit 1
fi
if ! command -v gh >/dev/null 2>&1; then
    echo "ERROR: gh CLI not found. Install it: brew install gh" >&2; exit 1
fi
if ! gh auth status >/dev/null 2>&1; then
    echo "ERROR: gh not authenticated. Run: gh auth login" >&2; exit 1
fi
NOTES_FILE="release-notes/v${VERSION}.md"
if [[ ! -f "${NOTES_FILE}" ]]; then
    echo "ERROR: ${NOTES_FILE} not found. Write the release notes first." >&2; exit 1
fi
if [[ -n "${TAP_DIR:-}" ]]; then
    if [[ ! -d "${TAP_DIR}" ]]; then
        echo "ERROR: TAP_DIR=${TAP_DIR} does not exist." >&2; exit 1
    fi
    if ! git -C "${TAP_DIR}" diff --quiet || ! git -C "${TAP_DIR}" diff --cached --quiet; then
        echo "ERROR: tap repo at ${TAP_DIR} has uncommitted changes." >&2; exit 1
    fi
fi
echo "    all checks passed"

if sed --version >/dev/null 2>&1; then
    SED_INPLACE=(sed -i)
else
    SED_INPLACE=(sed -i '')
fi

# ---- 2. Patch + commit version -------------------------------------------
echo "==> Updating VERSION=${VERSION} BUILD_NUMBER=${BUILD_NUMBER} in scripts/smoke-test.sh"
if [[ "${DRY_RUN}" == "0" ]]; then
    "${SED_INPLACE[@]}" -E "s/^VERSION=\".*\"/VERSION=\"${VERSION}\"/" scripts/smoke-test.sh
    "${SED_INPLACE[@]}" -E "s/^BUILD_NUMBER=\".*\"/BUILD_NUMBER=\"${BUILD_NUMBER}\"/" scripts/smoke-test.sh
    if ! git diff --quiet scripts/smoke-test.sh; then
        git add scripts/smoke-test.sh
        git commit -m "Bump version to ${VERSION} (build ${BUILD_NUMBER})"
    fi
fi

# ---- 3. Build ------------------------------------------------------------
if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> Running scripts/build-app.sh"
    ./scripts/build-app.sh
else
    echo "==> Would run scripts/build-app.sh (skipped in dry run)"
fi

# ---- 4. Tag + push private -----------------------------------------------
if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> Tagging v${VERSION} and pushing main + tag to private"
    git tag -a "v${VERSION}" -m "v${VERSION}"
    git push origin main
    git push origin "v${VERSION}"
fi

# ---- 5. Mirror to public -------------------------------------------------
if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> Mirroring to public ${PUBLIC_REPO}"
    MIRROR_ASSUME_YES=1 ./scripts/mirror-to-public.sh
else
    echo "==> Would mirror to public (skipped in dry run)"
fi

# ---- 6. Create the GitHub release on the PUBLIC repo ---------------------
RELEASE_TITLE_FIRST_LINE=$(head -1 "${NOTES_FILE}" | sed -E 's/^#+\s*//')
RELEASE_TITLE="v${VERSION}${RELEASE_TITLE_FIRST_LINE:+: ${RELEASE_TITLE_FIRST_LINE}}"

if [[ "${DRY_RUN}" == "0" ]]; then
    echo "==> gh release create v${VERSION} on ${PUBLIC_REPO}"
    # --target main creates the tag on public at the freshly mirrored HEAD (the
    # manual mirror pushes commits, not tags).
    gh release create "v${VERSION}" \
        dist/WhatBattery.zip \
        --repo "${PUBLIC_REPO}" \
        --target main \
        --title "${RELEASE_TITLE}" \
        --notes-file "${NOTES_FILE}"
else
    echo "==> Would create release: ${RELEASE_TITLE}"
fi

# ---- 7. Verify uploaded asset + push tap ---------------------------------
if [[ "${DRY_RUN}" == "0" && -n "${TAP_DIR:-}" ]]; then
    echo "==> Verifying remote asset sha matches local, then pushing tap"
    CASK_VERIFY_REMOTE=1 CASK_VERIFY_STRICT=1 CASK_AUTOPUSH=1 \
        ./scripts/bump-cask.sh "${VERSION}" "dist/WhatBattery.zip"
fi

# ---- 8. Close fixed issues on the public repo ----------------------------
PREV_TAG=$(git tag --list 'v*' --sort=-version:refname | grep -vxF "v${VERSION}" | head -1 || true)
if [[ -n "${PREV_TAG}" ]]; then
    FIXED_ISSUES=$(git log "${PREV_TAG}..v${VERSION}" --pretty=%B 2>/dev/null \
        | grep -ioE '(close[sd]?|fix(es|ed)?|resolve[sd]?) +#[0-9]+' \
        | grep -oE '[0-9]+' | sort -un || true)
    if [[ -n "${FIXED_ISSUES}" && "${DRY_RUN}" == "0" ]]; then
        echo "==> Closing fixed issues on ${PUBLIC_REPO} (since ${PREV_TAG})"
        for n in ${FIXED_ISSUES}; do
            STATE=$(gh issue view "${n}" --repo "${PUBLIC_REPO}" --json state --jq .state 2>/dev/null) || continue
            if [[ "${STATE}" == "OPEN" ]]; then
                gh issue close "${n}" --repo "${PUBLIC_REPO}" --comment "Fixed in v${VERSION}." >/dev/null 2>&1 \
                    && echo "    closed #${n}" || echo "    failed to close #${n}" >&2
            fi
        done
    fi
fi

echo
if [[ "${DRY_RUN}" == "1" ]]; then
    echo "Dry run complete. Re-run without --dry-run to ship v${VERSION}."
else
    echo "v${VERSION} shipped."
    echo "  GitHub:   https://github.com/${PUBLIC_REPO}/releases/tag/v${VERSION}"
    echo "  Homebrew: brew install --cask darrylmorley/whatbattery/whatbattery"
fi
