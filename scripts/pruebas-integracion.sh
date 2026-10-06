#!/usr/bin/env bash
# Pruebas de integración de la aplicación completa (Reto 3 del LAB-03).
#
# Vitest prueba el sitio estático y go test prueba la API con una base falsa.
# Esto prueba lo que ninguna de las dos puede: los tres contenedores juntos,
# hablando entre sí, y la API vista DESDE FUERA, pasando por nginx, que es
# como la ve el navegador del visitante. Si nginx dejara de reenviar /api/,
# las otras pruebas seguirían en verde y el libro de visitas estaría roto.
set -uo pipefail

BASE="${1:-http://localhost:8080}"
fallos=0
MARCA="integracion-$(date +%s)"

# comprobar <descripción> <esperado> <método> <ruta> [cuerpo]
comprobar() {
  local descripcion="$1" esperado="$2" metodo="$3" ruta="$4" cuerpo="${5:-}"
  local codigo
  if [ -n "$cuerpo" ]; then
    codigo=$(curl -s -o /tmp/respuesta -w '%{http_code}' -X "$metodo" "$BASE$ruta" \
      -H 'Content-Type: application/json' -d "$cuerpo")
  else
    codigo=$(curl -s -o /tmp/respuesta -w '%{http_code}' -X "$metodo" "$BASE$ruta")
  fi

  if [ "$codigo" = "$esperado" ]; then
    printf '  ok   %-58s HTTP %s\n' "$descripcion" "$codigo"
  else
    printf '  FALLA %-57s esperaba HTTP %s y respondió %s\n' "$descripcion" "$esperado" "$codigo"
    echo "       cuerpo: $(head -c 300 /tmp/respuesta)"
    fallos=$((fallos + 1))
  fi
}

echo "Contrato de la API en $BASE"

comprobar "la página se sirve" 200 GET /
comprobar "GET /api/health" 200 GET /api/health
comprobar "POST /api/mensajes válido" 201 POST /api/mensajes \
  "{\"nombre\":\"Pruebas\",\"mensaje\":\"$MARCA\"}"
comprobar "POST sin nombre" 400 POST /api/mensajes \
  '{"nombre":"","mensaje":"hola"}'
comprobar "POST con mensaje de 281 caracteres" 400 POST /api/mensajes \
  "{\"nombre\":\"Pruebas\",\"mensaje\":\"$(printf 'a%.0s' $(seq 281))\"}"
comprobar "POST con cuerpo que no es JSON" 400 POST /api/mensajes 'esto no es json'
comprobar "GET /api/mensajes" 200 GET /api/mensajes

# El mensaje que se acaba de crear tiene que estar en la lista: eso demuestra
# que la API llegó hasta PostgreSQL y volvió, no solo que respondió 201.
if grep -q "$MARCA" /tmp/respuesta; then
  printf '  ok   %-58s\n' "el mensaje creado aparece en la lista"
else
  printf '  FALLA %-57s\n' "el mensaje creado NO aparece en la lista"
  fallos=$((fallos + 1))
fi

echo
if [ "$fallos" -gt 0 ]; then
  echo "::error::$fallos prueba(s) de integración fallaron"
  exit 1
fi
echo "Todas las pruebas de integración pasaron."
