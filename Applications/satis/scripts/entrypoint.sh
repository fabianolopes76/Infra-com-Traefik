#!/bin/bash
set -e

# Configura auth do GitHub
if [ -n "$GITHUB_TOKEN" ]; then
    composer config --global github-oauth.github.com "$GITHUB_TOKEN"
    echo "[Satis] GitHub token configurado."
fi

# Build inicial
echo "[Satis] Iniciando build inicial..."
/usr/local/bin/satis-build

# Inicia serviços
service cron start
php-fpm -D

exec nginx -g "daemon off;"