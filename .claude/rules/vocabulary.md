---
paths:
  - src/word*.bats
  - src/annot.bats
  - e2e/vocabulary.spec.js
  - scripts/record_tables.py
---

# Vocabulary: the words looked up (quire#565)

Keyword: vocabulary. Every dictionary lookup that found the word and every Look up online is kept, with the sentence it
was in, and reviewed on KOReader's schedule. A switch in Settings beside Dictionaries (`settings-words-keep`, "Keep the
words I look up", on by default) turns keeping off; it is in the backup as `wordsKept`.

## Research (what comparable software does, and what was taken)

* Kindle's Vocabulary Builder keeps every word looked up, with the book and the sentence, lists newest first, filters
  Learning / Mastered, and reviews with flashcards (definition hidden until tapped). Taken: all of it.
* KOReader's Vocabulary builder (`plugins/vocabbuilder.koplugin`) keeps word, book, context (prefix and suffix around the
  word), create time, review time, due time and a streak; Got it adds one to the streak and the due time is 30 minutes,
  12 hours, 1, 2, 4, 7, 15 days, then 30 days times 2 to the (streak - 8), the exponent capped at 6; Forgot sets the streak
  to 0 and due in 5 minutes. Taken: the schedule exactly (`words_got_it_minutes` in `src/words_rules.bats`).
* Kobo's My Words (a beta feature since firmware 4.26, February 2021) keeps the words looked up, listed under More > Activity
  ([the-ebook-reader](https://blog.the-ebook-reader.com/2021/02/17/kobo-firmware-update-4-26-released-adds-new-my-words-feature/)).
  Apple Books, Play Books, Moon+ Reader and Thorium: no such list was found (quire#565 searched their help pages and
  MobileRead); this note makes no claim about them. Anki's lesson, from its card design, is that the card is the sentence with
  the word marked, the definition behind a reveal. Taken: sentence with the word marked (`.mk`), the definition shown only on
  request.
* No definition is stored: it is read again from the dictionary the reader has now, so a dictionary removed or added
  changes what the card shows and nothing stale is kept (and a licensed dictionary's text is not copied into the list).

## What a word is

One record per word under `words/<14 hex>`, the hex being the SHA-256 of the lowercased word, a colon and the language, so a
word looked up again (by word and language) is the same entry on every device. It is the record kind `word` of the codec
(`WORD_GROUPS` in `scripts/record_tables.py`, generated `src/wordrec.bats` and `src/wordimage.bats`; the groups follow the
`added` rules of #515, tested by `tests/static/groups.py` and its reject fixtures). A word holds the word as looked up, the
language, the book's id, the place (chapter, content node, UTF-16 offset), the sentence, the minute first and last looked
up, the count, and the state `Learning(streak, due)` or `Mastered`.

Bounds, each said when reached and none silent: a word at most 64 bytes; a sentence at most 510 bytes, cut at a character
(held as a head and a tail of two strings); at most 10000 words kept, tombstones among them (a lookup past it is not kept
and the reader is told, `WordsFull`, remedy `DeleteSomeWords`); the Words screen draws the newest 500 and says how many it
does not show; a failed write is said (`WordsNotStored`).

The sentence is `segment_sentences`' cut (`Intl.Segmenter` through bridge) around the selection (`annot_selection_place`,
`src/annot.bats`), the same cut read aloud uses.

## Edits are atomic

Lookup (`NoteLookup`), review, mastering, learning again and deleting are each one `idb_update` of the word's record
(`wordstore_edit`, `src/wordstore.bats`), so two edits cannot overwrite each other. A record is patched with
`word_record_patch`, so chunks a newer Quire wrote survive an older one's edit.

## Sync and backup

A deletion is a tombstone (`deleted` minutes, no strings), dropped after 180 days at start (`words_start`). The backup has a
`words` part (live words only); a restore from a file merges by the latest `modified` stamp, and a restore that replaces
(the Undo snapshot) puts back exactly the words it had. The sync file has `words` after the books: each device merges by
the latest change of each word (`words_sync_chunk`, `_words_take`). Every stamp read from a file is passed to `stamp_seen`
(`src/wordsjson.bats`), so a change made here after a sync is later than what was read; without it a deletion made on a
device whose clock is behind lost to the other device's older mastering (shown by `e2e/vocabulary.spec.js`, the sync test,
which failed with `deleted` 0 before `stamp_seen` was called and passes after). The privacy policy states all of this
(`homepage/privacy.html`).

## Screens

Words and Review are pushed screens with a top bar (`LWords`, `LReview` in `src/layer.bats`), opened from the library menu
(Words) and from the Words screen (Review). Each row is a labelled group: the word (opens the dictionary panel: the article
if a dictionary has it, else "No dictionary you added has this word" with Look up online), the sentence with the word marked,
the book's title, the count and state; Go to (opens the book at the place after the book is open, `_pending_jump` in
`src/bin/quire.bats`), Mark as mastered / Learn again, Delete (Undo offer `WordDeleted`). Share as CSV (`word,sentence,book,
language`, quoted, `quire-words.csv`) goes through `share_file`. `e2e/walk.js` walks both screens (layout, safe area, Back).

## What is proved and what is tested

Proved by types: the record codec's groups and CRC (the codec is the proof-carrying one of `src/record.bats`), array bounds
of every buffer here, each match is `case+`. Tested only: the schedule's numbers (`e2e/vocabulary.spec.js`, by a fake
clock), the JSON round trips (`tests/codec` for the record; the backup and sync specs for the JSON), the sentence cut (a case of its own in `e2e/vocabulary.spec.js`).
`mutation/wordrec` (`tests/groups.json`, `mutation-bytes-records`) mutates the generated module's lemmas in CI.
