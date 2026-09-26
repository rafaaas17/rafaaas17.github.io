#!/usr/bin/env bash
#
# Se ejecuta en CADA arranque del Codespace (postStartCommand), también al
# reanudarlo después de detenerlo.

set -euo pipefail

cd "$(dirname "$0")/.."

# --wait no devuelve el control hasta que los servicios están arriba (y, desde
# el Reto 2, sanos). Sin él, VS Code abriría la vista previa contra un nginx
# que todavía no acepta conexiones.
docker compose up -d --build --wait --wait-timeout 300

echo
docker compose ps
echo
echo "Perfil disponible en el puerto 8080."
