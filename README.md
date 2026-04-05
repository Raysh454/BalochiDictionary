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

## Definition search semantics

Definition mode now uses a two-stage strategy for better relevance:

1. Whole-word matching and ranking (exact definition matches first, then phrase-leading matches, then other whole-word matches).
2. If no whole-word results exist, it falls back to broad substring matching.
3. Numeric transliteration variants (for example `normalized_latin=1`) are deduplicated when an equivalent non-numeric canonical transliteration exists for the same headword+definitions.

For the web API (`/api/search`), you can disable fallback with:

- `strict_definition=true`

Example:

`/api/search?keyword=water&method=definition&limit=20&strict_definition=true`

## Browse feature (tab intent and behavior)

The browse feature is for scanning headwords in dictionary order instead of typing a search query.

- Intended UX in a tabbed client:
  - **Search tab**: query-driven lookup (current bundled UI behavior).
  - **Browse tab**: alphabetic list + paging + optional first-letter filter.
- Default tab behavior: keep **Search** as the default entry view. Browse is an additional navigation mode.

### High-level letter filtering / jumping flow

1. Call `GET /api/browse/letters` to render available letter buckets.
2. When a user picks a letter, call `GET /api/browse` with `letter=<selected>` and `offset=0`.
3. Use `pagination.nextOffset` / `pagination.hasMore` from each browse response to jump to the next page for the same filter.
4. Clearing the letter filter means calling `/api/browse` without `letter`.

## Browse API

### `GET /api/browse`

Query params:

- `limit` (optional): defaults to `50`, must be `>=1`, max `100`
- `offset` (optional): defaults to `0`, must be `>=0`
- `letter` (optional): prefix filter on `balochi` (`LIKE letter + '%'`)

Behavior:

- sorted by `balochi ASC, id ASC`
- returns lightweight rows only (`WordID`, `Balochi`, `Latin`, `NormalizedLatin`)
- deterministic paging via `offset` and `limit`

Response shape:

```json
{
  "items": [
    {
      "WordID": 2,
      "Balochi": "آ",
      "Latin": "alif-madda",
      "NormalizedLatin": "alifmadda"
    }
  ],
  "pagination": {
    "offset": 0,
    "limit": 1,
    "nextOffset": 1,
    "hasMore": false
  },
  "filter": {
    "letter": "آ"
  }
}
```

### `GET /api/browse/letters`

Returns grouped first-letter buckets used by browse UIs:

```json
{
  "letters": [
    { "letter": "ا", "count": 123 },
    { "letter": "آ", "count": 45 }
  ]
}
```

### `GET /api/browse/item`

Returns a full dictionary entry (including `Definitions`) for a selected browse row.

Query params:

- `word_id` (required): dictionary word id, must be a positive integer

Example:

`/api/browse/item?word_id=2`
