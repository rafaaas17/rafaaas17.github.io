# API del libro de visitas — primera versión.
#
# Compila y ejecuta en la misma imagen. Funciona, pero la imagen final se lleva
# el compilador de Go, el módulo cache y las fuentes: cientos de MB para correr
# un binario de unos pocos. El Reto 1 la parte en dos etapas.

# Regla 1: tag fijo, nunca latest.
FROM golang:1.23-bookworm

WORKDIR /src

# Regla 3: las dependencias primero y en su propia capa. Mientras go.mod y
# go.sum no cambien, Docker reutiliza esta capa y no vuelve a descargar nada.
COPY go.mod go.sum ./
RUN go mod download

COPY . .
RUN go build -o /src/api .

# Regla 6: ni una credencial aquí. Todo entra por variables de entorno en
# tiempo de ejecución (DB_HOST, DB_USER, DB_PASSWORD…).
EXPOSE 3000

# Regla 4: un solo proceso, en forma exec, para que reciba SIGTERM.
CMD ["/src/api"]
