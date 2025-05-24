package main

import (
	"balochi_dictionary_wails/internal/dictionary"
	"context"
	"database/sql"
	"encoding/json"

	_ "github.com/mattn/go-sqlite3"
)

// App struct
type App struct {
	ctx context.Context
	SQLiteSearcher *balochidictionary.SQLiteSearcher
}

// NewApp creates a new App application struct
func NewApp() *App {
	return &App{}
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

func (a *App) initializeDatabase() (*sql.DB, error) {
	db, err := sql.Open("sqlite3", "./internal/dictionary/Database/balochi_dict.db")
	if err != nil {
		return nil, err
	}

	return db, nil
}

func (a *App) InitSearcher() error {
	db, err := a.initializeDatabase()
	if err != nil {
		return err
	}

	sqliteSearcher, err :=  balochidictionary.NewSQLiteSearcher(db)
	if err != nil {
		return err
	}

	a.SQLiteSearcher = sqliteSearcher 

	return nil
}

func (a *App) Search(keyword string, searchMethod string, limit int) (string, error) {
	result, err := a.SQLiteSearcher.Search(keyword, searchMethod, limit)
	if err != nil {
		return "", err
	}
	
	jsonOutput, err := json.MarshalIndent(result, "", "  ")
	if err != nil {
		return "", err
	}

	return string(jsonOutput), nil
}
