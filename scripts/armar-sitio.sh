#!/usr/bin/env bash
# Arma la carpeta que se publica en GitHub Pages.
#
# El repositorio tiene mucho más de lo que debe ser público: compose.yaml, api/,
# db/, .env.example, los tests… Hasta el LAB-02 Pages servía la rama entera, así
# que todo eso quedaba en Internet (https://rafaaas17.github.io/compose.yaml).
# A partir de aquí lo que se publica es solo lo que este script copia.
#
# Vive en un script y no dentro del workflow a propósito: así el job build, el
# job test y yo en mi máquina armamos la MISMA carpeta con el mismo comando.
set -euo pipefail

cd "$(dirname "$0")/.."
DESTINO="${1:-_site}"

rm -rf "$DESTINO"
mkdir -p "$DESTINO"

# Lo único público: la página, sus estilos y su JavaScript.
cp index.html estilos.css libro-de-visitas.js "$DESTINO/"

# Las imágenes, si algún día hay.
if [ -d img ]; then
  cp -r img "$DESTINO/"
fi

echo "Sitio armado en $DESTINO/"
find "$DESTINO" -type f | sort
