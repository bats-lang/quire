(* opds -- a page of an OPDS catalogue, read: OPDS 1.2 (an Atom feed,
   XML) or OPDS 2 (JSON), into the same entries: links to other pages
   of the catalogue, and books (a title, an author, a cover and the
   EPUB to get), with the page's links to its next and previous pages
   and its search *)

(* What is read of a page is a feed: its title, its entries (at most
   ENTRIES_MOST, in its order), and the addresses of its next and
   previous pages, its search template (an address with {searchTerms},
   or OPDS 2's {?query}) and its OpenSearch description (a document
   that holds the template). Every address is resolved against the
   page's own, and every text is kept as decoded text (an Atom
   document's references decoded, a JSON string's escapes), so nothing
   of the page itself is kept: it is read from a piece and let go.

   A book's EPUB is its acquisition link (rel
   http://opds-spec.org/acquisition...) of type application/epub+zip,
   an EPUB 3 one first (its address or type says epub3 or version=3);
   its cover is its thumbnail, else its image. An entry with no
   acquisition link but a link to another page (an Atom or OPDS 2
   type) is a link. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use xml-tree as X

staload "jsonio.sats"
staload "epub_xml.sats"
staload "entity.sats"
staload "url.sats"

(* ============================================================
   Kept text
   ============================================================ *)

(* The longest text kept is 4096 bytes *)


(* Bytes kept from a page: text[0, text_len) (empty: none) *)
#pub datavtype kept =
  | {l:agz}{n:pos}{text_len:nat | text_len <= n; text_len <= 4096} Kept of ($A.arr(byte, l, n), int text_len)

#pub fn kept_none (): kept
implement kept_none () = Kept($A.alloc<byte>(1), 0)

#pub fn kept_free (text: kept): void
implement kept_free (text) = let val+ ~Kept(bytes, _) = text in $A.free<byte>(bytes) end

#pub fn kept_len (text: !kept): [text_len:nat | text_len <= 4096] int text_len
implement kept_len (text) = let
  val+ @Kept(_, text_len) = text
  val length = text_len
  prval () = fold@(text)
in length end

fun _copy {source_loc,target_loc:agz}{source_size,target_size:nat}
  {source_at,count:nat | source_at + count <= source_size}{target_at:nat | target_at + count <= target_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), source_at: int source_at,
   target: !$A.arr(byte, target_loc, target_size), target_at: int target_at, count: int count, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(target, target_at + i, $A.get<byte>(source, source_at + i))
  in _copy(source, source_at, target, target_at, count, i + 1) end

(* A copy of text: its bytes (one more than its length) and its length *)
#pub fn kept_copy (text: !kept): [l:agz][text_len:nat | text_len <= 4096] @($A.arr(byte, l, text_len + 1), int text_len)
implement kept_copy (text) = let
  val+ @Kept(bytes, text_len) = text
  val copy = $A.alloc<byte>(text_len + 1)
  val () = _copy(bytes, 0, copy, 0, text_len, 0)
  val length = text_len
  prval () = fold@(text)
in @(copy, length) end

(* bytes[0, text_len), kept *)
#pub fn kept_of {l:agz}{n:pos}{text_len:nat | text_len <= n} (bytes: !$A.arr(byte, l, n), text_len: int text_len): kept
implement kept_of (bytes, text_len) =
  if text_len > 4096 then kept_none()
  else let
    val copy = $A.alloc<byte>(text_len + 1)
    val () = _copy(bytes, 0, copy, 0, text_len, 0)
  in Kept(copy, text_len) end

fn _lower (code: int): int = if code >= 65 && code <= 90 then code + 32 else code

fn _byte_at {l:agz}{n:nat}{i:nat | i < n} (bytes: !$A.arr(byte, l, n), i: int i): [value:nat | value < 256] int value =
  $AR.low_byte(byte2int0($A.get<byte>(bytes, i)))

(* Whether bytes[at, at + text_len) is text, letters in any case *)
fun _matches {l:agz}{n:nat}{text_len:nat}{at:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (bytes: !$A.arr(byte, l, n), at: int at, text: string text_len, text_len: int text_len, i: int i): bool =
  if i >= text_len then true
  else if _lower(_byte_at(bytes, at + i)) <> char2int0(string_get_at(text, i)) then false
  else _matches(bytes, at, text, text_len, i + 1)

fun _has_from {l:agz}{n:nat}{length:nat | length <= n}{text_len:nat}{at:nat | at <= length} .<length - at>.
  (bytes: !$A.arr(byte, l, n), length: int length, text: string text_len, text_len: int text_len, at: int at): bool =
  if at + text_len > length then false
  else if _matches(bytes, at, text, text_len, 0) then true
  else if at >= length then false
  else _has_from(bytes, length, text, text_len, at + 1)

(* Whether text has, starts with or is the lower case literal pattern *)
fn _kept_has {pattern_len:nat} (text: !kept, pattern: string pattern_len): bool = let
  val+ @Kept(bytes, text_len) = text
  val found = _has_from(bytes, text_len, pattern, g1u2i(string1_length(pattern)), 0)
  prval () = fold@(text)
in found end

fn _kept_starts {pattern_len:nat} (text: !kept, pattern: string pattern_len): bool = let
  val+ @Kept(bytes, text_len) = text
  val pattern_len = g1u2i(string1_length(pattern))
  val found = (if pattern_len <= text_len then _matches(bytes, 0, pattern, pattern_len, 0) else false): bool
  prval () = fold@(text)
in found end

fn _kept_is {pattern_len:nat} (text: !kept, pattern: string pattern_len): bool = let
  val+ @Kept(bytes, text_len) = text
  val pattern_len = g1u2i(string1_length(pattern))
  val found = (if pattern_len = text_len then _matches(bytes, 0, pattern, pattern_len, 0) else false): bool
  prval () = fold@(text)
in found end

#pub fn kept_dup (text: !kept): kept
implement kept_dup (text) = let
  val+ @Kept(bytes, text_len) = text
  val copy = kept_of(bytes, text_len)
  prval () = fold@(text)
in copy end

(* slot, or value when slot is empty (the other one freed) *)
fn _first (slot: kept, value: kept): kept =
  if kept_len(slot) > 0 then let val () = kept_free(value) in slot end
  else let val () = kept_free(slot) in value end

(* raw, an address read from the page, resolved against base, the
   page's own *)
#pub fn opds_resolve (base: !kept, raw: !kept): kept
implement opds_resolve (base, raw) = let
  val+ @Kept(base_bytes, base_len) = base
  val+ @Kept(raw_bytes, raw_len) = raw
  val resolved = (if raw_len <= 0 then kept_none()
    else if base_len > 2048 then kept_none()
    else if raw_len > 2048 then kept_none()
    else let
      val+ ~Resolved(bytes, resolved_len) = url_resolve(base_bytes, base_len, raw_bytes, raw_len)
    in Kept(bytes, resolved_len) end): kept
  prval () = fold@(raw)
  prval () = fold@(base)
in resolved end

fn _resolve_free (base: !kept, raw: kept): kept = let
  val resolved = opds_resolve(base, raw)
  val () = kept_free(raw)
in resolved end

(* ============================================================
   What a page holds
   ============================================================ *)

#pub stadef ENTRIES_MOST = 500

(* A page's entries: a link (its title and address) or a book (its
   title, author, cover's address and EPUB's address; the cover and
   EPUB empty when it has none) *)
#pub datavtype entries(int) =
  | EntriesNil(0) of ()
  | {count:nat} EntryLink(count + 1) of (kept, kept, entries(count))
  | {count:nat} EntryBook(count + 1) of (kept, kept, kept, kept, entries(count))

fun _entries_free {count:nat} .<count>. (list: entries(count)): void =
  case+ list of
  | ~EntriesNil() => ()
  | ~EntryLink(title, address, rest) => let
      val () = kept_free(title)
      val () = kept_free(address)
    in _entries_free(rest) end
  | ~EntryBook(title, author, cover, epub, rest) => let
      val () = kept_free(title)
      val () = kept_free(author)
      val () = kept_free(cover)
      val () = kept_free(epub)
    in _entries_free(rest) end

fun _reverse {count,done:nat} .<count>. (list: entries(count), reversed: entries(done)): entries(count + done) =
  case+ list of
  | ~EntriesNil() => reversed
  | ~EntryLink(title, address, rest) => _reverse(rest, EntryLink(title, address, reversed))
  | ~EntryBook(title, author, cover, epub, rest) => _reverse(rest, EntryBook(title, author, cover, epub, reversed))

(* A page: its title, entries and how many, and the addresses of its
   next page, previous page, search template and search description *)
#pub datavtype feed =
  | {count:nat | count <= ENTRIES_MOST} Feed of (kept, entries(count), int count, kept, kept, kept, kept)

#pub fn feed_free (page: feed): void
implement feed_free (page) = let
  val+ ~Feed(title, list, _, next, previous, template, description) = page
  val () = kept_free(title)
  val () = _entries_free(list)
  val () = kept_free(next)
  val () = kept_free(previous)
  val () = kept_free(template)
in kept_free(description) end

fn _feed_empty (): feed = Feed(kept_none(), EntriesNil(), 0, kept_none(), kept_none(), kept_none(), kept_none())

(* One entry read, or none *)
datavtype one_entry =
  | OneLink of (kept, kept)
  | OneBook of (kept, kept, kept, kept)
  | NoEntry of ()

(* page with entry added (past ENTRIES_MOST, dropped); its entries
   are in reverse order until the page is read *)
fn _feed_add (page: feed, entry: one_entry): feed = let
  val+ ~Feed(title, list, count, next, previous, template, description) = page
in
  case+ entry of
  | ~NoEntry() => Feed(title, list, count, next, previous, template, description)
  | ~OneLink(link_title, address) =>
    if count < 500 then Feed(title, EntryLink(link_title, address, list), count + 1, next, previous, template, description)
    else let
      val () = kept_free(link_title)
      val () = kept_free(address)
    in Feed(title, list, count, next, previous, template, description) end
  | ~OneBook(book_title, author, cover, epub) =>
    if count < 500 then Feed(title, EntryBook(book_title, author, cover, epub, list), count + 1, next, previous, template, description)
    else let
      val () = kept_free(book_title)
      val () = kept_free(author)
      val () = kept_free(cover)
      val () = kept_free(epub)
    in Feed(title, list, count, next, previous, template, description) end
end

fn _feed_title (page: feed, text: kept): feed = let
  val+ ~Feed(title, list, count, next, previous, template, description) = page
in Feed(_first(title, text), list, count, next, previous, template, description) end

(* ============================================================
   Links: what a page's or an entry's links give
   ============================================================ *)

(* A link: its rel, address (as written), type and title *)
datavtype link = Link of (kept, kept, kept, kept)

(* What links gave, in five slots and a flag. A page's: its next and
   previous pages, search template and search description. An
   entry's: its EPUB 3, any EPUB, thumbnail, image and another page;
   and whether it had an acquisition link *)
datavtype picks = Picks of (kept, kept, kept, kept, kept, bool)

fn _picks_empty (): picks = Picks(kept_none(), kept_none(), kept_none(), kept_none(), kept_none(), false)

fn _picks_free (found: picks): void = let
  val+ ~Picks(first, second, third, fourth, fifth, _) = found
  val () = kept_free(first)
  val () = kept_free(second)
  val () = kept_free(third)
  val () = kept_free(fourth)
in kept_free(fifth) end

(* Which list of links is read: a page's, an entry's, or an OPDS 2
   entry's images *)
datatype link_list = PageLinks | EntryLinks | ImageLinks

fn _is_acquisition (rel: !kept): bool = _kept_starts(rel, "http://opds-spec.org/acquisition")

(* found, with what the link given gives in a list of links of kind *)
fn _pick (kind: link_list, found: picks, given: link): picks = let
  val+ ~Picks(first, second, third, fourth, fifth, acquired) = found
  val+ ~Link(rel, address, kind_of, link_title) = given
  val () = kept_free(link_title)
in
  case+ kind of
  | PageLinks() => let
    val is_next = _kept_is(rel, "next")
    val is_previous = (if _kept_is(rel, "previous") then true else _kept_is(rel, "prev")): bool
    val is_search = _kept_is(rel, "search")
    val is_template = (if is_search then (if _kept_has(address, "{searchterms}") then true else _kept_has(address, "{?query}")) else false): bool
    val is_description = (if is_search then _kept_has(kind_of, "opensearchdescription") else false): bool
    val () = kept_free(rel)
    val () = kept_free(kind_of)
  in
    if is_next then Picks(_first(first, address), second, third, fourth, fifth, acquired)
    else if is_previous then Picks(first, _first(second, address), third, fourth, fifth, acquired)
    else if is_template then Picks(first, second, _first(third, address), fourth, fifth, acquired)
    else if is_description then Picks(first, second, third, _first(fourth, address), fifth, acquired)
    else let val () = kept_free(address) in Picks(first, second, third, fourth, fifth, acquired) end
  end
  | ImageLinks() => let
    val () = kept_free(rel)
    val () = kept_free(kind_of)
  in Picks(first, second, _first(third, address), fourth, fifth, acquired) end
  | EntryLinks() => let
    val acquisition = _is_acquisition(rel)
    val epub = (if acquisition then _kept_starts(kind_of, "application/epub+zip") else false): bool
    val epub3 = (if epub then (if _kept_has(address, "epub3") then true else _kept_has(kind_of, "version=3")) else false): bool
    val thumbnail = (if _kept_is(rel, "http://opds-spec.org/image/thumbnail") then true
      else _kept_is(rel, "x-stanza-cover-image-thumbnail")): bool
    val image = (if _kept_is(rel, "http://opds-spec.org/image") then true
      else if _kept_is(rel, "http://opds-spec.org/cover") then true
      else _kept_is(rel, "x-stanza-cover-image")): bool
    val other_page = (if acquisition then false
      else if _kept_has(kind_of, "atom+xml") then true
      else _kept_has(kind_of, "opds+json")): bool
    val () = kept_free(rel)
    val () = kept_free(kind_of)
    val acquired = (if acquisition then true else acquired): bool
  in
    if epub3 then let
      val address_copy = kept_dup(address)
    in Picks(_first(first, address_copy), _first(second, address), third, fourth, fifth, acquired) end
    else if epub then Picks(first, _first(second, address), third, fourth, fifth, acquired)
    else if thumbnail then Picks(first, second, _first(third, address), fourth, fifth, acquired)
    else if image then Picks(first, second, third, _first(fourth, address), fifth, acquired)
    else if other_page then Picks(first, second, third, fourth, _first(fifth, address), acquired)
    else let val () = kept_free(address) in Picks(first, second, third, fourth, fifth, acquired) end
  end
end

(* The entry a title, an author and an entry's links make, its
   addresses resolved against base *)
fn _entry_of (base: !kept, title: kept, author: kept, found: picks): one_entry = let
  val+ ~Picks(epub3, epub, thumbnail, image, other_page, acquired) = found
  val epub = _first(epub3, epub)
  val cover = _first(thumbnail, image)
in
  if (if kept_len(epub) > 0 then true else acquired) then let
    val () = kept_free(other_page)
  in OneBook(title, author, _resolve_free(base, cover), _resolve_free(base, epub)) end
  else let
    val () = kept_free(epub)
    val () = kept_free(cover)
    val () = kept_free(author)
  in
    if kept_len(other_page) > 0 then OneLink(title, _resolve_free(base, other_page))
    else let
      val () = kept_free(title)
      val () = kept_free(other_page)
    in NoEntry() end
  end
end

(* page's next, previous, template and description from found *)
fn _feed_links (base: !kept, page: feed, found: picks): feed = let
  val+ ~Feed(title, list, count, next, previous, template, description) = page
  val+ ~Picks(found_next, found_previous, found_template, found_description, unused, _) = found
  val () = kept_free(unused)
in
  Feed(title, list, count,
    _first(next, _resolve_free(base, found_next)), _first(previous, _resolve_free(base, found_previous)),
    _first(template, _resolve_free(base, found_template)), _first(description, _resolve_free(base, found_description)))
end

(* ============================================================
   OPDS 1.2: an Atom feed
   ============================================================ *)

fn _read_at {l:agz}{n:pos}{i:nat | i < n} (data: !$A.borrow(byte, l, n), i: int i): [value:nat | value < 256] int value =
  $AR.low_byte(byte2int0($A.read<byte>(data, i)))

(* Just past the last ':' in data[offset + i, offset + name_len), or found *)
fun _local_start {l:agz}{n:pos}{offset,name_len:nat | offset + name_len <= n}{i:nat | i <= name_len}{found:nat | found <= i} .<name_len - i>.
  (data: !$A.borrow(byte, l, n), offset: int offset, name_len: int name_len, i: int i, found: int found)
  : [start:nat | found <= start; start <= name_len] int start =
  if i >= name_len then found
  else if _read_at(data, offset + i) = 58 then _local_start(data, offset, name_len, i + 1, i + 1)
  else _local_start(data, offset, name_len, i + 1, found)

fun _same {l:agz}{n:pos}{at:nat}{text_len:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (data: !$A.borrow(byte, l, n), at: int at, text: string text_len, text_len: int text_len, i: int i): bool =
  if i >= text_len then true
  else if _read_at(data, at + i) <> char2int0(string_get_at(text, i)) then false
  else _same(data, at, text, text_len, i + 1)

(* Whether the name data[offset, offset + name_len), its prefix aside, is wanted *)
fn _local_is {l:agz}{n:pos}{offset,name_len:nat | offset + name_len <= n}{local_len:nat}
  (data: !$A.borrow(byte, l, n), offset: int offset, name_len: int name_len, wanted: string local_len): bool = let
  val start = _local_start(data, offset, name_len, 0, 0)
  val local_len = g1u2i(string1_length(wanted))
in
  if name_len - start <> local_len then false
  else _same(data, offset + start, wanted, local_len, 0)
end

(* The value of the attribute whose name, its prefix aside, is wanted *)
fun _attribute {l:agz}{n:pos}{count:nat}{local_len:nat} .<count>.
  (data: !$A.borrow(byte, l, n), attributes: !$X.xml_attr_list(n, count), wanted: string local_len): xspan(n) =
  case+ attributes of
  | $X.xml_attrs_cons(name_offset, name_len, value_offset, value_len, rest) =>
    if _local_is(data, name_offset, name_len, wanted) then xspan_at(value_offset, value_len)
    else _attribute(data, rest, wanted)
  | $X.xml_attrs_nil() => xspan_none()

fn _is_space (code: int): bool = code = 32 || code = 9 || code = 10 || code = 13

fun _trim_start {l:agz}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop} .<stop - at>.
  (bytes: !$A.arr(byte, l, n), at: int at, stop: int stop): [start:nat | at <= start; start <= stop] int start =
  if at >= stop then stop
  else if _is_space(_byte_at(bytes, at)) then _trim_start(bytes, at + 1, stop)
  else at

fun _trim_end {l:agz}{n:nat}{start:nat}{stop:nat | start <= stop; stop <= n} .<stop - start>.
  (bytes: !$A.arr(byte, l, n), start: int start, stop: int stop): [end_at:nat | start <= end_at; end_at <= stop] int end_at =
  if stop <= start then start
  else if _is_space(_byte_at(bytes, stop - 1)) then _trim_end(bytes, start, stop - 1)
  else stop

fn _at_most {value,most:nat} (value: int value, most: int most): [least:nat | least <= value; least <= most] int least =
  if value > most then most else value

(* The text of span (at most most bytes of it), its references decoded
   and its ends trimmed *)
fn _span_text {l:agz}{n:pos}{most:pos | most <= 4096} (data: !$A.borrow(byte, l, n), span: xspan(n), most: int most): kept =
  case+ span of
  | ~xspan_none() => kept_none()
  | ~xspan_at(offset, span_len) => let
      val take = _at_most(span_len, most)
      val decoded = $A.alloc<byte>(take + 1)
      val decoded_len = decode_text(data, offset, take, decoded)
      val start = _trim_start(decoded, 0, decoded_len)
      val stop = _trim_end(decoded, start, decoded_len)
      val text_len = stop - start
      val text = $A.alloc<byte>(text_len + 1)
      val () = _copy(decoded, start, text, 0, text_len, 0)
      val () = $A.free<byte>(decoded)
    in Kept(text, text_len) end

(* The first text of nodes *)
fun _first_text {n:int}{size:nat} .<size>. (nodes: !$X.xml_node_list(n, size)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_text(text_offset, text_len) => xspan_at(text_offset, text_len)
     | $X.xml_element(_, _, _, _) => _first_text(rest))
  | $X.xml_nodes_nil() => xspan_none()

(* The first text of the first element of nodes named wanted *)
fun _child_text {l:agz}{n:pos}{size:nat}{local_len:nat} .<size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), wanted: string local_len): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_element(name_offset, name_len, _, children) =>
       if _local_is(data, name_offset, name_len, wanted) then _first_text(children)
       else _child_text(data, rest, wanted)
     | $X.xml_text(_, _) => _child_text(data, rest, wanted))
  | $X.xml_nodes_nil() => xspan_none()

(* The name of the first author of nodes *)
fun _author_name {l:agz}{n:pos}{size:nat} .<size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size)): xspan(n) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_element(name_offset, name_len, _, children) =>
       if _local_is(data, name_offset, name_len, "author") then _child_text(data, children, "name")
       else _author_name(data, rest)
     | $X.xml_text(_, _) => _author_name(data, rest))
  | $X.xml_nodes_nil() => xspan_none()

(* An Atom link: its attributes *)
fn _atom_link {l:agz}{n:pos}{count:nat} (data: !$A.borrow(byte, l, n), attributes: !$X.xml_attr_list(n, count)): link =
  Link(_span_text(data, _attribute(data, attributes, "rel"), 256), _span_text(data, _attribute(data, attributes, "href"), 2048),
    _span_text(data, _attribute(data, attributes, "type"), 256), kept_none())

(* found, with the links among nodes, of kind *)
fun _atom_links {l:agz}{n:pos}{size:nat} .<size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), kind: link_list, found: picks): picks =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_element(name_offset, name_len, attributes, _) =>
       if _local_is(data, name_offset, name_len, "link") then _atom_links(data, rest, kind, _pick(kind, found, _atom_link(data, attributes)))
       else _atom_links(data, rest, kind, found)
     | $X.xml_text(_, _) => _atom_links(data, rest, kind, found))
  | $X.xml_nodes_nil() => found

(* An Atom entry, from its children *)
fn _atom_entry {l:agz}{n:pos}{size:nat} (data: !$A.borrow(byte, l, n), children: !$X.xml_node_list(n, size), base: !kept): one_entry = let
  val title = _span_text(data, _child_text(data, children, "title"), 512)
  val author = _span_text(data, _author_name(data, children), 256)
  val found = _atom_links(data, children, EntryLinks(), _picks_empty())
in _entry_of(base, title, author, found) end

(* A feed's children: its title, links and entries *)
fun _atom_children {l:agz}{n:pos}{size:nat} .<size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), base: !kept, page: feed, found: picks): @(feed, picks) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_element(name_offset, name_len, attributes, children) =>
       if _local_is(data, name_offset, name_len, "entry") then
         _atom_children(data, rest, base, _feed_add(page, _atom_entry(data, children, base)), found)
       else if _local_is(data, name_offset, name_len, "link") then
         _atom_children(data, rest, base, page, _pick(PageLinks(), found, _atom_link(data, attributes)))
       else if _local_is(data, name_offset, name_len, "title") then
         _atom_children(data, rest, base, _feed_title(page, _span_text(data, _first_text(children), 512)), found)
       else _atom_children(data, rest, base, page, found)
     | $X.xml_text(_, _) => _atom_children(data, rest, base, page, found))
  | $X.xml_nodes_nil() => @(page, found)

(* The document's feed, read; whether it has one *)
fun _atom_root {l:agz}{n:pos}{size:nat} .<size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), base: !kept): @(feed, bool) =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_element(name_offset, name_len, _, children) =>
       if _local_is(data, name_offset, name_len, "feed") then let
         val @(page, found) = _atom_children(data, children, base, _feed_empty(), _picks_empty())
       in @(_feed_links(base, page, found), true) end
       else _atom_root(data, rest, base)
     | $X.xml_text(_, _) => _atom_root(data, rest, base))
  | $X.xml_nodes_nil() => @(_feed_empty(), false)

(* ============================================================
   OPDS 2: JSON
   ============================================================ *)

(* The string at position (at most most bytes of it), or none *)
fn _json_text {l:agz}{owner:addr}{n:nat}{position:nat | position < n}{most:pos | most <= 4096}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, most: int most): kept =
  if jr_is(buf, n, position, 34) then let
    val out = $A.alloc<byte>(most)
    val @(found, text_len, _) = jr_str(buf, n, position, out, most)
  in if found then Kept(out, text_len) else Kept(out, 0) end
  else kept_none()

(* Where the value of the member named name of the object whose members
   start at position is; -1 when it has none *)
fun _member {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n}{name_len:nat} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), name: string name_len)
  : [found:int | ~1 <= found; found < n] int found = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then ~1
  else if jr_is(buf, n, next, 125) then ~1
  else if jr_is(buf, n, next, 44) then _member(buf, n, next + 1, key, name)
  else let
    val @(found, key_len, value_start) = jr_key(buf, n, next, key, 32)
  in
    if ~found then ~1
    else if value_start >= n then ~1
    else if jr_key_is(key, key_len, name) then value_start
    else _member(buf, n, jr_skip(buf, n, value_start), key, name)
  end
end

(* The member name of the object at position, as text *)
fn _member_text {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position < n}{name_len:nat}{most:pos | most <= 4096}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), name: string name_len, most: int most): kept =
  if ~jr_is(buf, n, position, 123) then kept_none()
  else let
    val at = _member(buf, n, position + 1, key, name)
  in if at >= 0 then _json_text(buf, n, at, most) else kept_none() end

(* A string, or an object's name *)
fn _single_name {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position < n}{most:pos | most <= 4096}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), most: int most): kept =
  if jr_is(buf, n, position, 34) then _json_text(buf, n, position, most)
  else _member_text(buf, n, position, key, "name", most)

(* A string, an object's name, or an array's first of either: an
   author, or a link's rel *)
fn _name_at {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position < n}{most:pos | most <= 4096}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), most: int most): kept =
  if jr_is(buf, n, position, 91) then let
    val item = jr_ws(buf, n, position + 1)
  in if item < n then _single_name(buf, n, item, key, most) else kept_none() end
  else _single_name(buf, n, position, key, most)

(* The link object at position *)
fn _json_link {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32)): link = let
  val rel_at = _member(buf, n, position + 1, key, "rel")
  val rel = (if rel_at >= 0 then _name_at(buf, n, rel_at, key, 256) else kept_none()): kept
in
  Link(rel, _member_text(buf, n, position, key, "href", 2048), _member_text(buf, n, position, key, "type", 256),
    _member_text(buf, n, position, key, "title", 512))
end

(* found, with the link objects of the array's items from position on,
   to its closing bracket, of kind *)
fun _json_links {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), kind: link_list, found: picks): picks = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then found
  else if jr_is(buf, n, next, 93) then found
  else if jr_is(buf, n, next, 44) then _json_links(buf, n, next + 1, key, kind, found)
  else let
    val found = (if jr_is(buf, n, next, 123) then _pick(kind, found, _json_link(buf, n, next, key)) else found): picks
    val stop = jr_skip(buf, n, next)
  in if stop <= next then found else _json_links(buf, n, stop, key, kind, found) end
end

(* found, with the links of the array at at (-1: none) *)
fn _json_links_at {l,key_loc:agz}{owner:addr}{n:nat}{at:int | ~1 <= at; at < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, at: int at, key: !$A.arr(byte, key_loc, 32), kind: link_list, found: picks): picks =
  if at < 0 then found
  else if jr_is(buf, n, at, 91) then _json_links(buf, n, at + 1, key, kind, found)
  else found

(* A navigation item (a link object) at position: a link *)
fn _json_navigation_item {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), base: !kept): one_entry = let
  val+ ~Link(rel, address, kind_of, title) = _json_link(buf, n, position, key)
  val () = kept_free(rel)
  val () = kept_free(kind_of)
in
  if kept_len(address) > 0 then OneLink(title, _resolve_free(base, address))
  else let
    val () = kept_free(title)
    val () = kept_free(address)
  in NoEntry() end
end

(* A publication at position: a book *)
fn _json_publication {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), base: !kept): one_entry = let
  val metadata = _member(buf, n, position + 1, key, "metadata")
  val title = (if metadata >= 0 then _member_text(buf, n, metadata, key, "title", 512) else kept_none()): kept
  val author_at = (if metadata >= 0 then (if jr_is(buf, n, metadata, 123) then _member(buf, n, metadata + 1, key, "author") else ~1) else ~1)
    : [author_at:int | ~1 <= author_at; author_at < n] int author_at
  val author = (if author_at >= 0 then _name_at(buf, n, author_at, key, 256) else kept_none()): kept
  val found = _json_links_at(buf, n, _member(buf, n, position + 1, key, "links"), key, EntryLinks(), _picks_empty())
  val found = _json_links_at(buf, n, _member(buf, n, position + 1, key, "images"), key, ImageLinks(), found)
in _entry_of(base, title, author, found) end

(* page, with the entries of the array's items from position on, to its
   closing bracket: navigation links (books) or publications (not) *)
fun _json_entries {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), base: !kept, books: bool, page: feed): feed = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then page
  else if jr_is(buf, n, next, 93) then page
  else if jr_is(buf, n, next, 44) then _json_entries(buf, n, next + 1, key, base, books, page)
  else let
    val page = (if jr_is(buf, n, next, 123) then
        _feed_add(page, (if books then _json_publication(buf, n, next, key, base) else _json_navigation_item(buf, n, next, key, base)): one_entry)
      else page): feed
    val stop = jr_skip(buf, n, next)
  in if stop <= next then page else _json_entries(buf, n, stop, key, base, books, page) end
end

(* page, with the entries of the object at position: its navigation, then
   its publications *)
fn _json_collections {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), base: !kept, page: feed): feed = let
  val navigation = _member(buf, n, position + 1, key, "navigation")
  val page = (if navigation >= 0 then (if jr_is(buf, n, navigation, 91) then _json_entries(buf, n, navigation + 1, key, base, false, page) else page) else page): feed
  val publications = _member(buf, n, position + 1, key, "publications")
in if publications >= 0 then (if jr_is(buf, n, publications, 91) then _json_entries(buf, n, publications + 1, key, base, true, page) else page) else page end

(* page, with the entries of each group of the array's items from
   position on *)
fun _json_groups {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position <= n} .<n - position>.
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), base: !kept, page: feed): feed = let
  val next = jr_ws(buf, n, position)
in
  if next >= n then page
  else if jr_is(buf, n, next, 93) then page
  else if jr_is(buf, n, next, 44) then _json_groups(buf, n, next + 1, key, base, page)
  else let
    val page = (if jr_is(buf, n, next, 123) then _json_collections(buf, n, next, key, base, page) else page): feed
    val stop = jr_skip(buf, n, next)
  in if stop <= next then page else _json_groups(buf, n, stop, key, base, page) end
end

(* The OPDS 2 feed at position (its '{'); whether it is one: it has
   metadata, links, navigation, publications or groups *)
fn _json_feed {l,key_loc:agz}{owner:addr}{n:nat}{position:nat | position < n}
  (buf: !$A.arrx(byte, l, n, owner), n: int n, position: int position, key: !$A.arr(byte, key_loc, 32), base: !kept): @(feed, bool) = let
  val metadata = _member(buf, n, position + 1, key, "metadata")
  val links = _member(buf, n, position + 1, key, "links")
  val navigation = _member(buf, n, position + 1, key, "navigation")
  val publications = _member(buf, n, position + 1, key, "publications")
  val groups = _member(buf, n, position + 1, key, "groups")
  val is_feed = metadata >= 0 || links >= 0 || navigation >= 0 || publications >= 0 || groups >= 0
  val title = (if metadata >= 0 then _member_text(buf, n, metadata, key, "title", 512) else kept_none()): kept
  val page = _feed_title(_feed_empty(), title)
  val page = _json_collections(buf, n, position, key, base, page)
  val page = (if groups >= 0 then (if jr_is(buf, n, groups, 91) then _json_groups(buf, n, groups + 1, key, base, page) else page) else page): feed
  val found = _json_links_at(buf, n, links, key, PageLinks(), _picks_empty())
in @(_feed_links(base, page, found), is_feed) end

(* ============================================================
   A page read
   ============================================================ *)

(* Where the document in buf[0, n) begins: past white space and a
   UTF-8 byte order mark *)
fn _start {l:agz}{owner:addr}{n:nat} (buf: !$A.arrx(byte, l, n, owner), n: int n): [start:nat | start <= n] int start = let
  val at = (if n >= 3 then
      (if jr_is(buf, n, 0, 239) then (if jr_is(buf, n, 1, 187) then (if jr_is(buf, n, 2, 191) then 3 else 0) else 0) else 0)
    else 0): [at:nat | at <= 3; at <= n] int at
in jr_ws(buf, n, at) end

(* The page page[0, n), read from the address base: its feed, and
   whether it is a catalogue's page (an Atom feed, or an OPDS 2 feed);
   the page is handed back *)
#pub fn opds_read {l:agz}{owner:addr}{n:pos}
  (page: $A.arrx(byte, l, n, owner), n: int n, base: !kept): @($A.arrx(byte, l, n, owner), feed, bool)

implement opds_read (page, n, base) = let
  val start = _start(page, n)
in
  if start >= n then @(page, _feed_empty(), false)
  else if jr_is(page, n, start, 123) then let
    val key = $A.alloc<byte>(32)
    val @(read, is_feed) = _json_feed(page, n, start, key, base)
    val () = $A.free<byte>(key)
    val+ ~Feed(title, list, count, next, previous, template, description) = read
  in @(page, Feed(title, _reverse(list, EntriesNil()), count, next, previous, template, description), is_feed) end
  else if jr_is(page, n, start, 60) then let
    val @(frozen, borrowed) = $A.freeze<byte>(page)
    val nodes = $X.parse_document(borrowed, n)
    val @(read, is_feed) = _atom_root(borrowed, nodes, base)
    val () = $X.free_nodes(nodes)
    val () = $A.drop<byte>(frozen, borrowed)
    val+ ~Feed(title, list, count, next, previous, template, description) = read
  in @($A.thaw<byte>(frozen), Feed(title, _reverse(list, EntriesNil()), count, next, previous, template, description), is_feed) end
  else @(page, _feed_empty(), false)
end

(* ============================================================
   OpenSearch descriptions
   ============================================================ *)

(* The template of the first Url element among nodes (and their
   children) whose type is an Atom or OPDS one, when first_only is
   false; or of any Url, when it is true *)
fun _url_template {l:agz}{n:pos}{size:nat} .<size>.
  (data: !$A.borrow(byte, l, n), nodes: !$X.xml_node_list(n, size), any_type: bool): kept =
  case+ nodes of
  | $X.xml_nodes_cons(node, rest) =>
    (case+ node of
     | $X.xml_element(name_offset, name_len, attributes, children) =>
       if _local_is(data, name_offset, name_len, "url") || _local_is(data, name_offset, name_len, "Url") then let
         val kind_of = _span_text(data, _attribute(data, attributes, "type"), 256)
         val wanted = (if any_type then true else if _kept_has(kind_of, "atom") then true else _kept_has(kind_of, "opds")): bool
         val () = kept_free(kind_of)
       in
         if wanted then let
           val template = _span_text(data, _attribute(data, attributes, "template"), 2048)
         in if kept_len(template) > 0 then template else let val () = kept_free(template) in _url_template(data, rest, any_type) end end
         else _url_template(data, rest, any_type)
       end
       else let
         val inside = _url_template(data, children, any_type)
       in if kept_len(inside) > 0 then inside else let val () = kept_free(inside) in _url_template(data, rest, any_type) end end
     | $X.xml_text(_, _) => _url_template(data, rest, any_type))
  | $X.xml_nodes_nil() => kept_none()

(* The search template of the OpenSearch description page[0, n) (as it
   is written: resolved by the caller); the page is handed back *)
#pub fn opensearch_read {l:agz}{owner:addr}{n:pos}
  (page: $A.arrx(byte, l, n, owner), n: int n): @($A.arrx(byte, l, n, owner), kept)

implement opensearch_read (page, n) = let
  val @(frozen, borrowed) = $A.freeze<byte>(page)
  val nodes = $X.parse_document(borrowed, n)
  val typed = _url_template(borrowed, nodes, false)
  val any_type = _url_template(borrowed, nodes, true)
  val template = _first(typed, any_type)
  val () = $X.free_nodes(nodes)
  val () = $A.drop<byte>(frozen, borrowed)
in @($A.thaw<byte>(frozen), template) end

end (* #target wasm *)
