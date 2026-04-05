package main

import (
	"balochi_dictionary_wails/internal/search"
	"database/sql"
	"encoding/json"
	"net/http"
	"net/http/httptest"
	"strings"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

type browseResponse struct {
	Items []struct {
		WordID          int
		Balochi         string
		Latin           string
		NormalizedLatin string
	}
	Pagination struct {
		Offset     int
		Limit      int
		NextOffset int
		HasMore    bool
	}
	Filter struct {
		Letter string
	}
}

func setupWebTestService(t *testing.T) *search.Service {
	t.Helper()

	db, err := sql.Open("sqlite3", ":memory:")
	if err != nil {
		t.Fatalf("open sqlite memory db: %v", err)
	}

	statements := []string{
		`CREATE TABLE words (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			balochi TEXT,
			latin TEXT,
			normalized_latin TEXT
		);`,
		`CREATE TABLE definitions (
			id INTEGER PRIMARY KEY AUTOINCREMENT,
			part_of_speech TEXT,
			definition TEXT
		);`,
		`CREATE TABLE word_definitions (
			word_id INTEGER,
			definition_id INTEGER
		);`,
		`INSERT INTO words (id, balochi, latin, normalized_latin) VALUES
			(1, 'ا', 'alif', 'alif'),
			(2, 'آ', 'alif-madda', 'alifmadda'),
			(3, 'ب', 'be', 'be');`,
		`INSERT INTO definitions (id, part_of_speech, definition) VALUES
			(1, 'n', 'water');`,
		`INSERT INTO word_definitions (word_id, definition_id) VALUES
			(1, 1);`,
	}
	for _, stmt := range statements {
		if _, err := db.Exec(stmt); err != nil {
			t.Fatalf("exec statement: %v", err)
		}
	}

	service, err := search.NewService(db)
	if err != nil {
		t.Fatalf("new service: %v", err)
	}

	return service
}

func decodeBrowseResponse(t *testing.T, rec *httptest.ResponseRecorder) browseResponse {
	t.Helper()

	var response browseResponse
	if err := json.Unmarshal(rec.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}

	return response
}

func TestBrowseHandlerOrdersAlphabeticallyAndPagesConsistently(t *testing.T) {
	service := setupWebTestService(t)

	firstPageReq := httptest.NewRequest(http.MethodGet, "/api/browse?limit=2&offset=0", nil)
	firstPageRec := httptest.NewRecorder()
	browseHandler(service).ServeHTTP(firstPageRec, firstPageReq)

	if firstPageRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", firstPageRec.Code)
	}
	firstPage := decodeBrowseResponse(t, firstPageRec)

	if len(firstPage.Items) != 2 {
		t.Fatalf("expected 2 items on first page, got %d", len(firstPage.Items))
	}
	if firstPage.Items[0].Balochi > firstPage.Items[1].Balochi {
		t.Fatalf("expected first page to be sorted alphabetically: %+v", firstPage.Items)
	}
	if firstPage.Pagination.Offset != 0 || firstPage.Pagination.Limit != 2 || firstPage.Pagination.NextOffset != 2 || !firstPage.Pagination.HasMore {
		t.Fatalf("unexpected first-page pagination payload: %+v", firstPage.Pagination)
	}
	if firstPage.Filter.Letter != "" {
		t.Fatalf("expected empty filter letter, got %q", firstPage.Filter.Letter)
	}

	secondPageReq := httptest.NewRequest(http.MethodGet, "/api/browse?limit=2&offset=2", nil)
	secondPageRec := httptest.NewRecorder()
	browseHandler(service).ServeHTTP(secondPageRec, secondPageReq)

	if secondPageRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", secondPageRec.Code)
	}
	secondPage := decodeBrowseResponse(t, secondPageRec)

	if len(secondPage.Items) != 1 {
		t.Fatalf("expected 1 item on second page, got %d", len(secondPage.Items))
	}
	if secondPage.Pagination.Offset != 2 || secondPage.Pagination.Limit != 2 || secondPage.Pagination.NextOffset != 3 || secondPage.Pagination.HasMore {
		t.Fatalf("unexpected second-page pagination payload: %+v", secondPage.Pagination)
	}

	allReq := httptest.NewRequest(http.MethodGet, "/api/browse?limit=100&offset=0", nil)
	allRec := httptest.NewRecorder()
	browseHandler(service).ServeHTTP(allRec, allReq)
	if allRec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", allRec.Code)
	}
	all := decodeBrowseResponse(t, allRec)

	if len(all.Items) != 3 {
		t.Fatalf("expected 3 total items, got %d", len(all.Items))
	}
	if firstPage.Items[0].WordID != all.Items[0].WordID || firstPage.Items[1].WordID != all.Items[1].WordID || secondPage.Items[0].WordID != all.Items[2].WordID {
		t.Fatalf("pagination does not preserve alphabetical ordering across pages")
	}
}

func TestBrowseHandlerValidatesLimitAndOffset(t *testing.T) {
	service := setupWebTestService(t)

	tests := []string{
		"/api/browse?limit=0",
		"/api/browse?limit=101",
		"/api/browse?offset=-1",
	}

	for _, path := range tests {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rec := httptest.NewRecorder()
		browseHandler(service).ServeHTTP(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for %s, got %d", path, rec.Code)
		}
	}
}

func TestBrowseLettersHandlerReturnsCounts(t *testing.T) {
	service := setupWebTestService(t)

	req := httptest.NewRequest(http.MethodGet, "/api/browse/letters", nil)
	rec := httptest.NewRecorder()
	browseLettersHandler(service).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var response struct {
		Letters []struct {
			Letter string
			Count  int
		}
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}
	if len(response.Letters) != 3 {
		t.Fatalf("expected 3 letter buckets, got %d", len(response.Letters))
	}
}

func TestBrowseHandlerAppliesLetterFilter(t *testing.T) {
	service := setupWebTestService(t)

	req := httptest.NewRequest(http.MethodGet, "/api/browse?limit=10&offset=0&letter=آ", nil)
	rec := httptest.NewRecorder()

	browseHandler(service).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	response := decodeBrowseResponse(t, rec)
	if response.Filter.Letter != "آ" {
		t.Fatalf("expected filter.letter=آ, got %q", response.Filter.Letter)
	}
	if len(response.Items) != 1 {
		t.Fatalf("expected 1 filtered item, got %d", len(response.Items))
	}
	for _, item := range response.Items {
		if !strings.HasPrefix(item.Balochi, "آ") {
			t.Fatalf("expected item to match letter filter, got %q", item.Balochi)
		}
	}
}

func TestBrowseItemHandlerReturnsDetailedEntry(t *testing.T) {
	service := setupWebTestService(t)

	req := httptest.NewRequest(http.MethodGet, "/api/browse/item?word_id=1", nil)
	rec := httptest.NewRecorder()
	browseItemHandler(service).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200, got %d", rec.Code)
	}

	var response struct {
		WordID      int
		Balochi     string
		Definitions []struct {
			PartOfSpeech string
			Text         string
		}
	}
	if err := json.Unmarshal(rec.Body.Bytes(), &response); err != nil {
		t.Fatalf("decode response: %v", err)
	}

	if response.WordID != 1 || response.Balochi != "ا" {
		t.Fatalf("unexpected browse item payload: %+v", response)
	}
	if len(response.Definitions) != 1 || response.Definitions[0].Text != "water" {
		t.Fatalf("unexpected browse item definitions: %+v", response.Definitions)
	}
}

func TestBrowseItemHandlerValidatesWordID(t *testing.T) {
	service := setupWebTestService(t)

	tests := []string{
		"/api/browse/item",
		"/api/browse/item?word_id=0",
		"/api/browse/item?word_id=abc",
	}

	for _, path := range tests {
		req := httptest.NewRequest(http.MethodGet, path, nil)
		rec := httptest.NewRecorder()
		browseItemHandler(service).ServeHTTP(rec, req)
		if rec.Code != http.StatusBadRequest {
			t.Fatalf("expected 400 for %s, got %d", path, rec.Code)
		}
	}
}

func TestBrowseItemHandlerReturnsNotFoundForMissingWord(t *testing.T) {
	service := setupWebTestService(t)

	req := httptest.NewRequest(http.MethodGet, "/api/browse/item?word_id=999", nil)
	rec := httptest.NewRecorder()
	browseItemHandler(service).ServeHTTP(rec, req)

	if rec.Code != http.StatusNotFound {
		t.Fatalf("expected 404, got %d", rec.Code)
	}
}

func TestSearchHandlerStillWorks(t *testing.T) {
	service := setupWebTestService(t)

	req := httptest.NewRequest(http.MethodGet, "/api/search?keyword=ا&method=balochi&limit=10", nil)
	rec := httptest.NewRecorder()
	searchHandler(service).ServeHTTP(rec, req)

	if rec.Code != http.StatusOK {
		t.Fatalf("expected 200 from search handler, got %d", rec.Code)
	}
}
