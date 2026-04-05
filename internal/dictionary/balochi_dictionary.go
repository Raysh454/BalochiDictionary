package balochidictionary

import (
	"database/sql"
	"errors"
	"sort"
	"strings"
	"unicode"
)

type Result struct {
	WordID          int
	Balochi         string
	Latin           string
	NormalizedLatin string
	Definitions     []Definition
}

type Definition struct {
	PartOfSpeech string
	Text         string
}

type SQLiteSearcher struct {
	DB *sql.DB
}

type SearchOptions struct {
	StrictDefinition bool
}

func NewSQLiteSearcher(db *sql.DB) (*SQLiteSearcher, error) {
	if db == nil {
		return nil, errors.New("db cannot be nil")
	}

	return &SQLiteSearcher{
		DB: db,
	}, nil
}

func normalizeForDefinitionSearch(input string) string {
	var b strings.Builder
	b.Grow(len(input))
	for _, r := range strings.ToLower(input) {
		if unicode.IsLetter(r) || unicode.IsNumber(r) || unicode.IsSpace(r) {
			b.WriteRune(r)
			continue
		}
		b.WriteRune(' ')
	}

	return strings.Join(strings.Fields(b.String()), " ")
}

func (s *SQLiteSearcher) collectWordIDs(rows *sql.Rows) ([]int, error) {
	defer rows.Close()

	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return nil, err
		}
		ids = append(ids, id)
	}

	return ids, nil
}

func (s *SQLiteSearcher) searchDefinitionWordIds(query string, limit int, strictDefinition bool) ([]int, error) {
	normalizedQuery := normalizeForDefinitionSearch(query)
	if normalizedQuery == "" {
		return []int{}, nil
	}

	const normalizedDefinitionExpr = `
		trim(
			replace(replace(replace(replace(replace(replace(replace(replace(lower(d.definition),
			';', ' '), ',', ' '), '.', ' '), ':', ' '), '(', ' '), ')', ' '), '-', ' '), '/', ' ')
		)
	`

	wholeWordPattern := "% " + normalizedQuery + " %"
	startPattern := " " + normalizedQuery + " %"
	occurrenceToken := " " + normalizedQuery + " "

	wholeWordRows, err := s.DB.Query(
		`SELECT w.id
		FROM words AS w
		JOIN word_definitions AS wd ON w.id = wd.word_id
		JOIN definitions AS d ON wd.definition_id = d.id
		WHERE (' ' || `+normalizedDefinitionExpr+` || ' ') LIKE ?
		GROUP BY w.id
		ORDER BY
			MAX(CASE
				WHEN `+normalizedDefinitionExpr+` = ? THEN 300
				WHEN (' ' || `+normalizedDefinitionExpr+` || ' ') LIKE ? THEN 200
				ELSE 100
			END) +
			MAX((LENGTH(' ' || `+normalizedDefinitionExpr+` || ' ') - LENGTH(REPLACE(' ' || `+normalizedDefinitionExpr+` || ' ', ?, ''))) / LENGTH(?)) DESC,
			w.id ASC
		LIMIT ?`,
		wholeWordPattern,
		normalizedQuery,
		startPattern,
		occurrenceToken,
		occurrenceToken,
		limit,
	)
	if err != nil {
		return nil, err
	}

	ids, err := s.collectWordIDs(wholeWordRows)
	if err != nil {
		return nil, err
	}

	if len(ids) > 0 || strictDefinition {
		return ids, nil
	}

	fallbackRows, err := s.DB.Query(
		`SELECT DISTINCT w.id
		FROM words AS w
		JOIN word_definitions AS wd ON w.id = wd.word_id
		JOIN definitions AS d ON wd.definition_id = d.id
		WHERE lower(d.definition) LIKE ?
		LIMIT ?`,
		"%"+strings.ToLower(query)+"%",
		limit,
	)
	if err != nil {
		return nil, err
	}

	return s.collectWordIDs(fallbackRows)
}

func (s *SQLiteSearcher) fillWord(result *Result) error {
	rows, err := s.DB.Query("SELECT balochi, latin, normalized_latin FROM words WHERE id = ?", result.WordID)
	if err != nil {
		return err
	}
	defer rows.Close()

	if !rows.Next() {
		return sql.ErrNoRows
	}

	err = rows.Scan(&result.Balochi, &result.Latin, &result.NormalizedLatin)

	return err
}

func (s *SQLiteSearcher) fillDefinitions(result *Result) error {
	rows, err := s.DB.Query(
		`SELECT d.part_of_speech, d.definition FROM words AS w
			JOIN word_definitions AS wd ON w.id = wd.word_id
			JOIN definitions AS d ON wd.definition_id = d.id
			WHERE w.id = ?`,
		result.WordID)
	if err != nil {
		return err
	}
	defer rows.Close()

	var definition Definition

	for rows.Next() {
		err = rows.Scan(&definition.PartOfSpeech, &definition.Text)
		if err != nil {
			return err
		}

		result.Definitions = append(result.Definitions, definition)
	}

	return nil
}

func (s *SQLiteSearcher) loadWordById(id int) (*Result, error) {
	var result Result
	result.WordID = id

	err := s.fillWord(&result)
	if err != nil {
		return nil, err
	}

	err = s.fillDefinitions(&result)
	if err != nil {
		return nil, err
	}

	return &result, nil
}

func (s *SQLiteSearcher) loadWordsFromIDs(ids []int) ([]Result, error) {
	var results []Result

	for _, id := range ids {
		r, err := s.loadWordById(id)
		if err != nil {
			return nil, err
		}

		results = append(results, *r)
	}

	return deduplicateNumericVariants(results), nil
}

func definitionsSignature(definitions []Definition) string {
	signatures := make([]string, 0, len(definitions))
	for _, definition := range definitions {
		signatures = append(signatures, definition.PartOfSpeech+"\x1f"+definition.Text)
	}
	sort.Strings(signatures)
	return strings.Join(signatures, "\x1e")
}

func isNumericOnly(value string) bool {
	if value == "" {
		return false
	}

	for _, r := range value {
		if !unicode.IsDigit(r) {
			return false
		}
	}

	return true
}

func deduplicateNumericVariants(results []Result) []Result {
	deduped := make([]Result, 0, len(results))
	seenCanonicalIndex := make(map[string]int)

	for _, result := range results {
		key := result.Balochi + "\x1d" + definitionsSignature(result.Definitions)
		existingIndex, seen := seenCanonicalIndex[key]
		if !seen {
			seenCanonicalIndex[key] = len(deduped)
			deduped = append(deduped, result)
			continue
		}

		existing := deduped[existingIndex]
		existingIsNumeric := isNumericOnly(existing.NormalizedLatin)
		currentIsNumeric := isNumericOnly(result.NormalizedLatin)

		// Replace a numeric variant with a transliterated variant while preserving rank position.
		if existingIsNumeric && !currentIsNumeric {
			deduped[existingIndex] = result
			continue
		}

		// Hide extra numeric variants for the same headword+definition signature.
		if currentIsNumeric {
			continue
		}

		// Keep distinct non-numeric transliteration variants visible.
		deduped = append(deduped, result)
	}

	return deduped
}

func (s *SQLiteSearcher) searchWordIds(query string, field string, limit int, options SearchOptions) ([]int, error) {
	switch field {
	case "balochi":
		rows, err := s.DB.Query("SELECT id FROM words WHERE balochi LIKE ? LIMIT ?", query+"%", limit)
		if err != nil {
			return nil, err
		}
		return s.collectWordIDs(rows)
	case "latin":
		rows, err := s.DB.Query("SELECT id FROM words WHERE normalized_latin LIKE ? LIMIT ?", query+"%", limit)
		if err != nil {
			return nil, err
		}
		return s.collectWordIDs(rows)
	case "definition":
		return s.searchDefinitionWordIds(query, limit, options.StrictDefinition)
	default:
		return nil, errors.New("Invalid search method")
	}
}

func (s *SQLiteSearcher) SearchWithOptions(query string, field string, limit int, options SearchOptions) ([]Result, error) {
	ids, err := s.searchWordIds(query, field, limit, options)
	if err != nil {
		return nil, err
	}

	return s.loadWordsFromIDs(ids)
}

func (s *SQLiteSearcher) Search(query string, field string, limit int) ([]Result, error) {
	return s.SearchWithOptions(query, field, limit, SearchOptions{})
}
