package search

import (
	"balochi_dictionary_wails/internal/dictionary"
	"database/sql"
	"encoding/json"
	"errors"
)

type Service struct {
	searcher *balochidictionary.SQLiteSearcher
}

func NewService(db *sql.DB) (*Service, error) {
	if db == nil {
		return nil, errors.New("db cannot be nil")
	}

	searcher, err := balochidictionary.NewSQLiteSearcher(db)
	if err != nil {
		return nil, err
	}

	return &Service{searcher: searcher}, nil
}

func (s *Service) Search(keyword string, searchMethod string, limit int) ([]balochidictionary.Result, error) {
	return s.searcher.Search(keyword, searchMethod, limit)
}

func (s *Service) SearchJSON(keyword string, searchMethod string, limit int) (string, error) {
	result, err := s.Search(keyword, searchMethod, limit)
	if err != nil {
		return "", err
	}

	jsonOutput, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return "", err
	}

	return string(jsonOutput), nil
}
