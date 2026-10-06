#!/usr/bin/env bash
# Resume el resultado de las pruebas en el resumen del run (Reto 6).
#
# Quien aprueba el despliegue no va a abrir seis logs para saber qué está
# aprobando. Esto deja, en la pantalla del run, cuántas pruebas corrieron y
# cuántas pasaron, y si alguna falló, cuál.
#
# Uso: resumen-pruebas.sh informe-vitest.json informe-go.json
set -uo pipefail

VITEST="${1:?falta el informe de Vitest}"
GO="${2:?falta el informe de go test}"
SALIDA="${GITHUB_STEP_SUMMARY:-/dev/stdout}"

{
  echo "## 🧪 Pruebas"
  echo

  if [ -s "$VITEST" ]; then
    total=$(jq '.numTotalTests' "$VITEST")
    ok=$(jq '.numPassedTests' "$VITEST")
    mal=$(jq '.numFailedTests' "$VITEST")
    estado="✅"; [ "$mal" -gt 0 ] && estado="❌"
    echo "| Suite | Total | Pasaron | Fallaron | |"
    echo "|---|---:|---:|---:|---|"
    echo "| Sitio (Vitest + jsdom) | $total | $ok | $mal | $estado |"
  else
    echo "| Suite | Total | Pasaron | Fallaron | |"
    echo "|---|---:|---:|---:|---|"
    echo "| Sitio (Vitest + jsdom) | ? | ? | ? | ⚠️ sin informe |"
  fi

  if [ -s "$GO" ]; then
    gok=$(jq -s '[.[] | select(.Action == "pass" and .Test != null)] | length' "$GO")
    gmal=$(jq -s '[.[] | select(.Action == "fail" and .Test != null)] | length' "$GO")
    gestado="✅"; [ "$gmal" -gt 0 ] && gestado="❌"
    echo "| API en Go (httptest) | $((gok + gmal)) | $gok | $gmal | $gestado |"
  else
    echo "| API en Go (httptest) | ? | ? | ? | ⚠️ sin informe |"
  fi
  echo

  # Si algo falló, el detalle va aquí mismo: es lo único que se quiere leer.
  if [ -s "$VITEST" ] && [ "$(jq '.numFailedTests' "$VITEST")" -gt 0 ]; then
    echo "<details open><summary>Pruebas del sitio que fallaron</summary>"
    echo
    jq -r '.testResults[].assertionResults[] | select(.status == "failed") | "- **\(.fullName)**: \(.failureMessages[0] // "" | split("\n")[0])"' "$VITEST"
    echo
    echo "</details>"
    echo
  fi
  if [ -s "$GO" ] && [ "$(jq -s '[.[] | select(.Action == "fail" and .Test != null)] | length' "$GO")" -gt 0 ]; then
    echo "<details open><summary>Pruebas de la API que fallaron</summary>"
    echo
    jq -s -r '.[] | select(.Action == "fail" and .Test != null) | "- **\(.Test)**"' "$GO"
    echo
    echo "</details>"
    echo
  fi
} >> "$SALIDA"
