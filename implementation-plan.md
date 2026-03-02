# Quire Implementation Plan

## Overview

Quire is an EPUB e-reader reimplemented on the bats-lang ecosystem. The original quire
(23,822 lines across 22 modules built on ward) is replaced by ~2,900 lines using bats-lang
packages: widget, css, bridge, idb, zip, decompress, xml-tree, sha256, json, promise.

## Architecture

```
quire/
  bats.toml                  # kind = "bin", WASM target
  src/
    bin/quire.bats           # entry point: init, routing, event handling
    state.bats               # app_state datavtype
    epub.bats                # EPUB import pipeline
    library.bats             # book library: add/remove/sort, IDB persistence
    reader.bats              # chapter loading, pagination, navigation
    settings.bats            # user prefs: font, theme, margins
    views.bats               # all view rendering via widget package
    theme.bats               # CSS generation via css package
  e2e/
    smoke.spec.js            # quick WASM load + import test
    epub-reader.spec.js      # full e2e test suite (from moshez/quire)
    create-epub.js           # programmatic EPUB generation for tests
  test/
    fixtures/
      conan-stories.epub     # real-world EPUB test fixture
  playwright.config.js
  package.json               # playwright + vitest dev deps
```

## E2E Test Strategy

Tests are copied from github.com/moshez/quire. ALL tests start commented out.
As features are implemented, tests are progressively uncommented. Each phase
ends with CI green.

## Implementation Phases

### Phase 0: Scaffolding (task #200)
- Create repo, bats.toml, CI, e2e skeleton with all tests commented out

### Phase 1: State + Library + Empty Library View (tasks #201-#206)
- app_state datavtype, library load/save, empty library view, base CSS, entry point
- Uncomment: smoke test up to empty library check

### Phase 2: EPUB Import + Library Card (tasks #207-#211)
- EPUB import pipeline, library card view, import progress, wiring
- Uncomment: smoke import section, epub-reader import test up to line 127

### Phase 3: Reader Core (tasks #212-#217)
- Chapter loading, reader view with chrome, reader CSS, pagination
- Uncomment: smoke reader section, epub-reader lines 129-199

### Phase 4: Page Navigation (tasks #218-#221)
- Click zone page turn, prev/next buttons, keyboard nav
- Uncomment: epub-reader lines 223-334

### Phase 5: Chapter Navigation (tasks #222-#226)
- Chapter transitions, back button, position save
- Uncomment: chapter nav test, epub-reader lines 336-353

### Phase 6: Real-World EPUB + Robustness (tasks #227-#231)
- Uncomment: conan EPUB, SVG cover, large chapter, progress format tests

### Phase 7: Library Persistence + Position Restore (tasks #232-#237)
- Uncomment: persistence, position restore, resume, visibilitychange tests

### Phase 8: Settings (tasks #238-#240)
- Settings module, settings panel UI
- Uncomment: settings test

### Phase 9: Library Management (tasks #241-#252)
- Archive/restore, sort, hide/unhide, duplicate detection, error handling
- Uncomment: 7 related tests

### Phase 10: Cover Images + Search (tasks #253-#258)
- Cover extraction, search index, search panel
- Uncomment: 4 related tests

### Phase 11: Reader Chrome Polish (tasks #259-#271)
- TOC, bookmarks, scrubber, position stack, escape hierarchy, selection toolbar
- Uncomment: 7 related tests

### Phase 12: UI Polish (tasks #272-#285)
- Uncomment: 14 CSS/layout/UX verification tests
