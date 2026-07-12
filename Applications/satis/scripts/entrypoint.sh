#!/bin/bash
set -e

# Configura auth do GitHub
if [ -n "$GITHUB_TOKEN" ]; then
    composer config --global github-oauth.github.com "$GITHUB_TOKEN"
    echo "[Satis] GitHub token configurado."
fi

# O webhook (www-data via php-fpm) e o cron (root) compartilham log e lock —
# ambos precisam conseguir escrever, senão o redirecionamento `>> log` do
# webhook falha em silêncio e o disparo se perde.
touch /var/log/satis-build.log /var/lock/satis-build.lock
chmod 666 /var/log/satis-build.log /var/lock/satis-build.lock

# O composer roda como www-data no fluxo do webhook: o home compartilhado
# precisa ser gravável (cache/config do composer).
chmod -R a+rwX /root/.composer 2>/dev/null || true

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