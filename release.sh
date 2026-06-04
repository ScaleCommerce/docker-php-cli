#!/usr/bin/env bash
set -euo pipefail

# Step 2 of 2: tag v<php>-r<rev> and push. Tag push triggers release.yml,
# which builds multi-arch and publishes to ghcr.io. You pass the PHP version;
# the image revision <rev> is computed here (see below).
#
# Must be run AFTER ./build-local.sh <major> succeeded with a matching
# full version — the verification marker is checked below.
#
# Flags:
#   --no-push    stop after tagging (don't push to origin)

cd "$(dirname "$0")"

PUSH=1
VERSION=""
for arg in "$@"; do
  case "$arg" in
    --no-push) PUSH=0 ;;
    -*) echo "unknown flag: $arg" >&2; exit 2 ;;
    *) VERSION="$arg" ;;
  esac
done
if [[ -z "$VERSION" ]]; then
  echo "usage: $0 <php-full-version> [--no-push]   (e.g. 8.4.12)" >&2
  exit 2
fi
if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "invalid version '$VERSION' — expected X.Y.Z" >&2
  exit 2
fi
PHP_MAJOR="${VERSION%.*}"

IMAGE_LOCAL="php-cli-build:${PHP_MAJOR}-local"
IMAGE_INPUT_FILES=(Dockerfile)
MARKER=".build-verified-${PHP_MAJOR}"

log() { printf '\n→ %s\n' "$*"; }

# -- preflight ---------------------------------------------------------------

if [[ -n "$(git status --porcelain)" ]]; then
  echo "working tree is dirty — commit or stash first" >&2
  exit 1
fi
branch=$(git rev-parse --abbrev-ref HEAD)
if [[ "$branch" != "main" ]]; then
  echo "not on main (on $branch) — refusing to tag a release" >&2
  exit 1
fi
git fetch --quiet origin main
ahead=$(git rev-list --count origin/main..HEAD)
if [[ "$ahead" -ne 0 ]]; then
  echo "local main has $ahead unpushed commit(s) — push or reset them first" >&2
  git log --oneline origin/main..HEAD >&2
  exit 1
fi

if [[ ! -f "$MARKER" ]]; then
  echo "no $MARKER marker — run ./build-local.sh $PHP_MAJOR first" >&2
  exit 1
fi
# shellcheck source=/dev/null
source "$MARKER"
if ! docker image inspect "$IMAGE_LOCAL" >/dev/null 2>&1; then
  echo "no $IMAGE_LOCAL image — re-run ./build-local.sh $PHP_MAJOR" >&2
  exit 1
fi
current_image_sha=$(docker inspect --format '{{.Id}}' "$IMAGE_LOCAL")
if [[ "$current_image_sha" != "$image_sha" ]]; then
  echo "$IMAGE_LOCAL has been rebuilt since $MARKER was written — re-run ./build-local.sh $PHP_MAJOR" >&2
  exit 1
fi
current_content_hash=$(shasum -a 256 "${IMAGE_INPUT_FILES[@]}" | shasum -a 256 | awk '{print $1}')
if [[ "$current_content_hash" != "$content_hash" ]]; then
  echo "Dockerfile changed since ./build-local.sh — re-run it so the image reflects the committed code" >&2
  exit 1
fi
if [[ "$php_version" != "$VERSION" ]]; then
  echo "local build is PHP $php_version, but you asked to release $VERSION" >&2
  echo "re-run ./build-local.sh $PHP_MAJOR to pick up the latest Alpine patch, then retry" >&2
  exit 1
fi

# -- compute the next image revision -----------------------------------------
#
# Tags are v<php>-r<N>. <php> is the PHP patch; <N> is OUR image revision,
# bumped whenever image content changes while PHP stays put (zpinit bump,
# extension tweak) — the slot the bare PHP version lacks. The Dockerfile
# content_hash is stamped into each tag's annotation, so a byte-identical
# rebuild is refused instead of churning a pointless new revision.
# `|| true`: grep exits 1 when there are no existing revisions yet, which would
# otherwise trip `set -o pipefail` + `set -e` and kill the script silently.
last_rev=$(git tag -l "v${VERSION}-r*" | sed -E "s/^v${VERSION}-r//" | grep -E '^[0-9]+$' | sort -n | tail -1 || true)
if [[ -n "$last_rev" ]]; then
  prev_hash=$(git for-each-ref --format='%(contents)' "refs/tags/v${VERSION}-r${last_rev}" \
    | awk -F= '/^content_hash=/{print $2}')
  if [[ "$prev_hash" == "$content_hash" ]]; then
    echo "content is identical to v${VERSION}-r${last_rev} (same Dockerfile hash) — nothing to release" >&2
    exit 1
  fi
  REV=$((last_rev + 1))
else
  REV=1
fi
TAG="v${VERSION}-r${REV}"

if git rev-parse "$TAG" >/dev/null 2>&1; then
  echo "tag $TAG already exists — nothing to release" >&2
  exit 1
fi

# -- tag + push --------------------------------------------------------------

log "releasing PHP $VERSION (image revision r${REV}) on Alpine $alpine_version"
git tag -a "$TAG" -m "php=$VERSION
rev=$REV
alpine=$alpine_version
content_hash=$content_hash
image_sha=$image_sha"
log "tagged $TAG"

if [[ $PUSH -eq 0 ]]; then
  log "done (--no-push). run: git push origin $TAG"
  exit 0
fi

log "pushing tag $TAG"
git push origin "$TAG"
log "done. CI will publish:"
log "  ghcr.io/scalecommerce/docker-php-cli:${VERSION}-r${REV}  (immutable)"
log "  ghcr.io/scalecommerce/docker-php-cli:${VERSION}          (rolling -> r${REV})"
log "  ghcr.io/scalecommerce/docker-php-cli:${PHP_MAJOR}            (rolling)"
