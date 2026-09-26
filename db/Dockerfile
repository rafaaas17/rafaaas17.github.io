# Postgres con el esquema del libro de visitas ya incluido.
#
# La imagen oficial ejecuta, en orden alfabético, todo .sql que encuentre en
# /docker-entrypoint-initdb.d/, pero SOLO si el directorio de datos está vacío,
# es decir, la primera vez que arranca con un volumen nuevo.
FROM postgres:16-alpine

COPY init/ /docker-entrypoint-initdb.d/

# Reto 2: sano = acepta conexiones TCP, no = el proceso existe.
#
# -h 127.0.0.1 es deliberado. Durante la inicialización, la imagen oficial
# levanta un servidor temporal que escucha SOLO en el socket unix para correr
# los scripts de init/. Sin -h, pg_isready encontraría ese servidor temporal y
# daría la base por lista mientras todavía se están creando las tablas.
# Forzando TCP, el chequeo solo pasa cuando arranca el servidor de verdad.
#
# Forma shell para que $POSTGRES_USER y $POSTGRES_DB se expandan al ejecutarse.
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=12     CMD pg_isready -h 127.0.0.1 -U "$POSTGRES_USER" -d "$POSTGRES_DB" || exit 1
