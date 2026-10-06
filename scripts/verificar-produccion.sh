#!/usr/bin/env bash
# Revisa el sitio ya publicado (Reto 5 del LAB-03).
#
# Que deploy-prod termine en verde solo dice que GitHub aceptó el artefacto.
# Esto pregunta lo otro: ¿la página que ve un visitante funciona? Se ejecuta
# contra la URL real que devuelve deploy-pages, no contra localhost.
#
# Reintenta porque Pages tarda unos segundos en servir la versión nueva: la
# primera petición puede traer todavía la anterior desde la CDN.
set -uo pipefail

URL="${1:?falta la URL publicada}"
URL="${URL%/}"
INTENTOS="${2:-10}"
fallos=0

echo "Verificando $URL"

# 1. La página responde 200.
codigo=""
for i in $(seq 1 "$INTENTOS"); do
  codigo=$(curl -s -o pagina.html -w '%{http_code}' "$URL/")
  [ "$codigo" = "200" ] && break
  echo "  intento $i: HTTP $codigo, reintento en 6 s"
  sleep 6
done
if [ "$codigo" = "200" ]; then
  echo "  ok   GET / responde 200"
else
  echo "  FALLA GET / respondió $codigo después de $INTENTOS intentos"
  fallos=$((fallos + 1))
fi

# 2. Es mi perfil, no una página de error con código 200.
if grep -q "Rafael Alarcón Romero" pagina.html; then
  echo "  ok   la página trae mi nombre"
else
  echo "  FALLA la página no trae mi nombre"
  fallos=$((fallos + 1))
fi

# 3. El libro de visitas no rompe la página.
#
# En Pages no hay backend: /api/mensajes devuelve el 404 de GitHub, con HTML.
# libro-de-visitas.js comprueba el código y el Content-Type, deja la sección
# con su atributo hidden y no toca nada más. Si alguien quitara ese hidden,
# el visitante vería un formulario que no puede funcionar.
codigo_api=$(curl -s -o /dev/null -w '%{http_code}' "$URL/api/mensajes")
if [ "$codigo_api" = "404" ]; then
  echo "  ok   /api/mensajes da 404, que es lo esperado en Pages"
else
  echo "  FALLA /api/mensajes respondió $codigo_api (en Pages no hay backend)"
  fallos=$((fallos + 1))
fi

if grep -qE '<section id="libro-de-visitas"[^>]*\bhidden\b' pagina.html; then
  echo "  ok   el libro de visitas arranca oculto"
else
  echo "  FALLA el libro de visitas no arranca oculto: se vería un formulario muerto"
  fallos=$((fallos + 1))
fi

# 4. Lo interno sigue sin publicarse.
for interno in compose.yaml .env.example api/main.go README.md; do
  c=$(curl -s -o /dev/null -w '%{http_code}' "$URL/$interno")
  if [ "$c" = "404" ]; then
    echo "  ok   /$interno no está publicado (404)"
  else
    echo "  FALLA /$interno respondió $c: eso no debería ser público"
    fallos=$((fallos + 1))
  fi
done

echo
if [ "$fallos" -gt 0 ]; then
  echo "::error::$fallos comprobación(es) fallaron sobre el sitio publicado"
  exit 1
fi
echo "Producción verificada."
