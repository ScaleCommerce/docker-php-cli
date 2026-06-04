# docker-php-cli

Minimal Alpine-based PHP CLI image for developing PHP projects locally. Designed for use with PHP's built-in dev server (`php -S`) or a framework CLI — no FPM, no nginx (there's a separate full-stack image for that).

Includes PHP CLI with a broad extension set, Composer, Node.js, npm, and pnpm.

## Pull an image

```
docker pull ghcr.io/scalecommerce/docker-php-cli:8.4
```

Tag scheme (no `latest`, by design — pick a PHP major explicitly):
* `8.4` — rolling, tracks the latest 8.4.x
* `8.4.12` — immutable, pinned to a specific patch version

Supported PHP majors: **8.2, 8.3, 8.4, 8.5**. See [php.net supported versions](https://www.php.net/supported-versions.php) for current EOL dates.

Browse all published tags: https://github.com/ScaleCommerce/docker-php-cli/pkgs/container/docker-php-cli

## What's included

* **PHP CLI** with a broad extension set: core (bcmath, curl, gd, intl, mbstring, opcache, openssl, pdo_mysql, pdo_pgsql, pdo_sqlite, soap, sodium, zip, ...) plus common PECLs (apcu, redis, amqp, memcached, igbinary, msgpack, yaml, zstd)
* **Composer**
* **Node.js, npm, pnpm** — most PHP projects bundle a JS build toolchain
* **bash, git, unzip, curl, make**
* **zpinit + zpctl** as PID 1 — reaping init, one-off task wrapper, and process supervisor in one binary (see [Running as PID 1](#running-as-pid-1-zpinit))
* Sane dev defaults: `memory_limit=-1`, stable `/etc/php/conf.d/` config path (see [PHP configuration](#php-configuration) below)

Final image size is ~250 MB across all majors.

The extension set is identical in intent across majors, but the exact list can differ slightly because Alpine's PHP packaging varies per version (e.g. on 8.5 opcache is compiled into the core package rather than shipped separately). The authoritative list for each image lives at `/opt/extensions.txt`; versions of PHP, Alpine, Node, npm, pnpm, and Composer are at `/opt/versions.txt`. Both are also dumped into every GitHub Release's notes.

```
docker run --rm ghcr.io/scalecommerce/docker-php-cli:8.4 cat /opt/versions.txt
docker run --rm ghcr.io/scalecommerce/docker-php-cli:8.4 cat /opt/extensions.txt
```

## PHP configuration

PHP INI files live in `/etc/php/conf.d/` (a symlink to the real version-specific directory, e.g. `/etc/php84/conf.d/`). Use `/etc/php/conf.d/` in all images — the path is stable regardless of PHP version.

Defaults baked in:

* `memory_limit=-1` in `/etc/php/conf.d/zz-defaults.ini`

To change or add settings at runtime, mount your own INI file. Use a `zz-` prefix so it loads after the defaults:

```
docker run --rm -v "$(pwd):/app" \
  -v "$(pwd)/php-dev.ini:/etc/php/conf.d/zz-custom.ini" \
  ghcr.io/scalecommerce/docker-php-cli:8.4 \
  php -S 0.0.0.0:80 -t public
```

Inspect effective settings from inside the container:

```
php --ini           # where PHP looks for INI files
php -i | grep -i memory_limit
```

## Example usage

Built-in PHP dev server, current directory mounted as the project:
```
docker run --rm -v "$(pwd):/app" -p 80:80 \
  ghcr.io/scalecommerce/docker-php-cli:8.4 \
  php -S 0.0.0.0:80 -t public
```

One-off composer install:
```
docker run --rm -v "$(pwd):/app" \
  ghcr.io/scalecommerce/docker-php-cli:8.4 composer install
```

Interactive shell (prints versions on login):
```
docker run --rm -it -v "$(pwd):/app" \
  ghcr.io/scalecommerce/docker-php-cli:8.4 bash -l
```

> Note the explicit `bash -l`. A bare `docker run` (no command) starts zpinit
> in idle supervise mode, not a shell — see [Running as PID 1](#running-as-pid-1-zpinit).

## Running as PID 1 (zpinit)

The image's entrypoint is [zpinit](https://github.com/0ploy/zpinit): one
small static binary that acts as PID 1, replacing tini, `docker-entrypoint.sh`,
supervisord, and PM2. It picks its behavior from the command you pass — no
flags:

* **No command → supervise mode.** zpinit comes up as PID 1, opens its control
  socket, reaps zombies, and stays alive with an empty service set. This is the
  base for building your own image: drop service TOMLs into
  `/etc/zpinit/services/` and they get supervised (start order, readiness
  gating, crash-restart with backoff, graceful shutdown, live reload).
* **A command → wrap mode.** zpinit validates, then `exec`s your command and
  steps out of the way. This is why every example above (`composer install`,
  `php -S`, `bash -l`) works unchanged.

`zpctl` is on `PATH` for operators (`zpctl status`, `zpctl restart <svc>`,
`zpctl reload <svc>`, `zpctl tail -f <svc>`). zpinit's own flags are reachable
through the entrypoint:

```
docker run --rm ghcr.io/scalecommerce/docker-php-cli:8.4 --check-config /etc/zpinit/
docker run --rm ghcr.io/scalecommerce/docker-php-cli:8.4 --doctor       /etc/zpinit/
```

The base image ships empty `/etc/zpinit/services/` and
`/etc/zpinit/entrypoint.d/` directories for you to populate downstream.

### Supervised worker (e.g. Symfony messenger consumer)

Build on top of the image and add a service file. zpinit keeps the consumer
running, restarts it when `--time-limit` makes it exit, and reaps any children:

```dockerfile
FROM ghcr.io/scalecommerce/docker-php-cli:8.4
COPY . /app
RUN composer install --no-dev --no-interaction --prefer-dist
COPY services/ /etc/zpinit/services/
# No CMD: supervise mode runs the service(s) below.
```

`services/10-consumer.toml`:
```toml
command = ["php", "/app/bin/console", "messenger:consume", "async", "--time-limit=3600"]
restart = "always"
```

```
docker run -d ghcr.io/your-org/your-app
docker exec -it <container> zpctl status      # consumer -- RUNNING
docker exec -it <container> zpctl tail -f consumer
```

Run several consumers by adding more files (`20-consumer-priority.toml`, …);
they start in filename order. For N copies of one worker, set `replicas = 4`.

### Setup, then run (Symfony dev server)

Use `entrypoint.d/` for boot-time setup that must finish before the server
starts. Scripts run in filename order on every container start; a non-zero
exit aborts boot. This Symfony dev-server image installs the Symfony CLI if
missing, runs `composer install`, then starts the server:

```dockerfile
FROM ghcr.io/scalecommerce/docker-php-cli:8.4
COPY entrypoint.d/ /etc/zpinit/entrypoint.d/
COPY . /app
ENV PORT=8000
# Shell form so ${PORT} expands at runtime (zpinit does no env interpolation;
# the surrounding `sh -c` does). exec form ["..."] would NOT expand it.
CMD symfony server:start --no-tls --port=${PORT} --allow-all-ip
```

`entrypoint.d/10-symfony-cli.sh`:
```sh
#!/bin/sh
set -eu
if ! command -v symfony >/dev/null 2>&1; then
  curl -1sLf https://get.symfony.com/cli/installer | bash -s -- --install-dir=/usr/local/bin
fi
```

`entrypoint.d/20-composer-install.sh`:
```sh
#!/bin/sh
set -eu
cd /app
composer install --no-interaction --prefer-dist
```

Make the scripts executable (`chmod +x entrypoint.d/*.sh`) — zpinit skips
non-executable files and warns about them under `--check-config`. The Symfony
CLI install runs at every boot only until the binary exists; bake it into a
`RUN` layer instead if you'd rather pay that cost once at build time.

## Releasing

See [BUILD.md](./BUILD.md).
