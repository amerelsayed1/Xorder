# syntax=docker/dockerfile:1

# ===========================================================================
# Single-container monorepo build.
#   landing (apps/landing)      -> static, served at /
#   web SPA (apps/web)          -> static, served at / on admin subdomains
#   API + public menu (apps/api)-> Laravel (PHP-FPM), served at /api, /r, /menu
# All same-origin behind one nginx — no CORS, no subdomains required.
# ===========================================================================

# ---------------------------------------------------------------------------
# Stage 1 — build all front-end bundles with pnpm + Vite
# ---------------------------------------------------------------------------
FROM node:22-alpine AS assets
RUN corepack enable
WORKDIR /repo
COPY . .
RUN pnpm install --frozen-lockfile
# apps/api build = public-menu CSS (manifest for Blade @vite).
# apps/web build = SPA (base /).  apps/landing build = marketing site.
RUN pnpm --filter @xorder/api build \
    && pnpm --filter @xorder/web build \
    && pnpm --filter @xorder/landing build \
    && pnpm --filter @xorder/menu build

# ---------------------------------------------------------------------------
# Stage 2 — PHP dependencies (production, optimized autoloader)
# ---------------------------------------------------------------------------
FROM composer:2.8 AS vendor
WORKDIR /app
COPY apps/api .
RUN composer install \
        --no-dev \
        --optimize-autoloader \
        --no-scripts \
        --no-interaction \
        --prefer-dist \
        --ignore-platform-reqs

# ---------------------------------------------------------------------------
# Stage 3 — PHP-FPM runtime (the application container)
# ---------------------------------------------------------------------------
FROM php:8.3-fpm-alpine AS app

ADD https://github.com/mlocati/docker-php-extension-installer/releases/latest/download/install-php-extensions /usr/local/bin/
RUN chmod +x /usr/local/bin/install-php-extensions && \
    install-php-extensions \
        pdo_pgsql \
        gd \
        imagick \
        zip \
        intl \
        bcmath \
        exif \
        opcache \
        pcntl && \
    apk add --no-cache postgresql-client

WORKDIR /var/www/html

COPY apps/api/docker/php/php.ini /usr/local/etc/php/conf.d/zz-app.ini

# Laravel app code, vendor, and the built public-menu assets.
COPY apps/api .
COPY --from=vendor /app/vendor ./vendor
COPY --from=assets /repo/apps/api/public/build ./public/build

RUN chown -R www-data:www-data storage bootstrap/cache && \
    chmod -R 775 storage bootstrap/cache

COPY apps/api/docker/php/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

EXPOSE 9000
ENTRYPOINT ["entrypoint"]
CMD ["php-fpm"]

# ---------------------------------------------------------------------------
# Stage 4 — Nginx: serves landing + SPA statics, proxies PHP to `app`
# ---------------------------------------------------------------------------
FROM nginx:1.27-alpine AS web
# Which server-block config to bake in. Defaults to the dev/localhost one so
# `docker compose up` is unchanged. The production co-host stack overrides this
# with docker/nginx/default.prod.conf (xorder.io + *.xorder.io) via build args.
ARG NGINX_SITE_CONF=docker/nginx/default.conf
COPY ${NGINX_SITE_CONF} /etc/nginx/conf.d/default.conf
COPY docker/nginx/laravel.conf /etc/nginx/snippets/laravel.conf
# Laravel public dir (index.php target + /build assets) and the two front-ends.
# The SPA is built with base /, so it lives at the spa root.
COPY --from=app /var/www/html/public /var/www/html/public
COPY --from=assets /repo/apps/web/dist /var/www/spa
COPY --from=assets /repo/apps/landing/dist /var/www/landing
COPY --from=assets /repo/apps/menu/dist /var/www/menu/menu
