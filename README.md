# Balochi Dictionary (Flutter)

Android port of the [Balochi Dictionary](https://github.com/raysh454/BalochiDictionary)
originally built with Go and Wails. Data scraped from
<https://www.webonary.org/balochidictionary/browse/>.

The dictionary is fully offline: the same SQLite database the Go app embedded
(18,345 headwords, 16,269 definitions) ships as a Flutter asset.

## Features

- **Word of the Day** — one word per calendar day, plus the previous five days.
- **Browse** — headwords in dictionary order, filtered by a Balochi letter
  rail, loading further pages as you scroll.
- **Search** — by Balochi headword, Latin transliteration, or English
  definition, with the same ranking rules as the Go build.

## Running it

```bash
flutter pub get
flutter run                 # Android device or emulator
flutter run -d windows      # desktop, for development
```

Build a release APK:

```bash
flutter build apk --release
```

Run the tests (they execute against the real bundled dictionary):

```bash
flutter test
```

## How it maps to the Go original

| Go | Flutter |
| --- | --- |
| `internal/dictionary/balochi_dictionary.go` | `lib/data/dictionary_repository.dart` |
| `internal/search/service.go` | `lib/data/dictionary_repository.dart` |
| `App.deployDatabase` / `initializeDatabase` (`app.go`) | `lib/data/database_service.dart` |
| `frontend/src/components/BrowseTab.vue` | `lib/screens/browse_screen.dart` |
| `frontend/src/components/SearchTab.vue` | `lib/screens/search_screen.dart` |
| `frontend/src/components/LetterJumpSidebar.vue` | `lib/widgets/letter_jump_rail.dart` |
| `frontend/src/constants/balochiAlphabet.ts` | `lib/constants/balochi_alphabet.dart` |

The SQL is kept close to the original so search ranking and browse paging
behave the same:

- Latin and Balochi search rank exact matches first, then prefix matches
  shortest-first, with a deterministic lexical/id tie-break.
- Definition search does whole-word matching and ranking first, then falls
  back to broad substring matching when nothing matched.
- Numeric transliteration variants (`normalized_latin = '1'`) are
  de-duplicated against their readable equivalents.

There is no HTTP layer — the UI calls the repository directly, so the
`cmd/web` API surface has no counterpart here.

### Indexes

The shipped database carries no indexes, which makes the definition joins and
the word-of-the-day lookup full table scans — around 13 seconds per
word-of-the-day query. `DatabaseService` builds three indexes when it deploys
the database to app storage on first launch (about 0.1s and 0.9 MB), after
which those queries take milliseconds. Bump `DatabaseService.deploymentVersion`
if the asset or the index set changes, so installed copies get rebuilt.

## Word of the Day

The word is a pure function of the date, so it needs no stored state: the same
word shows all day, on every launch and every device, and past days can be
recomputed.

A day number is mapped to a pool index by multiplying it by a stride that is
coprime with the pool size. Because that mapping is a bijection over the pool,
every eligible word is shown exactly once before any word repeats — roughly a
49-year cycle over the 17,640 eligible headwords. Eligible means the word has
at least one definition and a real transliteration rather than one of the
digit-only placeholder variants.
