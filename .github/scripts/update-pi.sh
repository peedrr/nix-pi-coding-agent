#!/usr/bin/env bash
# update-pi.sh — Check for new upstream Pi releases and update packages/pi/package.nix
#
# Usage: ./.github/scripts/update-pi.sh
#
# This script can be run both in CI and locally. It:
#   1. Reads the current version from packages/pi/package.nix
#   2. Queries the latest release tag from earendil-works/pi
#   3. Skips if no newer version is available
#   4. Prefetches the source archive and computes the source hash
#   5. Extracts package-lock.json from the prefetched source
#   6. Updates version, src hash, lockfile ref in package.nix
#   7. Computes npmDepsHash via fake-hash build prefetch
#   8. Vendors the new package-lock.json and cleans up old ones
#   9. Exports metadata for GitHub Actions workflow consumption

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

UPSTREAM_OWNER="earendil-works"
UPSTREAM_REPO="pi"
PI_NIX="packages/pi/package.nix"
LOCKFILE_DIR="packages/pi"

# ---------------------------------------------------------------------------
# Step 1: Detect current version from pi.nix
# ---------------------------------------------------------------------------

current_version="$(grep -oP 'version = "\K[^"]+' "${PI_NIX}")"
echo "Current version in ${PI_NIX}: ${current_version}"

# ---------------------------------------------------------------------------
# Step 2: Detect latest version from upstream (or use override)
# ---------------------------------------------------------------------------

if [[ -n "${VERSION_OVERRIDE:-}" ]]; then
  latest_version="${VERSION_OVERRIDE#v}"
  echo "Using overridden version: ${latest_version}"
else
  # Try GitHub Releases API first, optionally authenticated.
  # GITHUB_TOKEN is injected by GitHub Actions; locally it can be unset.
  api_url="https://api.github.com/repos/${UPSTREAM_OWNER}/${UPSTREAM_REPO}/releases/latest"
  if [[ -n "${GITHUB_TOKEN:-}" ]]; then
    latest_tag="$(curl -sL -H "Authorization: Bearer ${GITHUB_TOKEN}" "${api_url}" | jq -r '.tag_name // empty')"
  else
    latest_tag="$(curl -sL "${api_url}" | jq -r '.tag_name // empty')"
  fi

  # Fall back to git ls-remote if the API returns nothing.
  if [[ -z "${latest_tag}" ]]; then
    echo "GitHub API returned no tag, falling back to git ls-remote..."
    latest_tag="$(git ls-remote --tags --refs "https://github.com/${UPSTREAM_OWNER}/${UPSTREAM_REPO}.git" 'v*' \
      | awk -F/ '{print $3}' \
      | grep -E '^v[0-9]+(\.[0-9]+)*$' \
      | sort -V \
      | tail -n1)"
  fi

  if [[ -z "${latest_tag}" ]]; then
    echo "ERROR: Could not determine latest upstream version." >&2
    exit 1
  fi

  latest_version="${latest_tag#v}"
fi

echo "Latest upstream version: ${latest_version}"

# ---------------------------------------------------------------------------
# Step 3: Skip if versions are equal or candidate is older
# ---------------------------------------------------------------------------

if [[ "${current_version}" == "${latest_version}" ]]; then
  echo "Versions are equal. Nothing to do."
  echo "UPDATE_REQUIRED=false" >> "${GITHUB_ENV:-/dev/null}"
  exit 0
fi

# Ensure the candidate is strictly newer than the current version.
newest="$(printf '%s\n%s\n' "${current_version}" "${latest_version}" | sort -V | tail -n1)"
if [[ "${newest}" != "${latest_version}" ]]; then
  echo "Candidate version ${latest_version} is older than current ${current_version}. Skipping."
  echo "UPDATE_REQUIRED=false" >> "${GITHUB_ENV:-/dev/null}"
  exit 0
fi

# ---------------------------------------------------------------------------
# Step 4: Prefetch source archive and compute source hash
# ---------------------------------------------------------------------------

VERSION="${latest_version}"
ARCHIVE_URL="https://github.com/${UPSTREAM_OWNER}/${UPSTREAM_REPO}/archive/refs/tags/v${VERSION}.tar.gz"

echo "Prefetching source archive: ${ARCHIVE_URL}"
prefetch_json="$(nix store prefetch-file --json --unpack "${ARCHIVE_URL}")"
src_hash="$(jq -r '.hash' <<< "${prefetch_json}")"
src_path="$(jq -r '.storePath' <<< "${prefetch_json}")"

echo "Source hash: ${src_hash}"

# ---------------------------------------------------------------------------
# Step 5: Extract package-lock.json from prefetched source
# ---------------------------------------------------------------------------

lockfile="${src_path}/package-lock.json"
if [[ ! -f "${lockfile}" ]]; then
  echo "ERROR: package-lock.json not found in prefetched source at ${lockfile}" >&2
  exit 1
fi

cp "${lockfile}" "${LOCKFILE_DIR}/package-lock.v${VERSION}.json"
echo "Vendored package-lock.json as ${LOCKFILE_DIR}/package-lock.v${VERSION}.json"

# ---------------------------------------------------------------------------
# Step 6: Update version, src hash, and lockfile ref in package.nix
# ---------------------------------------------------------------------------

sed -i 's/version = "[^"]*";/version = "'"${VERSION}"'";/' "${PI_NIX}"
sed -i 's@hash = "sha256-[^"]*";@hash = "'"${src_hash}"'";@' "${PI_NIX}"
sed -i 's@package-lock\.v[^ ]*\.json@package-lock.v'"${VERSION}"'.json@g' "${PI_NIX}"
git add "${LOCKFILE_DIR}/package-lock.v${VERSION}.json" "${PI_NIX}"

# ---------------------------------------------------------------------------
# Step 7: Compute npmDepsHash via fake-hash build prefetch
# ---------------------------------------------------------------------------
# prefetch-npm-deps does not account for npmWorkspace, npmRebuildFlags,
# or other buildNpmPackage options that affect the deps hash. Instead,
# set a fake hash, attempt a build, and extract the correct hash from
# the error output.

FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
sed -i 's@npmDepsHash = "sha256-[^"]*";@npmDepsHash = "'"${FAKE_HASH}"'";@' "${PI_NIX}"

npm_deps_hash="$(nix build .#pi --no-link 2>&1 \
  | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' \
  | head -n1)" || true

if [[ -z "${npm_deps_hash}" ]]; then
  echo "ERROR: Could not determine npmDepsHash from build output." >&2
  exit 1
fi

echo "npmDepsHash: ${npm_deps_hash}"
sed -i 's@npmDepsHash = "sha256-[^"]*";@npmDepsHash = "'"${npm_deps_hash}"'";@' "${PI_NIX}"

echo "Updated ${PI_NIX}"

# ---------------------------------------------------------------------------
# Step 8: Clean up old vendored lockfiles
# ---------------------------------------------------------------------------

for f in "${LOCKFILE_DIR}"/package-lock.v*.json; do
  if [[ -f "$f" && "$f" != "${LOCKFILE_DIR}/package-lock.v${VERSION}.json" ]]; then
    echo "Removing old vendored lockfile: $f"
    rm "$f"
  fi
done

# ---------------------------------------------------------------------------
# Step 9: Export metadata for GitHub Actions workflow consumption
# ---------------------------------------------------------------------------

if [[ -n "${GITHUB_ENV:-}" ]]; then
  echo "UPDATE_REQUIRED=true" >> "${GITHUB_ENV}"
  echo "NEW_VERSION=${VERSION}" >> "${GITHUB_ENV}"
  echo "SRC_HASH=${src_hash}" >> "${GITHUB_ENV}"
  echo "NPM_DEPS_HASH=${npm_deps_hash}" >> "${GITHUB_ENV}"
fi

echo "Update complete: ${current_version} -> ${VERSION}"
