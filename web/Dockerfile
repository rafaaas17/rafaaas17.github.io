# Servidor web del perfil.
#
# Contexto de build: la RAÍZ del repositorio, no esta carpeta.
#
# index.html, estilos.css y libro-de-visitas.js tienen que seguir en la raíz
# porque GitHub Pages los publica desde ahí, pero este Dockerfile vive en web/.
# Un COPY no puede salir de su contexto: "COPY ../index.html" es un error, no
# un atajo. La solución no está en el Dockerfile sino en quien lo construye:
# en compose.yaml el contexto es "." y el Dockerfile se indica aparte con
# "dockerfile: web/Dockerfile". Por eso las rutas de abajo se leen desde la raíz.

# Regla 1 y 2: tag fijo y base pequeña (alpine).
#
# Regla 5 / Reto 3: nginxinc/nginx-unprivileged en vez de la imagen oficial.
#
# La imagen oficial de nginx arranca como root y necesita serlo por una razón
# concreta: su proceso maestro abre el puerto 80, y en Linux los puertos por
# debajo de 1024 están reservados a root o a quien tenga CAP_NET_BIND_SERVICE.
# Recién después de abrirlo baja de privilegios y deja a los workers como
# usuario nginx. El resultado es que el PID 1 del contenedor sigue siendo root.
#
# Esta variante, mantenida por el mismo equipo de nginx, escucha en 8080 en vez
# de 80 y por eso puede correr entera como el usuario nginx (UID 101). Dentro
# de un contenedor el número de puerto da igual: quien decide en qué puerto se
# ve la aplicación es la publicación de compose ("8080:8080").
#
# Las alternativas que descarté: quedarme con la oficial y pasarle
# "user: 101" en compose (rompe, porque el entrypoint escribe en
# /var/run/nginx.pid y en las cachés siendo ya nginx), o darle
# CAP_NET_BIND_SERVICE para que un no-root abra el 80 (funciona, pero es
# devolverle un privilegio para conservar un número de puerto que no importa).
# Reto 5: rama mainline (1.31) sobre Alpine 3.24 y tag fijo hasta el parche.
# La 1.27 sobre Alpine 3.20 arrastraba las mismas CVE de musl, zlib, libxml2 y
# nghttp2 que la API, más las del propio nginx.
FROM nginxinc/nginx-unprivileged:1.31.6-alpine3.24

# Regla 3: primero la configuración, que casi nunca cambia; después el sitio,
# que cambia en cada commit. Así editar el perfil no invalida la capa de nginx.
COPY web/nginx.conf /etc/nginx/conf.d/default.conf

# De dónde sale el sitio que se copia a la imagen.
#
# Por defecto, la raíz: así "docker compose up" sigue funcionando en mi
# máquina sin pasos previos. En el pipeline (LAB-03) se construye con
# --build-arg SITIO=_site, que es la carpeta que armó el job build y que
# probó Vitest. De ese modo la imagen que se escanea, la que pasa el smoke
# y la página que se publica llevan exactamente los mismos archivos.
ARG SITIO=.
COPY ${SITIO}/index.html ${SITIO}/estilos.css ${SITIO}/libro-de-visitas.js /usr/share/nginx/html/

# Regla 6: nada de credenciales. Este contenedor no tiene ninguna que guardar.
EXPOSE 8080

# Reto 2: wget de busybox contra el /healthz que define nginx.conf.
# Forma JSON (DL3025): sin ella Docker envuelve el comando en un shell
# implícito. Aquí el shell se nombra, porque hace falta para el "||".
HEALTHCHECK --interval=10s --timeout=3s --start-period=5s --retries=3 \
    CMD ["sh", "-c", "wget -q -O /dev/null http://127.0.0.1:8080/healthz || exit 1"]

# La imagen oficial ya trae su ENTRYPOINT y arranca nginx en primer plano
# (regla 4: un proceso por contenedor, y que sea el PID 1 el que reciba SIGTERM).
