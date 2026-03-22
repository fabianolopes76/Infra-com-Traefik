#!/bin/bash
set -e

echo "[$(date)] Iniciando rebuild do Satis..."

php /satis/bin/satis build \
    /var/satis/config/satis.json \
    /var/satis/output \
    --no-interaction \
    --ansi

echo "[$(date)] Build concluído."