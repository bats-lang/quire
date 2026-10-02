# Quire

An EPUB e-reader built on the [bats-lang](https://github.com/bats-lang) ecosystem. Runs entirely in the browser as a WebAssembly progressive web app.

**[Try Quire](https://bats-lang.github.io/quire/)**

## Features

**Library**
- Import EPUB files by picking or dropping them; on Android, open them
  from another app or share them to Quire
- Import progress, a message for files that are not EPUBs, and a question
  when a book is imported twice (matched by its SHA-256)
- Cards with covers, titles, authors and progress; sort by last opened,
  title, author or date added; search by title or author
- Shelves: the library, hidden books and archived books (an archived
  book keeps its place and notes, and is read again by importing it)
- Book info, delete, and a factory reset

**Reading**
- Pages turned by buttons, keys (arrows, Page Up/Down, Space, Home, End),
  taps on the page's sides, the mouse wheel and swipes; right-to-left
  books turn the other way
- The contents (EPUB 3 nav or EPUB 2 NCX), a scrubber with chapter ticks,
  and a back button after every jump
- The place is kept: on reopening, after a reload, and when the type
  size, spacing, margins or window size change
- Search in the book, with results by chapter and the match marked
- Bookmarks, highlights and notes, exported as Markdown
- The book's markup, links (inside the book and out of it), images,
  tables and its own fonts

**Settings and data**
- Type size, line spacing, margins, font (Literata, Inter or the book's)
  and theme (auto, light, sepia, dark), applied and kept as they change
- Backup and restore of the library, settings, places and annotations as
  one JSON file (not the EPUBs); a book restored before it is imported
  takes its state back when it is
- Works offline as a PWA, and as an Android app

## Architecture

Quire is written in [Bats](https://github.com/bats-lang/bats), a language that compiles to ATS2 and then to WebAssembly. The UI is rendered through a virtual DOM diffing protocol via the [bridge](https://github.com/bats-lang/bridge) package.

Key packages used:
- **widget** — virtual DOM tree and diff generation
- **dom** — binary DOM protocol emitter
- **bridge** — WASM-to-JS bridge with event handling
- **css** — CSS class generation
- **zip/decompress** — EPUB archive extraction
- **xml-tree** — XML/OPF metadata parsing

## Development

```bash
# Write the version (src/version.bats, not in git): the date and short
# SHA of the commit built from
scripts/version.sh

# Build the app (wasm) and the PWA generator (native)
bats build --repository ../repository-prototype

# Generate the PWA (into dist/pwa) and the Android project
./dist/debug/gen-pwa

# Run the e2e tests (desktop and phone for every area; the layout tests
# at five screen sizes)
npx playwright test
```

## License

See individual package repositories for license information.
