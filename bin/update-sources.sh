#!/usr/bin/env bash
# Maintain sources.json: find the newest pnpm release, hash every platform
# tarball, write the file back.
#
#   ./bin/update-sources.sh                  # update
#   ./bin/update-sources.sh --check          # report only, never write
#   TAG=v12.17.0 ./bin/update-sources.sh     # pin an explicit release
#
# pnpm publishes two release lines at once (11.x LTS and 12.x stable). This
# repository tracks one line only: the highest semver wins, so 12.17.0 beats
# 11.28.10 without any special casing.
#
# Both platforms are hashed on every run, on whatever machine runs the script:
# the tarballs are just downloads, so an x86_64 runner can hash the arm64 one.
# That property is the whole reason this repository exists — a per-platform hash
# recomputed only for the host silently rots for everyone else.
set -euo pipefail

cd "$(dirname "$0")/.."

SOURCES="sources.json"
REPO="pnpm/pnpm"

# system -> release asset suffix.
PLATFORMS=(
  "x86_64-linux:linux-x64"
  "aarch64-linux:linux-arm64"
)

check_only=false
if [[ "${1:-}" == "--check" ]]; then
  check_only=true
fi

die() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

for tool in curl jq nix-prefetch-url; do
  command -v "$tool" >/dev/null || die "missing dependency: $tool"
done

if [[ -n "${TAG:-}" ]]; then
  tag="${TAG#v}"
  printf 'using pinned tag v%s\n' "$tag"
else
  printf 'listing releases of %s ...\n' "$REPO"
  # Newest first by created_at. 30 entries comfortably covers both active
  # release lines; the highest semver among them is the one we want.
  releases=$(curl -fsS --retry 3 "https://api.github.com/repos/${REPO}/releases?per_page=30") \
    || die "cannot list releases of $REPO"

  tag=$(jq -r '.[].tag_name' <<<"$releases" \
    | grep -oE '^v?[0-9]+\.[0-9]+\.[0-9]+$' \
    | sed 's/^v//' \
    | sort -V \
    | tail -n1) || true
  [[ -n "${tag:-}" ]] || die "no semver release tag found"
fi

current=$(jq -r '.version' "$SOURCES")
printf 'upstream: %s   current: %s\n' "$tag" "$current"

if [[ "$tag" == "$current" ]] && $check_only; then
  printf 'up to date\n'
  exit 0
fi

platform_entries=()
for entry in "${PLATFORMS[@]}"; do
  system=${entry%%:*}
  arch=${entry##*:}
  asset="pnpm-${arch}.tar.gz"
  url="https://github.com/${REPO}/releases/download/v${tag}/${asset}"

  if $check_only; then
    printf '%s: %s (not hashed in --check mode)\n' "$system" "$asset"
    platform_entries+=("placeholder")
    continue
  fi

  printf 'hashing %s ... ' "$asset"
  base32=$(nix-prefetch-url --type sha256 "$url" 2>/dev/null) \
    || die "download or hash failed: $url"
  sri=$(nix hash convert --hash-algo sha256 --to sri "$base32")
  printf '%s\n' "$sri"

  platform_entries+=("$(jq -nc --arg tarball "$asset" --arg hash "$sri" \
    '{tarball:$tarball, hash:$hash}')")
done

if $check_only; then
  # Reached only when the version moved: report and signal "not up to date".
  exit 1
fi

new_json=$(jq -n --arg version "$tag" '{version: $version, platforms: {}}')

idx=0
for entry in "${PLATFORMS[@]}"; do
  system=${entry%%:*}
  new_json=$(jq -c --arg system "$system" --argjson value "${platform_entries[$idx]}" \
    '.platforms[$system] = $value' <<<"$new_json")
  idx=$((idx + 1))
done

printf '%s\n' "$new_json" | jq . > "$SOURCES.tmp"
mv "$SOURCES.tmp" "$SOURCES"

printf 'wrote %s (pnpm %s)\n' "$SOURCES" "$tag"
