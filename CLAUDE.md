# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## About this file

Kept minimal on purpose. Don't add anything an agent would find by reading the Dockerfile, scripts, or README in 30 seconds — those are authoritative. Every line here biases every future response; when updating, ask "would removing this cause a mistake?"

## Project

Single parametric Dockerfile → minimal Alpine-based PHP CLI images for 8.2/8.3/8.4/8.5, published to `ghcr.io/scalecommerce/docker-php-cli`. No FPM, no nginx — that's a separate image.

## Critical: PHP → Alpine mapping is duplicated

```
8.2              → alpine 3.22
8.3, 8.4, 8.5    → alpine 3.23
```

Lives as a `case` statement in BOTH `build-local.sh` AND `.github/workflows/release.yml`. If you change one, change the other — local and CI builds diverge silently otherwise.

## Release flow (non-obvious invariants)

Two steps: `./build-local.sh <major>` then `./release.sh <full-version>`. `build-local.sh` writes `.build-verified-<major>` (image SHA + Dockerfile content hash + resolved full PHP version). `release.sh` refuses to tag unless the requested version exactly matches what the local build produced. This is deliberate: if Alpine bumped the PHP patch between the two steps, you must re-run `build-local.sh` and release the *new* version. CI re-verifies post-push against the tag for the same reason.

Each release pushes `X.Y.Z` (immutable) + `X.Y` (rolling). **No `latest` tag — deliberate.** Don't add one without discussing it.

## zpinit is the entrypoint (PID 1)

`ENTRYPOINT ["zpinit"]`, **no CMD — intentional.** Bare `docker run` → zpinit
supervise mode (Mode 3) with an empty `services/`: idle, reaping, control
socket up. Passing a command → wrap mode (Mode 1): zpinit execs it and exits.
This is a base image for downstream services, hence:

- Empty `/etc/zpinit/services/` and `/etc/zpinit/entrypoint.d/` are created
  (via `mkdir` in the RUN block) as scaffolding for downstream `COPY`s. Don't
  add a `zpinit.toml` or any service file here — keep the base unopinionated.
- `zpctl` is shipped (not just `zpinit`) so downstream consumers/operators can
  manage supervised workers (Symfony messenger consumers, etc.).
- `PATH` / `COMPOSER_ALLOW_SUPERUSER` stay as Dockerfile `ENV`, **not** zpinit
  `[env]`: a dev image needs them visible inside `docker exec`, which `[env]`
  (spawn-path only) would hide.
- Banner is left on (no `ZPINIT_NO_BANNER`) — useful in `docker logs`.
- `ZPINIT_VERSION` is pinned once in the Dockerfile `ARG` (single source; not
  duplicated in the scripts like the Alpine map). Bumping it re-hashes the
  Dockerfile → invalidates `.build-verified-*`. Don't float it to `:latest`.

## Dockerfile quirks

- Extension list lives in the `EXTENSIONS` variable inside the RUN block. A per-package probe (`apk search -q -x`) silently filters missing packages and logs a `Note:` line. Alpine's PHP packaging isn't uniform across majors — e.g. `php85-opcache` isn't a separate package (opcache is compiled into the `php85` core). If you add an extension and it doesn't end up in the image, check the build log for the skip.
- `/etc/php/conf.d/zz-defaults.ini` sets `memory_limit=-1`. The `zz-` prefix makes it load last; user-mounted overrides need a later prefix (e.g. `zzz-`) to win.

## Maintenance: check for newer Alpine/PHP before each release

Three drift patterns. Run these checks before cutting a release (or periodically — Alpine pushes PHP patches regularly).

**1. Patch bump in our current Alpine+PHP combo.** Alpine's `phpXY` package moves from e.g. 8.4.20 → 8.4.21 without any change on our side. Just run `./build-local.sh <major>` and compare the printed full version to the latest published tag. If different, release the new version.

**2. Older PHP major becoming available on newer Alpine.** 8.2 currently pins us to Alpine 3.22. When Alpine 3.23 (or newer) eventually packages `php82`, we can consolidate. Check:

```
docker run --rm alpine:3.23 sh -c 'apk update -q && apk list php82 2>/dev/null'
```

Non-empty output → update the `case` in both `build-local.sh` and `release.yml` to use the newer Alpine for 8.2, rebuild, release.

**3. New Alpine stable (e.g. 3.24 ships).** Re-run the probe above for each phpXY we care about against the new Alpine. If every active major has a package, migrate all mappings to the new Alpine, rebuild, release each major.

## When adding a new PHP major (e.g. 8.6)

Update the `case` in both `build-local.sh` AND `release.yml`. Confirm `phpXY` packages exist on the Alpine you pick (`docker run --rm alpine:X.Y sh -c 'apk update -q && apk list phpXY 2>/dev/null'`). Run `./build-local.sh X.Y` and inspect the `Note:` skips — if a critical extension is missing, decide whether to wait for Alpine to package it or adjust the extension list.
