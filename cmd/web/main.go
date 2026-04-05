package main

import (
	"balochi_dictionary_wails/internal/search"
	"database/sql"
	"encoding/json"
	"errors"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	_ "github.com/mattn/go-sqlite3"
)

const (
	defaultLimit       = 100
	defaultPort        = "8080"
	defaultBrowseLimit = 50
	maxBrowseLimit     = 100
)

func main() {
	service, err := setupSearchService()
	if err != nil {
		log.Fatal(err)
	}

	mux := http.NewServeMux()
	mux.HandleFunc("/api/health", healthHandler)
	mux.HandleFunc("/api/search", searchHandler(service))
	mux.HandleFunc("/api/browse", browseHandler(service))
	mux.HandleFunc("/api/browse/letters", browseLettersHandler(service))
	mux.Handle("/", spaFileServer("frontend/dist"))

	port := os.Getenv("PORT")
	if port == "" {
		port = defaultPort
	}

	addr := ":" + port
	log.Printf("web server listening on %s", addr)
	if err := http.ListenAndServe(addr, mux); err != nil {
		log.Fatal(err)
	}
}

func setupSearchService() (*search.Service, error) {
	dbPath := filepath.Join("internal", "dictionary", "Database", "balochi_dict.db")
	if _, err := os.Stat(dbPath); err != nil {
		return nil, err
	}

	db, err := sql.Open("sqlite3", dbPath)
	if err != nil {
		return nil, err
	}

	return search.NewService(db)
}

func healthHandler(w http.ResponseWriter, _ *http.Request) {
	writeJSON(w, http.StatusOK, map[string]string{"status": "ok"})
}

func searchHandler(service *search.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		query := r.URL.Query()
		keyword := query.Get("keyword")
		searchMethod := query.Get("method")
		if searchMethod == "" {
			searchMethod = "balochi"
		}

		limit, err := parseLimit(query.Get("limit"))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		strictDefinition, err := parseBoolDefaultFalse(query.Get("strict_definition"))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		result, err := service.SearchWithOptions(keyword, searchMethod, limit, search.SearchOptions{
			StrictDefinition: strictDefinition,
		})
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		writeJSON(w, http.StatusOK, result)
	}
}

func browseHandler(service *search.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, r *http.Request) {
		query := r.URL.Query()
		letter := query.Get("letter")

		limit, err := parseBrowseLimit(query.Get("limit"))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		offset, err := parseBrowseOffset(query.Get("offset"))
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		response, err := service.Browse(letter, limit, offset)
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		writeJSON(w, http.StatusOK, response)
	}
}

func browseLettersHandler(service *search.Service) http.HandlerFunc {
	return func(w http.ResponseWriter, _ *http.Request) {
		response, err := service.BrowseLetters()
		if err != nil {
			http.Error(w, err.Error(), http.StatusBadRequest)
			return
		}

		writeJSON(w, http.StatusOK, response)
	}
}

func parseLimit(limitString string) (int, error) {
	if limitString == "" {
		return defaultLimit, nil
	}

	limit, err := strconv.Atoi(limitString)
	if err != nil || limit < 1 {
		return 0, errors.New("limit must be a positive integer")
	}

	return limit, nil
}

func parseBoolDefaultFalse(value string) (bool, error) {
	if value == "" {
		return false, nil
	}

	parsed, err := strconv.ParseBool(value)
	if err != nil {
		return false, errors.New("strict_definition must be true or false")
	}

	return parsed, nil
}

func parseBrowseLimit(limitString string) (int, error) {
	if limitString == "" {
		return defaultBrowseLimit, nil
	}

	limit, err := strconv.Atoi(limitString)
	if err != nil || limit < 1 {
		return 0, errors.New("limit must be a positive integer")
	}
	if limit > maxBrowseLimit {
		return 0, errors.New("limit must be <= 100")
	}

	return limit, nil
}

func parseBrowseOffset(offsetString string) (int, error) {
	if offsetString == "" {
		return 0, nil
	}

	offset, err := strconv.Atoi(offsetString)
	if err != nil || offset < 0 {
		return 0, errors.New("offset must be a non-negative integer")
	}

	return offset, nil
}

func writeJSON(w http.ResponseWriter, statusCode int, payload any) {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(statusCode)
	if err := json.NewEncoder(w).Encode(payload); err != nil {
		http.Error(w, err.Error(), http.StatusInternalServerError)
	}
}

func spaFileServer(root string) http.Handler {
	fileServer := http.FileServer(http.Dir(root))

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		relativePath := strings.TrimPrefix(filepath.Clean(r.URL.Path), "/")
		path := filepath.Join(root, relativePath)
		if stat, err := os.Stat(path); err == nil && !stat.IsDir() {
			fileServer.ServeHTTP(w, r)
			return
		}

		http.ServeFile(w, r, filepath.Join(root, "index.html"))
	})
}
