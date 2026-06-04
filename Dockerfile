ARG ALPINE_VERSION=3.23
ARG PHP_VERSION=8.4
# Single source of truth for the zpinit/zpctl version. Bumping this changes
# the Dockerfile content hash, which invalidates .build-verified-* and forces
# a rebuild before release. Keep it pinned; never float to :latest.
ARG ZPINIT_VERSION=0.4.0

FROM ghcr.io/0ploy/zpinit:${ZPINIT_VERSION} AS zpinit

FROM alpine:${ALPINE_VERSION}

ARG ALPINE_VERSION
ARG PHP_VERSION
ARG ZPINIT_VERSION

LABEL org.opencontainers.image.source="https://github.com/ScaleCommerce/docker-php-cli" \
      org.opencontainers.image.description="Minimal Alpine-based PHP CLI image for PHP project development" \
      org.opencontainers.image.licenses="MIT"

ENV PATH=/opt/:$PATH \
    COMPOSER_ALLOW_SUPERUSER=1

# zpinit (PID 1) + zpctl (operator CLI). Multi-arch: COPY --from resolves the
# matching arch per build platform.
COPY --from=zpinit /usr/local/bin/zpinit /usr/local/bin/zpinit
COPY --from=zpinit /usr/local/bin/zpctl  /usr/local/bin/zpctl

RUN set -eux; \
    PHP=$(echo "$PHP_VERSION" | tr -d '.'); \
    EXTENSIONS=" \
        bcmath bz2 calendar ctype curl dom exif ffi fileinfo ftp \
        gd gettext iconv intl mbstring mysqli mysqlnd opcache openssl \
        pcntl pdo pdo_mysql pdo_pgsql pdo_sqlite phar posix session \
        shmop simplexml soap sockets sodium sqlite3 sysvmsg sysvsem \
        sysvshm tokenizer xml xmlreader xmlwriter xsl zip \
        pecl-amqp pecl-apcu pecl-igbinary pecl-memcached pecl-msgpack \
        pecl-redis pecl-yaml pecl-zstd"; \
    apk update; \
    AVAIL=""; SKIPPED=""; \
    for ext in $EXTENSIONS; do \
        pkg="php${PHP}-${ext}"; \
        if apk search -q -x "$pkg" | grep -q .; then \
            AVAIL="$AVAIL $pkg"; \
        else \
            SKIPPED="$SKIPPED $pkg"; \
        fi; \
    done; \
    if [ -n "$SKIPPED" ]; then \
        echo "Note: the following packages are unavailable on alpine:${ALPINE_VERSION:-?} and will be skipped:$SKIPPED" >&2; \
    fi; \
    apk add --no-cache \
        bash git unzip curl make \
        nodejs npm \
        composer \
        php${PHP} \
        $AVAIL; \
    rm -rf /var/cache/apk/*; \
    ln -sf /usr/bin/php${PHP} /usr/bin/php; \
    ln -sfn /etc/php${PHP} /etc/php; \
    printf 'memory_limit=-1\n' > /etc/php/conf.d/zz-defaults.ini; \
    npm install -g pnpm; \
    npm cache clean --force; \
    mkdir -p /opt /etc/zpinit/services /etc/zpinit/entrypoint.d; \
    . /etc/os-release; \
    PHP_FULL_VER=$(php -r 'echo PHP_VERSION;'); \
    NODE_VER=$(node -v); \
    NPM_VER=$(npm -v); \
    PNPM_VER=$(pnpm -v); \
    COMPOSER_VER=$(composer --version --no-ansi 2>&1 | head -1); \
    { \
      echo "$PRETTY_NAME ($(cat /etc/alpine-release))"; \
      echo "PHP version is $PHP_FULL_VER"; \
      echo "Node.js version is $NODE_VER"; \
      echo "npm version is $NPM_VER"; \
      echo "pnpm version is $PNPM_VER"; \
      echo "$COMPOSER_VER"; \
      echo "zpinit version is $(zpinit --version)"; \
      echo ""; \
    } > /opt/versions.txt; \
    php -m > /opt/extensions.txt; \
    echo "PATH=/opt/:\$PATH" >> /root/.profile; \
    echo "cat /opt/versions.txt" >> /root/.profile

WORKDIR /app

ENTRYPOINT ["zpinit"]
# No CMD on purpose. A bare `docker run` starts zpinit in supervise mode
# (Mode 3) with an empty services/: PID 1 up, control socket open, reaping,
# idle. Pass a command to wrap it instead (Mode 1):
#   docker run <img> composer install
#   docker run -it <img> bash -l
# Downstream images add /etc/zpinit/services/*.toml (supervised workers, e.g.
# Symfony messenger consumers) and/or /etc/zpinit/entrypoint.d/* (setup steps).
