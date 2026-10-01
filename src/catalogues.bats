(* catalogues -- the OPDS catalogues books are got from: the list of
   them, kept in storage, removed with Undo and listed in the backup;
   one of them is browsed by catalogue.bats *)

(* The list is stored under "catalogues": "QCT1", the number the next
   one added takes and how many there are (big-endian u32s), then each
   one's number, its name's length and name, and its address's length
   and address. Until something is stored the list is Project
   Gutenberg's catalogue alone. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use wasm.bats-packages.dev/decompress as DC

staload "ui.sats"
staload "layer.sats"
staload "undo.sats"
staload "book.sats"
staload "mem.sats"
staload "jsonio.sats"
staload "app.sats"
staload "stardict.sats"
staload "opds.sats"
staload "url.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload DR = "wasm.bats-packages.dev/bridge/src/dom_read.sats"

(* The most catalogues kept *)
#define MOST_CATALOGUES 64
(* A stored entry's most bytes: its number, and its name and address
   with their lengths *)
#define ENTRY_MOST 8204

fn _byte_at {l:agz}{n:nat}{i:nat | i < n} (bytes: !$A.arr(byte, l, n), i: int i): [value:nat | value < 256] int value =
  $AR.low_byte(byte2int0($A.get<byte>(bytes, i)))

fun _copy {source_loc,target_loc:agz}{source_size,target_size:nat}
  {source_at,count:nat | source_at + count <= source_size}{target_at:nat | target_at + count <= target_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), source_at: int source_at,
   target: !$A.arr(byte, target_loc, target_size), target_at: int target_at, count: int count, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(target, target_at + i, $A.get<byte>(source, source_at + i))
  in _copy(source, source_at, target, target_at, count, i + 1) end

fun _trim_start {l:agz}{n:nat}{stop:nat | stop <= n}{at:nat | at <= stop} .<stop - at>.
  (bytes: !$A.arr(byte, l, n), at: int at, stop: int stop): [start:nat | at <= start; start <= stop] int start =
  if at >= stop then stop
  else if _byte_at(bytes, at) <= 32 then _trim_start(bytes, at + 1, stop)
  else at

fun _trim_end {l:agz}{n:nat}{start:nat}{stop:nat | start <= stop; stop <= n} .<stop - start>.
  (bytes: !$A.arr(byte, l, n), start: int start, stop: int stop): [end_at:nat | start <= end_at; end_at <= stop] int end_at =
  if stop <= start then start
  else if _byte_at(bytes, stop - 1) <= 32 then _trim_end(bytes, start, stop - 1)
  else stop

(* text's bytes at buffer[at, at + text_len) *)
fun _put_string {l:agz}{n:nat}{text_len:nat}{at:nat | at + text_len <= n}{i:nat | i <= text_len} .<text_len - i>.
  (buffer: !$A.arr(byte, l, n), at: int at, text: string text_len, text_len: int text_len, i: int i): int(at + text_len) =
  if i >= text_len then at + text_len
  else let
    val () = $A.write_byte(buffer, at + i, $AR.byte_of_char(string_get_at(text, i)))
  in _put_string(buffer, at, text, text_len, i + 1) end

fn _literal_bytes {text_len:pos | text_len < 256} (text: string text_len): [l:agz] @($A.arr(byte, l, text_len), int text_len) = let
  val text_len = g1u2i(string1_length(text))
  val bytes = $A.alloc<byte>(text_len)
  val _ = _put_string(bytes, 0, text, text_len, 0)
in @(bytes, text_len) end

(* A literal, kept *)
fn _kept_literal {text_len:pos | text_len < 256} (text: string text_len): kept = let
  val @(bytes, text_len) = _literal_bytes(text)
  val text = kept_of(bytes, text_len)
  val () = $A.free<byte>(bytes)
in text end

(* ============================================================
   The catalogues
   ============================================================ *)

(* Each catalogue: its number, name and address *)
datavtype catalogues(int) =
  | CataloguesNil(0) of ()
  | {count:nat} CatalogueCons(count + 1) of (int, kept, kept, catalogues(count))

fun _list_free {count:nat} .<count>. (list: catalogues(count)): void =
  case+ list of
  | ~CataloguesNil() => ()
  | ~CatalogueCons(_, name, address, rest) => let
      val () = kept_free(name)
      val () = kept_free(address)
    in _list_free(rest) end

fun _list_count {count:nat} .<count>. (list: !catalogues(count)): int count =
  case+ list of
  | CataloguesNil() => 0
  | @CatalogueCons(_, _, _, rest) => let
      val count = 1 + _list_count(rest)
      prval () = fold@(list)
    in count end

fun _list_join {front,back:nat} .<front>. (list: catalogues(front), back: catalogues(back)): catalogues(front + back) =
  case+ list of
  | ~CataloguesNil() => back
  | ~CatalogueCons(id, name, address, rest) => CatalogueCons(id, name, address, _list_join(rest, back))

(* list with extra put in at index (at its end, past it) *)
fun _list_insert {count,extra:nat} .<count>. (list: catalogues(count), index: int, extra: catalogues(extra)): catalogues(count + extra) =
  if index <= 0 then _list_join(extra, list)
  else (case+ list of
    | ~CataloguesNil() => extra
    | ~CatalogueCons(id, name, address, rest) => CatalogueCons(id, name, address, _list_insert(rest, index - 1, extra)))

(* list without the entry at index, and that entry (none past its end) *)
fun _list_take_at {count:nat} .<count>. (list: catalogues(count), index: int)
  : [left,taken:nat | left + taken == count; taken <= 1] @(catalogues(left), catalogues(taken)) =
  case+ list of
  | ~CataloguesNil() => @(CataloguesNil(), CataloguesNil())
  | ~CatalogueCons(id, name, address, rest) =>
    if index = 0 then @(rest, CatalogueCons(id, name, address, CataloguesNil()))
    else let
      val @(left, taken) = _list_take_at(rest, index - 1)
    in @(CatalogueCons(id, name, address, left), taken) end

(* list without the entry numbered id, and that entry *)
fun _list_take_id {count:nat} .<count>. (list: catalogues(count), id: int)
  : [left,taken:nat | left + taken == count; taken <= 1] @(catalogues(left), catalogues(taken)) =
  case+ list of
  | ~CataloguesNil() => @(CataloguesNil(), CataloguesNil())
  | ~CatalogueCons(entry_id, name, address, rest) =>
    if entry_id = id then @(rest, CatalogueCons(entry_id, name, address, CataloguesNil()))
    else let
      val @(left, taken) = _list_take_id(rest, id)
    in @(CatalogueCons(entry_id, name, address, left), taken) end

(* The number of the entry at index, or -1 *)
fun _list_id_at {count:nat} .<count>. (list: !catalogues(count), index: int): int =
  case+ list of
  | CataloguesNil() => ~1
  | @CatalogueCons(id, _, _, rest) =>
    if index = 0 then let val found = id; prval () = fold@(list) in found end
    else let
      val found = _list_id_at(rest, index - 1)
      prval () = fold@(list)
    in found end

(* The address of the entry at index, copied (none past the end) *)
fun _list_address_at {count:nat} .<count>. (list: !catalogues(count), index: int): kept =
  case+ list of
  | CataloguesNil() => kept_none()
  | @CatalogueCons(_, _, address, rest) =>
    if index = 0 then let val found = kept_dup(address); prval () = fold@(list) in found end
    else let
      val found = _list_address_at(rest, index - 1)
      prval () = fold@(list)
    in found end

(* The catalogues, the number the next one added takes, and whether
   they were read from storage yet *)
datavtype catalogue_cell = {count:nat} CatalogueCell of (catalogues(count), int)

val _catalogues = ref<catalogue_cell>(CatalogueCell(CataloguesNil(), 1))

fn _list_take (): catalogue_cell = let
  var cell: catalogue_cell = CatalogueCell(CataloguesNil(), 1)
  val () = ref_exch_elt<catalogue_cell>(_catalogues, cell)
in cell end

fn _list_put (cell: catalogue_cell): void = let
  var previous: catalogue_cell = cell
  val () = ref_exch_elt<catalogue_cell>(_catalogues, previous)
  val+ ~CatalogueCell(list, _) = previous
in _list_free(list) end

(* The catalogues removed whose Undo is still offered: kept (and
   stored) until it is made final *)
datavtype removed_cell = {count:nat} RemovedCell of (catalogues(count))

val _removed = ref<removed_cell>(RemovedCell(CataloguesNil()))

fn _removed_take (): removed_cell = let
  var cell: removed_cell = RemovedCell(CataloguesNil())
  val () = ref_exch_elt<removed_cell>(_removed, cell)
in cell end

fn _removed_put (cell: removed_cell): void = let
  var previous: removed_cell = cell
  val () = ref_exch_elt<removed_cell>(_removed, previous)
  val+ ~RemovedCell(list) = previous
in _list_free(list) end

(* ============================================================
   Storage
   ============================================================ *)

(* text's length and bytes at out[at, ...): where they end *)
fn _put_kept {l:agz}{n:nat}{at:nat | at + 4 + 4096 <= n}
  (out: !$A.arr(byte, l, n), at: int at, text: !kept): [stop:nat | at + 4 <= stop; stop <= at + 4 + 4096] int stop = let
  val+ @Kept(bytes, text_len) = text
  val () = u32_put(out, at, text_len)
  val () = _copy(bytes, 0, out, at + 4, text_len, 0)
  val stop = at + 4 + text_len
  prval () = fold@(text)
in stop end


fun _write_entries {l:agz}{n:nat}{count:nat}{at:nat | at + ENTRY_MOST * count <= n} .<count>.
  (out: !$A.arr(byte, l, n), at: int at, list: !catalogues(count)): [stop:nat | stop <= at + ENTRY_MOST * count] int stop =
  case+ list of
  | CataloguesNil() => at
  | @CatalogueCons(id, name, address, rest) => let
      val () = u32_put(out, at, id)
      val after_name = _put_kept(out, at + 4, name)
      val after_address = _put_kept(out, after_name, address)
      val stop = _write_entries(out, after_address, rest)
      prval () = fold@(list)
    in stop end

fn _storage_key (): [l:agz] @($A.arr(byte, l, 10), int 10) = let
  val key = $A.alloc<byte>(10)
  val _ = _put_string(key, 0, "catalogues", 10, 0)
in @(key, 10) end

(* Stores the list (with the catalogues whose removal can still be
   undone) under "catalogues" *)
fn _save (): void = let
  val+ ~CatalogueCell(list, next_id) = _list_take()
  val+ ~RemovedCell(removed) = _removed_take()
  val total = _list_count(list) + _list_count(removed)
in
  if total > 120 then let
    val () = _removed_put(RemovedCell(removed))
  in _list_put(CatalogueCell(list, next_id)) end
  else let
    val size = 12 + ENTRY_MOST * total
    val out = $A.alloc<byte>(size)
    val () = $A.write_text(out, 0, $A.text_lit("QCT1"), 4)
    val () = u32_put(out, 4, next_id)
    val () = u32_put(out, 8, total)
    val stop = _write_entries(out, 12, list)
    val stop = _write_entries(out, stop, removed)
    val () = _removed_put(RemovedCell(removed))
    val () = _list_put(CatalogueCell(list, next_id))
    val @(out_frozen, out_bytes) = $A.freeze<byte>(out)
    val @(used, rest) = $A.borrow_split<byte>(out_frozen, out_bytes, stop)
    val @(key, key_len) = _storage_key()
    val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
    val () = $P.discard<Int>($IDB.idb_put(key_bytes, key_len, used, stop))
    val () = release_bytes(key_frozen, key_bytes)
    val out_bytes = $A.borrow_join<byte>(out_frozen, used, rest)
  in release_bytes(out_frozen, out_bytes) end
end

(* The text stored at data[at, n): its length (a u32) and bytes; and
   where it ends (-1 when it does not fit) *)
fn _read_kept {l:agz}{n:pos}{at:nat | at <= n} (data: !$A.arr(byte, l, n), n: int n, at: int at)
  : [stop:int | stop == ~1 || (at < stop && stop <= n)] @(kept, int stop) =
  if at + 4 > n then @(kept_none(), ~1)
  else let
    val text_len = u32_at(data, at)
  in
    if text_len < 0 then @(kept_none(), ~1)
    else if text_len > 4096 then @(kept_none(), ~1)
    else if at + 4 + text_len > n then @(kept_none(), ~1)
    else let
      val bytes = $A.alloc<byte>(text_len + 1)
      val () = _copy(data, at + 4, bytes, 0, text_len, 0)
    in @(Kept(bytes, text_len), at + 4 + text_len) end
  end

(* The entries stored at data[at, n), remaining of them, after list *)
fun _parse_entries {l:agz}{n:pos}{at:nat | at <= n}{remaining:nat}{count:nat} .<remaining>.
  (data: !$A.arr(byte, l, n), n: int n, at: int at, remaining: int remaining, list: catalogues(count)): [total:nat] catalogues(total) =
  if remaining <= 0 then list
  else if at + 4 > n then list
  else let
    val id = u32_at(data, at)
    val @(name, after_name) = _read_kept(data, n, at + 4)
  in
    if after_name < 0 then let val () = kept_free(name) in list end
    else let
      val @(address, after_address) = _read_kept(data, n, after_name)
    in
      if after_address < 0 then let
        val () = kept_free(name)
        val () = kept_free(address)
      in list end
      else if id <= 0 then let
        val () = kept_free(name)
        val () = kept_free(address)
      in list end
      else _parse_entries(data, n, after_address, remaining - 1, _list_join(list, CatalogueCons(id, name, address, CataloguesNil())))
    end
  end

(* Project Gutenberg's catalogue, the one there is until the reader
   changes the list *)
fn _preset (): catalogues(1) =
  CatalogueCons(1, _kept_literal("Project Gutenberg"), _kept_literal("https://www.gutenberg.org/ebooks/search.opds/"), CataloguesNil())

(* Reads the catalogues stored under "catalogues" *)
#pub fn catalogue_load (): $P.promise(int, $P.Chained)

implement catalogue_load () = let
  val @(key, key_len) = _storage_key()
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val stored = $IDB.idb_get(key_bytes, key_len)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<Int><int>($P.vow(stored), lam(handle) =>
    case+ take_blob(handle) of
    | ~NoBlobBytes() => let val () = _list_put(CatalogueCell(_preset(), 2)) in $P.ret<int>(0) end
    | ~BlobBytes(data, n) =>
      if n < 12 then let val () = $A.free<byte>(data) in $P.ret<int>(0) end
      else if _byte_at(data, 0) <> 81 then let val () = $A.free<byte>(data) in $P.ret<int>(0) end
      else if _byte_at(data, 1) <> 67 then let val () = $A.free<byte>(data) in $P.ret<int>(0) end
      else let
        val next_id = u32_at(data, 4)
        val total = u32_at(data, 8)
        val total = (if total < 0 then 0 else if total > 1000 then 1000 else total): [total:nat | total <= 1000] int total
        val list = _parse_entries(data, n, 12, total, CataloguesNil())
        val () = $A.free<byte>(data)
        val () = _list_put(CatalogueCell(list, (if next_id > 0 then next_id else 1000)))
      in $P.ret<int>(0) end)
end

(* ============================================================
   The catalogues panel
   ============================================================ *)

(* The text of the numbered element id: text, or "Untitled" when it is empty *)
#pub fn kept_text_n {id_loc:agz}{id_len:pos | id_len < 256} (id: $A.arr(byte, id_loc, id_len), id_len: int id_len, text: !kept): void

implement kept_text_n (id, id_len, text) = let
  val @(bytes, text_len) = kept_copy(text)
in
  if text_len > 0 then ui_text_n_buf(id, id_len, bytes, text_len)
  else let
    val () = $A.free<byte>(bytes)
  in ui_text_n(id, id_len, "Untitled") end
end

(* Each catalogue's row from index on: its name, which opens it, and
   Remove *)
fun _rows {count:nat}{index:nat} .<count>. (list: !catalogues(count), index: int index): void =
  case+ list of
  | CataloguesNil() => ()
  | @CatalogueCons(_, name, _, rest) => let
      val @(row, row_len) = nid_make("catalogue-row", index)
      val () = ui_add_n("catalogues-list", row, row_len, TDiv)
      val @(row, row_len) = nid_make("catalogue-row", index)
      val () = ui_attr_n(row, row_len, AClass, "srow")
      val @(row, row_len) = nid_make("catalogue-row", index)
      val @(opener, opener_len) = nid_make("catalogue-open", index)
      val () = ui_btn_nn(row, row_len, opener, opener_len, "link")
      val @(opener, opener_len) = nid_make("catalogue-open", index)
      val () = kept_text_n(opener, opener_len, name)
      val @(row, row_len) = nid_make("catalogue-row", index)
      val @(opener, opener_len) = nid_make("catalogue-open", index)
      val () = ui_labelled_nn(row, row_len, NGroup, opener, opener_len)
      val @(row, row_len) = nid_make("catalogue-row", index)
      val @(remove, remove_len) = nid_make("drop-catalogue", index)
      val () = ui_text_btn_nn(row, row_len, remove, remove_len, "btn", "Remove")
      val () = _rows(rest, index + 1)
      prval () = fold@(list)
    in end

fn _render (): void = let
  val () = ui_clear("catalogues-list")
  val+ ~CatalogueCell(list, next_id) = _list_take()
  val count = _list_count(list)
  val () = _rows(list, 0)
  val () = _list_put(CatalogueCell(list, next_id))
in ui_show("catalogues-none", count = 0) end

fn _list_say {text_len:pos | text_len < 256} (text: string text_len): void = ui_text("catalogues-status", text)

(* The address of the catalogue at index of the list (none past its end) *)
#pub fn catalogue_address (index: int): kept

implement catalogue_address (index) = let
  val+ ~CatalogueCell(list, next_id) = _list_take()
  val address = _list_address_at(list, index)
  val () = _list_put(CatalogueCell(list, next_id))
in address end

(* Opens the catalogues panel *)
#pub fn catalogue_panel_open (): void

implement catalogue_panel_open () = let
  val () = _render()
  val () = ui_text_buf("catalogues-status", $A.alloc<byte>(1), 0)
  val () = layer_open(LCatalogues())
in ui_focus("catalogues-done") end

(* What the field id holds, its ends trimmed: at most most bytes *)
#pub fn field_kept {id_len:pos | id_len < 256}{most:pos | most <= 4096} (id: string id_len, most: int most): kept

implement field_kept (id, most) = let
  val @(id_bytes, id_len) = _literal_bytes(id)
  val @(id_frozen, id_borrowed) = $A.freeze<byte>(id_bytes)
  val value = $DR.read_input_value(id_borrowed, id_len)
  val () = release_bytes(id_frozen, id_borrowed)
in
  case+ value of
  | ~$R.none() => kept_none()
  | ~$R.some(blob) => let
      val value_len = $DC.blob_len(blob)
    in
      if value_len <= 0 then let val () = $DC.blob_free(blob) in kept_none() end
      else if value_len > most then let val () = $DC.blob_free(blob) in kept_none() end
      else let
        val bytes = $A.alloc<byte>(value_len)
        val () = $DC.blob_read(blob, 0, bytes, value_len)
        val () = $DC.blob_free(blob)
        val start = _trim_start(bytes, 0, value_len)
        val stop = _trim_end(bytes, start, value_len)
        val text_len = stop - start
        val text = $A.alloc<byte>(text_len + 1)
        val () = _copy(bytes, start, text, 0, text_len, 0)
        val () = $A.free<byte>(bytes)
      in Kept(text, text_len) end
    end
end

(* Whether text is an http or https address *)
fn _is_web (text: !kept): bool = let
  val+ @Kept(bytes, text_len) = text
  val web = url_is_web(bytes, text_len)
  prval () = fold@(text)
in web end

(* Adds the catalogue the fields name: its address must be an http or
   https one; with no name, its address names it *)
#pub fn catalogue_add (): void

implement catalogue_add () = let
  val name = field_kept("catalogue-name", 256)
  val address = field_kept("catalogue-address", 2048)
in
  if ~_is_web(address) then let
    val () = kept_free(name)
    val () = kept_free(address)
  in _list_say("Give the catalogue a URL that starts with https:// or http://.") end
  else let
    val+ ~CatalogueCell(list, next_id) = _list_take()
    val count = _list_count(list)
  in
    if count >= MOST_CATALOGUES then let
      val () = _list_put(CatalogueCell(list, next_id))
      val () = kept_free(name)
      val () = kept_free(address)
    in _list_say("There are too many catalogues.") end
    else let
      val name = (if kept_len(name) > 0 then name else let val () = kept_free(name) in kept_dup(address) end): kept
      val list = _list_join(list, CatalogueCons(next_id, name, address, CataloguesNil()))
      val () = _list_put(CatalogueCell(list, next_id + 1))
      val () = _save()
      val () = _render()
      val () = app_catalogue_form()
    in _list_say("Catalogue added.") end
  end
end

(* Catalogue id, removed for good once its Undo is not taken *)
fn _forget (id: int): void = let
  val+ ~RemovedCell(removed) = _removed_take()
  val @(left, taken) = _list_take_id(removed, id)
  val () = _list_free(taken)
  val () = _removed_put(RemovedCell(left))
in _save() end

(* Catalogue id put back at index *)
fn _restore (id: int, index: int): void = let
  val+ ~RemovedCell(removed) = _removed_take()
  val @(left, taken) = _list_take_id(removed, id)
  val () = _removed_put(RemovedCell(left))
  val+ ~CatalogueCell(list, next_id) = _list_take()
  val () = _list_put(CatalogueCell(_list_insert(list, index, taken), next_id))
  val () = _render()
in _save() end

(* Removes the catalogue at index of the panel's list: at once, and
   offered back by the Undo toast *)
#pub fn catalogue_remove (index: int): void

implement catalogue_remove (index) = let
  val+ ~CatalogueCell(list, next_id) = _list_take()
  val id = _list_id_at(list, index)
  val @(left, taken) = _list_take_at(list, index)
  val () = _list_put(CatalogueCell(left, next_id))
  val+ ~RemovedCell(removed) = _removed_take()
  val () = _removed_put(RemovedCell(_list_join(removed, taken)))
in
  if id < 0 then ()
  else let
    val () = _render()
    val () = _save()
  in undo_offer("Catalogue removed", lam () => _restore(id, index), lam () => _forget(id)) end
end

(* ============================================================
   The backup: the catalogues' names and addresses
   ============================================================ *)

#define JSON_ENTRY_MOST 49200

fn _json_kept {l:agz}{owner:addr}{n:nat}{at:nat | at + 2 + 6 * 4096 <= n}
  (out: !$A.arrx(byte, l, n, owner), at: int at, text: !kept): [stop:nat | stop <= at + 2 + 6 * 4096] int stop = let
  val+ @Kept(bytes, text_len) = text
  val stop = jw_str(out, at, bytes, text_len)
  prval () = fold@(text)
in stop end

fun _json_entries {l:agz}{owner:addr}{n:nat}{count:nat}{at:nat | at + JSON_ENTRY_MOST * count <= n} .<count>.
  (out: !$A.arrx(byte, l, n, owner), at: int at, list: !catalogues(count), first: bool): [stop:nat | stop <= at + JSON_ENTRY_MOST * count] int stop =
  case+ list of
  | CataloguesNil() => at
  | @CatalogueCons(_, name, address, rest) => let
      val next = (if first then jw_lit(out, at, "{\"name\":") else jw_lit(out, at, ",{\"name\":")): [next:nat | at + 8 <= next; next <= at + 9] int next
      val next = _json_kept(out, next, name): [next:nat | next <= at + 24587] int next
      val next = jw_lit(out, next, ",\"url\":"): [next:nat | next <= at + 24594] int next
      val next = _json_kept(out, next, address): [next:nat | next <= at + 49172] int next
      val next = jw_lit(out, next, "}"): [next:nat | next <= at + 49173] int next
      val stop = _json_entries(out, next, rest, false)
      prval () = fold@(list)
    in stop end

(* ,"catalogues":[{"name": ..., "url": ...}, ...] *)
#pub fn catalogue_backup_json (): jchunk

implement catalogue_backup_json () = let
  val+ ~CatalogueCell(list, next_id) = _list_take()
  val count = _list_count(list)
in
  if count > 1000 then let val () = _list_put(CatalogueCell(list, next_id)) in JNone() end
  else case+ piece_new(32 + JSON_ENTRY_MOST * count) of
  | ~NoPiece() => let val () = _list_put(CatalogueCell(list, next_id)) in JNone() end
  | ~Piece(owner, out) => let
      val next = jw_lit(out, 0, ",\"catalogues\":[")
      val next = _json_entries(out, next, list, true)
      val next = jw_lit(out, next, "]")
      val () = _list_put(CatalogueCell(list, next_id))
    in JChunk(owner, out, next) end
end

end (* #target wasm *)
