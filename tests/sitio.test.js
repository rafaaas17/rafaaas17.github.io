// Pruebas del sitio que se publica.
//
// Se corren sobre _site/, no sobre la raíz del repositorio: _site/ es
// exactamente lo que el job deploy-prod sube a GitHub Pages. Probar la raíz
// sería probar una carpeta distinta de la que se publica.
import { describe, it, expect, beforeAll } from 'vitest'
import { readFileSync, existsSync } from 'node:fs'
import { JSDOM } from 'jsdom'

const SITIO = '_site' // la carpeta que arma scripts/armar-sitio.sh
let html
let doc

beforeAll(() => {
  html = readFileSync(`${SITIO}/index.html`, 'utf-8')
  doc = new JSDOM(html).window.document
})

describe('index.html', () => {
  it('tiene un título', () => {
    expect(doc.title.trim()).not.toBe('')
  })

  it('muestra mi nombre en el h1', () => {
    expect(doc.querySelector('h1')?.textContent).toContain('Rafael Alarcón Romero')
  })

  it('todas las imágenes tienen texto alternativo', () => {
    const sinAlt = [...doc.querySelectorAll('img')].filter((img) => !img.getAttribute('alt'))
    expect(sinAlt).toHaveLength(0)
  })

  it('los archivos locales que usa la página existen', () => {
    const rutas = [...doc.querySelectorAll('script[src], link[rel="stylesheet"], img[src]')]
      .map((el) => el.getAttribute('src') ?? el.getAttribute('href'))
      .filter((ruta) => !/^(https?:)?\/\//.test(ruta)) // ignora lo que viene de Internet
    for (const ruta of rutas) {
      expect(existsSync(`${SITIO}/${ruta}`), `falta ${ruta}`).toBe(true)
    }
  })
})

describe('el sitio que se publica', () => {
  it('no incluye archivos internos del repositorio', () => {
    for (const interno of ['compose.yaml', '.env.example', 'api', 'db', 'tests']) {
      expect(existsSync(`${SITIO}/${interno}`), `${interno} no debería publicarse`).toBe(false)
    }
  })
})

// ───────────────────────── Mis pruebas ─────────────────────────

describe('cabecera del documento', () => {
  // Las tres cosas que hacen que la página se lea bien en un celular y que un
  // lector de pantalla la pronuncie en español. Son fáciles de perder en un
  // merge y nadie las nota mirando la página.
  it('declara el idioma español', () => {
    expect(doc.documentElement.getAttribute('lang')).toBe('es')
  })

  it('declara el charset y el viewport', () => {
    expect(doc.querySelector('meta[charset]')?.getAttribute('charset')?.toLowerCase()).toBe('utf-8')
    expect(doc.querySelector('meta[name="viewport"]')?.getAttribute('content')).toContain('width=device-width')
  })
})

describe('estructura de títulos', () => {
  // Un solo h1 y sin saltos de nivel: es lo que usa un lector de pantalla para
  // armar el índice de la página.
  it('hay exactamente un h1', () => {
    expect(doc.querySelectorAll('h1')).toHaveLength(1)
  })

  it('los títulos no saltan de nivel', () => {
    const niveles = [...doc.querySelectorAll('h1, h2, h3, h4, h5, h6')].map((h) => Number(h.tagName[1]))
    expect(niveles[0]).toBe(1)
    for (let i = 1; i < niveles.length; i++) {
      expect(niveles[i] - niveles[i - 1], `salto de h${niveles[i - 1]} a h${niveles[i]}`).toBeLessThanOrEqual(1)
    }
  })
})

describe('enlaces externos', () => {
  // target="_blank" sin rel="noopener" le da a la página destino acceso a
  // window.opener, y con eso puede redirigir mi pestaña a otro sitio.
  it('abren en otra pestaña y llevan rel="noopener"', () => {
    const externos = [...doc.querySelectorAll('a[href^="http"]')]
    expect(externos.length).toBeGreaterThan(0)
    for (const a of externos) {
      expect(a.getAttribute('target'), `${a.getAttribute('href')} sin target`).toBe('_blank')
      expect(a.getAttribute('rel') ?? '', `${a.getAttribute('href')} sin noopener`).toContain('noopener')
    }
  })
})

describe('libro de visitas', () => {
  // La sección existe en el HTML aunque en Pages no se vea: libro-de-visitas.js
  // la muestra solo si la API contesta. Si alguien la borra sin querer, el
  // LAB-02 deja de estar en el sitio y nadie se entera.
  it('tiene el formulario con los campos nombre y mensaje', () => {
    const form = doc.querySelector('#libro-de-visitas form')
    expect(form, 'no está el formulario del libro de visitas').not.toBeNull()
    expect(form.querySelector('[name="nombre"]'), 'falta el campo nombre').not.toBeNull()
    expect(form.querySelector('[name="mensaje"]'), 'falta el campo mensaje').not.toBeNull()
  })

  it('los límites del formulario son los mismos que valida la API', () => {
    // La API responde 400 si el nombre pasa de 60 o el mensaje de 280.
    // Si el HTML deja escribir más, el visitante se entera del límite
    // recién cuando el servidor lo rechaza.
    const form = doc.querySelector('#libro-de-visitas form')
    expect(form.querySelector('[name="nombre"]').getAttribute('maxlength')).toBe('60')
    expect(form.querySelector('[name="mensaje"]').getAttribute('maxlength')).toBe('280')
  })
})

describe('nada apunta a mi máquina', () => {
  // En Pages no hay backend ni puertos locales: una URL con localhost funciona
  // en mi laptop y da error en el sitio publicado.
  it('ni el HTML ni el JavaScript mencionan localhost o rutas locales', () => {
    const js = readFileSync(`${SITIO}/libro-de-visitas.js`, 'utf-8')
    for (const [nombre, contenido] of [['index.html', html], ['libro-de-visitas.js', js]]) {
      expect(contenido, `${nombre} menciona localhost`).not.toMatch(/localhost|127\.0\.0\.1/)
      expect(contenido, `${nombre} trae una ruta de Windows`).not.toMatch(/[A-Za-z]:\\\\?Users/)
      expect(contenido, `${nombre} quedó con marcas de conflicto`).not.toMatch(/^<{7} |^>{7} /m)
    }
  })
})
