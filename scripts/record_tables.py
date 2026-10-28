# The groups of the stored records: tag, whether the record needs it, its fields
# (name, "i" a 32-bit number or "s" a string of up to 255 bytes). The tags are in
# ascending order, which is the order they are written in.
#
# A group is one of three, "req", "opt" or "added" (quire#497, quire#510: nothing makes a record unusable but what
# is not a record at all, so req and opt differ in what they say, not in whether the record is used):
#   req    the record needs it: one without it, or with it damaged, is read with the group's substitutes
#          (SUBSTITUTES below), and the group is lost (said, and the bytes kept when the record is repaired);
#   opt    every version of the format has written it: as req, a record without it or with it damaged is
#          read with the group's defaults and the group is lost;
#   added  a group added to the format after records were written: one without it was written before
#          the group existed, which is no loss and no damage (it reads with the group's defaults, as an
#          absent PNG ancillary chunk, a protobuf field or an SQLite column added with a default does),
#          and one with it damaged is lost as an "opt" one is. Every group added from now on is "added"
#          (quire#515: tests/static/groups.py), and is named in RELEASES with a library of the table before it.
# What stands in for a group that is lost or missing (quire#510): the defaults of its fields are 0 and the empty
# string, except for the fields named here. A record is used whatever it lost, so even a group the record needs has
# a substitute: a book whose title is lost is shown as "Untitled" (the word the contents panel uses for a label with
# none) and its ids are the record's own key's (libstore); the title and author can be read again from the book's
# file when it is next opened.
SUBSTITUTES = {"title": "Untitled"}
BOOK_GROUPS = [
  ("AUTH", "req", [("author", "s")]),
  ("BOOK", "req", [("id_high", "i"), ("id_low", "i")]),
  ("COLL", "opt", [("collections", "i"), ("collections_modified", "i")]),
  ("ELSE", "opt", [("minutes_elsewhere", "i"), ("pages_elsewhere", "i")]),
  ("FNSH", "opt", [("finished_at", "i"), ("finished_modified", "i")]),
  ("ORDR", "opt", [("position", "i")]),
  ("PLCE", "opt", [("chapter", "i"), ("chapters", "i"), ("page", "i"), ("pages", "i"), ("anchor", "i"), ("place_modified", "i"), ("place_declined", "i")]),
  ("SERI", "opt", [("series", "s"), ("series_number", "i")]),
  ("SHLF", "opt", [("shelf", "i"), ("added", "i"), ("opened", "i"), ("shelf_modified", "i")]),
  ("SIZE", "opt", [("file_size", "i"), ("cover", "i"), ("done", "i")]),
  ("TIME", "opt", [("minutes_read", "i"), ("pages_read", "i")]),
  ("TITL", "req", [("title", "s")]),
  # lower case first letter: ancillary, so a Quire that does not know it keeps it and still reads the record
  ("prog", "added", [("progress_weighted", "i")]),
  # a series position kept in hundredths (quire#434): 0 none, else the hundredths plus 10000001; with no such
  # chunk the position is the whole number of SERI, which an older Quire reads and writes
  ("snum", "added", [("series_position", "i")]),
  # the direction of the title and of the author as the package gives them (quire#419): two codes in one number
  ("tdir", "added", [("text_directions", "i")]),
]
BOOK_KIND = 1
# The "added" groups in the order they were added, each with the commit that added it (quire#515). Every
# table that ever shipped is a prefix of this list on top of the first table's groups (the req and opt ones),
# and e2e/old-library.spec.js opens a library of each: tests/static/groups.py fails a group that is not
# here, one added as "req" or "opt", and a table with no such library.
RELEASES = [("prog", "bb473e5"), ("tdir", "04dcf63"), ("snum", "6002bcf")]
INDEX_GROUPS = [
  ("LEGA", "opt", [("legacy_size", "i"), ("legacy_sum", "i")]),
  ("NAMS", "req", [("name_count", "i")] + [(f"name{k}", "s") for k in range(8)]),
]
INDEX_KIND = 2
# A word looked up (quire#565): one record for each word and language, "words/<14 hex digits>". Its tags are in
# ascending order. A new kind starts its own first table (its groups are req and opt, as the book's and the
# index's first tables are); a group added to it later is "added" and named in RELEASES (tests/static/groups.py).
#   BOOK  the book it was looked up in
#   COUN  how many times it was looked up, and the minutes of the first and of the latest lookup
#   LANG  the language of the book it was looked up in
#   MODF  when it last changed (sync's stamp), and when it was deleted (0: it is not): a deleted word keeps
#         only its key and these, which is its tombstone
#   PLCE  the place of its latest lookup: chapter, content node and UTF-16 offset
#   SENT  the sentence it was in, in two strings (the head, then the tail)
#   STAT  whether it is mastered, the streak of reviews it was known in a row and the minute it is due
#   WORD  the word as looked up
WORD_GROUPS = [
  ("BOOK", "req", [("book_high", "i"), ("book_low", "i")]),
  ("COUN", "opt", [("lookups", "i"), ("first_minute", "i"), ("last_minute", "i")]),
  ("LANG", "req", [("language", "s")]),
  ("MODF", "opt", [("modified", "i"), ("deleted", "i")]),
  ("PLCE", "opt", [("chapter", "i"), ("node", "i"), ("offset", "i")]),
  ("SENT", "opt", [("sentence_head", "s"), ("sentence_tail", "s")]),
  ("STAT", "opt", [("mastered", "i"), ("streak", "i"), ("due", "i")]),
  ("WORD", "req", [("word", "s")]),
]
WORD_KIND = 3

def tables(name):
    if name == "book":
        return BOOK_GROUPS, BOOK_KIND
    if name == "word":
        return WORD_GROUPS, WORD_KIND
    return INDEX_GROUPS, INDEX_KIND


# The area keyword each generated module's comments name (the notes in .claude/rules/)
AREAS = {"book": "library-records", "index": "library-records", "word": "vocabulary"}


def one_line_comments(text, name):
    """Every comment of a generated module is one line and names its area by keyword (CLAUDE.md)."""
    import re
    def one(match):
        return "(* " + " ".join(match.group(1).split()) + " (keyword: " + AREAS[name] + ") *)"
    return re.sub(r"\(\*(.*?)\*\)", one, text, flags=re.S)
