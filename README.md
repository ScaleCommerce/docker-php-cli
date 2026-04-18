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
  ghcr.io/scalecommerce/docker-php-cli:8.4
```

## Releasing

See [BUILD.md](./BUILD.md).
