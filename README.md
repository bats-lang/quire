# Quire

An EPUB e-reader built on the [bats-lang](https://github.com/bats-lang) ecosystem. Runs entirely in the browser as a WebAssembly progressive web app.

**[Try Quire](https://bats-lang.github.io/quire/)**

## Features

- Import EPUB files from your device
- Paginated chapter reading with click/tap navigation
- Chapter-by-chapter progress tracking
- Font size settings with persistence
- Library view with book cards
- Works offline as a PWA

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
# Build WASM app
bats build --only wasm --repository ../repository-prototype

# Build PWA generator (native)
bats build --only native --repository ../repository-prototype

# Generate PWA shell
mkdir -p dist/pwa && dist/debug/gen-pwa

# Run e2e tests
npx playwright test
```

## License

See individual package repositories for license information.
