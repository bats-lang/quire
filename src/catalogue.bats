(* catalogue -- an OPDS catalogue browsed, a page at a time, with Get
   importing a book (the list of catalogues is catalogues.bats) *)

(* A page of a catalogue is fetched through the bridge (its status and
   bytes), read into a piece of at most FEED_MOST bytes (a larger one
   is refused), read (opds.bats) and let go: what is shown is kept as
   the page's feed, and the pages browsed through are a trail of
   addresses, so Back fetches the page before again. A book's EPUB is
   fetched the same way, put on the JS side as a file (file_store),
   and imported as a picked file is; where a browser may not read it
   (the fetch fails: CORS), Get gives way to a link that downloads it,
   to import it then. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R

staload "ui.sats"
staload "layer.sats"
staload "book.sats"
staload "mem.sats"
staload "app.sats"
staload "opds.sats"
staload "url.sats"
staload "import.sats"
staload "catalogues.sats"
staload FE = "wasm.bats-packages.dev/bridge/src/fetch.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"

(* The most bytes a page of a catalogue is read in *)
#define FEED_MOST 4194304
(* The most bytes of a book got *)
#define BOOK_MOST 268435456
(* The most pages Back goes back through *)
#define TRAIL_MOST 64

(* ============================================================
   Browsing: the trail of pages, and the page shown
   ============================================================ *)

(* The addresses of the pages browsed through, the one shown first *)
datavtype trail(int) =
  | TrailNil(0) of ()
  | {depth:nat} TrailCons(depth + 1) of (kept, trail(depth))

fun _trail_free {depth:nat} .<depth>. (pages: trail(depth)): void =
  case+ pages of
  | ~TrailNil() => ()
  | ~TrailCons(address, rest) => let val () = kept_free(address) in _trail_free(rest) end

(* pages without its last (oldest) page *)
fun _trail_drop_last {depth:nat} .<depth>. (pages: trail(depth)): [left:nat | left <= depth] trail(left) =
  case+ pages of
  | ~TrailNil() => TrailNil()
  | ~TrailCons(address, rest) =>
    (case+ rest of
     | ~TrailNil() => let val () = kept_free(address) in TrailNil() end
     | rest => TrailCons(address, _trail_drop_last(rest)))

datavtype trail_cell = {depth:nat} TrailCell of (trail(depth), int)

val _trail = ref<trail_cell>(TrailCell(TrailNil(), 0))

fn _trail_take (): trail_cell = let
  var cell: trail_cell = TrailCell(TrailNil(), 0)
  val () = ref_exch_elt<trail_cell>(_trail, cell)
in cell end

fn _trail_put (cell: trail_cell): void = let
  var previous: trail_cell = cell
  val () = ref_exch_elt<trail_cell>(_trail, previous)
  val+ ~TrailCell(pages, _) = previous
in _trail_free(pages) end

(* The page shown's address, copied (none when there is none) *)
fn _trail_top (): kept = let
  val+ ~TrailCell(pages, depth) = _trail_take()
in
  case+ pages of
  | TrailNil() => let val () = _trail_put(TrailCell(pages, depth)) in kept_none() end
  | @TrailCons(address, _) => let
      val top = kept_dup(address)
      prval () = fold@(pages)
      val () = _trail_put(TrailCell(pages, depth))
    in top end
end

(* address put on the trail, as the page shown; past TRAIL_MOST pages,
   the oldest goes *)
fn _trail_push (address: kept): void = let
  val+ ~TrailCell(pages, depth) = _trail_take()
in
  if depth >= TRAIL_MOST then let
    val shorter = _trail_drop_last(pages)
  in _trail_put(TrailCell(TrailCons(address, shorter), TRAIL_MOST)) end
  else _trail_put(TrailCell(TrailCons(address, pages), depth + 1))
end

(* The page shown taken off the trail; whether one is left *)
fn _trail_pop (): bool = let
  val+ ~TrailCell(pages, depth) = _trail_take()
in
  case+ pages of
  | ~TrailNil() => let val () = _trail_put(TrailCell(TrailNil(), 0)) in false end
  | ~TrailCons(address, rest) => let
      val () = kept_free(address)
      val left = (case+ rest of TrailNil() => false | TrailCons(_, _) => true): bool
      val () = _trail_put(TrailCell(rest, (if depth > 0 then depth - 1 else 0)))
    in left end
end

(* The page shown, read *)
datavtype shown =
  | Shown of feed
  | NothingShown of ()

val _shown = ref<shown>(NothingShown())

fn _shown_take (): shown = let
  var cell: shown = NothingShown()
  val () = ref_exch_elt<shown>(_shown, cell)
in cell end

fn _shown_put (page: shown): void = let
  var previous: shown = page
  val () = ref_exch_elt<shown>(_shown, previous)
in
  case+ previous of
  | ~Shown(read) => feed_free(read)
  | ~NothingShown() => ()
end

(* The number of the latest page asked for: an answer to an earlier
   one is let go *)
val _request = ref<int>(0)

fn _say {text_len:pos | text_len < 256} (text: string text_len): void = let
  val () = ui_text("catalogue-status", text)
in ui_show("catalogue-status", true) end

fn _quiet (): void = ui_show("catalogue-status", false)

(* What a fetch gave: its status and bytes in a piece, or why not *)
datavtype fetched =
  | {arena_loc,piece_loc:agz}{size:pos} Fetched of (piece_owner(size, arena_loc), $A.arrx(byte, piece_loc, size, arena_loc), int size)
  | Blocked of ()         (* the request failed: a network error, or CORS *)
  | Refused of int        (* an HTTP status other than 2xx *)
  | TooLarge of ()
  | Empty of ()

fn _fetched_free (got: fetched): void =
  case+ got of
  | ~Fetched(owner, piece, _) => piece_free(owner, piece)
  | ~Blocked() => ()
  | ~Refused(_) => ()
  | ~TooLarge() => ()
  | ~Empty() => ()

(* What a fetch came to, read into a piece of at most most bytes *)
fn _claim {most:pos | most <= 268435456} (got: $FE.fetched, most: int most): fetched =
  case+ got of
  | ~$FE.NoResponse() => Blocked()
  | ~$FE.Responded(response) => let
      val status = $FE.fetch_status(response)
      val blob = $FE.fetch_body(response)
    in
      if status < 200 then let val () = $BD.blob_free(blob) in Refused(status) end
      else if status > 299 then let val () = $BD.blob_free(blob) in Refused(status) end
      else let
        val size = $BD.blob_len(blob)
      in
        if size <= 0 then let val () = $BD.blob_free(blob) in Empty() end
        else if size > most then let val () = $BD.blob_free(blob) in TooLarge() end
        else (case+ piece_new(size) of
          | ~NoPiece() => let val () = $BD.blob_free(blob) in TooLarge() end
          | ~Piece(owner, piece) => let
              val () = $BD.blob_read(blob, 0, piece, size)
              val () = $BD.blob_free(blob)
            in Fetched(owner, piece, size) end)
      end
    end

(* What a fetch gave, nobody took: its piece freed *)
implement $P.dispose<fetched>(got) = _fetched_free(got)

(* Fetches address (an address shown is at most URL_MOST bytes), read
   into a piece of at most most bytes *)
fn _fetch {most:pos | most <= 268435456} (address: !kept, most: int most): $P.promise(fetched, $P.Chained) = let
  val @(bytes, address_len) = kept_copy(address)
in
  if address_len <= 0 then let val () = $A.free<byte>(bytes) in $P.ret<fetched>(Blocked()) end
  else let
    val @(frozen, borrowed) = $A.freeze<byte>(bytes)
    val @(used, rest) = $A.borrow_split<byte>(frozen, borrowed, address_len)
    val fetching = $FE.fetch(used, address_len)
    val borrowed = $A.borrow_join<byte>(frozen, used, rest)
    val () = release_bytes(frozen, borrowed)
  in $P.and_then<$FE.fetched><fetched>(fetching, llam(got) => $P.ret<fetched>(_claim(got, most))) end
end

(* ============================================================
   A page shown
   ============================================================ *)

(* Each entry's row from index on: a link to another page, or a book
   (its cover, title and author, Get, and the link that downloads it
   where Get cannot) *)
fun _entry_rows {count:nat}{index:nat} .<count>. (list: !entries(count), index: int index): void =
  case+ list of
  | EntriesNil() => ()
  | @EntryLink(title, _, rest) => let
      val @(link, link_len) = nid_make("feed-link", index)
      val () = ui_btn_n("catalogue-list", link, link_len, "pi")
      val @(link, link_len) = nid_make("feed-link", index)
      val () = kept_text_n(link, link_len, title)
      val () = _entry_rows(rest, index + 1)
      prval () = fold@(list)
    in end
  | @EntryBook(title, author, cover, epub, rest) => let
      val @(entry, entry_len) = nid_make("book-entry", index)
      val () = ui_add_n("catalogue-list", entry, entry_len, TDiv)
      val @(entry, entry_len) = nid_make("book-entry", index)
      val () = ui_attr_n(entry, entry_len, AClass, "bkrow")
      val @(cover_url, cover_len) = kept_copy(cover)
      val () = (if cover_len > 0 then let
          val @(entry, entry_len) = nid_make("book-entry", index)
          val @(image, image_len) = nid_make("book-cover", index)
          val () = ui_img_nn(entry, entry_len, image, image_len, "cov")
          val @(image, image_len) = nid_make("book-cover", index)
        in ui_web_src_n(image, image_len, cover_url, cover_len) end
        else $A.free<byte>(cover_url))
      val @(entry, entry_len) = nid_make("book-entry", index)
      val @(text, text_len) = nid_make("book-text", index)
      val () = ui_add_nn(entry, entry_len, text, text_len, TDiv)
      val @(text, text_len) = nid_make("book-text", index)
      val () = ui_attr_n(text, text_len, AClass, "cinfo")
      val @(text, text_len) = nid_make("book-text", index)
      val @(heading, heading_len) = nid_make("book-title", index)
      val () = ui_add_nn(text, text_len, heading, heading_len, TDiv)
      val @(heading, heading_len) = nid_make("book-title", index)
      val () = ui_attr_n(heading, heading_len, AClass, "bt")
      val @(heading, heading_len) = nid_make("book-title", index)
      val () = kept_text_n(heading, heading_len, title)
      val @(entry, entry_len) = nid_make("book-entry", index)
      val @(heading, heading_len) = nid_make("book-title", index)
      val () = ui_labelled_nn(entry, entry_len, NGroup, heading, heading_len)
      val @(author_text, author_len) = kept_copy(author)
      val () = (if author_len > 0 then let
          val @(text, text_len) = nid_make("book-text", index)
          val @(byline, byline_len) = nid_make("book-author", index)
          val () = ui_add_nn(text, text_len, byline, byline_len, TDiv)
          val @(byline, byline_len) = nid_make("book-author", index)
          val () = ui_attr_n(byline, byline_len, AClass, "ba")
          val @(byline, byline_len) = nid_make("book-author", index)
        in ui_text_n_buf(byline, byline_len, author_text, author_len) end
        else $A.free<byte>(author_text))
      val @(epub_url, epub_len) = kept_copy(epub)
      val () = (if epub_len > 0 then let
          val @(entry, entry_len) = nid_make("book-entry", index)
          val @(get, get_len) = nid_make("book-get", index)
          val () = ui_text_btn_nn(entry, entry_len, get, get_len, "btn btn-p", "Get")
          val @(entry, entry_len) = nid_make("book-entry", index)
          val @(download, download_len) = nid_make("book-download", index)
          val () = ui_download_nn(entry, entry_len, download, download_len, "btn", "Download")
          val @(download, download_len) = nid_make("book-download", index)
          val () = ui_web_href_n(download, download_len, epub_url, epub_len)
          val @(download, download_len) = nid_make("book-download", index)
          val () = ui_show_n(download, download_len, false)
          val @(entry, entry_len) = nid_make("book-entry", index)
          val @(then_text, then_len) = nid_make("book-then", index)
          val () = ui_add_nn(entry, entry_len, then_text, then_len, TSpan)
          val @(then_text, then_len) = nid_make("book-then", index)
          val () = ui_attr_n(then_text, then_len, AClass, "ba")
          val @(then_text, then_len) = nid_make("book-then", index)
          val () = ui_text_n(then_text, then_len, "then import it")
          val @(then_text, then_len) = nid_make("book-then", index)
        in ui_show_n(then_text, then_len, false) end
        else $A.free<byte>(epub_url))
      val () = _entry_rows(rest, index + 1)
      prval () = fold@(list)
    in end

(* Shows the search field, emptied *)
fn _search_shown (): void = let
  val () = app_catalogue_search()
in ui_show("catalogue-search-bar", true) end

(* The search template's description read from fetched: the template,
   resolved against the description's address, put in the page shown
   (when it is still the one asked for, request) *)
fn _described (got: fetched, request: int): void =
  case+ got of
  | ~Fetched(owner, piece, size) =>
    if request <> !_request then piece_free(owner, piece)
    else let
      val @(piece, raw) = opensearch_read(piece, size)
      val () = piece_free(owner, piece)
    in
      case+ _shown_take() of
      | ~NothingShown() => let val () = kept_free(raw) in _shown_put(NothingShown()) end
      | ~Shown(read) => let
          val+ ~Feed(title, list, count, next, previous, template, description) = read
          val resolved = opds_resolve(description, raw)
          val () = kept_free(raw)
          val found = kept_len(resolved) > 0
          val () = kept_free(template)
          val () = _shown_put(Shown(Feed(title, list, count, next, previous, resolved, description)))
        in if found then _search_shown() else () end
    end
  | other => _fetched_free(other)

(* Shows page, the answer to request *)
fn _show (page: feed, request: int): void = let
  val+ ~Feed(title, list, count, next, previous, template, description) = page
  val @(heading, heading_len) = kept_copy(title)
  val () = (if heading_len > 0 then ui_text_buf("catalogue-title", heading, heading_len)
    else let val () = $A.free<byte>(heading) in ui_text("catalogue-title", "Catalogue") end)
  val () = ui_clear("catalogue-list")
  val () = _entry_rows(list, 0)
  val has_next = kept_len(next) > 0
  val has_previous = kept_len(previous) > 0
  val () = ui_show("catalogue-next", has_next)
  val () = ui_show("catalogue-previous", has_previous)
  val () = ui_show("catalogue-pages", has_next || has_previous)
  val has_template = kept_len(template) > 0
  val () = (if has_template then _search_shown() else ui_show("catalogue-search-bar", false))
  val () = (if count = 0 then _say("Nothing here.") else _quiet())
  val describing = (if has_template then kept_none() else kept_dup(description)): kept
  val () = _shown_put(Shown(Feed(title, list, count, next, previous, template, description)))
in
  if kept_len(describing) <= 0 then kept_free(describing)
  else let
    val fetching = _fetch(describing, FEED_MOST)
    val () = kept_free(describing)
  in
    $P.finish<fetched>(fetching, llam(got) => _described(got, request))
  end
end

(* The answer to request, page asked for, read *)
fn _arrived (got: fetched, request: int): void =
  if request <> !_request then _fetched_free(got)
  else case+ got of
  | ~Fetched(owner, piece, size) => let
      val base = _trail_top()
      val @(piece, page, is_feed) = opds_read(piece, size, base)
      val () = kept_free(base)
      val () = piece_free(owner, piece)
    in
      if is_feed then _show(page, request)
      else let
        val () = feed_free(page)
      in _say("This isn't a catalogue.") end
    end
  | ~Blocked() => _say("This catalogue doesn't let a browser read it.")
  | ~Refused(status) =>
    if status = 404 then _say("Not found.")
    else if status = 401 then _say("Needs a sign-in.")
    else if status = 403 then _say("Needs a sign-in.")
    else _say("This catalogue could not be read.")
  | ~TooLarge() => _say("This page of the catalogue is too large to read.")
  | ~Empty() => _say("This isn't a catalogue.")

(* Fetches and shows the page on top of the trail *)
fn _load (): void = let
  val address = _trail_top()
  val request = !_request + 1
  val () = !_request := request
  val () = _shown_put(NothingShown())
  val () = ui_clear("catalogue-list")
  val () = ui_show("catalogue-pages", false)
  val () = ui_show("catalogue-search-bar", false)
  val () = _say("Loading\xE2\x80\xA6")
  val fetching = _fetch(address, FEED_MOST)
  val () = kept_free(address)
in
  $P.finish<fetched>(fetching, llam(got) => _arrived(got, request))
end

(* Goes to the page at address *)
fn _go (address: kept): void =
  if kept_len(address) <= 0 then kept_free(address)
  else let
    val () = _trail_push(address)
  in _load() end

(* Opens the catalogue at index of the list, at its first page *)
#pub fn catalogue_open (index: int): void

implement catalogue_open (index) = let
  val address = catalogue_address(index)
in
  if kept_len(address) <= 0 then kept_free(address)
  else let
    val () = _trail_put(TrailCell(TrailNil(), 0))
    val () = layer_close(LCatalogues())
    val () = ui_text("catalogue-title", "Catalogue")
    val () = layer_open(LCatalogue())
    val () = ui_focus("catalogue-back")
  in _go(address) end
end

(* Closes the catalogue: what it showed goes *)
#pub fn catalogue_close (): void

implement catalogue_close () = let
  val () = !_request := !_request + 1
  val () = _shown_put(NothingShown())
  val () = _trail_put(TrailCell(TrailNil(), 0))
  val () = ui_clear("catalogue-list")
in layer_close(LCatalogue()) end

(* Back: to the page before, or from the first page to the list *)
#pub fn catalogue_back (): void

implement catalogue_back () =
  if _trail_pop() then _load()
  else let
    val () = catalogue_close()
  in catalogue_panel_open() end

(* What the page shown has: an entry's address (a link's, which = 0),
   EPUB (1) or title (2) *)
fun _entry_text {count:nat} .<count>. (list: !entries(count), index: int, which: int): kept =
  case+ list of
  | EntriesNil() => kept_none()
  | @EntryLink(title, address, rest) =>
    if index = 0 then let
      val found = (if which = 0 then kept_dup(address) else if which = 2 then kept_dup(title) else kept_none()): kept
      prval () = fold@(list)
    in found end
    else let
      val found = _entry_text(rest, index - 1, which)
      prval () = fold@(list)
    in found end
  | @EntryBook(title, _, _, epub, rest) =>
    if index = 0 then let
      val found = (if which = 1 then kept_dup(epub) else if which = 2 then kept_dup(title) else kept_none()): kept
      prval () = fold@(list)
    in found end
    else let
      val found = _entry_text(rest, index - 1, which)
      prval () = fold@(list)
    in found end

fn _shown_entry (index: int, which: int): kept =
  case+ _shown_take() of
  | ~NothingShown() => let val () = _shown_put(NothingShown()) in kept_none() end
  | ~Shown(read) => let
      val+ ~Feed(title, list, count, next, previous, template, description) = read
      val found = _entry_text(list, index, which)
      val () = _shown_put(Shown(Feed(title, list, count, next, previous, template, description)))
    in found end

(* The page shown's next page (which = 0), previous page (1) or search
   template (2) *)
fn _shown_link (which: int): kept =
  case+ _shown_take() of
  | ~NothingShown() => let val () = _shown_put(NothingShown()) in kept_none() end
  | ~Shown(read) => let
      val+ ~Feed(title, list, count, next, previous, template, description) = read
      val found = (if which = 0 then kept_dup(next) else if which = 1 then kept_dup(previous) else kept_dup(template)): kept
      val () = _shown_put(Shown(Feed(title, list, count, next, previous, template, description)))
    in found end

(* Follows the link at index of the page shown *)
#pub fn catalogue_follow (index: int): void
implement catalogue_follow (index) = _go(_shown_entry(index, 0))

(* The page shown's next or previous page *)
#pub fn catalogue_next (): void
implement catalogue_next () = _go(_shown_link(0))

#pub fn catalogue_previous (): void
implement catalogue_previous () = _go(_shown_link(1))

(* Searches the catalogue for what the search field holds *)
#pub fn catalogue_search (): void

implement catalogue_search () = let
  val query = field_kept("catalogue-search", 256)
  val template = _shown_link(2)
  val query_len = kept_len(query)
  val template_len = kept_len(template)
in
  if query_len <= 0 then let
    val () = kept_free(query)
  in kept_free(template) end
  else if template_len <= 0 then let
    val () = kept_free(query)
  in kept_free(template) end
  else let
    val @(query_bytes, query_len) = kept_copy(query)
    val @(template_bytes, template_len) = kept_copy(template)
    val () = kept_free(query)
    val () = kept_free(template)
    val+ ~Resolved(filled, filled_len) = (if query_len <= 256 then (if template_len <= 2048 then
        url_fill(template_bytes, template_len, query_bytes, query_len) else Resolved($A.alloc<byte>(1), 0))
      else Resolved($A.alloc<byte>(1), 0)): resolved
    val () = $A.free<byte>(query_bytes)
    val () = $A.free<byte>(template_bytes)
    val address = kept_of(filled, filled_len)
    val () = $A.free<byte>(filled)
  in _go(address) end
end

(* ============================================================
   Getting a book
   ============================================================ *)

(* Get, given way to the link that downloads the book at index, with
   "then import it" *)
fn _blocked {index:nat} (index: int index): void = let
  val @(get, get_len) = nid_make("book-get", index)
  val () = ui_show_n(get, get_len, false)
  val @(download, download_len) = nid_make("book-download", index)
  val () = ui_show_n(download, download_len, true)
  val @(then_text, then_len) = nid_make("book-then", index)
in ui_show_n(then_text, then_len, true) end

(* The book at index of request's page, fetched (got): imported *)
fn _got {index:nat} (got: fetched, index: int index, request: int): void =
  case+ got of
  | ~Fetched(owner, piece, size) => let
      val @(frozen, borrowed) = $A.freeze<byte>(piece)
      val book_file = $BF.file_store(borrowed, size)
      val () = $A.drop<byte>(frozen, borrowed)
      val () = piece_free(owner, $A.thaw<byte>(frozen))
      val title = (if request = !_request then _shown_entry(index, 2) else kept_none()): kept
      val @(name, name_len) = kept_copy(title)
      val () = kept_free(title)
      val () = _say("Importing the book\xE2\x80\xA6")
      val importing = import_fetched(book_file, size, name, name_len)
      val () = $A.free<byte>(name)
    in
      $P.finish<import_outcome>(importing, llam(outcome) =>
        case+ outcome of
        | ~Added(_) => _say("Added to your library.")
        | ~Failed() => _say("This book could not be imported.")
        | ~Kept() => _quiet())
    end
  | ~Blocked() =>
    if request = !_request then let
      val () = _quiet()
    in _blocked(index) end
    else ()
  | ~Refused(status) =>
    if status = 404 then _say("The book was not found.")
    else _say("The book could not be downloaded.")
  | ~TooLarge() => _say("The book is too large.")
  | ~Empty() => _say("The book could not be downloaded.")

(* Gets the book at index of the page shown: its EPUB fetched and
   imported *)
#pub fn catalogue_get {index:nat} (index: int index): void

implement catalogue_get (index) = let
  val epub = _shown_entry(index, 1)
  val request = !_request
in
  if kept_len(epub) <= 0 then kept_free(epub)
  else let
    val () = _say("Downloading the book\xE2\x80\xA6")
    val fetching = _fetch(epub, BOOK_MOST)
    val () = kept_free(epub)
  in
    $P.finish<fetched>(fetching, llam(got) => _got(got, index, request))
  end
end


end (* #target wasm *)
