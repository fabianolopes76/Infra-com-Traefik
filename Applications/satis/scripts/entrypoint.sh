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

# Inicia cron
service cron start

# Inicia PHP-FPM em background
php-fpm &

# Aguarda o FPM inicializar
sleep 2

# Inicia Nginx em foreground (processo principal)
exec nginx -g "daemon off;"