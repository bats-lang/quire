---
paths:
  - src/dictionary.bats
  - src/stardict.bats
  - src/catalogue*.bats
  - src/opds.bats
  - src/url.bats
  - e2e/dictionary*
  - e2e/create-stardict.js
  - e2e/catalogue*
---

# Offline dictionaries and catalogues

### Offline dictionaries

`src/dictionary.bats` keeps the StarDict dictionaries Look up reads
without a connection (`src/stardict.bats` reads their bytes: the
.ifo's keys, the headwords' order, an article as text). Like an EPUB,
a dictionary's files never enter wasm memory to stay: they are stored
from the JS side (bridge's `$BF.file_idb_put`) and read back by
ranges. Its import checks the .ifo and the .idx's size, every record
of the .idx and .syn, and a .dict.dz's chunk table, and stores a table ('X') of
every 64th headword of each with where its record is; a lookup
binary-searches it and reads one block of records. An article is
shown as text only (`article_text`): HTML and XDXF tags are dropped,
never put in the DOM. The list of dictionaries (`dicts`) is stored
under "dicts"; a removal moves the dictionary to the Trash (#396, as a
book is: `dict_state`, `Installed | InTrash`, stored in bit 4 of the
form's byte), offered back by the Undo toast, its files kept. It is out of
Look up, listed under the books while the Trash is the shelf shown
(`trash-dictionaries`, `dict_trash_render`) with a Restore, and only Empty
Trash deletes its files, as it deletes a book's, in the Accepted branch
of `lib_ask_harm` (`src/library.bats`; the dialog says dictionaries go
too). `dictionary.bats` exports only data about what the Trash holds:
`dict_trash_count`, and `dict_trash_take`, which takes the Trash's
dictionaries out of the list and hands over the storage keys of their
files (`dict_file_keys`) without deleting any. The function that deletes
those keys, `_dictionary_files_delete`, has no `#pub` and is called from
that one branch, so no other module can delete a dictionary's files, and
the compiler says so (`tests/static/reject/dictionary-files-deleted-elsewhere`;
the scan `tests/static/trash.py` that stood in for it is gone, #628). That
is possible because `library.bats` stands above `dictionary.bats`: a staload
cycle between them is an error of ATS (a looping trace), so `lib_key` is in
`src/stored_key.bats`, which depends on nothing, and `dictionary.bats`
cannot tell `library.bats` that the Trash's dictionaries changed. Instead
the Trash's heading asks (`dict_trash_count`), what changes the Trash's
dictionaries is followed by `lib_trash_head_show` (quire.bats'
`_trash_dictionaries`, `_dictionary_removed`, after `dict_trash_restore`),
and `dict_remove` returns the promise of how its Undo offer settled, so the
heading is shown again after an Undo too. What the types do not reach:
`dict_trash_take` itself may be called anywhere and drops the dictionaries
from the Trash's list, leaving their files; only the deleting of the files
is confined. Drive and
Files by Google keep trashed items, which still use storage, until they
are emptied; the Trash shows counts, not sizes (a dictionary's files are
on the JS side). The backup lists the
dictionaries' names and languages, not their files.

### Catalogues

`src/catalogues.bats` keeps the OPDS catalogues books are got from
(the library menu's Catalogues): each one's name and URL, stored under
"catalogues", Project Gutenberg's alone until the list is changed. A
removal is offered back by the Undo toast; the backup lists them by
name and URL. `src/catalogue.bats` browses one, a page at a time, each
page a step of a trail Back walks (and from the first page, back to
the list). A page is fetched through the bridge (`$FE.fetch`: its
status and bytes), read into an arena piece of at most 4 MiB (a larger
one is refused) and read by `src/opds.bats`, OPDS 1.2 (Atom, with
xml-tree) or OPDS 2 (JSON, with jsonio), into a feed of at most 500
entries: links to other pages, and books (title, author, cover, EPUB)
with Get; its next and previous pages; its search template
(`{searchTerms}`, or OPDS 2's `{?query}`), or the OpenSearch
description that holds one, fetched after the page. Every address is
resolved against the page's own (`src/url.bats`, RFC 3986). Get
fetches the EPUB acquisition link (an EPUB 3 one first), puts its
bytes on the JS side (bridge's `$BF.file_store`) and imports them as a
picked file is (`import_fetched`), so a book already there is asked
about. Where the fetch fails (in a browser, a page without CORS), Get
gives way to a download link (`ui_download_nn`) "then import it". A
page that cannot be read says why: not readable by a browser, not
found (404), needs a sign-in (401, 403), or not a catalogue.
