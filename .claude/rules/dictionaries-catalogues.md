---
paths:
  - src/dictionary.bats
  - src/stardict.bats
  - src/catalogue*.bats
  - src/opds.bats
  - src/url.bats
  - src/stored_key.bats
  - e2e/dictionary*
  - e2e/create-stardict.js
  - e2e/catalogue*
---

# Offline dictionaries and catalogues

## Offline dictionaries

`src/dictionary.bats` keeps the StarDict dictionaries Look up reads without a
connection (`src/stardict.bats` reads their bytes). Like an EPUB, a dictionary's
files never enter wasm memory to stay: they are stored from the JS side
(bridge's `$BF.file_idb_put`) and read back by ranges. Import checks the .ifo,
the .idx's size, every record of the .idx and .syn and a .dict.dz's chunk table,
and stores a table ('X') of every 64th headword; a lookup binary-searches it
and reads one block. An article is shown as text only (`article_text`): HTML
and XDXF tags are dropped, never put in the DOM. The list is stored under
"dicts"; the backup lists names and languages, not files.

**Removal goes to the Trash** (#396, as a book does): `dict_state`
(`Installed | InTrash`, bit 4 of the form's byte), offered back by Undo, files
kept, out of Look up, listed under the books while the Trash is shown
(`dict_trash_render`) with a Restore. **Only Empty Trash deletes the files**, in
the Accepted branch of `lib_ask_harm` (`src/library.bats`). The compiler
enforces it: `dictionary.bats` exports only `dict_trash_count` and
`dict_trash_take` (which hands over the storage keys, `dict_file_keys`, without
deleting), and the function that deletes them, `_dictionary_files_delete`, has
no `#pub` and is called from that one branch
(`tests/static/reject/dictionary-files-deleted-elsewhere`). Not reached by the
types: `dict_trash_take` may be called anywhere and drops the dictionaries from
the Trash's list, leaving their files.

`library.bats` stands above `dictionary.bats` (a staload cycle is an ATS
error, so `lib_key` is in `src/stored_key.bats`), so `dictionary.bats` cannot
tell the library that the Trash's dictionaries changed: the Trash's heading asks
(`dict_trash_count`), and what changes them is followed by
`lib_trash_head_show` (quire.bats' `_trash_dictionaries`,
`_dictionary_removed`; `dict_remove` returns the promise of how its Undo
settled). The Trash shows counts, not sizes (the files are on the JS side).

## Catalogues

`src/catalogues.bats` keeps the OPDS catalogues books are got from (the library
menu's Catalogues): name and URL under "catalogues", Project Gutenberg's alone
until changed; a removal is offered back by Undo; the backup lists them.
`src/catalogue.bats` browses one a page at a time, each page a step of a trail
Back walks. A page is fetched through the bridge (`$FE.fetch`), read into an
arena piece of at most 4 MiB (`FEED_MOST`; larger is refused) and parsed by
`src/opds.bats` (OPDS 1.2 Atom with xml-tree, OPDS 2 JSON with jsonio) into a
feed of at most 500 entries, with next and previous pages and a search template
(`{searchTerms}`, OPDS 2's `{?query}`, or the OpenSearch description that holds
one). Every address is resolved against the page's own (`src/url.bats`, RFC
3986). Get fetches the EPUB acquisition link (an EPUB 3 one first), puts its
bytes on the JS side (`$BF.file_store`) and imports them as a picked file is
(`import_fetched`). Where the fetch fails (a browser, a page without CORS) Get
gives way to a download link (`ui_download_nn`). A page that cannot be read
says why: not readable by a browser, 404, needs a sign-in (401, 403), or not a
catalogue. DRM entries are in `backup-errors.md`.
