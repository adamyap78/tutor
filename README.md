# Tutor

Fast, keyboard-first, offline-first Magic: The Gathering card browser for macOS (Apple Silicon).
Swift + SwiftUI + SQLite. Card data from [Scryfall](https://scryfall.com) bulk files.

## Build & run

```sh
Scripts/build_app.sh        # -> dist/Tutor.app (needs only Xcode Command Line Tools)
open "dist/Tutor.app"
```

First launch downloads ~80 MB of card data into `~/Library/Application Support/Tutor/`.

## Keys

↑↓ navigate · ⏎ inspect · ⇥ flip · ⌘K/⌘F search · ⌘C copy name · ⇧⌘C copy details ·
⌘G grid/list · ⌘O Scryfall · ⌘R refresh data · ⎋ back/clear

Search uses Scryfall-style syntax: `t:creature c:r mv<=3 f:modern o:draw`, `-`, `or`, `( )`, `"phrases"`.
