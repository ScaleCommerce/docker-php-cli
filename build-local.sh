#!/usr/bin/env bash
set -euo pipefail

# Step 1 of 2: build the image locally (host arch) and extract the full PHP
# version. If the shown version is what you want to publish, run
# ./release.sh <full-version>.

cd "$(dirname "$0")"

if [[ $# -ne 1 ]]; then
  echo "usage: $0 <php-major>   (e.g. 8.4)" >&2
  exit 2
fi
PHP_MAJOR="$1"
if ! [[ "$PHP_MAJOR" =~ ^[0-9]+\.[0-9]+$ ]]; then
  echo "invalid PHP version '$PHP_MAJOR' — expected X.Y (e.g. 8.4)" >&2
  exit 2
fi

# PHP major -> Alpine branch. Keep in sync with .github/workflows/release.yml.
case "$PHP_MAJOR" in
  8.2)         ALPINE_VERSION=3.22 ;;
  8.3|8.4|8.5) ALPINE_VERSION=3.23 ;;
  *) echo "unsupported PHP version: $PHP_MAJOR" >&2; exit 2 ;;
esac

IMAGE_LOCAL="php-cli-build:${PHP_MAJOR}-local"
IMAGE_INPUT_FILES=(Dockerfile)

log() { printf '\n→ %s\n' "$*"; }

rm -f ".build-verified-${PHP_MAJOR}"

log "building $IMAGE_LOCAL (alpine:${ALPINE_VERSION}, host arch)"
docker build \
  --build-arg "ALPINE_VERSION=$ALPINE_VERSION" \
  --build-arg "PHP_VERSION=$PHP_MAJOR" \
  -t "$IMAGE_LOCAL" .

VERSIONS_TXT=$(docker run --rm "$IMAGE_LOCAL" cat /opt/versions.txt)
PHP_FULL_VER=$(printf '%s\n' "$VERSIONS_TXT" | awk '/^PHP version is/ {print $NF}')
if [[ -z "$PHP_FULL_VER" ]]; then
  echo "could not extract PHP version from image" >&2
  printf '%s\n' "$VERSIONS_TXT" >&2
  exit 1
fi
PHP_MAJOR_FROM_BUILD="${PHP_FULL_VER%.*}"
if [[ "$PHP_MAJOR_FROM_BUILD" != "$PHP_MAJOR" ]]; then
  echo "expected PHP $PHP_MAJOR.x, got $PHP_FULL_VER" >&2
  exit 1
fi

log "built PHP $PHP_FULL_VER"
log "image versions:"
printf '%s\n' "$VERSIONS_TXT" | sed 's/^/   /'

IMAGE_SHA=$(docker inspect --format '{{.Id}}' "$IMAGE_LOCAL")
CONTENT_HASH=$(shasum -a 256 "${IMAGE_INPUT_FILES[@]}" | shasum -a 256 | awk '{print $1}')
{
  echo "image_sha=$IMAGE_SHA"
  echo "content_hash=$CONTENT_HASH"
  echo "alpine_version=$ALPINE_VERSION"
  echo "php_version=$PHP_FULL_VER"
} > ".build-verified-${PHP_MAJOR}"

log "OK"
log "next: ./release.sh $PHP_FULL_VER"
