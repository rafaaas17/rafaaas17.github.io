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
RUN apk add --no-cache ca-certificates tzdata

COPY --from=build /out/api /usr/local/bin/api

# Regla 6: ninguna credencial en ninguna capa. Todo entra por variables de
# entorno en tiempo de ejecución.
EXPOSE 3000

# Regla 4: un proceso, en forma exec, para que sea PID 1 y reciba SIGTERM.
ENTRYPOINT ["/usr/local/bin/api"]
