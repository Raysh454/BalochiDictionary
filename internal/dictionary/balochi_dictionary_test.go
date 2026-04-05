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
			(5, 'dup', 'duplatin', 'duplatin'),
			(6, 'a', 'ax', 'ax');`,
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

func TestBrowseReturnsAlphabeticalRowsWithDeterministicPaging(t *testing.T) {
	searcher := setupTestSearcher(t)

	items, hasMore, err := searcher.Browse("", 2, 0)
	if err != nil {
		t.Fatalf("browse: %v", err)
	}

	if !hasMore {
		t.Fatalf("expected hasMore for first page")
	}
	if len(items) != 2 {
		t.Fatalf("expected 2 items, got %d", len(items))
	}
	if items[0].WordID != 1 || items[1].WordID != 6 {
		t.Fatalf("expected tie-break by id for same balochi values, got ids %d, %d", items[0].WordID, items[1].WordID)
	}

	nextItems, nextHasMore, err := searcher.Browse("", 2, 2)
	if err != nil {
		t.Fatalf("browse next page: %v", err)
	}

	if !nextHasMore {
		t.Fatalf("expected hasMore for second page")
	}
	if len(nextItems) != 2 {
		t.Fatalf("expected 2 items on second page, got %d", len(nextItems))
	}
	if nextItems[0].WordID != 2 || nextItems[1].WordID != 3 {
		t.Fatalf("expected stable alphabetical pagination, got ids %d, %d", nextItems[0].WordID, nextItems[1].WordID)
	}
}

func TestBrowseFiltersByLetter(t *testing.T) {
	searcher := setupTestSearcher(t)

	items, hasMore, err := searcher.Browse("d", 10, 0)
	if err != nil {
		t.Fatalf("browse with letter: %v", err)
	}

	if hasMore {
		t.Fatalf("expected no extra pages for filtered result")
	}
	if len(items) != 2 {
		t.Fatalf("expected 2 filtered items, got %d", len(items))
	}
	for _, item := range items {
		if item.Balochi != "dup" {
			t.Fatalf("expected only 'dup' rows for letter filter, got %q", item.Balochi)
		}
	}
}

func TestBrowseLettersReturnsGroupedCounts(t *testing.T) {
	searcher := setupTestSearcher(t)

	letters, err := searcher.BrowseLetters()
	if err != nil {
		t.Fatalf("browse letters: %v", err)
	}

	expected := map[string]int{
		"a": 2,
		"b": 1,
		"c": 1,
		"d": 2,
	}
	if len(letters) != len(expected) {
		t.Fatalf("expected %d letter groups, got %d", len(expected), len(letters))
	}
	for _, letter := range letters {
		count, ok := expected[letter.Letter]
		if !ok {
			t.Fatalf("unexpected letter %q in browse letters", letter.Letter)
		}
		if count != letter.Count {
			t.Fatalf("unexpected count for letter %q: got %d want %d", letter.Letter, letter.Count, count)
		}
	}
}

func TestWordByIDReturnsDefinitions(t *testing.T) {
	searcher := setupTestSearcher(t)

	result, err := searcher.WordByID(1)
	if err != nil {
		t.Fatalf("word by id: %v", err)
	}

	if result.Balochi != "a" {
		t.Fatalf("unexpected word payload: %+v", result)
	}
	if len(result.Definitions) != 1 || result.Definitions[0].Text != "water" {
		t.Fatalf("unexpected definitions payload: %+v", result.Definitions)
	}
}
