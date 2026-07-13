#!/bin/bash
set -e

# Configura auth do GitHub
if [ -n "$GITHUB_TOKEN" ]; then
    composer config --global github-oauth.github.com "$GITHUB_TOKEN"
    echo "[Satis] GitHub token configurado."
fi

# Reescreve TODO clone SSH de github.com para HTTPS COM o token embutido. O driver
# GitHub do Composer gera a URL scp-style `git@github.com:...` no `git clone --mirror`
# de source (dev-main); num container sem chave SSH isso morre em "Permission denied
# (publickey)" / "Host key verification failed" e o build inteiro falha. O rewrite no
# nível do git resolve na raiz — e o token embutido cobre os repos privados upsolve-br.
# UMA linha (single-valued) para ser idempotente entre restarts. Diagnosticado 2026-07-12.
git config --global url."https://x-access-token:${GITHUB_TOKEN}@github.com/".insteadOf "git@github.com:"

# O webhook (www-data via php-fpm) e o cron (root) compartilham log e lock —
# ambos precisam conseguir escrever, senão o redirecionamento `>> log` do
# webhook falha em silêncio e o disparo se perde.
touch /var/log/satis-build.log /var/lock/satis-build.lock
chmod 666 /var/log/satis-build.log /var/lock/satis-build.lock

# O composer roda como www-data no fluxo do webhook: o home compartilhado
# precisa ser gravável (cache/config do composer).
chmod -R a+rwX /root/.composer 2>/dev/null || true

# Inicia cron
service cron start

# Inicia PHP-FPM em background
php-fpm &

# Aguarda o FPM inicializar
sleep 2

# Build inicial em BACKGROUND — NÃO-fatal e NÃO-bloqueante. Em cache frio o build
# leva minutos (varre cada tag/branch de ~20 repos via API). Se rodasse antes do
# nginx (bloqueante), o site ficaria 404 até o build terminar — e se falhasse com
# `set -e`, derrubava o PID 1 em crash loop. Foi o incidente de 2026-07-12. Aqui o
# nginx sobe JÁ, servindo o output existente, e o catálogo é atualizado quando o
# build terminar; o próximo webhook/cron re-tenta em caso de falha.
(
    echo "[Satis] Iniciando build inicial (background)..."
    if /usr/local/bin/satis-build; then
        echo "[Satis] Build inicial concluído."
    else
        echo "[Satis] AVISO: build inicial falhou — servindo o output existente; webhook/cron re-tentará."
    fi
) &

# Inicia Nginx em foreground (processo principal)
exec nginx -g "daemon off;"