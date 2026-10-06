// Pruebas de la API del libro de visitas.
//
// Prueban el contrato que el navegador y nginx ven: qué código de estado
// devuelve cada ruta. No necesitan Postgres porque todas las validaciones
// ocurren antes de tocar la base: si una validación se rompe y la petición
// llega hasta el INSERT, la prueba falla con 500 en vez de 400, que es
// exactamente lo que quiero que me avise el pipeline.
package main

import (
	"database/sql"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"
)

// baseInalcanzable devuelve un *sql.DB que apunta a un puerto donde no hay
// nadie. sql.Open no conecta, así que esto no falla aquí: falla cuando el
// handler intenta usarla, que es lo que quiero para probar /api/health.
func baseInalcanzable(t *testing.T) *sql.DB {
	t.Helper()
	db, err := sql.Open("pgx", "postgres://nadie:nada@127.0.0.1:1/vacio?sslmode=disable&connect_timeout=1")
	if err != nil {
		t.Fatalf("sql.Open: %v", err)
	}
	t.Cleanup(func() { db.Close() })
	return db
}

func pedir(t *testing.T, metodo, ruta, cuerpo string) *httptest.ResponseRecorder {
	t.Helper()
	req := httptest.NewRequest(metodo, ruta, strings.NewReader(cuerpo))
	req.Header.Set("Content-Type", "application/json")
	grabadora := httptest.NewRecorder()
	nuevoMux(baseInalcanzable(t)).ServeHTTP(grabadora, req)
	return grabadora
}

func TestPostMensajeInvalido(t *testing.T) {
	casos := []struct {
		nombre   string
		cuerpo   string
		esperado int
	}{
		{"sin nombre", `{"nombre":"","mensaje":"hola"}`, http.StatusBadRequest},
		{"sin mensaje", `{"nombre":"Rafael","mensaje":"   "}`, http.StatusBadRequest},
		{"nombre de más de 60", `{"nombre":"` + strings.Repeat("a", 61) + `","mensaje":"hola"}`, http.StatusBadRequest},
		{"mensaje de más de 280", `{"nombre":"Rafael","mensaje":"` + strings.Repeat("a", 281) + `"}`, http.StatusBadRequest},
		{"cuerpo que no es JSON", `esto no es json`, http.StatusBadRequest},
	}

	for _, c := range casos {
		t.Run(c.nombre, func(t *testing.T) {
			r := pedir(t, http.MethodPost, "/api/mensajes", c.cuerpo)
			if r.Code != c.esperado {
				t.Errorf("POST /api/mensajes (%s): esperaba %d y devolvió %d — cuerpo: %s",
					c.nombre, c.esperado, r.Code, r.Body.String())
			}
			if ct := r.Header().Get("Content-Type"); ct != "application/json" {
				t.Errorf("Content-Type: esperaba application/json y devolvió %q", ct)
			}
		})
	}
}

// El límite de 280 es exacto: 280 caracteres entran y 281 no. Un "mayor o
// igual" en vez de un "mayor" rompe esta prueba.
func TestMensajeDe280CaracteresPasaLaValidacion(t *testing.T) {
	r := pedir(t, http.MethodPost, "/api/mensajes", `{"nombre":"Rafael","mensaje":"`+strings.Repeat("a", 280)+`"}`)
	if r.Code == http.StatusBadRequest {
		t.Errorf("280 caracteres deberían pasar la validación, y devolvió 400: %s", r.Body.String())
	}
}

// Si la base no contesta, la API no puede decir que está sana: tiene que
// devolver 503. De eso depende el "condition: service_healthy" de compose.
func TestHealthSinBaseDevuelve503(t *testing.T) {
	r := pedir(t, http.MethodGet, "/api/health", "")
	if r.Code != http.StatusServiceUnavailable {
		t.Errorf("GET /api/health sin base: esperaba 503 y devolvió %d", r.Code)
	}
}

// Todo lo que no es una ruta registrada es 404, no 200. Si esto cambia,
// nginx estaría reenviando a la API cosas que no son de la API.
func TestRutaDesconocidaDevuelve404(t *testing.T) {
	r := pedir(t, http.MethodGet, "/api/no-existe", "")
	if r.Code != http.StatusNotFound {
		t.Errorf("GET /api/no-existe: esperaba 404 y devolvió %d", r.Code)
	}
}
