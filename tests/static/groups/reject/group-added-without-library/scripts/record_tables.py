# The groups of the stored records: tag, whether the record needs it, its fields
# (name, "i" a 32-bit number or "s" a string of up to 255 bytes). The tags are in
# ascending order, which is the order they are written in.
#
# A group is one of three, "req", "opt" or "added" (quire#497):
#   req    the record needs it: one without it, or with it damaged, is damaged;
#   opt    every version of the format has written it: one without it is damaged, one with it
#          damaged is read with the group's defaults (lost, and its bytes kept when the record is repaired);
#   added  a group added to the format after records were written: one without it was written before
#          the group existed, which is no loss and no damage (it reads with the group's defaults, as an
#          absent PNG ancillary chunk, a protobuf field or an SQLite column added with a default does),
#          and one with it damaged is lost as an "opt" one is. Every group added from now on is "added"
#          (quire#515: tests/static/groups.py), and is named in RELEASES with a library of the table before it.
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
  ("zone", "added", [("zone_number", "i")]),
]
BOOK_KIND = 1
# The "added" groups in the order they were added, each with the commit that added it (quire#515). Every
# table that ever shipped is a prefix of this list on top of the first table's groups (the req and opt ones),
# and e2e/old-library.spec.js opens a library of each: tests/static/groups.py fails a group that is not
# here, one added as "req" or "opt", and a table with no such library.
RELEASES = [("prog", "bb473e5"), ("tdir", "04dcf63"), ("snum", "6002bcf"), ("zone", "1234567")]
INDEX_GROUPS = [
  ("LEGA", "opt", [("legacy_size", "i"), ("legacy_sum", "i")]),
  ("NAMS", "req", [("name_count", "i")] + [(f"name{k}", "s") for k in range(8)]),
]
INDEX_KIND = 2

def tables(name):
    if name == "book":
        return BOOK_GROUPS, BOOK_KIND
    return INDEX_GROUPS, INDEX_KIND
