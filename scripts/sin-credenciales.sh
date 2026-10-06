#!/usr/bin/env bash
# Que el repositorio siga sin credenciales, no solo hoy.
#
# Viene del Reto 6 del LAB-02 (workflow sin-secretos.yml) y ahora es el primer
# paso del job build: es la revisión más barata del pipeline y la que más caro
# sale si falta. Está en un script, y no dentro del YAML, por dos razones:
# puedo correrlo en mi máquina antes de hacer push, y puede excluirse a sí
# mismo del rastreo. La primera versión lo tenía escrito dentro del workflow y
# el pipeline se cayó solo: el patrón que busca aparecía en la línea que lo
# buscaba.
set -euo pipefail

cd "$(dirname "$0")/.."

# 1. El .env nunca estuvo versionado, en ningún commit de ninguna rama.
if git log --all --full-history --oneline -- .env | grep .; then
  echo "::error::.env aparece en el historial de Git"
  exit 1
fi

# 2. Existe la plantilla y el .env de verdad está ignorado.
test -f .env.example
: > .env
git check-ignore -q .env
rm -f .env

# 3. Ningún archivo versionado trae una contraseña con valor.
#
# Se filtran las menciones que no son una contraseña: ${VARIABLE},
# $(comando) y los ejemplos del README, que escriben el nombre de la
# variable seguido de puntos suspensivos.
if git grep -nEI 'POSTGRES_PASSWORD=[^[:space:]]+' \
  -- . ':!.env.example' ':!scripts/sin-credenciales.sh' \
  | grep -vE '\$\{|\$\(|…|\.\.\.'; then
  echo "::error::hay una contraseña escrita en un archivo versionado"
  exit 1
fi

echo "OK: sin credenciales en el repositorio."
