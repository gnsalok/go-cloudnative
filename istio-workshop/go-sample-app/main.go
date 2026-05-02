package main

import (
	"fmt"
	"io"
	"log"
	"net/http"
	"os"
	"time"
)

func getenv(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func appInfo() string {
	role := getenv("APP_ROLE", "backend")
	version := getenv("VERSION", getenv("APP_VERSION", "v1"))
	hostname := getenv("HOSTNAME", "unknown")
	return fmt.Sprintf("role=%s version=%s pod=%s", role, version, hostname)
}

func main() {
	role := getenv("APP_ROLE", "backend")
	backendURL := getenv("BACKEND_URL", "")

	http.HandleFunc("/healthz", func(w http.ResponseWriter, _ *http.Request) {
		w.WriteHeader(http.StatusOK)
		_, _ = w.Write([]byte("ok\n"))
	})

	http.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		_, _ = fmt.Fprintf(w, "hello from go-sample-app (%s)\n", appInfo())
		_, _ = fmt.Fprintf(w, "method=%s path=%s\n", r.Method, r.URL.Path)
	})

	http.HandleFunc("/call-backend", func(w http.ResponseWriter, _ *http.Request) {
		if role != "frontend" {
			http.Error(w, "this endpoint is only enabled for frontend role", http.StatusBadRequest)
			return
		}
		if backendURL == "" {
			http.Error(w, "BACKEND_URL is not configured", http.StatusInternalServerError)
			return
		}

		client := &http.Client{Timeout: 5 * time.Second}
		resp, err := client.Get(backendURL)
		if err != nil {
			http.Error(w, fmt.Sprintf("backend call failed: %v", err), http.StatusBadGateway)
			return
		}
		defer resp.Body.Close()

		body, err := io.ReadAll(resp.Body)
		if err != nil {
			http.Error(w, fmt.Sprintf("failed reading backend response: %v", err), http.StatusBadGateway)
			return
		}

		_, _ = fmt.Fprintf(w, "frontend (%s) called backend: %s\n", appInfo(), backendURL)
		_, _ = fmt.Fprintf(w, "backend_status=%d\n", resp.StatusCode)
		_, _ = fmt.Fprintf(w, "backend_response:\n%s", string(body))
	})

	log.Printf("starting go-sample-app on :8080 (%s)", appInfo())
	if err := http.ListenAndServe(":8080", nil); err != nil {
		log.Fatalf("server exited: %v", err)
	}
}
