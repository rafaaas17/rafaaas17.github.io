# Perfil — Rafael Alarcón Romero

[![CI/CD](https://github.com/rafaaas17/rafaaas17.github.io/actions/workflows/ci-cd.yml/badge.svg?branch=main)](https://github.com/rafaaas17/rafaaas17.github.io/actions/workflows/ci-cd.yml)

Sitio personal publicado en **https://rafaaas17.github.io**

Desde el LAB-02 el perfil tiene además un **libro de visitas**, y para eso el
sitio dejó de ser una página estática: es una aplicación de tres servicios en
contenedores.

| Servicio | Qué hace | Imagen | Puerto |
|---|---|---|---|
| `web` | nginx: sirve el perfil y hace de reverse proxy hacia `/api/` | [`ghcr.io/rafaaas17/perfil-web:1.0`](https://github.com/rafaaas17/rafaaas17.github.io/pkgs/container/perfil-web) | `8080` en tu máquina |
| `api` | La API del libro de visitas, en Go | [`ghcr.io/rafaaas17/perfil-api:1.0`](https://github.com/rafaaas17/rafaaas17.github.io/pkgs/container/perfil-api) | interno |
| `db` | Postgres 16 con un volumen para que los mensajes persistan | se construye en local | interno |

**Solo `web` publica un puerto.** A la API se llega pasando por nginx, y a la
base de datos solo desde la API.

```
navegador ──HTTP──▶ web ──proxy /api/──▶ api ──SQL──▶ db ──▶ volumen pgdata
                    └── red frontend ──┘   └── red backend ──┘
```

---

## El pipeline (LAB-03)

Todo lo que entra a `main` pasa por [`.github/workflows/ci-cd.yml`](.github/workflows/ci-cd.yml).
Los jobs se encadenan con `needs`: si uno falla, los siguientes no corren.

```
build ──▶ test ──▶ package ──▶ security ──┬─▶ smoke ──────┬─▶ deploy-prod
 lint      vitest    ghcr        trivy     │   contenedor  │   ✋ aprobación
 _site/    go test   sha-<commit> semgrep   └─▶ integracion ┘
```

| Job | Qué hace | Qué lo pone en rojo |
|---|---|---|
| `build` | Control de credenciales, HTMLHint sobre `index.html`, Hadolint sobre los tres `Dockerfile`, `gofmt` + `go vet`, compila la API y arma `_site/` | Un `<img>` sin `alt`, un `FROM` sin tag, código sin formatear, una contraseña versionada |
| `test` | Baja el artefacto de Pages y corre Vitest sobre **esos** bytes (13 pruebas), más `go test` de la API | Una prueba del sitio o de la API |
| `package` | Publica `perfil-web` y `perfil-api` en GHCR con el tag `sha-<commit>` | Un `Dockerfile` que no construye |
| `security` | Trivy sobre las dos imágenes recién publicadas y Semgrep sobre mi código | Una `CRITICAL` con corrección, o un hallazgo de nivel `error` |
| `integracion` | Levanta los tres servicios con Compose y prueba el contrato de la API pasando por nginx; escanea la imagen de la base | Un 502, un código HTTP distinto del esperado, un mensaje que no llega a Postgres |
| `smoke` | Baja la imagen escaneada, la levanta y le pide `GET /` | Que no responda 200 o que la página no traiga mi nombre |
| `deploy-prod` | Publica `_site/` en Pages y revisa la URL ya publicada | Solo corre en push a `main`, y **espera aprobación** |

Lo que se prueba, lo que se empaqueta y lo que se publica es el mismo `_site/`: `build` lo
sube una vez como artefacto y los demás jobs lo bajan, en vez de volver a armarlo.

Cada run deja un **resumen** con el resultado de las pruebas, las vulnerabilidades por
severidad y la URL desplegada, para que quien aprueba sepa qué está aprobando.

### Qué se publica
Desde el LAB-03, GitHub Pages ya no sirve la rama: sirve el artefacto que arma
`scripts/armar-sitio.sh`, que lleva `index.html`, `estilos.css` y `libro-de-visitas.js` y
nada más. Por eso `https://rafaaas17.github.io/compose.yaml` ahora responde **404**.

## Delivery o deployment

Mi pipeline es **Continuous Delivery**: de `build` a `smoke` todo es automático y, cuando
termina, la versión ya está construida, escaneada, probada y subida a GitHub Packages, es
decir, lista para producción. El único paso que no ocurre solo es el último:
`deploy-prod` se queda en *Waiting* hasta que alguien aprueba el despliegue.

### Qué cambiaría para que fuera Continuous Deployment

Una sola cosa, y no está en el código:

| | Hoy (Delivery) | Continuous Deployment |
|---|---|---|
| `build` → `smoke` | automático | automático |
| Paso a producción | el environment `github-pages` tiene **Required reviewers**, y el job espera | sin esa regla, `deploy-prod` arranca apenas termina `smoke` |
| Qué hay que tocar | — | Settings → Environments → `github-pages` → quitar *Required reviewers* |

En `ci-cd.yml` no cambiaría ni una línea: la espera no la produce el workflow sino la
regla de protección del environment. Esa es la parte que me sorprendió del Bloque 02: la
frontera entre las dos prácticas es una casilla de configuración, no una arquitectura
distinta.

### Cuándo sí lo haría

Cuando el pipeline sepa responder *solo* la pregunta que hoy respondo yo al aprobar: «¿esto
está bien para producción?». Para este sitio estático eso estaría cerca: tengo linters,
13 pruebas sobre el artefacto, Trivy sobre la imagen, un smoke sobre el contenedor, una
verificación de la URL después de desplegar (Reto 5) y una vuelta atrás probada. Con eso,
la aprobación manual agrega poco: un humano mirando una pantalla verde termina aprobando
sin leer, y una aprobación que siempre se da no es un control, es un trámite.

### Cuándo no lo haría

- **Cuando la vuelta atrás no es barata.** Aquí revertir es otro despliegue de dos
  minutos. Con una migración de base de datos que borra una columna, no hay botón de
  deshacer, y ahí la aprobación es lo que separa un error de un incidente.
- **Cuando el despliegue tiene un costo fuera del sistema:** una app móvil que pasa por
  revisión de la tienda, un cliente que tiene que avisar a sus usuarios, un corte
  acordado con un área de negocio.
- **Cuando el pipeline todavía no cubre lo que importa.** Si no tengo pruebas de lo que
  de verdad puede romperse, automatizar el paso a producción no me da velocidad: me da
  errores más rápido.
- **Cuando hay una regla externa que exige la firma de una persona** (un control de
  cambios, una auditoría). Ahí la aprobación no es técnica, es la evidencia de quién
  autorizó qué, y el registro del environment la deja por escrito.

## Cómo levantarlo

### En GitHub Codespaces

**Code → Codespaces → Create codespace on main.** No hay nada que escribir: el
entorno se construye, genera su `.env`, levanta los tres servicios y abre la
vista previa del perfil solo.

### En tu máquina

Necesitas Docker con el plugin de Compose.

```bash
cp .env.example .env     # una sola vez; edita la contraseña
docker compose up -d --build
```

Y abre http://localhost:8080.

```bash
docker compose ps        # ver el estado de los tres servicios
docker compose down      # apagar, conservando los mensajes
docker compose down -v   # apagar y borrar el volumen (y los mensajes)
```

### Descargar las imágenes sin construirlas

Son públicas, no hace falta autenticarse:

```bash
docker pull ghcr.io/rafaaas17/perfil-api:1.0
docker pull ghcr.io/rafaaas17/perfil-web:1.0
```

---

## Estructura

```
.
├── index.html                  ← en la raíz: GitHub Pages lo necesita ahí
├── estilos.css
├── libro-de-visitas.js         ← cliente de la API
├── web/
│   ├── Dockerfile              ← se construye desde la raíz del repositorio
│   └── nginx.conf              ← sirve el perfil y hace proxy de /api/
├── api/                        ← la API en Go (de lab-02-recursos)
│   ├── Dockerfile              ← dos etapas
│   ├── .dockerignore
│   └── main.go, go.mod, go.sum
├── db/
│   ├── Dockerfile              ← postgres:16-alpine + los scripts de init/
│   └── init/                   ← crea la tabla mensajes
├── compose.yaml                ← los tres servicios, dos redes, un volumen
├── .env.example                ← sí se versiona
├── .env                        ← nunca se versiona
├── .devcontainer/
│   ├── devcontainer.json       ← arranque automático en Codespaces
│   ├── preparar-entorno.sh     ← genera el .env (una vez)
│   └── levantar.sh             ← docker compose up (cada arranque)
├── scripts/
│   ├── armar-sitio.sh          ← arma _site/, lo único que se publica
│   ├── sin-credenciales.sh     ← vigila que no entre ninguna credencial
│   ├── pruebas-integracion.sh  ← contrato de la API, pasando por nginx
│   ├── verificar-produccion.sh ← revisa la URL ya publicada
│   └── resumen-pruebas.sh      ← resumen del run
├── tests/
│   └── sitio.test.js           ← 13 pruebas del sitio (Vitest + jsdom)
├── package.json                ← Vitest, jsdom y HTMLHint
├── .htmlhintrc                 ← reglas del linter de HTML
├── .hadolint.yaml              ← reglas del linter de Dockerfile
├── .trivyignore                ← vulnerabilidades aceptadas, con su porqué
└── .github/
    ├── dependabot.yml          ← acciones, npm, docker y Go al día
    ├── scripts/
    │   └── resumen-trivy.py    ← resume el JSON de Trivy (texto o Markdown)
    └── workflows/
        ├── ci-cd.yml           ← el pipeline: seis etapas y una aprobación
        └── verificar.yml       ← criterios del LAB-02, solo a mano
```

`publicar-imagenes.yml` y `sin-secretos.yml` desaparecieron en el LAB-03: lo que hacían
son ahora el job `package` y el primer paso de `build`. `verificar.yml` no es un segundo
pipeline: solo corre a mano (`workflow_dispatch`) y existe para reproducir los criterios
de aceptación del LAB-02 en un runner limpio.

## Si algo sale mal: volver atrás

El despliegue a producción pasa por una aprobación, pero una aprobación no evita los
errores: evita los errores *que se ven antes de aprobar*. Para el resto hay dos caminos, y
los dos terminan en un despliegue normal.

**1. `git revert` (el que uso).** Se revierte el commit de merge que causó el problema, en
una rama, con su pull request:

```bash
git switch main && git pull
git switch -c fix/volver-atras
git revert -m 1 <sha-del-merge>     # -m 1: quedarse con lo que había en main
git push -u origin fix/volver-atras
gh pr create --fill
```

Ese PR vuelve a pasar por `build`, `test`, `package`, `security`, `integracion` y `smoke`,
y al mezclarlo despliega la versión anterior. Tarda lo que tarda el pipeline (unos tres
minutos más la aprobación), y deja en el historial *qué* se deshizo y *por qué*.

**2. Volver a lanzar un despliegue viejo.** En Actions se puede hacer *Re-run all jobs*
sobre un run anterior que terminó en verde: se reconstruye desde aquel commit y se publica
otra vez. Es más rápido, pero `main` sigue conteniendo el cambio malo: el repositorio dice
una cosa y producción dice otra, y el próximo push lo vuelve a publicar.

**Cuál elijo.** El `revert`, salvo que el sitio esté caído y cada minuto cuente. Es la idea
del curso: todo pasa por el pipeline, y el estado de producción es el de `main`. El re-run
es un parche para ganar tiempo, no un arreglo; después del re-run hay que revertir igual.

**Probado:** [PR #34](https://github.com/rafaaas17/rafaaas17.github.io/pull/34) revirtió un
cambio que ya estaba publicado, y el paso «Revisar el sitio publicado» confirmó que la URL
real volvió a la versión anterior.

## La página en GitHub Pages no se rompe

`https://rafaaas17.github.io` se publica desde el pipeline, cuando apruebo el despliegue
(antes del LAB-03 salía con cada push a `main`), y ahí
**no hay backend**: `/api/mensajes` devuelve un 404 con HTML.
`libro-de-visitas.js` lo detecta —comprueba el código de estado *y* que el
`Content-Type` sea JSON—, deja la sección con su atributo `hidden`, escribe un
aviso en la consola y no toca nada más. El perfil se ve exactamente igual que
en el LAB-01.

---

## Bitácora de decisiones — LAB-03

La evidencia de esta bitácora son los runs de la pestaña
[Actions](https://github.com/rafaaas17/rafaaas17.github.io/actions/workflows/ci-cd.yml).
Cada entrada enlaza el run que la demuestra: uno en rojo cuando rompí algo a propósito y
otro en verde cuando lo arreglé.

### Reto 1: Pipeline rápido

- **Decisión:** cuatro cachés y un job en paralelo. `~/.npm` con `package-lock.json` como
  clave, los módulos y la caché de compilación de Go con `go.sum`, las capas de Docker en
  la caché de Actions (`type=gha`) y la base de vulnerabilidades de Trivy. Las pruebas de
  integración corren en paralelo con el smoke.
- **Antes y después** (el mismo pipeline, lo único que cambia son las cachés):

  | Job | Sin cachés | Con cachés | |
  |---|---:|---:|---|
  | `build` | 41 s | 28 s | −32 % |
  | `test` | 36 s | 25 s | −31 % |
  | `package` | 47 s | 36 s | −23 % |
  | `security` | 21 s | 16 s | −24 % |
  | `smoke` | 8 s | 9 s | +1 s |
  | **Reloj del run** | **200 s** | **124 s** | **−38 %** |

  - Sin cachés: [run 37537619419](https://github.com/rafaaas17/rafaaas17.github.io/actions/runs/37537619419)
  - Con cachés: [run 37538483897](https://github.com/rafaaas17/rafaaas17.github.io/actions/runs/37538483897)
    (es el mismo run relanzado cuando las cachés de `main` ya estaban llenas)

  La diferencia entre la suma de los jobs (153 s → 114 s) y el reloj (200 s → 124 s) es el
  tiempo que tarda cada runner en arrancar: seis máquinas en cadena arrancan seis veces.
- **Alternativas que evalué:**
  1. *Juntar jobs para pagar menos arranques.* Build y test en uno solo ahorraban unos 15 s.
     En contra: se pierde la lectura de la pestaña Actions (¿falló el linter o una prueba?)
     y se pierde la compuerta. No vale 15 s.
  2. *Paralelizar la cadena principal.* No se puede sin romper lo que el pipeline promete:
     `package` solo tiene sentido si `test` pasó, y `security` solo si existe la imagen.
     El único paralelismo honesto es entre jobs que dependen de lo mismo y no entre sí:
     `integracion` y `smoke`, los dos hijos de `security`.
  3. *No cachear nada y vivir con tres minutos.* Es defendible hoy, con un sitio de tres
     archivos; deja de serlo en la semana 6, cuando el pipeline haga más cosas.
- **Por qué elegí esta:** la caché no cambia lo que el pipeline comprueba, solo lo que
  vuelve a descargar. Ninguna compuerta se saltó para ganar tiempo.
- **Fuentes consultadas:**
  - https://docs.github.com/actions/how-tos/write-workflows/choose-what-workflows-do/cache-dependencies
  - https://docs.docker.com/build/cache/backends/gha/
  - https://github.com/actions/setup-node#caching-global-packages-data
- **Cómo lo verifiqué:** con la tabla de arriba, sacada de la pestaña Actions. Los dos runs
  tienen exactamente el mismo contenido de workflow: el segundo es el primero relanzado.
- **Qué no me funcionó:** medir el primer run con cachés. Salió **más lento** que el de
  antes (242 s), y por un momento pensé que las cachés empeoraban las cosas. Lo que pasaba
  es que ese run era el que las estaba *llenando*: `cache-to: type=gha,mode=max` sube todas
  las capas, y eso cuesta. La medición que vale es la del estado estable, no la del primer
  día. Aprendí también que una caché creada en una rama no la ve `main`, pero la de `main`
  sí la ven todas las ramas.

### Reto 2: SAST y resultados a la vista

- **Decisión:** Semgrep (OSS, en contenedor) corre dentro del job `security` sobre la API
  en Go, el JavaScript del sitio, los Dockerfile y los propios workflows. Sus hallazgos y
  los de Trivy se publican en Security → Code scanning con `upload-sarif`, en tres
  categorías separadas. Lo de nivel `error` frena el pipeline; el resto queda registrado.
- **Alternativas que evalué:**
  1. *CodeQL.* A favor: es de GitHub, se integra sin SARIF intermedio y su análisis es más
     profundo (sigue el flujo de los datos, no solo el patrón). En contra: para Go necesita
     compilar y su análisis tarda varios minutos por lenguaje; con el Reto 1 encima, le
     agregaba al pipeline más de lo que yo iba a leer.
  2. *Bandit.* Descartado por un motivo simple: es solo para Python y aquí no hay Python
     de producción.
  3. *Semgrep.* Corre en ~15 s, trae reglas listas por lenguaje (`p/golang`,
     `p/javascript`, `p/secrets`, `p/dockerfile`, `p/github-actions`) y escupe SARIF.
- **Por qué elegí esta:** por el costo por hallazgo. En un sitio de este tamaño, Semgrep me
  da la mayoría del valor en una fracción del tiempo, y el tiempo del pipeline es lo que
  decide si la gente lo espera o lo ignora.
- **La diferencia entre las tres cosas que escanean:**
  | | Qué mira | Herramienta aquí |
  |---|---|---|
  | SAST | el código que escribo yo | Semgrep |
  | SCA | las dependencias que declaro (`go.sum`, `package-lock.json`) | Trivy y Dependabot |
  | Escaneo de imagen | el sistema operativo y los binarios dentro del contenedor | Trivy |
- **Fuentes consultadas:**
  - https://semgrep.dev/docs/
  - https://docs.github.com/code-security/code-scanning/integrating-with-code-scanning/uploading-a-sarif-file-to-github
  - https://github.com/aquasecurity/trivy-action
- **Cómo lo verifiqué:** en su primera corrida, Semgrep devolvió **28 hallazgos** y los
  dejó en Code scanning; después de arreglarlos, la misma categoría quedó en 0. Para ver a
  Trivy encontrando cosas hay un PR aparte con una imagen base vieja.
- **Qué no me funcionó:** mi idea inicial era que el informe y la compuerta fueran el mismo
  escaneo. No sirve: la compuerta tiene que ser estrecha (`CRITICAL` con corrección) para
  que un rojo signifique algo, y el informe tiene que ser amplio (hasta `MEDIUM`, incluidas
  las que no tienen parche) para que Code scanning sirva de inventario. Son dos escaneos
  con dos propósitos, y solo uno tiene `exit-code: 1`.

### Reto 3: Pruebas de integración con Compose

- **Decisión:** un job `integracion` que levanta los tres servicios con
  `docker compose up -d --build --wait` y corre `scripts/pruebas-integracion.sh`, que prueba
  el contrato de la API **desde fuera**, pasando por nginx: `GET /api/health` 200, un POST
  válido 201, un POST sin nombre 400, uno de 281 caracteres 400, uno con cuerpo que no es
  JSON 400, y el mensaje recién creado aparece en `GET /api/mensajes`.
- **Cómo arranca Compose sin mi `.env`:** el runner no lo tiene, y `compose.yaml` se niega a
  arrancar sin él (`${POSTGRES_PASSWORD:?...}`). Lo genera el mismo script del Codespace,
  `.devcontainer/preparar-entorno.sh`, con `openssl rand -hex 24`. La credencial nace y
  muere dentro del job: no hay ningún secreto que guardar en GitHub ni que rotar después.
- **Alternativas que evalué:**
  1. *Un secreto de repositorio con la contraseña de pruebas.* Funciona, pero agrega un
     secreto de verdad para una base de datos que vive 90 segundos, y además hay que
     acordarse de rotarlo.
  2. *Escribir estas pruebas en Vitest con `fetch`.* Habría quedado todo en un solo
     lenguaje. Lo descarté porque obliga a instalar Node y las dependencias en un job que
     solo necesita `curl`, y porque el contrato se lee mejor como una tabla de códigos HTTP.
  3. *Escribirlas con `curl` en un script* (elegida): sin dependencias, y el mismo script
     lo puedo correr en mi máquina contra `localhost:8080`.
- **Por qué el último caso es el importante:** comprobar que el POST devuelve 201 solo prueba
  que la API contestó. Buscar el mensaje en el GET siguiente prueba que llegó hasta
  PostgreSQL y volvió, que es lo que el visitante espera.
- **`if: failure()`:** los logs de los contenedores solo se imprimen cuando algo falla. En
  verde, ochenta líneas de logs son ruido que nadie lee y que esconde lo que importa.
- **Fuentes consultadas:**
  - https://docs.docker.com/reference/cli/docker/compose/up/ (`--wait`, `--wait-timeout`)
  - https://docs.github.com/actions/reference/workflows-and-actions/expressions#failure
- **Cómo lo verifiqué:** con los dos runs que pide el reto.
  - 🔴 [run 37541732659](https://github.com/rafaaas17/rafaaas17.github.io/actions/runs/37541732659)
    ([PR #30](https://github.com/rafaaas17/rafaaas17.github.io/pull/30), cerrado sin mezclar):
    cambié `proxy_pass http://api:3000` por `3001` en `nginx.conf`. `build`, `test`,
    `package`, `security` y `smoke` siguieron **en verde**, y `integracion` se puso en rojo
    con siete 502. Ese es el error que ninguna otra etapa puede ver.
  - 🟢 [run 37541272923](https://github.com/rafaaas17/rafaaas17.github.io/actions/runs/37541272923)
    ([PR #29](https://github.com/rafaaas17/rafaaas17.github.io/pull/29)): con el proxy
    correcto, las ocho comprobaciones pasan.
- **Qué no me funcionó:** mi primera idea era probar el libro de visitas dentro del job
  `smoke`, con la imagen de `web` sola. No se puede: sin la red de Compose, nginx ni
  siquiera arranca, porque resuelve el nombre `api` al iniciar y no al recibir la petición.
  Por eso `smoke` levanta la imagen con `--add-host api:127.0.0.1` y se limita al sitio
  estático, y la aplicación completa se prueba en su propio job.

### Reto 4: mínimo privilegio y cadena de suministro

- **Decisión:** las 28 referencias a acciones de terceros quedaron fijadas al SHA completo
  del commit, con la versión al lado como comentario, y Dependabot vigila cuatro
  ecosistemas (`github-actions`, `npm`, `docker`, `gomod`). Cada job declara sus propios
  `permissions`; el workflow entero arranca con `contents: read`.
- **Cómo apareció:** no lo busqué yo. La primera corrida de Semgrep devolvió 28 hallazgos
  de una sola regla, `github-actions-mutable-action-tag`, uno por cada acción fijada con un
  tag. Y la protección de `main` no dejó mezclar el PR mientras esos hilos siguieran
  abiertos. El control encontró el problema del reto siguiente.
- **Por qué un tag no alcanza:** un tag de Git es un puntero que su dueño puede mover a otro
  commit. Si alguien compromete el repositorio de una acción y reapunta `v45`, mi pipeline
  ejecuta código nuevo sin que yo toque una línea, y con el token del workflow en la mano.
  Es lo que pasó con `tj-actions/changed-files` en marzo de 2025. Un SHA no se puede mover:
  identifica el contenido.
- **Alternativas que evalué:**
  1. *Dejar los tags y confiar en los mantenedores.* Es lo más cómodo y lo que hace casi
     todo el mundo; el costo aparece una sola vez, y es enorme.
  2. *Fijar por SHA sin Dependabot.* Cierra la puerta de los tags y abre la de las acciones
     viejas: un SHA nunca se actualiza solo, y nadie se acuerda de revisarlo a mano.
  3. *Fijar por SHA con Dependabot* (elegida): el SHA fija qué se ejecuta, Dependabot
     propone el cambio y el pipeline lo revisa antes de entrar.
- **Permisos:** el workflow empieza con `contents: read`. Solo `package` tiene
  `packages: write` y solo `security` tiene `security-events: write`. Un `write-all`
  convertiría a cualquier acción de terceros en dueña del repositorio: podría escribir
  commits, abrir releases, borrar ramas o leer los secretos a los que llegue el job.
- **Fuentes consultadas:**
  - https://docs.github.com/actions/security-for-github-actions/security-guides/security-hardening-for-github-actions
  - https://www.stepsecurity.io/blog/harden-runner-detection-tj-actions-changed-files-incident
  - https://docs.github.com/code-security/dependabot/working-with-dependabot/keeping-your-actions-up-to-date-with-dependabot
- **Cómo lo verifiqué:** Semgrep pasó de 28 hallazgos a 0 en el mismo PR, y los hilos de
  Code scanning quedaron resueltos solos.
- **Qué no me funcionó:** intenté mezclar el PR con los 28 hallazgos abiertos, pensando que
  eran solo avisos. La protección de la rama lo impidió por `required conversation
  resolution`. Me pareció molesto durante treinta segundos y correcto después.

### Reto 5: Revisar producción y volver atrás

- **Decisión:** después de `deploy-pages`, un paso corre
  `scripts/verificar-produccion.sh` contra la URL que devuelve `page_url`, con reintentos.
  Comprueba nueve cosas: que `GET /` responde 200, que la página trae mi nombre, que
  `/api/mensajes` da 404 (en Pages no hay backend) y que la sección del libro de visitas
  sigue con su atributo `hidden`, y que `compose.yaml`, `.env.example`, `api/main.go` y
  `README.md` no están publicados.
- **Por qué las dos del libro de visitas:** es la parte frágil. En Pages no hay API, así
  que `libro-de-visitas.js` detecta el 404 y deja la sección oculta. Si alguien quitara ese
  `hidden`, el visitante vería un formulario que no puede enviar nada, y ni los linters ni
  Vitest lo notarían: en el HTML estaría todo bien.
- **Reintentos, no un `sleep`:** la CDN de Pages tarda unos segundos en servir la versión
  nueva. Un `sleep 30` es una apuesta: si tarda 40 s falla, y si tarda 2 s desperdicia 28.
  El script reintenta hasta diez veces cada 6 s y sigue apenas responde.
- **La vuelta atrás, probada:** desplegué a propósito la sección «Ahora estoy
  **aprendiedo**» ([PR #33](https://github.com/rafaaas17/rafaaas17.github.io/pull/33)). Una
  errata que ningún linter ve y ninguna prueba detecta, porque no es un error técnico. La
  revertí con [PR #34](https://github.com/rafaaas17/rafaaas17.github.io/pull/34)
  (`git revert -m 1`), el PR pasó por las seis compuertas y al mezclarlo el sitio volvió a
  la versión anterior. Después la agregué bien escrita en el
  [PR #35](https://github.com/rafaaas17/rafaaas17.github.io/pull/35).
- **¿`git revert` o relanzar un despliegue viejo?** Las dos cosas devuelven el sitio
  anterior, pero solo una deja el repositorio diciendo la verdad. Con *Re-run all jobs* de
  un run antiguo, producción vuelve atrás y `main` se queda con el cambio malo: el
  siguiente push lo vuelve a publicar, y entre tanto nadie sabe qué hay desplegado
  mirando el código. Con `revert`, el estado de producción sigue siendo el de `main` y el
  historial explica qué se deshizo. El re-run lo dejo para una urgencia donde los tres
  minutos del pipeline importen, y aun así después hay que revertir.
- **Alternativas que evalué:** hacer la comprobación con `curl` suelto dentro del YAML
  (más corto, pero no se puede correr en la máquina ni se lee bien), o montar un
  `workflow_dispatch` aparte para verificar a demanda (útil, pero entonces la verificación
  deja de ser parte del despliegue y se convierte en algo que alguien tiene que acordarse
  de lanzar).
- **Fuentes consultadas:**
  - https://github.com/actions/deploy-pages (la salida `page_url`)
  - https://docs.github.com/actions/how-tos/manage-workflow-runs/re-run-workflows-and-jobs
  - https://git-scm.com/docs/git-revert (`-m 1` en un commit de merge)
- **Cómo lo verifiqué:** el paso «Revisar el sitio publicado» del
  [run 37542421385](https://github.com/rafaaas17/rafaaas17.github.io/actions/runs/37542421385)
  lista las nueve comprobaciones en verde, y el
  [run de la vuelta atrás](https://github.com/rafaaas17/rafaaas17.github.io/actions/runs/37548317497)
  las repite sobre la versión revertida.
- **Qué no me funcionó:** la primera versión del script daba por buena cualquier respuesta
  200. Un 200 también lo devuelve una página de error de Pages, así que agregué la
  comprobación del nombre: 200 dice que algo contestó, no que sea mi perfil.

### Reto 6: El pipeline se explica solo

- **Decisión:** cada run escribe en `$GITHUB_STEP_SUMMARY` cuántas pruebas corrieron y
  cuántas pasaron (sitio y API por separado), el conteo de vulnerabilidades por severidad
  de cada imagen con la tabla de CRITICAL y HIGH, cuántos hallazgos devolvió Semgrep, qué
  imagen probó el smoke y a qué URL se desplegó. El README lleva el badge del workflow.
- **Por qué:** quien aprueba el despliegue tiene que saber qué está aprobando. Si para eso
  hay que abrir seis logs, nadie lo hace y la aprobación se vuelve un trámite: se aprieta
  «Approve» porque todo está verde. El resumen pone en una pantalla lo que justifica el
  clic.
- **Alternativas que evalué:**
  1. *El formato `table` de Trivy directo al resumen.* Es lo más rápido de escribir, pero
     la tabla de Trivy mide 120 columnas y en el resumen se corta.
  2. *El formato `template` de Trivy con una plantilla Go.* Da control total, a cambio de
     aprender su sintaxis y mantenerla en un archivo aparte.
  3. *Reutilizar `resumen-trivy.py` del LAB-02* (elegida): ya existía, ya sabía leer el
     JSON de Trivy y solo le agregué una salida en Markdown. Una herramienta menos que
     aprender y un script menos que mantener.
- **Detalle que me gustó:** el detalle de las pruebas que fallaron sale con `<details open>`
  y el resto plegado. Lo que está bien se cuenta; lo que está mal se lee.
- **Fuentes consultadas:**
  - https://docs.github.com/actions/how-tos/write-workflows/choose-what-workflows-do/control-the-concurrency-of-workflows-and-jobs
  - https://github.blog/news-insights/product-news/supercharging-github-actions-with-job-summaries/
  - https://docs.github.com/actions/how-tos/monitor-workflows/add-a-status-badge
- **Cómo lo verifiqué:** en el resumen de cualquier run de `main` desde el PR #32.
- **Qué no me funcionó:** la primera versión corría `go test` dos veces, una para el log
  legible y otra para el JSON. Lo arreglé con `tee` y `jq`, y con `set -o pipefail`, porque
  sin eso el paso tomaba el código de salida de `jq` y una prueba en rojo pasaba por verde.
  Es el tipo de error que convierte un pipeline en decoración.

### Sobre el B3: cómo le llega `_site/` al job test

- **Decisión:** el job `build` arma `_site/` con `scripts/armar-sitio.sh` y lo sube con
  `actions/upload-pages-artifact`. El job `test` **baja ese mismo artefacto** y lo
  desempaqueta antes de correr Vitest. El job `package` hace lo mismo y construye la
  imagen de `web` con `--build-arg SITIO=_site`.
- **Alternativas que evalué:**
  1. *Volver a ejecutar `scripts/armar-sitio.sh` en el job test.* A favor: más simple, un
     paso menos y sin esperar a que el artefacto suba y baje (unos 8 s). En contra: pruebo
     una carpeta que armé por segunda vez. Si el script dependiera de algo del entorno
     (una variable, un archivo que solo existe en un runner, la fecha), podría armar algo
     distinto y yo estaría probando una carpeta y publicando otra.
  2. *Un solo job que haga build, test y package.* A favor: `_site/` no viaja a ningún
     lado. En contra: pierdo las compuertas: en la pestaña Actions ya no puedo ver si lo
     que falló fue el linter o una prueba, y no puedo paralelizar nada.
- **Por qué elegí esta:** el artefacto es exactamente lo que `deploy-pages` publica. Al
  probar el artefacto, Vitest revisa los mismos bytes que terminan en producción, y la
  imagen de `web` también se construye con ellos. Que el script sea determinista es algo
  que yo creo; que el tar sea el mismo es algo que el pipeline demuestra.
- **Fuentes consultadas:**
  - https://github.com/actions/upload-pages-artifact
  - https://github.com/actions/download-artifact
  - https://docs.github.com/actions/how-tos/write-workflows/choose-what-workflows-do/store-and-share-data
- **Cómo lo verifiqué:** en el job `test`, el paso «Desempaquetar el sitio en `_site/`»
  lista los archivos: `index.html`, `estilos.css` y `libro-de-visitas.js`, y nada más. Y
  la prueba «no incluye archivos internos del repositorio» falla si ahí aparece
  `compose.yaml`, `api/`, `db/`, `.env.example` o `tests/`.
- **Qué no me funcionó:** la primera versión armaba `_site/` otra vez en `test`. Funcionaba,
  pero no demostraba nada: el día que el script cambie en una rama y el workflow no, las
  dos carpetas dejan de ser la misma y ninguna prueba se entera.

---

## Bitácora de decisiones — LAB-02

Toda la evidencia de esta bitácora sale del workflow
[**Verificar los retos**](https://github.com/rafaaas17/rafaaas17.github.io/actions/workflows/verificar.yml),
que ejecuta los comandos de aceptación sobre un runner limpio. Se puede
relanzar desde *Actions → Verificar los retos → Run workflow*.

Y empiezo por una aclaración, porque condiciona el resto: **Docker Desktop no
levantaba el daemon en mi máquina** mientras hacía este laboratorio. En vez de
pelearme con eso moví la verificación a GitHub Actions y a un Codespace, que
además es el entorno con el que se califica. Eso tiene una consecuencia honesta
sobre esta bitácora: varias alternativas las descarté **leyendo la
documentación, no chocándome con ellas**. Cuando es así, lo digo, en vez de
inventarme un mensaje de error que suene bien.

---

### Reto 1: Imagen mínima

- **Decisión:** partir `api/Dockerfile` en dos etapas. La primera compila con el
  toolchain completo de Go; la segunda es un Alpine al que solo se le copia el
  binario, compilado con `CGO_ENABLED=0` para que sea estático y no dependa de
  la libc de la imagen donde corra.

- **Alternativas que evalué:**

  | | A favor | En contra |
  |---|---|---|
  | Una etapa (`golang:1.23-bookworm`) | Un solo `FROM`, se entiende de un vistazo | 1,03 GB para correr un binario de 9,6 MB, con compilador y fuentes dentro |
  | Multi-stage → `scratch` | ~10 MB, superficie de ataque casi nula | No hay shell: `docker compose exec api whoami` (Reto 3) no tiene qué ejecutar, y el healthcheck HTTP (Reto 2) exigiría compilar un segundo binario |
  | Multi-stage → `gcr.io/distroless/static` | ~12 MB, trae certificados y `/etc/passwd` | Mismo problema: sin shell ni `wget` |
  | **Multi-stage → `alpine`** | 20,4 MB, y busybox da `whoami`, `wget` y `sh` | ~10 MB más que scratch |

- **Por qué elegí esta:** los MB extra de Alpine compran dos retos verificables
  y la posibilidad de entrar al contenedor a depurar. Pero lo importante es que
  **la reducción no viene de la imagen base sino de separar las etapas**: lo que
  no se copia con `COPY --from` no existe en la imagen final. No es lo mismo que
  borrarlo con un `RUN rm`, porque eso deja la capa anterior intacta y el
  contenido se puede recuperar.

  Las dos banderas que lo hacen posible:
  `CGO_ENABLED=0` (binario estático, independiente de la libc de destino) y
  `-trimpath -ldflags="-s -w"` (quita rutas de compilación, tabla de símbolos e
  información de depuración).

- **Fuentes consultadas:**
  - [Multi-stage builds](https://docs.docker.com/build/building/multi-stage/) — Docker Docs
  - [`cgo`](https://pkg.go.dev/cmd/cgo) y [flags del enlazador](https://pkg.go.dev/cmd/link) — Go
  - [distroless](https://github.com/GoogleContainerTools/distroless)
  - [`.dockerignore`](https://docs.docker.com/build/concepts/context/#dockerignore-files)

- **Cómo lo verifiqué:**

  ```
  $ docker images --format "table {{.Repository}}:{{.Tag}}\t{{.Size}}"
  REPOSITORY:TAG                                      SIZE
  perfil-api:ingenua                                  1.03GB
  ghcr.io/rafaaas17/perfil-api:1.0                    20.2MB
  ghcr.io/rafaaas17/perfil-web:1.0                    54.6MB
  perfil-db:1.0                                       294MB
  ```

  | | Bytes | |
  |---|---:|---|
  | Una etapa | 1 028 749 024 | |
  | Dos etapas | **20 358 616** | **−98,0 %** |

  El criterio pedía bajar de la mitad; bajó a **1/50**. (Justo después del
  Reto 1 eran 18,4 MB; subió a 20,4 MB al actualizar la base y el compilador en
  el Reto 5, y esos 2 MB de más compran 75 vulnerabilidades menos.)

  ```
  $ docker history ghcr.io/rafaaas17/perfil-api:1.0
  SIZE      CREATED BY
  0B        ENTRYPOINT ["/usr/local/bin/api"]
  0B        HEALTHCHECK {Test:[CMD-SHELL wget -q -O /dev/null "http://127.0.0.1:${PORT:-3000}/api/health" || exit 1] ...}
  0B        EXPOSE [3000/tcp]
  0B        USER 10001:10001
  11MB      COPY /out/api /usr/local/bin/api # buildkit
  907kB     RUN /bin/sh -c apk add --no-cache ca-certificates tzdata && addgroup ... && adduser ... # buildkit
  0B        CMD ["/bin/sh"]
  8.42MB    ADD alpine-minirootfs-3.24.2-x86_64.tar.gz / # buildkit
  ```

  Ocho capas y ninguna del compilador. Comprobado también desde dentro:

  ```
  hay binario de go?  no, ninguno
  hay cache de apk?   (vacío)
  hay codigo fuente?  no existe /src
  ```

- **Qué no me funcionó:** el multi-stage salió bien a la primera, así que lo
  honesto es decir qué **no llegué a probar**: no construí la variante con
  `scratch`. La descarté sobre el papel al ver que los criterios de los Retos 2
  y 3 exigen `wget` y `whoami` *dentro* del contenedor y que `scratch` no tiene
  ni shell ni binarios. Es una decisión tomada leyendo; si me la discuten no
  tengo una captura que enseñar, tengo el argumento.

  Lo que sí se me rompió de verdad fue más tonto. Al escribir los `HEALTHCHECK`
  se me colapsaron las continuaciones de línea y quedaron
  `--retries=5     CMD wget …` en una sola línea. Docker las lee igual, así que
  **no falló nada**, y justo por eso casi se queda así; lo arreglé en el PR del
  Reto 3. La lección: que algo funcione no quiere decir que esté bien escrito.

---

### Reto 2: Arranque ordenado

- **Decisión:** un `HEALTHCHECK` en cada uno de los tres Dockerfiles, y
  `depends_on` con `condition: service_healthy` en `compose.yaml`.

- **Alternativas que evalué:**

  | | A favor | En contra |
  |---|---|---|
  | `depends_on` a secas | Ya estaba escrito | Solo ordena el arranque: la API arranca en cuanto el contenedor de Postgres *existe*, segundos antes de que acepte conexiones |
  | `restart: unless-stopped` y que reintente | Cero configuración; acaba funcionando | Funciona por insistencia: durante el ciclo de reinicios el sitio devuelve errores, y en el Codespace la vista previa se abre justo en ese hueco |
  | Un `wait-for-it.sh` como entrypoint | Independiente de Compose | Mete lógica de arranque en la imagen, suma un proceso y hay que mantenerlo |
  | **`HEALTHCHECK` + `condition: service_healthy`** | Es la pregunta correcta: *¿estás listo?*, no *¿existes?* | Algo más de configuración |
  | `healthcheck:` en `compose.yaml` en lugar del Dockerfile | Menos líneas, todo en un archivo | La imagen deja de describirse a sí misma |

- **Por qué elegí esta:** los chequeos van **en el Dockerfile** porque quien haga
  `docker run` de `ghcr.io/rafaaas17/perfil-api:1.0` sin mi `compose.yaml`
  merece tener el mismo chequeo. En el LAB-03 compose desaparece y las imágenes
  siguen siendo estas.

  | Servicio | Comando | Por qué |
  |---|---|---|
  | `db` | `pg_isready -h 127.0.0.1 -U … -d …` | ver abajo |
  | `api` | `wget -q -O /dev/null "http://127.0.0.1:${PORT:-3000}/api/health"` | `/api/health` hace *ping* a Postgres y devuelve **503** si no lo alcanza: un proceso vivo que no ve su base de datos no está sano |
  | `web` | `wget -q -O /dev/null http://127.0.0.1:8080/healthz` | `/healthz` responde 200 sin tocar disco ni la API |

  **El `-h 127.0.0.1` de `pg_isready` es la parte fina.** Durante la
  inicialización, la imagen oficial de Postgres levanta un servidor temporal que
  escucha **solo en el socket unix** para ejecutar los scripts de `init/`. Sin
  `-h`, `pg_isready` encuentra ese servidor temporal y da la base por lista
  mientras las tablas todavía se están creando.

  Y el chequeo HTTP **sin `curl`**: Alpine no lo trae y no lo instalé. `wget` de
  busybox ya está en la imagen; instalar `curl` habría sumado peso y superficie
  justo después del Reto 1. Los dos chequeos HTTP van en **forma shell** (sin
  corchetes) para que `${PORT}` se expanda en tiempo de ejecución.

- **Fuentes consultadas:**
  - [`HEALTHCHECK`](https://docs.docker.com/reference/dockerfile/#healthcheck) — Dockerfile reference
  - [Control startup order](https://docs.docker.com/compose/how-tos/startup-order/) — Docker Docs
  - [`depends_on`](https://docs.docker.com/reference/compose-file/services/#depends_on) — Compose spec
  - [`pg_isready`](https://www.postgresql.org/docs/16/app-pg-isready.html) — PostgreSQL 16
  - [`docker-entrypoint.sh` de Postgres](https://github.com/docker-library/postgres/blob/master/16/alpine3.24/docker-entrypoint.sh) — el servidor temporal sobre socket unix

- **Cómo lo verifiqué:**

  ```
  $ docker compose ps
  NAME           IMAGE                              SERVICE   STATUS
  perfil-api-1   ghcr.io/rafaaas17/perfil-api:1.0   api       Up 11 seconds (healthy)
  perfil-db-1    perfil-db:1.0                      db        Up 16 seconds (healthy)
  perfil-web-1   ghcr.io/rafaaas17/perfil-web:1.0   web       Up 5 seconds (healthy)
  ```

  Y `docker compose up -d --wait` devuelve el control recién cuando los tres
  pasan por `Waiting → Healthy`, en cascada:

  ```
   Container perfil-db-1   Started
   Container perfil-db-1   Waiting
   Container perfil-db-1   Healthy
   Container perfil-api-1  Starting
   Container perfil-api-1  Waiting
   Container perfil-api-1  Healthy
   Container perfil-web-1  Starting
   Container perfil-web-1  Waiting
   Container perfil-web-1  Healthy
  ```

- **Qué no me funcionó:** nada, y conviene decirlo así. Funcionó en la primera
  ejecución del workflow.

  El `-h 127.0.0.1` **no lo aprendí a golpes**: lo puse desde el principio
  porque el README del repositorio de recursos avisa de que los scripts de
  `init/` corren una sola vez y con el volumen vacío, y eso me mandó a leer el
  `docker-entrypoint.sh` de la imagen oficial, donde se ve el servidor temporal.
  El fallo que **habría** tenido es conocido: `pg_isready` sin `-h` da `healthy`
  en un par de segundos, la API arranca y se encuentra con que la tabla
  `mensajes` todavía no existe, de forma intermitente según lo rápida que sea la
  máquina. No lo sufrí; lo evité leyendo.

---

### Reto 3: Nadie es root

- **Decisión:** los tres contenedores corren como un usuario sin privilegios, y
  cada uno lo consigue de una forma distinta.

- **Alternativas que evalué**, para el caso difícil, que es `web`:

  | | A favor | En contra |
  |---|---|---|
  | Imagen oficial de nginx tal cual | Es la que todo el mundo usa | El PID 1 es root; solo los *workers* bajan a `nginx` |
  | Oficial + `user: "101"` en compose | Un renglón | El entrypoint crea `/var/cache/nginx/*` y `/var/run/nginx.pid` siendo root; si ya no lo es, falla al arrancar |
  | Oficial + `cap_add: [NET_BIND_SERVICE]` | Funciona y conserva el puerto 80 | Es devolverle un privilegio al contenedor para conservar un número de puerto que dentro de Docker no significa nada |
  | **`nginxinc/nginx-unprivileged`** | Del mismo equipo de nginx; escucha en 8080 y trae los permisos ya resueltos | Otra imagen que seguir |

- **Por qué elegí esta:** **la imagen oficial de nginx necesita ser root por una
  razón concreta:** su proceso maestro abre el puerto **80**, y en Linux los
  puertos por debajo de 1024 están reservados a root o a quien tenga
  `CAP_NET_BIND_SERVICE`. Recién después de abrirlo baja de privilegios. La
  variante *unprivileged* escucha en 8080 y por eso no necesita serlo nunca.
  Dentro de un contenedor el número de puerto da igual: quien decide en qué
  puerto se ve la aplicación es `ports: "8080:8080"`. Por eso la API también
  escucha en 3000 y no en 80.

  En `api`, Alpine no trae ningún usuario sin privilegios pensado para esto, así
  que lo creo en la misma capa del `apk add`. Uso `USER 10001:10001` **en
  numérico** y no `USER app`: así Kubernetes puede comprobar `runAsNonRoot` sin
  resolver `/etc/passwd`, que es lo que va a hacer falta en el LAB-03. El nombre
  igual existe, y por eso `whoami` responde `app`.

  En `db` hay un matiz que casi se me pasa: **el proceso de Postgres nunca corre
  como root**. El entrypoint oficial arranca como root solo para ajustar
  permisos y enseguida baja a `postgres` con `gosu`. Pero el *contenedor* sí es
  root, y `docker compose exec db whoami` respondería `root`. `USER postgres` lo
  cierra, y funciona porque la imagen deja `/var/lib/postgresql/data` con
  permisos que `postgres` puede usar y Docker crea el volumen nombrado heredando
  esos permisos; al detectar que no es root, el entrypoint se salta el `gosu`.

- **Fuentes consultadas:**
  - [`nginx-unprivileged`](https://github.com/nginx/docker-nginx-unprivileged) — repositorio oficial
  - [`USER`](https://docs.docker.com/reference/dockerfile/#user) — Dockerfile reference
  - [`capabilities(7)`](https://man7.org/linux/man-pages/man7/capabilities.7.html) — `CAP_NET_BIND_SERVICE`
  - [`docker-entrypoint.sh` de Postgres](https://github.com/docker-library/postgres/blob/master/16/alpine3.24/docker-entrypoint.sh) — la rama `if [ "$(id -u)" = '0' ]`
  - [Configure a Security Context](https://kubernetes.io/docs/tasks/configure-pod-container/security-context/) — `runAsNonRoot`

- **Cómo lo verifiqué:**

  ```
  $ for s in web api db; do docker compose exec $s whoami; done
  web  nginx
  api  app
  db   postgres

  $ for s in web api db; do docker compose exec $s id; done
  web  uid=101(nginx)   gid=101(nginx)   groups=101(nginx)
  api  uid=10001(app)   gid=10001(app)   groups=10001(app)
  db   uid=70(postgres) gid=70(postgres) groups=70(postgres)
  ```

- **Qué no me funcionó:** las dos alternativas de la tabla (`user: "101"` sobre
  la imagen oficial y `cap_add: NET_BIND_SERVICE`) **no las probé**. Las
  descarté leyendo el `docker-entrypoint.sh` de la imagen oficial y el README de
  `nginx-unprivileged`, donde el propio equipo de nginx explica por qué existe
  esa variante. Si me preguntan por el mensaje de error exacto, no lo tengo:
  tengo el motivo.

  Lo que sí me preocupaba de verdad era `db`, porque `USER postgres` depende de
  que el volumen nombrado herede los permisos del directorio de datos de la
  imagen, y si no, Postgres no arranca. Eso **sí** lo verifiqué antes de darlo
  por bueno: el entrypoint detecta que no es root, se salta el `gosu` y arranca
  igual. Era el punto donde más fácil era equivocarse.

---

### Reto 4: Red segmentada

- **Decisión:** dos redes. `frontend` conecta `web` con `api`; `backend`
  conecta `api` con `db` y está marcada `internal: true`. `api` es el único
  servicio en las dos.

- **Alternativas que evalué:**

  | | A favor | En contra |
  |---|---|---|
  | Una sola red (lo que hace compose por defecto) | Cero configuración | Los tres se ven entre sí: desde `web`, que es el contenedor expuesto a internet, se puede abrir una conexión a `db:5432` |
  | Una red + reglas de firewall dentro de los contenedores | Control fino | Hay que mantenerlas en cada imagen y basta un error para abrir el paso |
  | **Dos redes** | La separación es topológica: no hay ruta, no hay nombre | Hay que declararlas y pensar qué servicio va en cuál |

- **Por qué elegí esta:** una red de Docker es un switch virtual con su propio
  DNS, y un contenedor solo resuelve los nombres de los servicios conectados a
  **su misma red**. Desde `web` el nombre `db` no es que esté prohibido: **no
  existe**. No hay reglas que alguien pueda desactivar por error.

  `internal: true` en `backend` va un paso más: Docker no le pone gateway, así
  que la base de datos no tiene salida a internet. No la necesita, y a quien
  consiguiera ejecutar algo dentro de `db` le quita por dónde sacar los datos.
  `api` conserva salida porque también está en `frontend`.

  **`ports` y `expose` no son lo mismo:** `ports` publica el puerto en el host y
  es lo único que abre un agujero hacia fuera de Docker; solo lo tiene `web`.
  `expose` no publica nada, solo documenta qué puerto escucha el contenedor. En
  una red definida por el usuario los contenedores se alcanzan igual aunque no
  haya `expose`; lo dejo porque declara la intención.

- **Fuentes consultadas:**
  - [Networking in Compose](https://docs.docker.com/compose/how-tos/networking/) — Docker Docs
  - [`networks` top-level element](https://docs.docker.com/reference/compose-file/networks/) — incluido `internal`
  - [Container networking](https://docs.docker.com/engine/network/) — el DNS embebido en 127.0.0.11
  - [Least privilege](https://csrc.nist.gov/glossary/term/least_privilege) — NIST

- **Cómo lo verifiqué:**

  ```
  $ docker network ls --filter name=perfil
  NETWORK ID     NAME              DRIVER    SCOPE
  fb51412f4075   perfil_backend    bridge    local
  f45b1f979f89   perfil_frontend   bridge    local

  $ docker compose exec api getent hosts db
  172.18.0.2        db  db                    ← resuelve

  $ docker compose exec web getent hosts db
                                              ← sin salida, código de salida 2

  $ docker compose ps --format "table {{.Service}}\t{{.Ports}}"
  SERVICE   PORTS
  api       3000/tcp
  db
  web       0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp
  ```

  Ni `api` ni `db` publican nada hacia el host: solo `web`.

- **Qué no me funcionó:** también salió a la primera. Lo que sí me hizo dudar
  fue `internal: true`: mi primer impulso fue ponerlo en las **dos** redes, y me
  frené al caer en que `api` es el único servicio en las dos y, si las dos son
  internas, se queda sin salida a internet. Hoy no la necesita, pero el día que
  la necesite el síntoma sería un *timeout* en la aplicación y la causa estaría
  en `compose.yaml`, que es donde nadie mira.

  Y queda una cosa a medias que prefiero decir: `proxy_pass http://api:3000`
  hace que **nginx resuelva el nombre `api` una sola vez, al cargar la
  configuración**. Si `api` se reinicia y Docker le da otra IP, nginx sigue
  hablando con la vieja hasta que se recargue. Ahora no molesta porque
  `depends_on: condition: service_healthy` garantiza que `api` ya existe cuando
  `web` arranca, pero la solución de verdad es declarar
  `resolver 127.0.0.11 valid=10s` y pasar la URL por una variable. No lo hice
  para no tocar el manejo de la URI del `proxy_pass`, que es la parte frágil de
  esta configuración. Lo dejo anotado como deuda.

---

### Reto 5: Escaneo de vulnerabilidades

- **Decisión:** escanear con **Trivy 0.58.0** y arreglar en **dos vueltas**:
  primero las imágenes base de los tres servicios —incluida la del
  **compilador**—, y después las **dependencias del módulo de Go**. La imagen de
  la API terminó en **0 vulnerabilidades**, desde 7 997.

- **Alternativas que evalué:**

  | | A favor | En contra |
  |---|---|---|
  | Docker Scout | Integrado en Docker Desktop, buena salida | Requiere cuenta de Docker y tiene límites en el plan gratuito; además mi Docker Desktop no arrancaba |
  | **Trivy** | Open source (Aqua Security), corre como contenedor, sin cuenta, y **escanea también el binario de Go** | La base de datos de CVE se descarga en cada ejecución |
  | `grype` | Muy parecido | Nada en contra; elegí Trivy por documentación y por ser el más usado en CI |

- **Por qué elegí esta:** Trivy no necesita cuenta, corre como un contenedor más
  y, sobre todo, no se queda en los paquetes del sistema: **también lee el
  binario de Go**, que es donde estaba la mitad del problema.

  **Lo que no esperaba:** Go enlaza estáticamente su biblioteca estándar y graba
  en el binario con qué toolchain se compiló, así que la versión del compilador
  **no se queda en la etapa de build**: Trivy la lee en la imagen final. Con
  Go 1.23 aparecían `CVE-2026-56853` (net/http), `CVE-2026-56860` (net/url),
  `CVE-2026-56862` (crypto/tls), `CVE-2026-56858` (html/template) y una docena
  más, todas con *fixed version* `1.25.13 / 1.26.6 / 1.27.0-rc.3`. No hay nada
  que arreglar en `main.go`: **las arregla el compilador**.

  **La CVE que elijo para explicar: `CVE-2026-40200`, en `musl`.** `musl` es la
  implementación de libc de Alpine: la biblioteca C que usa todo lo que corre
  dentro de la imagen. Aunque el binario de Go sea estático, `wget`, `whoami` y
  el resto de busybox la usan entera. Es un desbordamiento de pila que permite
  ejecución arbitraria de código o denegación de servicio, y es crítica porque
  un fallo en la libc es alcanzable desde casi cualquier ruta que procese datos
  externos.

  Afecta a `musl 1.2.5-r9`, la que trae Alpine 3.20, y está corregida en
  `1.2.5-r11`. **No se parchea a mano:** no puedo recompilar musl dentro de la
  imagen, y un `apk upgrade` sobre 3.20 no la trae porque el parche salió en la
  rama siguiente. La corrección es subir de rama, a `alpine:3.24.2`. Lo mismo
  con `CVE-2026-22184` (zlib) y, en `web`, `CVE-2026-27135` (nghttp2) y las de
  libxml2.

  **Primera vuelta — las bases y el compilador:**

  | Archivo | Antes | Ahora |
  |---|---|---|
  | `api/Dockerfile` (build) | `golang:1.23-alpine3.20` | `golang:1.27.1-alpine3.24` |
  | `api/Dockerfile` (final) | `alpine:3.20` | `alpine:3.24.2` |
  | `web/Dockerfile` | `nginxinc/nginx-unprivileged:1.27-alpine` | `nginxinc/nginx-unprivileged:1.31.6-alpine3.24` |
  | `db/Dockerfile` | `postgres:16-alpine` | `postgres:16.15-alpine3.24` |

  **Segunda vuelta — las dependencias.** Con las bases al día quedaban 26
  vulnerabilidades en la API, y el resumen detallado enseñó que **ya no venían
  ni de Alpine ni de la biblioteca estándar**, sino del propio módulo:

  | Origen | Paquete | Instalada | Corregida en | |
  |---|---|---|---|---|
  | `gobinary` | `github.com/jackc/pgx/v5` | v5.7.1 | 5.9.0 | 2 × CRITICAL |
  | `gobinary` | `golang.org/x/crypto` | v0.27.0 | 0.31.0 – 0.55.0 | 13 × HIGH |
  | `gobinary` | `golang.org/x/text` | v0.18.0 | 0.39.0 | 1 × HIGH |

  Había versión corregida para todas, así que `go get -u` y `go mod tidy`.
  Lo interesante no fue la actualización sino una desaparición: **pgx 5.11 ya no
  depende de `golang.org/x/crypto`**, que era el origen de 13 de las 14 altas.
  Una dependencia que no existe no tiene CVE. `main.go` no cambió ni una línea,
  porque `pgx` se usa a través de `database/sql`.

- **Fuentes consultadas:**
  - [Trivy — Scanning images](https://trivy.dev/latest/docs/target/container_image/)
  - [Trivy — Go binaries](https://trivy.dev/latest/docs/coverage/language/golang/) — por qué se escanea el binario
  - [CVE-2026-40200](https://avd.aquasec.com/nvd/cve-2026-40200) — Aqua Vulnerability Database
  - [Go security policy](https://go.dev/doc/devel/release#policy)
  - [Alpine security tracker](https://security.alpinelinux.org/)
  - [CVSS v3.1](https://www.first.org/cvss/v3.1/specification-document) — cómo se lee una severidad

- **Cómo lo verifiqué:**

  Cuatro escaneos de la **misma imagen de la API** con el mismo comando, en
  cuatro momentos del laboratorio:

  | Imagen de la API | Total | CRITICAL | HIGH |
  |---|---:|---:|---:|
  | Una etapa, `golang:1.23-bookworm` | 7 997 | 48 | 1 371 |
  | Multi-stage sobre `alpine:3.20`, compilada con Go 1.23 | 75 | 3 | 35 |
  | Multi-stage sobre `alpine:3.24.2`, compilada con Go 1.27.1 | 26 | 2 | 14 |
  | **…y con `pgx` y `golang.org/x/*` actualizados** | **0** | **0** | **0** |

  ```
  $ docker run --rm -v /var/run/docker.sock:/var/run/docker.sock \
      aquasec/trivy:0.58.0 image --scanners vuln --format json \
      ghcr.io/rafaaas17/perfil-api:1.0 > trivy.json
  $ python3 .github/scripts/resumen-trivy.py trivy.json

  ---- ghcr.io/rafaaas17/perfil-api:1.0 ----
    total: 0   (ninguna)
    sin CRITICAL ni HIGH
  ```

  Y las otras dos imágenes:

  ```
  ---- ghcr.io/rafaaas17/perfil-web:1.0 ----
    total: 1   HIGH=1
    SEV       ORIGEN     PAQUETE     INSTALADA   CORREGIDA EN   CVE
    HIGH      alpine     libexpat    2.8.4-r0    2.8.5-r0       CVE-2026-93990

  ---- perfil-db:1.0 ----
    total: 46   CRITICAL=1  HIGH=21  MEDIUM=21  LOW=2  UNKNOWN=1
    SEV       ORIGEN     PAQUETE     INSTALADA   CORREGIDA EN              CVE
    CRITICAL  gobinary   stdlib      v1.24.6     1.24.13, 1.25.7, 1.26.…   CVE-2025-68121
    HIGH      gobinary   stdlib      v1.24.6     1.24.12, 1.25.6           CVE-2025-61726
    …  (las 22 son de "gobinary stdlib v1.24.6", ninguna de Alpine)
  ```

  **Las 22 CRITICAL/HIGH de `db` salen todas del mismo sitio** y ninguna es de
  un paquete de Alpine: son de binarios de Go que la imagen oficial de Postgres
  trae compilados con Go 1.24.6, empezando por `gosu`. Eso es lo que se acepta,
  y abajo está por qué.

- **Qué no me funcionó:** este es el reto donde de verdad me equivoqué, tres
  veces.

  **Una.** Daba por hecho que después del Reto 1 el trabajo estaba hecho: pasar
  de 7 997 a 75 vulnerabilidades parecía suficiente. Al abrir el detalle
  resultó que **la mayoría de las que quedaban no venían de Alpine sino del
  binario de Go**, porque el compilador enlaza su biblioteca estándar dentro y
  graba su versión. Yo había asumido que la etapa de build «desaparecía»
  entera, y no es cierto: desaparece el compilador, pero no lo que el
  compilador dejó dentro del binario.

  **Dos.** Cambié la base de `db` de `postgres:16-alpine` a
  `postgres:16.15-alpine3.24` esperando bajar sus vulnerabilidades, y **no bajó
  ninguna**: el conteo quedó idéntico. `16-alpine` ya era un alias de
  `16.15-alpine3.24`. El cambio sigue valiendo la pena, pero **no por seguridad
  sino por reproducibilidad** —un tag flotante hace que dos builds del mismo
  commit puedan dar imágenes distintas—, y decirlo bien importa: la medida no
  hizo lo que yo creía.

  **Tres, y es la que más me enseñó.** Al actualizar las dependencias se rompió
  el propio workflow de verificación:

  ```
  ERROR: process "/bin/sh -c go mod download" did not complete successfully: exit code 1
  ```

  El paso que construye el «antes» tomaba **solo el `Dockerfile`** de aquel
  commit y lo construía contra el `api/` de hoy. Aquel Dockerfile usa
  `golang:1.23-bookworm` y el `go.mod` de hoy exige `go 1.26.0`, así que Go se
  negó. Lo arreglé reconstruyendo con `git archive` la carpeta `api/` **entera**
  de ese commit: el «antes» honesto es el código de entonces con el compilador
  de entonces, no una mezcla. Sin el workflow no me habría enterado de que mi
  punto de comparación se había podrido por debajo.

- **Qué acepté:** «cero vulnerabilidades» no es la meta, aunque en la API haya
  salido. Quedan dos casos y los dos se aceptan a conciencia:

  **`web`, 1 HIGH:** `CVE-2026-93990` en `libexpat 2.8.4-r0`, corregida en
  `2.8.5-r0`. El parche existe pero todavía no está en la imagen publicada de
  `nginx-unprivileged`. Podría forzarlo con `USER root` + `apk upgrade` y volver
  a bajar de privilegios, pero eso cambia una capa de root y algo de
  reproducibilidad por una CVE de un parser de XML que el camino del proxy no
  usa. Prefiero esperar a la imagen siguiente.

  **`db`, 1 CRITICAL y 21 HIGH:** las 22 son de `gobinary stdlib v1.24.6`,
  ninguna de un paquete de Alpine. Son los binarios de Go que la imagen oficial
  de Postgres trae compilados por sus mantenedores, empezando por `gosu`. Para
  quitarlas tendría que dejar de usar la imagen oficial y construir Postgres yo:
  cambiaría unas CVE conocidas y con parche por un montón de errores míos.

  Tampoco puse `--exit-code 1` en el escaneo de CI, por lo mismo: un workflow
  que se pone rojo por algo que no se puede arreglar se acaba ignorando, y
  entonces ya no sirve para nada.

---

### Reto 6: Cero secretos… y aun así arranca solo

- **Decisión:** no guardar ninguna contraseña. El `.env` no está en el
  repositorio y **nadie lo escribe**: `.devcontainer/preparar-entorno.sh` lo
  genera en el Codespace, la primera vez, con
  `POSTGRES_PASSWORD=$(openssl rand -hex 24)`.

- **La contradicción del enunciado, y cómo se resuelve:** el repositorio no
  puede tener la contraseña, pero un Codespace recién creado tampoco tiene
  `.env` y la aplicación tiene que arrancar sola. Parecen incompatibles hasta
  que uno cae en que **nadie necesita conocer esa contraseña**. Solo la usan
  `api` y `db`, dentro de la red `backend`, que ni siquiera publica el puerto
  5432. No es un secreto que haya que transmitir: es un valor que dos
  contenedores tienen que compartir. Y para eso no hace falta guardarlo en
  ningún sitio, basta con generarlo donde se va a usar.

- **Alternativas que evalué:**

  | | A favor | En contra |
  |---|---|---|
  | Contraseña fija en `compose.yaml` | Arranca solo, sin más | Es exactamente lo que el reto prohíbe, y son −5 puntos |
  | `ENV POSTGRES_PASSWORD=…` en el Dockerfile | Igual de cómodo | Peor: queda en una capa de la imagen, visible con `docker history --no-trunc` para cualquiera que haga `pull`. Borrarla en una capa posterior no la quita |
  | **Secretos de Codespaces** | Es el mecanismo correcto de GitHub y el que usaría en un proyecto real | **No le sirve a quien califica:** el secreto es de *mi* cuenta. Cuando el profesor abra un Codespace desde la suya, la variable no existe y la aplicación no arranca. El B3 se cae |
  | `docker secret` / secretos de Compose | Lo correcto en producción: el valor va a un archivo, no al entorno | Sigue haciendo falta que el archivo exista, así que no resuelve el problema, solo lo mueve |
  | **Generar el `.env` en `postCreateCommand`** | El repositorio no tiene nada que filtrar y el Codespace arranca solo, con contraseña distinta cada vez | La contraseña es efímera: si alguien borra el `.env` sin borrar el volumen, los datos quedan inaccesibles |

- **Por qué elegí esta:** es la única que cumple las dos condiciones a la vez. Y
  dejó clara una distinción que antes no tenía del todo: **una credencial de
  desarrollo no es un secreto de producción**. Esta contraseña protege una base
  de datos efímera, sin puerto publicado, en una red interna y con datos de
  prueba. Su valor no importa; lo que importa es que no viaje en el repositorio,
  porque el hábito de commitear un `.env` es el que después filtra el de
  producción. En un proyecto real el valor vendría de un gestor de secretos, y
  el mecanismo —variables de entorno, nunca capas de imagen— sería el mismo.

  Por eso va en `postCreateCommand` y no en `postStartCommand`: generar el
  `.env` corre **una sola vez**. Si corriera en cada arranque, cada reanudación
  del Codespace cambiaría la contraseña y dejaría el volumen de Postgres
  inaccesible.

- **Fuentes consultadas:**
  - [Environment variables in Compose](https://docs.docker.com/compose/how-tos/environment-variables/set-environment-variables/)
  - [Interpolation y `${VAR:?error}`](https://docs.docker.com/reference/compose-file/interpolation/)
  - [Managing secrets for Codespaces](https://docs.github.com/en/codespaces/managing-your-codespaces/managing-your-account-specific-secrets-for-github-codespaces) — de quién son los secretos
  - [Lifecycle scripts](https://containers.dev/implementors/json_reference/#lifecycle-scripts) — containers.dev
  - [`docker history`](https://docs.docker.com/reference/cli/docker/image/history/)

- **Cómo lo verifiqué:**

  ```
  $ git log --all --full-history -- .env
                                        ← sin salida: nunca estuvo versionado

  $ docker history --no-trunc ghcr.io/rafaaas17/perfil-api:1.0 | grep -i password
  sin credenciales en ninguna capa
  $ docker history --no-trunc ghcr.io/rafaaas17/perfil-web:1.0 | grep -i password
  sin credenciales en ninguna capa
  $ docker history --no-trunc perfil-db:1.0 | grep -i password
  sin credenciales en ninguna capa

  $ docker image inspect ghcr.io/rafaaas17/perfil-api:1.0 --format '{{json .Config.Env}}'
  ["PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin"]
  ```

  La imagen de la API no graba **ninguna** variable propia: solo el `PATH` que
  hereda de Alpine. Todo lo demás —`DB_HOST`, `DB_USER`, `DB_PASSWORD`— entra
  en tiempo de ejecución desde `compose.yaml`, que a su vez lo lee del `.env`
  que no está en el repositorio.

  Y el workflow [**Sin secretos**](https://github.com/rafaaas17/rafaaas17.github.io/actions/workflows/sin-secretos.yml)
  repite estas comprobaciones en **cada pull request**: revisar esto a mano
  funciona una vez; en un repositorio que se sigue tocando, el único control que
  sirve es el que corre solo y bloquea el PR.

- **Qué no me funcionó:** mi primera idea fue un secreto de Codespaces, y la
  abandoné **antes de configurarla**, leyendo la documentación: los secretos de
  Codespaces son de la cuenta del usuario, no del repositorio. Habría
  funcionado perfecto en mi Codespace y justo por eso no sirve — quien califique
  abre uno desde su cuenta, donde esa variable no existe,
  `${POSTGRES_PASSWORD:?…}` aborta el `compose up` y el B3 se pierde entero. Es
  el caso de manual de una solución que funciona en la máquina de uno y en
  ninguna otra, y la habría entregado si no llego a leer de quién son los
  secretos.

---

### Sobre el B3: que arranque solo

No es un reto numerado, pero es con lo que se califica todo lo demás.

- **`postCreateCommand` vs `postStartCommand`.** `postCreateCommand` corre **una
  sola vez**, al crear el Codespace: ahí va generar el `.env`.
  `postStartCommand` corre en **cada** arranque, también al reanudar un
  Codespace detenido: ahí va `docker compose up -d --build --wait`. Si el
  `compose up` estuviera en `postCreateCommand`, funcionaría la primera vez y
  fallaría después, al detener y reanudar el Codespace, que es lo que uno hace
  todo el tiempo para no gastar cuota.
- **`waitFor: postStartCommand`.** Por defecto VS Code da el entorno por listo
  antes de que termine `postStartCommand` y abre la vista previa contra un nginx
  que todavía no existe. Con `waitFor`, y con `--wait` cerrando el otro lado, la
  vista previa se abre cuando los tres servicios están `healthy`.
- **`docker-in-docker` y no `docker-outside-of-docker`.** El devcontainer es él
  mismo un contenedor; sin la feature no hay daemon dentro.
  `docker-outside-of-docker` reutiliza el del host montando su socket y gasta
  menos, pero comparte daemon con lo que haya fuera y complica la relación entre
  rutas. Para un entorno efímero preferí el aislamiento.
- **`onAutoForward: openPreview`** en el puerto 8080, el único publicado.
- **La feature `sshd`** la agregué después, cuando quise comprobar el arranque
  desde la terminal con `gh codespace ssh` y me encontré con
  *failed to start SSH server*. No cambia el arranque; solo permite verificarlo
  sin abrir el navegador.

**Verificado en un Codespace nuevo:**

Codespace creado desde cero el **26/09/2026 a las 05:48 UTC** (00:48 en Lima)
sobre el commit `78d6cbf` de `main`. **No se ejecutó ningún comando de
arranque**: lo que sigue es el estado en el que estaba el entorno al entrar.

```
$ git log --oneline -1
78d6cbf Merge pull request #21 from rafaaas17/feature/actualizar-dependencias

$ docker compose ps
SERVICE   STATUS                    PORTS
api       Up 37 seconds (healthy)   3000/tcp
db        Up 42 seconds (healthy)   5432/tcp
web       Up 31 seconds (healthy)   0.0.0.0:8080->8080/tcp, [::]:8080->8080/tcp

$ curl -fsS http://localhost:8080/ | grep -o "<title>.*</title>"
<title>Rafael Alarcón Romero</title>

$ curl -fsS http://localhost:8080/api/health
{"status":"ok"}

$ curl -fsS -X POST http://localhost:8080/api/mensajes \
    -H "Content-Type: application/json" \
    -d '{"nombre":"Prueba en Codespace","mensaje":"Arrancó solo, sin escribir ningún comando."}'
{"id":3,"nombre":"Prueba en Codespace","mensaje":"Arrancó solo, sin escribir ningún comando.","fecha":"2026-09-26T05:48:31.601528Z"}

$ for s in web api db; do docker compose exec $s whoami; done
web  nginx
api  app
db   postgres

$ docker compose exec web getent hosts db   → sin salida
$ docker compose exec api getent hosts db   → 172.19.0.2  db
```

El `.env` que usa ese Codespace lo generó `preparar-entorno.sh` al crearlo, con
una contraseña aleatoria que no existe en ningún otro sitio.
