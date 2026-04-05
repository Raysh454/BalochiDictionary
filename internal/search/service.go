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

type SearchOptions struct {
	StrictDefinition bool
}

type BrowsePage struct {
	Items      []balochidictionary.BrowseRow `json:"items"`
	Pagination BrowsePagination              `json:"pagination"`
	Filter     BrowseFilter                  `json:"filter"`
}

type BrowsePagination struct {
	Offset     int  `json:"offset"`
	Limit      int  `json:"limit"`
	NextOffset int  `json:"nextOffset"`
	HasMore    bool `json:"hasMore"`
}

type BrowseFilter struct {
	Letter string `json:"letter"`
}

type BrowseLettersResponse struct {
	Letters []balochidictionary.BrowseLetter `json:"letters"`
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

func (s *Service) SearchWithOptions(keyword string, searchMethod string, limit int, options SearchOptions) ([]balochidictionary.Result, error) {
	return s.searcher.SearchWithOptions(keyword, searchMethod, limit, balochidictionary.SearchOptions{
		StrictDefinition: options.StrictDefinition,
	})
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

func (s *Service) SearchJSONWithOptions(keyword string, searchMethod string, limit int, options SearchOptions) (string, error) {
	result, err := s.SearchWithOptions(keyword, searchMethod, limit, options)
	if err != nil {
		return "", err
	}

	jsonOutput, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return "", err
	}

	return string(jsonOutput), nil
}

func (s *Service) Browse(letter string, limit int, offset int) (BrowsePage, error) {
	items, hasMore, err := s.searcher.Browse(letter, limit, offset)
	if err != nil {
		return BrowsePage{}, err
	}

	return BrowsePage{
		Items: items,
		Pagination: BrowsePagination{
			Offset:     offset,
			Limit:      limit,
			NextOffset: offset + len(items),
			HasMore:    hasMore,
		},
		Filter: BrowseFilter{
			Letter: letter,
		},
	}, nil
}

func (s *Service) BrowseLetters() (BrowseLettersResponse, error) {
	letters, err := s.searcher.BrowseLetters()
	if err != nil {
		return BrowseLettersResponse{}, err
	}

	return BrowseLettersResponse{Letters: letters}, nil
}
