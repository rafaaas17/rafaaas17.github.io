# Perfil — Rafael Alarcón Romero

Sitio personal publicado en https://rafaaas17.github.io

Desde el LAB-02 el perfil tiene además un **libro de visitas**, y para eso el
sitio es una aplicación de tres servicios en contenedores:

| Servicio | Qué hace | Puerto |
|---|---|---|
| `web` | nginx: sirve el perfil y hace de reverse proxy hacia `/api/` | `8080` en tu máquina |
| `api` | La API del libro de visitas, en Go | interno |
| `db`  | Postgres 16 con un volumen para que los mensajes persistan | interno |

Solo `web` publica un puerto. A la API se llega pasando por nginx, y a la base
de datos solo desde la API.

## Cómo levantarlo en tu máquina

Necesitas Docker con el plugin de Compose.

```bash
cp .env.example .env     # una sola vez; edita la contraseña
docker compose up -d --build
```

Y abre http://localhost:8080.

Para apagarlo:

```bash
docker compose down      # conserva los mensajes
docker compose down -v   # borra también el volumen y los mensajes
```

## Cómo levantarlo en GitHub Codespaces

No hay nada que hacer: **Code → Codespaces → Create codespace on main**. El
entorno se construye, genera su `.env`, levanta los tres servicios y abre la
vista previa solo.

## Cómo se publica la página

Cada push a `main` despliega `index.html` con GitHub Pages. Ahí no hay backend:
`/api/` no existe, el libro de visitas se queda oculto y el resto del perfil se
ve igual que siempre.

## Flujo de trabajo

- `main` protegida; todo cambio entra por pull request
- Una rama por cambio: `feature/*`, `fix/*`, `docs/*`
- Mensajes de commit en imperativo, ≤ 50 caracteres

## Historial del curso

- **S02** — Sitio inicial, ramas y pull requests
- **S03** — Libro de visitas: tres servicios en contenedores
