package balochidictionary

import (
	"database/sql"
	"errors"
)

type Result struct {
	WordID int
	Balochi string
	Latin string
	NormalizedLatin string
	Definitions []Definition
}

type Definition struct {
	PartOfSpeech string
	Text string
}

type SQLiteSearcher struct {
	DB *sql.DB
}

func NewSQLiteSearcher(db *sql.DB) (*SQLiteSearcher, error) {
	if db == nil {
		return nil, errors.New("db cannot be nil")
	}

	return &SQLiteSearcher{
		DB: db,
	}, nil
}

func (s *SQLiteSearcher) searchWordIds(query string, field string, limit int) (*sql.Rows, error) {
	var rows *sql.Rows
	var err error

	switch (field) {
		case "balochi":
			rows, err = s.DB.Query("SELECT id FROM words WHERE balochi LIKE ? LIMIT ?", query + "%", limit)
		case "latin":
			rows, err = s.DB.Query("SELECT id FROM words WHERE normalized_latin LIKE ? LIMIT ?", query + "%", limit)
		case "definition":
			rows, err = s.DB.Query(
				`SELECT w.id FROM words AS w 
					JOIN word_definitions AS wd ON w.id = wd.word_id
					JOIN definitions AS d ON wd.definition_id = d.id
					WHERE d.definition LIKE ? LIMIT ?`,
					"%" + query + "%", limit)
		default:
			return nil, errors.New("Invalid search method")
	}

	return rows, err
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

func (s *SQLiteSearcher) loadWordById (id int) (*Result, error){
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

func (s *SQLiteSearcher) loadWordsFromRows(rows *sql.Rows) ([]Result, error) {
	var results []Result

	for rows.Next() {
		var r *Result
		var id int
		
		err := rows.Scan(&id)
		if err != nil {
			return nil, err
		}

		r, err = s.loadWordById(id)

		if err != nil {
			return nil, err
		}

		results = append(results, *r)
	}

	return results, nil
}

func (s *SQLiteSearcher) Search(query string, field string, limit int) ([]Result, error) {
	rows, err := s.searchWordIds(query, field, limit)

	if err != nil {
		return nil, err
	}

	defer rows.Close()

	return s.loadWordsFromRows(rows)
}
