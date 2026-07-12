#!/bin/bash
set -e

# Serialização de builds (lockfile + debounce) ------------------------------
#
# O GitHub entrega DOIS webhooks por release (push do commit + push da tag) e
# o webhook.php dispara satis-build em background por entrega. Sem lock, dois
# builds globais correm em paralelo escrevendo no mesmo /var/satis/output e
# um sobrescreve o resultado do outro (visto em produção 2026-07-04: a tag
# nova aparecia no p2 e "sumia" em seguida).
#
# Modelo: um único build por vez (flock). Quem chega com o lock ocupado NÃO
# espera nem duplica — apenas garante a flag "pending" e sai; o processo que
# detém o lock re-executa o build enquanto a flag existir. Resultado: N
# disparos concorrentes = 1 build em curso + no máximo 1 build de recarga,
# sempre com o estado mais novo dos repositórios.

# PATH mínimo do cron (/usr/bin:/bin) não enxerga o php da imagem oficial
# (/usr/local/bin/php) — TODOS os builds do cron falharam por semanas com
# "php: command not found". Binário por caminho absoluto, sempre.
PHP_BIN=/usr/local/bin/php

# O webhook roda como www-data, cujo HOME não tem o github-oauth configurado
# pelo entrypoint (repos upsolve-br são privados) — aponta o composer para o
# home com credenciais, independente do usuário que disparou.
export COMPOSER_HOME=${COMPOSER_HOME:-/root/.composer}

# O webhook roda como www-data e o cron como root: lock e flag precisam ser
# graváveis por ambos (senão o flock/touch do segundo usuário falha em
# silêncio e o disparo se perde).
umask 000

# Ao baixar os dists, o Composer cria seu diretório vendor/composer RELATIVO ao
# cwd. O webhook roda via php-fpm com cwd=/var/webhook (não-gravável por www-data)
# → build falha com "/var/webhook/vendor/composer does not exist and could not be
# created" (só no fluxo do webhook; o build manual roda de cwd gravável). Roda
# sempre de um cwd gravável por qualquer usuário. Issue #31.
cd /tmp

LOCK_FILE=/var/lock/satis-build.lock
PENDING_FLAG=/var/lock/satis-build.pending

run_build() {
    echo "[$(date)] Iniciando rebuild do Satis..."

    "$PHP_BIN" /satis/bin/satis build \
        /var/satis/config/satis.json \
        /var/satis/output \
        --no-interaction \
        --ansi

    echo "[$(date)] Build concluído."
}

# Registra a intenção ANTES de tentar o lock: se outro build está em curso,
# ele verá a flag ao terminar e fará a recarga.
touch "$PENDING_FLAG"

exec 9>"$LOCK_FILE"

if ! flock --nonblock 9; then
    echo "[$(date)] Build já em execução — recarga agendada via ${PENDING_FLAG}."
    exit 0
fi

while [ -e "$PENDING_FLAG" ]; do
    rm -f "$PENDING_FLAG"
    run_build
done
