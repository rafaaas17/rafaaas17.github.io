# Postgres con el esquema del libro de visitas ya incluido.
#
# La imagen oficial ejecuta, en orden alfabético, todo .sql que encuentre en
# /docker-entrypoint-initdb.d/, pero SOLO si el directorio de datos está vacío,
# es decir, la primera vez que arranca con un volumen nuevo.
# Reto 5 y regla 1: el tag "16-alpine" flota. Fijado a la versión exacta y
# sobre Alpine 3.24, que es donde están parcheadas musl y zlib.
FROM postgres:18.6-alpine3.24

COPY init/ /docker-entrypoint-initdb.d/

# Regla 5 / Reto 3: el contenedor entero corre como postgres (UID 70).
#
# Sin esta línea el PID 1 es root: el entrypoint oficial arranca como root
# para poder ajustar permisos del directorio de datos y recién entonces baja
# a postgres con gosu. El proceso de Postgres nunca fue root, pero el
# contenedor sí, y "docker compose exec db whoami" respondería root.
#
# Funciona porque la imagen oficial deja /var/lib/postgresql/data con permisos
# que el usuario postgres puede usar, y Docker crea el volumen nombrado
# heredando esos permisos. Al detectar que no es root, el entrypoint se salta
# el gosu y sigue de largo.
USER postgres

# Reto 2: sano = acepta conexiones TCP, no = el proceso existe.
#
# -h 127.0.0.1 es deliberado. Durante la inicialización, la imagen oficial
# levanta un servidor temporal que escucha SOLO en el socket unix para correr
# los scripts de init/. Sin -h, pg_isready encontraría ese servidor temporal y
# daría la base por lista mientras todavía se están creando las tablas.
# Forzando TCP, el chequeo solo pasa cuando arranca el servidor de verdad.
#
# Forma JSON (DL3025) con el shell nombrado: $POSTGRES_USER y $POSTGRES_DB
# tienen que expandirse al ejecutarse, y hace falta el "||".
HEALTHCHECK --interval=5s --timeout=3s --start-period=10s --retries=12 \
    CMD ["sh", "-c", "pg_isready -h 127.0.0.1 -U \"$POSTGRES_USER\" -d \"$POSTGRES_DB\" || exit 1"]
