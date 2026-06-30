# syntax=docker/dockerfile:1

# ---------------------------------------------------------------------------
# Stage 1 — build front-end assets (Vue SPA + Tailwind) with Vite
# ---------------------------------------------------------------------------
FROM node:22-alpine AS assets
WORKDIR /app
COPY package.json package-lock.json vite.config.js ./
RUN npm ci
# Full source is needed so Tailwind can scan blade + vue files (@source globs).
COPY . .
RUN npm run build

# ---------------------------------------------------------------------------
# Stage 2 — install PHP dependencies (production, optimized autoloader)
# ---------------------------------------------------------------------------
FROM composer:2.8 AS vendor
WORKDIR /app
COPY . .
RUN composer install \
        --no-dev \
        --optimize-autoloader \
        --no-scripts \
        --no-interaction \
        --prefer-dist \
        --ignore-platform-reqs
        # Platform extensions (gd, imagick, …) live in the runtime image,
        # not this composer build image — they are verified there at boot.

# ---------------------------------------------------------------------------
# Stage 3 — PHP-FPM runtime (the application container)
# ---------------------------------------------------------------------------
FROM php:8.3-fpm-alpine AS app

# PHP extensions: pgsql (db), gd + imagick (images & QR PNG), plus the usual.
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

COPY docker/php/php.ini /usr/local/etc/php/conf.d/zz-app.ini

# Application code, vendor, and the built front-end assets.
COPY . .
COPY --from=vendor /app/vendor ./vendor
COPY --from=assets /app/public/build ./public/build

RUN chown -R www-data:www-data storage bootstrap/cache && \
    chmod -R 775 storage bootstrap/cache

COPY docker/php/entrypoint.sh /usr/local/bin/entrypoint
RUN chmod +x /usr/local/bin/entrypoint

EXPOSE 9000
ENTRYPOINT ["entrypoint"]
CMD ["php-fpm"]

# ---------------------------------------------------------------------------
# Stage 4 — Nginx (serves static assets + proxies PHP to the app container)
# ---------------------------------------------------------------------------
FROM nginx:1.27-alpine AS web
COPY docker/nginx/default.conf /etc/nginx/conf.d/default.conf
# Static files (public/, including built assets) are served directly by nginx.
COPY --from=app /var/www/html/public /var/www/html/public
