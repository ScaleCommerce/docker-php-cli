# Release a new version

Two steps.

### 1. Build locally

```
./build-local.sh 8.4
```

Builds the image for PHP 8.4 on host arch, pulling whatever patch Alpine currently ships as `php84`. Prints the full PHP version. If the version shown is what you want to publish, continue.

### 2. Release

```
./release.sh 8.4.12            # tag v8.4.12-rN and push — triggers CI
./release.sh 8.4.12 --no-push  # tag but don't push
```

You pass the **PHP version**; `release.sh` computes the image revision `rN` itself — the next free `r` for that PHP version (`r1`, `r2`, …), or it refuses if the content is byte-identical to the last revision (the Dockerfile `content_hash` is stamped into each tag's annotation). It also checks that `build-local.sh` ran against this exact version (via the `.build-verified-8.4` marker), then tags `v8.4.12-rN` and pushes. The tag push triggers `.github/workflows/release.yml`, which:

1. Builds multi-arch (amd64/arm64) with matching Alpine + PHP build args.
2. Pushes three tags: `…:8.4.12-rN` (immutable), `…:8.4.12` (rolling → newest revision), and `…:8.4` (rolling → newest patch).
3. Pulls the published image and verifies it actually contains PHP 8.4.12 — guards against Alpine bumping the patch between your local build and the CI run.
4. Creates a GitHub Release whose body contains `/opt/versions.txt` and `/opt/extensions.txt`.

### Image revisions (`-rN`)

The version axis is PHP-only, but the image bundles more than PHP (zpinit, Node, pnpm, Composer, the entrypoint). When that tooling changes without a PHP patch bump, `-rN` is where it's recorded: `8.4.12-r1` → `8.4.12-r2`. The `8.4.12` and `8.4` tags roll forward to the newest revision, so casual pulls always get the latest; pin `-rN` for reproducible/rollback-able builds. Old revisions are safe to prune from GHCR whenever — nothing is obligated to keep them.

### Preconditions for `release.sh`

* Working tree clean, on `main`, no unpushed commits.
* `./build-local.sh <major>` was run first.
* The version you're releasing matches what the local build produced. If Alpine bumped the patch while you were preparing the release, the check fires — re-run `build-local.sh` and release the new version instead.

## Alpine → PHP version mapping

| PHP | Alpine |
| --- | ------ |
| 8.2 | 3.22   |
| 8.3 | 3.23   |
| 8.4 | 3.23   |
| 8.5 | 3.23   |

Kept in two places that must stay in sync: `build-local.sh` and `.github/workflows/release.yml`. If Alpine's PHP packaging moves, update both.

## zpinit version

Pinned in **one** place: the `ARG ZPINIT_VERSION` default in `Dockerfile`
(unlike the Alpine map, it is *not* duplicated in the scripts — both local and
CI builds inherit the Dockerfile default). The binary is pulled from
`ghcr.io/0ploy/zpinit:<version>` via a build stage; it's multi-arch, so the
`COPY --from` resolves amd64/arm64 automatically per build platform.

To bump it, edit the `ARG ZPINIT_VERSION` line. That changes the Dockerfile
content hash, which invalidates `.build-verified-*`, so `release.sh` will
refuse to tag until you re-run `build-local.sh`. The installed version is
recorded in `/opt/versions.txt` (and therefore in each GitHub Release body).

## Manual multi-arch build (fallback)

Only use this if CI is broken. You'll need a GitHub PAT with `write:packages`:

```
echo $GH_PAT | docker login ghcr.io -u <github-user> --password-stdin
docker buildx create --name multiplatform-builder --use   # first time only
docker buildx build --push --platform linux/amd64,linux/arm64 \
  --build-arg ALPINE_VERSION=3.23 --build-arg PHP_VERSION=8.4 \
  -t ghcr.io/scalecommerce/docker-php-cli:8.4.12 \
  -t ghcr.io/scalecommerce/docker-php-cli:8.4 .
```
