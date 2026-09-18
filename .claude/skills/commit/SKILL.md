---
name: commit
description: Reglas de commit y de pull request del curso IF-1116. Úsala siempre que vayas a crear un commit, proponer un mensaje de commit, crear una rama o redactar un pull request en este repositorio.
---

# Reglas de commit — IF-1116

## Flujo de trabajo (GitHub Flow)
1. `main` está protegida: nunca hagas commit ni push directo a `main`.
2. Una rama por tarea: `feature/*`, `fix/*` o `docs/*`.
3. Todo cambio entra a `main` por pull request, con merge commit.
4. Ramas cortas: se borran después del merge.
5. Nunca uses `git push --force` sobre `main` ni reescribas commits ya subidos:
   para deshacer usa `git revert`, no `git reset`.

## Mensaje de commit
- El título debe completar la frase: *"Si se aplica, este commit va a…"*
- Imperativo y en español: "Agregar", "Corregir", "Precisar"
  (no "Agregado", "Agrega" ni "Agregando").
- Máximo 50 caracteres y sin punto final.
- Un solo tema por commit: si el título necesita "y", probablemente son dos commits.
- Cuerpo opcional, separado del título por una línea en blanco:
  explica qué cambió y por qué, no cómo.

## Antes de confirmar
1. Revisa `git status` y `git diff --staged`: solo entra lo que corresponde al tema.
2. Nunca incluyas credenciales, `.env` ni archivos basura.
3. Propón el mensaje y deja que la persona lo revise.
   El último clic sigue siendo humano.

## Pull request
- Título: el objetivo del cambio, en imperativo.
- Descripción: qué agrega y por qué, redactada a partir de los commits de la rama.
