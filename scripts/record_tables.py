# The groups of the stored records: tag, whether the record needs it, its fields
# (name, "i" a 32-bit number or "s" a string of up to 255 bytes). The tags are in
# ascending order, which is the order they are written in.
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
  ("prog", "opt", [("progress_weighted", "i")]),
  # a series position kept in hundredths (quire#434): 0 none, else the hundredths plus 10000001; with no such
  # chunk the position is the whole number of SERI, which an older Quire reads and writes
  ("snum", "opt", [("series_position", "i")]),
  # the direction of the title and of the author as the package gives them (quire#419): two codes in one number
  ("tdir", "opt", [("text_directions", "i")]),
]
BOOK_KIND = 1
INDEX_GROUPS = [
  ("LEGA", "opt", [("legacy_size", "i"), ("legacy_sum", "i")]),
  ("NAMS", "req", [("name_count", "i")] + [(f"name{k}", "s") for k in range(8)]),
]
INDEX_KIND = 2

def tables(name):
    if name == "book":
        return BOOK_GROUPS, BOOK_KIND
    return INDEX_GROUPS, INDEX_KIND
