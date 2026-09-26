// Libro de visitas: API del LAB-02 en Go (net/http + pgx).
//
// Toda la configuración entra por variables de entorno. Aquí no hay ni una
// contraseña ni un nombre de host escrito a mano, y así debe seguir.
package main

import (
	"context"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"net/url"
	"os"
	"os/signal"
	"strings"
	"syscall"
	"time"
	"unicode/utf8"

	_ "github.com/jackc/pgx/v5/stdlib"
)

type mensaje struct {
	ID      int       `json:"id"`
	Nombre  string    `json:"nombre"`
	Mensaje string    `json:"mensaje"`
	Fecha   time.Time `json:"fecha"`
}

func env(clave, porDefecto string) string {
	if v := os.Getenv(clave); v != "" {
		return v
	}
	return porDefecto
}

func responder(w http.ResponseWriter, codigo int, cuerpo any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(codigo)
	json.NewEncoder(w).Encode(cuerpo)
}

func main() {
	// Se arma como URL para que una contraseña con símbolos raros no rompa nada.
	dsn := url.URL{
		Scheme:   "postgres",
		User:     url.UserPassword(env("DB_USER", "app"), os.Getenv("DB_PASSWORD")),
		Host:     env("DB_HOST", "db") + ":" + env("DB_PORT", "5432"),
		Path:     env("DB_NAME", "libro"),
		RawQuery: "sslmode=disable&connect_timeout=3",
	}
	db, err := sql.Open("pgx", dsn.String())
	if err != nil {
		log.Fatal(err)
	}
	db.SetMaxOpenConns(5)

	mux := http.NewServeMux()

	mux.HandleFunc("GET /api/health", func(w http.ResponseWriter, r *http.Request) {
		// "Estoy vivo" no alcanza: si no puedo hablar con la base, no estoy sano.
		ctx, cancelar := context.WithTimeout(r.Context(), 3*time.Second)
		defer cancelar()
		if err := db.PingContext(ctx); err != nil {
			responder(w, http.StatusServiceUnavailable, map[string]string{"status": "error", "detalle": err.Error()})
			return
		}
		responder(w, http.StatusOK, map[string]string{"status": "ok"})
	})

	mux.HandleFunc("GET /api/mensajes", func(w http.ResponseWriter, r *http.Request) {
		filas, err := db.QueryContext(r.Context(),
			"SELECT id, nombre, mensaje, fecha FROM mensajes ORDER BY fecha DESC, id DESC LIMIT 100")
		if err != nil {
			log.Println(err)
			responder(w, http.StatusInternalServerError, map[string]string{"error": "Error interno."})
			return
		}
		defer filas.Close()

		mensajes := []mensaje{} // vacío, no nil: así el JSON es [] y no null
		for filas.Next() {
			var m mensaje
			if err := filas.Scan(&m.ID, &m.Nombre, &m.Mensaje, &m.Fecha); err != nil {
				log.Println(err)
				responder(w, http.StatusInternalServerError, map[string]string{"error": "Error interno."})
				return
			}
			mensajes = append(mensajes, m)
		}
		responder(w, http.StatusOK, mensajes)
	})

	mux.HandleFunc("POST /api/mensajes", func(w http.ResponseWriter, r *http.Request) {
		var datos struct{ Nombre, Mensaje string }
		if err := json.NewDecoder(http.MaxBytesReader(w, r.Body, 10<<10)).Decode(&datos); err != nil {
			responder(w, http.StatusBadRequest, map[string]string{"error": "El cuerpo no es JSON válido."})
			return
		}
		nombre, texto := strings.TrimSpace(datos.Nombre), strings.TrimSpace(datos.Mensaje)

		switch {
		case nombre == "" || texto == "":
			responder(w, http.StatusBadRequest, map[string]string{"error": "Faltan el nombre o el mensaje."})
			return
		case utf8.RuneCountInString(nombre) > 60:
			responder(w, http.StatusBadRequest, map[string]string{"error": "El nombre no puede pasar de 60 caracteres."})
			return
		case utf8.RuneCountInString(texto) > 280:
			responder(w, http.StatusBadRequest, map[string]string{"error": "El mensaje no puede pasar de 280 caracteres."})
			return
		}

		var m mensaje
		// Parámetros, nunca concatenar texto del usuario dentro del SQL.
		err := db.QueryRowContext(r.Context(),
			"INSERT INTO mensajes (nombre, mensaje) VALUES ($1, $2) RETURNING id, nombre, mensaje, fecha",
			nombre, texto).Scan(&m.ID, &m.Nombre, &m.Mensaje, &m.Fecha)
		if err != nil {
			log.Println(err)
			responder(w, http.StatusInternalServerError, map[string]string{"error": "Error interno."})
			return
		}
		responder(w, http.StatusCreated, m)
	})

	servidor := &http.Server{Addr: ":" + env("PORT", "3000"), Handler: mux, ReadHeaderTimeout: 5 * time.Second}

	// Sin esto, "docker stop" tarda 10 segundos: el proceso ignora la señal de apagado.
	go func() {
		senal := make(chan os.Signal, 1)
		signal.Notify(senal, syscall.SIGINT, syscall.SIGTERM)
		log.Printf("Señal %v: cerrando", <-senal)
		ctx, cancelar := context.WithTimeout(context.Background(), 5*time.Second)
		defer cancelar()
		servidor.Shutdown(ctx)
	}()

	log.Printf("API escuchando en el puerto %s", env("PORT", "3000"))
	if err := servidor.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
		log.Fatal(err)
	}
	db.Close()
}
