package balochidictionary

import (
	"database/sql"
	"testing"

	_ "github.com/mattn/go-sqlite3"
)

func setupTestSearcher(t *testing.T) *SQLiteSearcher {
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
			(1, 'a', 'aw', 'aw'),
			(2, 'b', 'atash', 'atash'),
			(3, 'c', 'abr', 'abr'),
			(4, 'dup', '1', '1'),
			(5, 'dup', 'duplatin', 'duplatin');`,
		`INSERT INTO definitions (id, part_of_speech, definition) VALUES
			(1, 'n', 'water'),
			(2, 'n', 'firewater; strong drink'),
			(3, 'n', 'water container'),
			(4, 'n', 'fresh water');`,
		`INSERT INTO word_definitions (word_id, definition_id) VALUES
			(1, 1),
			(2, 2),
			(3, 3),
			(4, 4),
			(5, 4);`,
	}

	for _, stmt := range statements {
		if _, err := db.Exec(stmt); err != nil {
			t.Fatalf("exec statement: %v", err)
		}
	}

	searcher, err := NewSQLiteSearcher(db)
	if err != nil {
		t.Fatalf("create searcher: %v", err)
	}

	return searcher
}

func TestDefinitionSearchPrefersWholeWordAndRanksExactFirst(t *testing.T) {
	searcher := setupTestSearcher(t)

	results, err := searcher.Search("water", "definition", 10)
	if err != nil {
		t.Fatalf("search: %v", err)
	}

	if len(results) < 2 {
		t.Fatalf("expected at least 2 whole-word results, got %d", len(results))
	}

	if results[0].Latin != "aw" {
		t.Fatalf("expected exact definition match first, got %q", results[0].Latin)
	}

	for _, result := range results {
		if result.Latin == "atash" {
			t.Fatalf("expected firewater result to be excluded when whole-word matches exist")
		}
	}
}

func TestDefinitionSearchFallbackContainsWhenNoWholeWordMatch(t *testing.T) {
	searcher := setupTestSearcher(t)

	results, err := searcher.Search("wate", "definition", 10)
	if err != nil {
		t.Fatalf("search: %v", err)
	}

	if len(results) == 0 {
		t.Fatalf("expected fallback contains results, got none")
	}
}

func TestDefinitionSearchStrictModeDisablesFallback(t *testing.T) {
	searcher := setupTestSearcher(t)

	results, err := searcher.SearchWithOptions("wate", "definition", 10, SearchOptions{
		StrictDefinition: true,
	})
	if err != nil {
		t.Fatalf("search with strict options: %v", err)
	}

	if len(results) != 0 {
		t.Fatalf("expected no results in strict mode when no whole-word match exists, got %d", len(results))
	}
}

func TestSearchDeduplicatesNumericVariantWhenCanonicalExists(t *testing.T) {
	searcher := setupTestSearcher(t)

	results, err := searcher.Search("water", "definition", 20)
	if err != nil {
		t.Fatalf("search: %v", err)
	}

	dupCount := 0
	for _, result := range results {
		if result.Balochi != "dup" {
			continue
		}
		dupCount++
		if result.NormalizedLatin != "duplatin" {
			t.Fatalf("expected canonical non-numeric variant, got normalized_latin=%q", result.NormalizedLatin)
		}
	}

	if dupCount != 1 {
		t.Fatalf("expected exactly one deduplicated dup entry, got %d", dupCount)
	}
}
