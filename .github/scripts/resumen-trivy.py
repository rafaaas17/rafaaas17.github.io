#!/usr/bin/env python3
"""Resume un informe JSON de Trivy en algo que se pueda pegar en la bitácora.

La tabla que imprime Trivy es ilegible en el log de Actions: se corta, mezcla
los paquetes y no deja ver de dónde sale cada vulnerabilidad. Esto imprime el
conteo por severidad y, para las CRITICAL y HIGH, una línea por vulnerabilidad
con el paquete, la versión instalada y la versión que la corrige, que es lo que
hace falta para decidir si se puede arreglar o hay que aceptarla.

Uso:  python3 resumen-trivy.py informe.json [--markdown "nombre de la imagen"]

Con --markdown escribe una tabla para $GITHUB_STEP_SUMMARY (LAB-03, Reto 6):
quien aprueba el despliegue ve cuántas vulnerabilidades hay y de qué severidad
sin abrir el log del job.
"""
import collections
import json
import sys

ORDEN = ["CRITICAL", "HIGH", "MEDIUM", "LOW", "UNKNOWN"]


def markdown(filas, titulo):
    """Tabla para el resumen del run (LAB-03, Reto 6)."""
    conteo = collections.Counter(f[0] for f in filas)
    print("#### %s" % titulo)
    print()
    print("| " + " | ".join(ORDEN) + " | total |")
    print("|" + "---:|" * (len(ORDEN) + 1))
    print("| " + " | ".join(str(conteo[s]) for s in ORDEN) + " | %d |" % len(filas))
    print()

    graves = [f for f in filas if f[0] in ("CRITICAL", "HIGH")]
    if not graves:
        print("Sin CRITICAL ni HIGH.")
        print()
        return
    print("<details><summary>CRITICAL y HIGH (%d)</summary>" % len(graves))
    print()
    print("| Severidad | Paquete | Instalada | Corregida en | CVE |")
    print("|---|---|---|---|---|")
    for f in sorted(graves, key=lambda x: (ORDEN.index(x[0]), x[2])):
        print("| %s | `%s` | `%s` | %s | [%s](https://avd.aquasec.com/nvd/%s) |"
              % (f[0], f[2], f[3], f[4], f[5], f[5].lower()))
    print()
    print("</details>")
    print()


def main(ruta, titulo=None):
    with open(ruta, encoding="utf-8") as f:
        informe = json.load(f)

    filas = []
    for resultado in informe.get("Results") or []:
        # "Target" distingue los paquetes del sistema operativo del binario de
        # Go: es lo que permite ver que una CVE viene del compilador y no de
        # la imagen base.
        origen = resultado.get("Type") or resultado.get("Target") or "?"
        for v in resultado.get("Vulnerabilities") or []:
            filas.append((
                v.get("Severity", "UNKNOWN"),
                origen,
                v.get("PkgName", "?"),
                v.get("InstalledVersion", "?"),
                v.get("FixedVersion") or "sin parche",
                v.get("VulnerabilityID", "?"),
            ))

    if titulo is not None:
        markdown(filas, titulo)
        return

    conteo = collections.Counter(f[0] for f in filas)
    detalle = "  ".join("%s=%d" % (s, conteo[s]) for s in ORDEN if conteo[s])
    print("  total: %d   %s" % (len(filas), detalle or "(ninguna)"))

    graves = [f for f in filas if f[0] in ("CRITICAL", "HIGH")]
    if not graves:
        print("  sin CRITICAL ni HIGH")
        return

    print("  %-8s  %-16s  %-26s  %-18s  %-22s  %s"
          % ("SEV", "ORIGEN", "PAQUETE", "INSTALADA", "CORREGIDA EN", "CVE"))
    for f in sorted(graves, key=lambda x: (ORDEN.index(x[0]), x[1], x[2], x[5])):
        print("  %-8s  %-16s  %-26s  %-18s  %-22s  %s"
              % (f[0], f[1][:16], f[2][:26], f[3][:18], f[4][:22], f[5]))


if __name__ == "__main__":
    if "--markdown" in sys.argv:
        i = sys.argv.index("--markdown")
        main(sys.argv[1], sys.argv[i + 1])
    else:
        main(sys.argv[1])
