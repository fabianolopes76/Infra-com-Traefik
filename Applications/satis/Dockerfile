FROM php:8.4-fpm

RUN apt-get update && apt-get install -y \
    git \
    zip \
    unzip \
    curl \
    bash \
    nginx \
    cron \
    libzip-dev \
    && docker-php-ext-install zip \
    && rm -rf /var/lib/apt/lists/*

# Composer
COPY --from=composer:2 /usr/bin/composer /usr/bin/composer

# Instala o Satis
RUN composer create-project composer/satis:dev-main /satis --no-interaction

# Diretórios de trabalho
RUN mkdir -p /var/satis/output /var/satis/config /var/webhook /root/.composer

# Arquivos de configuração
COPY scripts/build.sh /usr/local/bin/satis-build
COPY scripts/entrypoint.sh /entrypoint.sh
COPY config/webhook.php /var/webhook/webhook.php
COPY config/nginx.conf /etc/nginx/nginx.conf

RUN chmod +x /usr/local/bin/satis-build /entrypoint.sh

# Cron para rebuild a cada 6 horas
RUN echo "0 */6 * * * root /usr/local/bin/satis-build >> /var/log/satis-build.log 2>&1" \
    > /etc/cron.d/satis-build \
    && chmod 0644 /etc/cron.d/satis-build

EXPOSE 8080

WORKDIR /var/satis

ENTRYPOINT ["/entrypoint.sh"]