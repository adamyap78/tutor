# AGENTS.md

macOS SwiftUI app: instant offline MTG card search over a local SQLite DB built from Scryfall bulk data.

## Commands
- Build app: `Scripts/build_app.sh` (outputs `dist/MTG Viewer.app`)
- Compile only: `swift build -c release`
- Fetch/rebuild data: `.build/release/MTGViewer --import`
- Benchmark queries: `.build/release/MTGViewer --bench` (keep common queries < 10 ms)
- Alternate data dir: `MTG_DATA_DIR=/path`

## Layout (`Sources/MTGViewer/`)
- `Query.swift` Scryfall syntax → SQL · `CardStore.swift` read-only DB access · `Importer.swift` download, parse, build, atomic swap
- `AppModel.swift` all UI state · `Views.swift`, `ManaViews.swift` UI · `ImageStore.swift` image cache + warmer · `CLI.swift` dev commands

## Rules
- Speed is the product: no network or blocking work on the search/selection path; DB reads stay off the main thread except `row`/`full` lookups.
- The DB is replaced atomically and never modified in place. Changing the schema or import logic means bumping `CardStore.schemaVersion` and re-importing.
- Only Command Line Tools are installed (no Xcode): `@State` fails (missing macro plugin), use `@StateObject`/`@Observable`. Don't name types `Text`.
- Swift 5 language mode. SQLite via the system `SQLite3` module; no third-party dependencies.
- Verify UI changes by running the built app, not just compiling.
