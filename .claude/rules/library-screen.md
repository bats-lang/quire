---
paths:
  - src/library*.bats
  - src/app.bats
  - src/bin/quire.bats
  - src/layer.bats
  - e2e/library*
  - e2e/walk.js
  - e2e/settings-screen*
  - e2e/back*
  - e2e/layout*
---

# The library screen

Decided by research (what comparable library apps do) in #375, #376, #377, #404:

* **The bar is one row** (`library-bar`): the name, Import (`import-button`, a
  plus; its file input, named Import EPUB, lies over it, since a page cannot open
  the picker itself), Sort and view (`sort-menu-button`) and More options, with
  the search field on a row under them (Material 3's top app bar is a title and
  up to three actions, the rest in an overflow). At 320 px the first card begins
  in the top 40% of the screen (`e2e/library.spec.js`). Import is an icon, not a
  chip: chips are for filters and choices, not actions.
* **Sort and view is one menu** (`LSortMenu`, `sort-menu`): the five orders
  (`sort_order`: Last opened, Title, Author, Date added, Series) and List or Grid
  (`layout`) as two groups of `menuitemradio`s (`ui_menu_choice`), the current
  one `aria-checked`. `tests/static/next.py` fails a `*_next` function that takes
  and gives a datatype of more than three constructors (the reader's footer
  readout is the one allowed). The filters (All, Unread, Reading, Finished) stay
  chips.
* **Hidden, Archived and Trash are screens of their own** (`LShelf`,
  `shelf-header`, in place of the library's bar), opened from the library menu;
  there is no shelf selector. A shelf is a layer, so Escape, Back and the back
  button close it as one step (`_escape_overlay`), and the filters, search and
  collection are the library's alone (`_passes` lets everything on a shelf
  through; opening a shelf clears the search and the collection). A book opened
  from a shelf's screen closes to the library (`_show_reader`). A shelf's rows
  offer Unhide, Unarchive (it says to import the file again: archiving drops the
  file) and Restore (Trash); a row's actions open on its More button and on a
  long press or right click.
* **A book's menu is grouped, and Book info reads** (quire#386): Read (Continue
  once opened, Read again once finished: `lib_reading_state`, the one rule behind
  the card's word and the filter chips; none for a book in the Trash or
  archived), Book info, Collections, a divider (`role=separator`, `.msep`), Hide,
  Archive, and Move to Trash, made by `ui_removal_item` from a `removal` and drawn
  by `[data-removal]` with a line above it; it is not red, since Undo and Restore
  bring the book back. Book info has the same Read as its primary button and the
  author in `.info-author`, proven on the page's ground. `strayGrounds`
  (`e2e/controls-shown.js`) fails a text element whose own ground is not the one
  behind it unless it is a control or a card. A book whose metadata says nothing
  of its accessibility is told so once, not by a line under each heading.
* **An empty library says what to do, and only that one** (`emptiness`:
  `NoBooksYet | NoMatch | NoCollection | NoUnread | NoneReading | NoneFinished |
  NothingHidden | NothingArchived | TrashEmpty`, by `_emptiness_of`,
  `_emptiness_text`; `_emptiness_offers` is true for `NoBooksYet` alone). With no
  book the bar keeps its name and menu (`_tools_show`), and the message offers
  Import EPUB (`empty-import`, its own file input `empty-import-file`, both
  inputs always there so a pick is never lost to a control made again) and Get
  free books (`empty-catalogues`). Every other reason is said and offers nothing,
  since importing would not change it. The unreadable library (#374) keeps the
  bar's inert Import and no offer.
* **The book menu button is one box in both views** (#495): 48 by 48, centred in
  a list item, over the cover's corner in the grid, never stretched.
  `cardMoreBoxes` (`e2e/controls-shown.js`) measures it and `e2e/layout.spec.js`
  fails if the two views differ.
* **One word for a book's state** (`reading_state`: `StateUnread | StateReading |
  StateFinished`): the filter and the card use it.
* `e2e/library.spec.js` plays each of these; `e2e/walk.js` walks the sort and view
  menu and the shelf screens, so the layout, safe area, target size and Back
  specs cover them.
