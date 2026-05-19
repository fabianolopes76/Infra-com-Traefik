#!/bin/bash
# satis-run.sh — wrapper safe para builds ad-hoc do Satis no servidor.
#
# Em vez de `docker compose run satis satis-build` (que cria containers
# zumbis quando esquecido o --rm), usa `docker compose exec` no container
# já vivo. Não há contêiner novo, não há zumbi.
#
# Em 2026-05-19, 4 containers `satis-satis-run-*` vivos há 5 semanas
# travaram inodes de bind-mounts e causaram 1h de debug do CI. Ver
# Applications/satis/README.md para detalhes.

set -euo pipefail

# Detecta diretório do projeto (assumindo que esse script está em
# Applications/satis/scripts/ relativo ao repo raiz).
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SATIS_DIR="$(dirname "$SCRIPT_DIR")"

cd "$SATIS_DIR"

# Garante que o container está vivo. Sobe se não estiver.
if ! docker compose ps --status running --services 2>/dev/null | grep -q '^satis$'; then
    echo "[satis-run] Container satis não está rodando — subindo..."
    docker compose up -d satis
    # Aguarda o entrypoint completar o build inicial.
    sleep 5
fi

echo "[satis-run] Executando rebuild via exec (não cria zumbi)..."
docker compose exec -T satis /usr/local/bin/satis-build

echo "[satis-run] Build concluído. Verifique https://packages.upsolve.com.br/packages.json"
