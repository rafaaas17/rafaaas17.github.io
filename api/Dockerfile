# syntax=docker/dockerfile:1

# API del libro de visitas — Reto 1: imagen mínima.
#
# Dos etapas. En la primera hay un compilador de Go y 700 MB de toolchain; en
# la segunda solo queda un binario. La clave es que lo que no se copia con
# COPY --from simplemente no existe en la imagen final: no es que se borre en
# una capa posterior (eso no sirve, la capa anterior sigue ahí y se puede
# recuperar), es que nunca entra.


# ─────────────────────── Etapa 1: compilar ───────────────────────
# Regla 1: tag fijo. Regla 2 incluso aquí: la variante alpine del compilador
# pesa la mitad que la de Debian y se descarga mucho más rápido.
FROM golang:1.23-alpine3.20 AS build

WORKDIR /src

# Regla 3: las dependencias en su propia capa, antes del código. Mientras
# go.mod y go.sum no cambien, esta capa se reutiliza y no se vuelve a
# descargar nada de la red.
COPY go.mod go.sum ./
RUN go mod download

COPY . .

# CGO_ENABLED=0 es lo que hace posible la etapa 2: sin cgo el binario es
# estático y no depende de la libc de la imagen donde corra.
#   -trimpath          quita las rutas absolutas de compilación del binario
#   -ldflags="-s -w"   quita la tabla de símbolos y la información de depuración
RUN CGO_ENABLED=0 GOOS=linux \
    go build -trimpath -ldflags="-s -w" -o /out/api .


# ─────────────────────── Etapa 2: ejecutar ───────────────────────
# Regla 2: base pequeña. Alpine son ~8 MB.
#
# Por qué alpine y no scratch ni distroless, que serían aún más pequeñas:
# porque el contenedor tiene que poder responder "docker compose exec api
# whoami" (Reto 3) y hacerse un healthcheck HTTP a sí mismo (Reto 2). Ni
# scratch ni distroless traen shell ni wget. Alpine cuesta 8 MB y da las dos
# cosas con busybox.
FROM alpine:3.20

# ca-certificates: si algún día la API habla con un servicio por HTTPS.
# tzdata: para que las fechas del libro de visitas no salgan siempre en UTC.
#
# Regla 5 / Reto 3: un usuario sin privilegios, creado en la misma capa.
# El UID 10001 es alto a propósito: los bajos ya están tomados por usuarios
# del sistema, y si algún día un volumen se monta con ese UID no se lo va a
# encontrar mapeado a nadie con permisos interesantes en el host.
RUN apk add --no-cache ca-certificates tzdata \
 && addgroup -g 10001 -S app \
 && adduser  -u 10001 -S -G app -H -s /sbin/nologin app

# El binario es de root y el usuario app solo puede leerlo y ejecutarlo:
# ni siquiera el proceso puede reescribir su propio ejecutable.
COPY --from=build /out/api /usr/local/bin/api

# Regla 6: ninguna credencial en ninguna capa. Todo entra por variables de
# entorno en tiempo de ejecución.
# Reto 3: a partir de aquí nadie es root. En numérico y no "USER app" porque
# así Kubernetes puede comprobar runAsNonRoot sin resolver /etc/passwd, que es
# lo que va a hacer falta en el LAB-03. El nombre igual existe, y por eso
# "docker compose exec api whoami" responde "app" y no un número.
USER 10001:10001

# El puerto 3000 y no el 80: los puertos por debajo de 1024 son privilegiados
# y un proceso sin root no puede abrirlos sin CAP_NET_BIND_SERVICE.
EXPOSE 3000

# Reto 2: el healthcheck viaja DENTRO de la imagen, no en compose.yaml.
#
# /api/health no dice "estoy vivo": intenta hablar con Postgres y devuelve 503
# si no puede. Un proceso levantado que no alcanza su base de datos no está
# sano, y así compose no da por bueno el arranque antes de tiempo.
#
# Forma shell (sin corchetes) a propósito: así ${PORT} se expande en tiempo de
# ejecución y el chequeo sigue al puerto que realmente esté escuchando.
# wget es el de busybox, que ya viene en alpine: no hace falta instalar curl.
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=5 \
    CMD wget -q -O /dev/null "http://127.0.0.1:${PORT:-3000}/api/health" || exit 1

# Regla 4: un proceso, en forma exec, para que sea PID 1 y reciba SIGTERM.
ENTRYPOINT ["/usr/local/bin/api"]
