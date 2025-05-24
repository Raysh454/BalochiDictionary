package main

import (
	"balochi_dictionary_wails/internal/dictionary"
	"context"
	"database/sql"
	"embed"
	"encoding/json"
	"os"
	"path/filepath"

	_ "github.com/mattn/go-sqlite3"
)

// App struct
type App struct {
	ctx context.Context
	SQLiteSearcher *balochidictionary.SQLiteSearcher
	assets embed.FS
}

// NewApp creates a new App application struct
func NewApp(assets embed.FS) *App {
	return &App{
		assets: assets,
	}
}

// startup is called when the app starts. The context is saved
// so we can call the runtime methods
func (a *App) startup(ctx context.Context) {
	a.ctx = ctx
}

func (a *App) deployDatabase() (string, error) {
	const embeddedPath = "internal/dictionary/Database/balochi_dict.db"

	configDir, err := os.UserConfigDir()
	if err != nil {
		return "", err
	}

	appDir := filepath.Join(configDir, "BalochiDictionary")
	os.MkdirAll(appDir, 0755)

	dbPath := filepath.Join(appDir, "balochi_dict.db")

	if _, err := os.Stat(dbPath); os.IsNotExist(err) {
		data, err := a.assets.ReadFile(embeddedPath)
		if err != nil {
			return "", err 
		}
		err = os.WriteFile(dbPath, data, 0644)
		if err != nil {
			return "", err 
		}
	}

	return dbPath, nil
}

func (a *App) initializeDatabase() (*sql.DB, error) {

	dbPath, err := a.deployDatabase()
	if err != nil {
		return nil, err
	}

	db, err := sql.Open("sqlite3", dbPath)
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
