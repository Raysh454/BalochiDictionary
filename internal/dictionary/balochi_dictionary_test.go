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
	if len(items[0].Definitions) != 1 || items[0].Definitions[0].Text != "water" {
		t.Fatalf("expected browse item definitions for word 1, got %+v", items[0].Definitions)
	}
	if len(items[1].Definitions) != 0 {
		t.Fatalf("expected empty definitions for word 6, got %+v", items[1].Definitions)
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
		if len(item.Definitions) != 1 || item.Definitions[0].Text != "fresh water" {
			t.Fatalf("expected filtered browse row definitions, got %+v", item.Definitions)
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

func TestBalochiSearchRanksExactThenShortestPrefixThenDeterministicTieBreak(t *testing.T) {
	searcher := setupTestSearcher(t)

	if _, err := searcher.DB.Exec(`
		INSERT INTO words (id, balochi, latin, normalized_latin) VALUES
			(7, 'ka', 'k-latin-1', 'k-latin-1'),
			(8, 'ka', 'k-latin-2', 'k-latin-2'),
			(9, 'kaa', 'k-latin-3', 'k-latin-3'),
			(10, 'kab', 'k-latin-4', 'k-latin-4'),
			(11, 'kaa', 'k-latin-5', 'k-latin-5'),
			(12, 'kaab', 'k-latin-6', 'k-latin-6'),
			(13, 'kaac', 'k-latin-7', 'k-latin-7');
	`); err != nil {
		t.Fatalf("insert ranking rows: %v", err)
	}

	results, err := searcher.Search("ka", "balochi", 20)
	if err != nil {
		t.Fatalf("search: %v", err)
	}

	if len(results) < 7 {
		t.Fatalf("expected at least 7 results, got %d", len(results))
	}

	expectedOrder := []int{7, 8, 9, 11, 10, 12, 13}
	for i, id := range expectedOrder {
		if results[i].WordID != id {
			t.Fatalf("unexpected rank at index %d: got id=%d want id=%d", i, results[i].WordID, id)
		}
	}
}

func TestLatinSearchRanksExactThenShortestPrefixThenDeterministicTieBreak(t *testing.T) {
	searcher := setupTestSearcher(t)

	if _, err := searcher.DB.Exec(`
		INSERT INTO words (id, balochi, latin, normalized_latin) VALUES
			(7, 'x1', 'la-1', 'la'),
			(8, 'x2', 'la-2', 'la'),
			(9, 'x3', 'la-3', 'laa'),
			(10, 'x4', 'la-4', 'lab'),
			(11, 'x5', 'la-5', 'laa'),
			(12, 'x6', 'la-6', 'laab'),
			(13, 'x7', 'la-7', 'laac');
	`); err != nil {
		t.Fatalf("insert ranking rows: %v", err)
	}

	results, err := searcher.Search("la", "latin", 20)
	if err != nil {
		t.Fatalf("search: %v", err)
	}

	if len(results) < 7 {
		t.Fatalf("expected at least 7 results, got %d", len(results))
	}

	expectedOrder := []int{7, 8, 9, 11, 10, 12, 13}
	for i, id := range expectedOrder {
		if results[i].WordID != id {
			t.Fatalf("unexpected rank at index %d: got id=%d want id=%d", i, results[i].WordID, id)
		}
	}
}
