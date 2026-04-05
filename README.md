# Balochi Dictionary

## About

Balochi Dictionary made using Go and [Wails](https://wails.io/docs/gettingstarted/building).
Data scraped from: https://www.webonary.org/balochidictionary/browse/

## Installation

Releases are available to directly download.

To compile from source, follow the instructions to install wails at: https://wails.io/docs/gettingstarted/installation
Then to build the project, run

```bash
wails build
```

The built file will be present at build/bin

## Run as a web app (local)

Build the frontend bundle:

```bash
cd frontend
npm install
npm run build
```

Run the web server from the repository root:

```bash
go run ./cmd/web
```

Then open `http://localhost:8080`.

## Deploy on Railway

This repository now includes a `Dockerfile` for Railway deployment of the full web app (UI + API).

1. Set Railway service to deploy with the repo `Dockerfile`.
2. Railway will provide `PORT`; the server binds to it automatically.
3. Deploy.

The dictionary database is shipped as a static read-only SQLite file inside the image (`internal/dictionary/Database/balochi_dict.db`).
