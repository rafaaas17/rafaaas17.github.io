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

# Regla 1 y 2: tag fijo y base pequeña (alpine, ~50 MB frente a ~190 MB de la
# variante Debian).
FROM nginx:1.27-alpine

# Regla 3: primero la configuración, que casi nunca cambia; después el sitio,
# que cambia en cada commit. Así editar el perfil no invalida la capa de nginx.
COPY web/nginx.conf /etc/nginx/conf.d/default.conf
COPY index.html estilos.css libro-de-visitas.js /usr/share/nginx/html/

# Regla 6: nada de credenciales. Este contenedor no tiene ninguna que guardar.
EXPOSE 80

# La imagen oficial ya trae su ENTRYPOINT y arranca nginx en primer plano
# (regla 4: un proceso por contenedor, y que sea el PID 1 el que reciba SIGTERM).
