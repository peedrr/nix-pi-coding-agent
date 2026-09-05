#!/usr/bin/env bash
# update-pi.sh — Check for new published @earendil-works/pi-coding-agent releases
# and update packages/pi/package.nix for the tarball-based npm build.
#
# Usage: ./.github/scripts/update-pi.sh
#
# This script can be run both in CI and locally. It:
#   1. Reads the current version from packages/pi/package.nix
#   2. Queries the latest version from the npm registry dist-tags
#   3. Skips if no newer version is available
#   4. Updates the synthetic-root package.json with the new version
#   5. Regenerates the vendored package-lock.json
#   6. Fixes any missing integrity hashes in the generated lockfile
#   7. Updates version and lockfile reference in package.nix
#   8. Computes npmDepsHash via fake-hash build prefetch
#   9. Cleans up old vendored lockfiles
#  10. Exports metadata for GitHub Actions workflow consumption

set -euo pipefail

# ---------------------------------------------------------------------------
# Configuration
# ---------------------------------------------------------------------------

NPM_SCOPE="@earendil-works"
PI_PACKAGE="pi-coding-agent"
PI_NIX="packages/pi/package.nix"
PI_JSON="packages/pi/package.json"
LOCKFILE_DIR="packages/pi"

# Packages that must sit beside pi-coding-agent in the synthetic root so that
# pi-subagents background children can resolve them from the host package root.
SYNTHETIC_DEPS=(
  "pi-coding-agent"
  "pi-client"
  "pi-protocol"
  "pi-server"
)

# ---------------------------------------------------------------------------
# Step 1: Detect current version from package.nix
# ---------------------------------------------------------------------------

current_version="$(grep -oP 'version = "\K[^"]+' "${PI_NIX}")"
echo "Current version in ${PI_NIX}: ${current_version}"

# ---------------------------------------------------------------------------
# Step 2: Detect latest version from npm registry (or use override)
# ---------------------------------------------------------------------------

if [[ -n "${VERSION_OVERRIDE:-}" ]]; then
  latest_version="${VERSION_OVERRIDE#v}"
  echo "Using overridden version: ${latest_version}"
else
  echo "Querying npm registry for latest ${NPM_SCOPE}/${PI_PACKAGE} version..."
  latest_version="$(curl -fsSL "https://registry.npmjs.org/${NPM_SCOPE}/${PI_PACKAGE}" \
    | jq -r '.["dist-tags"].latest')"

  if [[ -z "${latest_version}" || "${latest_version}" == "null" ]]; then
    echo "ERROR: Could not determine latest npm version." >&2
    exit 1
  fi
fi

echo "Latest npm version: ${latest_version}"

# ---------------------------------------------------------------------------
# Step 3: Skip if versions are equal or candidate is older
# ---------------------------------------------------------------------------

if [[ "${current_version}" == "${latest_version}" ]]; then
  echo "Versions are equal. Nothing to do."
  echo "UPDATE_REQUIRED=false" >> "${GITHUB_ENV:-/dev/null}"
  exit 0
fi

newest="$(printf '%s\n%s\n' "${current_version}" "${latest_version}" | sort -V | tail -n1)"
if [[ "${newest}" != "${latest_version}" ]]; then
  echo "Candidate version ${latest_version} is older than current ${current_version}. Skipping."
  echo "UPDATE_REQUIRED=false" >> "${GITHUB_ENV:-/dev/null}"
  exit 0
fi

VERSION="${latest_version}"

# ---------------------------------------------------------------------------
# Step 4: Update synthetic-root package.json
# ---------------------------------------------------------------------------

echo "Updating ${PI_JSON} dependencies to ${VERSION}..."

jq_args=()
for dep in "${SYNTHETIC_DEPS[@]}"; do
  jq_args+=(--arg "dep" "${dep}" --arg "ver" "${VERSION}" '.dependencies["'"${NPM_SCOPE}/${dep}"'"] = $ver')
done
# Chain the updates via successive jq runs is awkward; build one filter.
# Simpler: use a single jq program that sets each dependency.
jq_filter="."
for dep in "${SYNTHETIC_DEPS[@]}"; do
  jq_filter="${jq_filter} | .dependencies[\"${NPM_SCOPE}/${dep}\"] = \"${VERSION}\""
done
jq_filter="${jq_filter} | .version = \"${VERSION}\""

jq "${jq_filter}" "${PI_JSON}" > "${PI_JSON}.tmp"
mv "${PI_JSON}.tmp" "${PI_JSON}"

# ---------------------------------------------------------------------------
# Step 5: Regenerate the vendored package-lock.json
# ---------------------------------------------------------------------------

tmpdir="$(mktemp -d)"
cp "${PI_JSON}" "${tmpdir}/package.json"
(
  cd "${tmpdir}"
  npm install --package-lock-only --ignore-scripts
)
lockfile="${tmpdir}/package-lock.json"

# ---------------------------------------------------------------------------
# Step 5b: Fill in any missing integrity hashes
# ---------------------------------------------------------------------------
# npm install --package-lock-only can omit integrity for packages that are
# pinned by an upstream npm-shrinkwrap.json. prefetch-npm-deps requires
# integrity for every non-git dependency, so compute sha512 for each missing
# resolved tarball.

missing_entries="$(jq -r '.packages | to_entries[] | select(.value.resolved and (.value.integrity | not)) | [.key, .value.resolved] | @tsv' "${lockfile}")"

if [[ -n "${missing_entries}" ]]; then
  echo "Filling missing integrity hashes..."
  while IFS=$'\t' read -r key url; do
    [[ -z "${key}" ]] && continue
    if [[ ! "${url}" =~ ^https?:// ]]; then
      echo "ERROR: Cannot compute integrity for non-HTTP resolved URL: ${url}" >&2
      exit 1
    fi
    integrity="$(nix store prefetch-file --json --hash-type sha512 "${url}" | jq -r '.hash')"
    jq --arg key "${key}" --arg integrity "${integrity}" '.packages[$key].integrity = $integrity' "${lockfile}" > "${lockfile}.tmp"
    mv "${lockfile}.tmp" "${lockfile}"
  done <<< "${missing_entries}"
fi

cp "${lockfile}" "${LOCKFILE_DIR}/package-lock.v${VERSION}.json"
rm -rf "${tmpdir}"
echo "Vendored package-lock.json as ${LOCKFILE_DIR}/package-lock.v${VERSION}.json"

# ---------------------------------------------------------------------------
# Step 6: Update version and lockfile reference in package.nix
# ---------------------------------------------------------------------------

sed -i 's/version = "[^"]*";/version = "'"${VERSION}"'";/' "${PI_NIX}"
sed -i 's@package-lock\.v[^ ]*\.json@package-lock.v'"${VERSION}"'.json@g' "${PI_NIX}"
git add "${PI_JSON}" "${LOCKFILE_DIR}/package-lock.v${VERSION}.json" "${PI_NIX}"

# ---------------------------------------------------------------------------
# Step 7: Compute npmDepsHash via fake-hash build prefetch
# ---------------------------------------------------------------------------

FAKE_HASH="sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
sed -i 's@npmDepsHash = "sha256-[^"]*";@npmDepsHash = "'"${FAKE_HASH}"'";/' "${PI_NIX}"

npm_deps_hash="$(nix build .#pi --no-link 2>&1 \
  | grep -oP 'got:\s+\Ksha256-[A-Za-z0-9+/=]+' \
  | head -n1)" || true

if [[ -z "${npm_deps_hash}" ]]; then
  echo "ERROR: Could not determine npmDepsHash from build output." >&2
  exit 1
fi

echo "npmDepsHash: ${npm_deps_hash}"
sed -i 's@npmDepsHash = "sha256-[^"]*";@npmDepsHash = "'"${npm_deps_hash}"'";/' "${PI_NIX}"

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
  echo "NPM_DEPS_HASH=${npm_deps_hash}" >> "${GITHUB_ENV}"
fi

echo "Update complete: ${current_version} -> ${VERSION}"
