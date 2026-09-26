#!/usr/bin/env bash
#
# Se ejecuta UNA sola vez, al crear el Codespace (postCreateCommand).
#
# Resuelve la contradicción del Reto 6: la contraseña de Postgres no puede
# estar en el repositorio, pero un Codespace recién creado tampoco tiene .env
# y la aplicación tiene que arrancar sola. La respuesta es no guardar ninguna
# contraseña: generarla aquí, en el Codespace, la primera vez.

set -euo pipefail

cd "$(dirname "$0")/.."

if [ -f .env ]; then
  echo "Ya existe un .env: no lo toco."
  exit 0
fi

cp .env.example .env

# Contraseña distinta en cada Codespace. Nadie la escribió, nadie la conoce y
# no hace falta conocerla: solo la usan api y db dentro de la red de compose.
clave="$(openssl rand -hex 24)"
sed -i "s|^POSTGRES_PASSWORD=.*|POSTGRES_PASSWORD=${clave}|" .env

echo "Listo: .env generado con una contraseña aleatoria."
