(* chapter_hrefs -- the names of a book's chapters, kept to find them
   again in a corrected file (quire#425).

   A book's chapters are numbered in spine order, and a corrected file
   can add, remove or reorder them, so a place or a note kept as a
   chapter number points at another chapter. The chapter's href (its
   spine item's file, as the package names it) is what the chapter is:
   a record under the book's key 'h' holds each chapter's href, one per
   line (a chapter that names no file is an empty line, so the lines are
   numbered as the chapters are), written when a book is imported and when
   it is opened. A replace reads the old file's record and the new
   file's hrefs, and a chapter map says where each old chapter went. *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use str as S
#use xml-tree as X

staload "epub_xml.sats"
staload "book.sats"
staload "mem.sats"
staload "library.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"

(* A record's most bytes: what a read of storage gives whole *)
#define HREFS_MOST 1048576

(* The line feed that ends each href *)
#define LINE_FEED 10

(* ============================================================
   The hrefs of a book
   ============================================================ *)

(* The chapters' hrefs, one per line, or none (a package with none, or
   with more than the record holds) *)
#pub datavtype hrefs =
  | {l:agz}{n:pos | n <= 1048576} Hrefs of ($A.arr(byte, l, n), int n)
  | NoHrefs of ()

#pub fn hrefs_free (found: hrefs): void

implement hrefs_free (found) =
  case+ found of
  | ~Hrefs(bytes, _) => $A.free<byte>(bytes)
  | ~NoHrefs() => ()

implement $P.dispose<hrefs>(found) = hrefs_free(found)

(* source[j, count) copied to target[j, count) *)
fun _copy_bytes {source_loc,target_loc:agz}{source_size,target_size:pos}{count:nat | count <= source_size; count <= target_size}{j:nat | j <= count} .<count - j>.
  (source: !$A.arr(byte, source_loc, source_size), target: !$A.arr(byte, target_loc, target_size), count: int count, j: int j): void =
  if j >= count then ()
  else let
    val () = $A.set<byte>(target, j, $A.get<byte>(source, j))
  in _copy_bytes(source, target, count, j + 1) end

(* A copy of found *)
#pub fn hrefs_copy (found: !hrefs): hrefs

implement hrefs_copy (found) =
  case+ found of
  | Hrefs(bytes, size) => let
      val copy = $A.alloc<byte>(size)
      val () = _copy_bytes(bytes, copy, size, 0)
    in Hrefs(copy, size) end
  | NoHrefs() => NoHrefs()

(* The bytes of the hrefs of the first count spine items of the package,
   as the reader numbers its chapters (_spine_chapters in reader.bats):
   an item that names no file is a chapter with an empty line, one whose
   file is not a content document (and has no fallback that is) is not a
   chapter. The length is summed first *)
fun _length {l:agz}{n:pos}{tree_size:nat}{item,count:nat | item <= count} .<count - item>.
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size),
   item: int item, count: int count, sum: int): int =
  if item >= count then sum
  else if sum > HREFS_MOST then sum
  else (case+ find_chapter_href_n(data, data_len, nodes, item) of
    | ~xspan_none() => _length(data, data_len, nodes, item + 1, count, sum + 1)
    | ~xspan_at(_, _) =>
      (case+ find_chapter_shown_href_n(data, data_len, nodes, item) of
       | ~xspan_none() => _length(data, data_len, nodes, item + 1, count, sum)
       | ~xspan_at(_, href_len) => _length(data, data_len, nodes, item + 1, count, sum + href_len + 1)))

fun _fill {l:agz}{n:pos}{tree_size:nat}{target_loc:agz}{size:pos}{item,count:nat | item <= count}{position:nat | position <= size} .<count - item>.
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size),
   target: !$A.arr(byte, target_loc, size), size: int size, item: int item, count: int count, position: int position): void =
  if item >= count then ()
  else (case+ find_chapter_href_n(data, data_len, nodes, item) of
    | ~xspan_none() =>
      if position >= size then ()
      else let
        val () = $A.set<byte>(target, position, $A.int2byte(LINE_FEED))
      in _fill(data, data_len, nodes, target, size, item + 1, count, position + 1) end
    | ~xspan_at(_, _) =>
      (case+ find_chapter_shown_href_n(data, data_len, nodes, item) of
       | ~xspan_none() => _fill(data, data_len, nodes, target, size, item + 1, count, position)
       | ~xspan_at(href_offset, href_len) =>
         if position + href_len + 1 > size then ()
         else let
           val () = $S.copy_from_borrow(data, href_offset, data_len, target, position, size, href_len)
           val () = $A.set<byte>(target, position + href_len, $A.int2byte(LINE_FEED))
         in _fill(data, data_len, nodes, target, size, item + 1, count, position + href_len + 1) end))

(* The hrefs of the package data[0, data_len) (parsed into nodes) *)
#pub fn hrefs_of_package {l:agz}{n:pos}{tree_size:nat}
  (data: !$A.borrow(byte, l, n), data_len: int n, nodes: !$X.xml_node_list(n, tree_size)): hrefs

implement hrefs_of_package (data, data_len, nodes) = let
  val count = count_spine_items(data, nodes)
  val total = g1ofg0(_length(data, data_len, nodes, 0, count, 0))
in
  if total <= 0 then NoHrefs()
  else if total > HREFS_MOST then NoHrefs()
  else let
    val bytes = $A.alloc<byte>(total)
    val () = _fill(data, data_len, nodes, bytes, total, 0, count, 0)
  in Hrefs(bytes, total) end
end

(* ============================================================
   Lines
   ============================================================ *)

(* Where line target (from 0) starts in blob[0, n), scanning from
   position, which starts line `line`; n when there is no such line *)
fun _line_start {l:agz}{n:pos}{position:nat | position <= n}{line:nat} .<n - position>.
  (blob: !$A.arr(byte, l, n), n: int n, position: int position, line: int line, target: int): [start:nat | start <= n] int start =
  if line >= target then position
  else if position >= n then n
  else if byte2int0($A.get<byte>(blob, position)) = LINE_FEED then _line_start(blob, n, position + 1, line + 1, target)
  else _line_start(blob, n, position + 1, line, target)

(* The length of the line that starts at start in blob[0, n), without
   its line feed *)
fun _line_length {l:agz}{n:pos}{start:nat | start <= n}{j:nat | start + j <= n} .<n - start - j>.
  (blob: !$A.arr(byte, l, n), n: int n, start: int start, j: int j): [len:nat | start + len <= n] int len =
  if start + j >= n then j
  else if byte2int0($A.get<byte>(blob, start + j)) = LINE_FEED then j
  else _line_length(blob, n, start, j + 1)

(* Whether a[a_start, a_start + len) and b[b_start, b_start + len) are
   the same bytes *)
fun _same_bytes {a_loc,b_loc:agz}{a_size,b_size:pos}{a_start,b_start,len:nat | a_start + len <= a_size; b_start + len <= b_size}{j:nat | j <= len} .<len - j>.
  (a: !$A.arr(byte, a_loc, a_size), a_start: int a_start, b: !$A.arr(byte, b_loc, b_size), b_start: int b_start, len: int len, j: int j): bool =
  if j >= len then true
  else if byte2int0($A.get<byte>(a, a_start + j)) <> byte2int0($A.get<byte>(b, b_start + j)) then false
  else _same_bytes(a, a_start, b, b_start, len, j + 1)

(* The number of the line of b[0, b_size) that is a[a_start, a_start +
   len), from line on, scanning from position; -1 when none is *)
fun _find_line {a_loc,b_loc:agz}{a_size,b_size:pos}{a_start,len:nat | a_start + len <= a_size}{position:nat | position <= b_size}{line:nat} .<b_size - position>.
  (a: !$A.arr(byte, a_loc, a_size), a_start: int a_start, len: int len,
   b: !$A.arr(byte, b_loc, b_size), b_size: int b_size, position: int position, line: int line): [found:int | found >= ~1] int found =
  if position >= b_size then ~1
  else let
    val line_len = _line_length(b, b_size, position, 0)
  in
    if line_len = len then
      (if _same_bytes(a, a_start, b, position, len, 0) then line
       else if position + line_len + 1 > b_size then ~1
       else _find_line(a, a_start, len, b, b_size, position + line_len + 1, line + 1))
    else if position + line_len + 1 > b_size then ~1
    else _find_line(a, a_start, len, b, b_size, position + line_len + 1, line + 1)
  end

(* The number of the line of new[0, new_size) that is the same href as
   line old_index of old[0, old_size), or -1 when there is none (or the
   old line is empty: a chapter that names no file is no chapter to find) *)
fn _new_index {old_loc,new_loc:agz}{old_size,new_size:pos}
  (old: !$A.arr(byte, old_loc, old_size), old_size: int old_size, old_index: int,
   new: !$A.arr(byte, new_loc, new_size), new_size: int new_size): [found:int | found >= ~1] int found =
  if old_index < 0 then ~1
  else let
    val start = _line_start(old, old_size, 0, 0, old_index)
  in
    if start >= old_size then ~1
    else let
      val len = _line_length(old, old_size, start, 0)
    in
      if len <= 0 then ~1
      else _find_line(old, start, len, new, new_size, 0, 0)
    end
  end

(* The number of lines of blob[0, n), counting from position *)
fun _count_lines {l:agz}{n:pos}{position:nat | position <= n} .<n - position>.
  (blob: !$A.arr(byte, l, n), n: int n, position: int position, count: int): int =
  if position >= n then count
  else if byte2int0($A.get<byte>(blob, position)) = LINE_FEED then _count_lines(blob, n, position + 1, count + 1)
  else _count_lines(blob, n, position + 1, count)

(* The number of chapters found.hrefs names; -1 when it names none *)
#pub fn hrefs_count (found: !hrefs): Int

implement hrefs_count (found) =
  case+ found of
  | Hrefs(bytes, size) => g1ofg0(_count_lines(bytes, size, 0, 0))
  | NoHrefs() => ~1

(* Whether a[0, a_size) and b[0, b_size) are the same bytes *)
fn _same_blobs {a_loc,b_loc:agz}{a_size,b_size:pos}
  (a: !$A.arr(byte, a_loc, a_size), a_size: int a_size, b: !$A.arr(byte, b_loc, b_size), b_size: int b_size): bool =
  if a_size <> b_size then false
  else _same_bytes(a, 0, b, 0, a_size, 0)

(* ============================================================
   Where the chapters went
   ============================================================ *)

(* Where the chapters of a book's old file went in its new one. By
   their hrefs when both files' are known; else, when only the count of
   chapters is (the old file's hrefs were not kept: a book not opened
   since they were), by their numbers, which holds only if the count is
   the same. *)
#pub datavtype chapter_map =
  | {old_loc,new_loc:agz}{old_size,new_size:pos}
    MapByHref of ($A.arr(byte, old_loc, old_size), int old_size, $A.arr(byte, new_loc, new_size), int new_size)
  | MapByNumber of (int, int)

#pub fn chapter_map_free (map: chapter_map): void

implement chapter_map_free (map) =
  case+ map of
  | ~MapByHref(old, _, new, _) => let
      val () = $A.free<byte>(old)
    in $A.free<byte>(new) end
  | ~MapByNumber(_, _) => ()

(* The map from an old file's hrefs (none: not kept) and its count of
   chapters to a new file's hrefs and count of chapters; the hrefs are
   consumed *)
#pub fn chapter_map_make (old: hrefs, old_count: int, new: hrefs, new_count: int): chapter_map

implement chapter_map_make (old, old_count, new, new_count) =
  case+ old of
  | ~NoHrefs() => let
      val () = hrefs_free(new)
    in MapByNumber(old_count, new_count) end
  | ~Hrefs(old_bytes, old_size) =>
    (case+ new of
     | ~NoHrefs() => let
         val () = $A.free<byte>(old_bytes)
       in MapByNumber(old_count, new_count) end
     | ~Hrefs(new_bytes, new_size) => MapByHref(old_bytes, old_size, new_bytes, new_size))

(* The number of chapters of the new file, when the map knows it by
   its hrefs; else the count it was made with *)
#pub fn chapter_map_new_count (map: !chapter_map): Int

implement chapter_map_new_count (map) =
  case+ map of
  | MapByHref(_, _, new, new_size) => g1ofg0(_count_lines(new, new_size, 0, 0))
  | MapByNumber(_, new_count) => g1ofg0(new_count)

(* The number of chapters of the old file *)
fn _old_count (map: !chapter_map): int =
  case+ map of
  | MapByHref(old, old_size, _, _) => _count_lines(old, old_size, 0, 0)
  | MapByNumber(old_count, _) => old_count

(* Whether the new file's chapters are the old file's, the same hrefs in
   the same order (a map by number, of the same count, is taken to be) *)
#pub fn chapter_map_unchanged (map: !chapter_map): bool

implement chapter_map_unchanged (map) =
  case+ map of
  | MapByHref(old, old_size, new, new_size) => _same_blobs(old, old_size, new, new_size)
  | MapByNumber(old_count, new_count) => old_count = new_count

(* Where old chapter old_index (from 0) is in the new file: its number, or -1
   when the new file has no chapter of its href (or, by number, a
   different count of chapters) *)
#pub fn chapter_map_target (map: !chapter_map, old_index: Int): Int

implement chapter_map_target (map, old_index) =
  case+ map of
  | MapByHref(old, old_size, new, new_size) => _new_index(old, old_size, old_index, new, new_size)
  | MapByNumber(old_count, new_count) =>
    if old_index < 0 then ~1
    else if old_count <> new_count then ~1
    else if old_index >= new_count then ~1
    else old_index

(* Where the place in old chapter old_index is in the new file: its
   chapter when it is there; else the chapter of the same number when
   there are as many chapters; else the first *)
#pub fn chapter_map_place (map: !chapter_map, old_index: Int): Int

implement chapter_map_place (map, old_index) = let
  val target = chapter_map_target(map, old_index)
in
  if target >= 0 then target
  else if old_index >= 0 then (if _old_count(map) = chapter_map_new_count(map) then old_index else 0)
  else 0
end

(* ============================================================
   Stored under 'h'
   ============================================================ *)

(* The hrefs record of book (id_high, id_low) is kept *)
fn _key_of (id_high: Int, id_low: Int): [l:agz] $A.arr(byte, l, 15) = lib_key(104, id_high, id_low)

(* Keeps found as the hrefs of the book (id_high, id_low), consumed *)
#pub fn hrefs_store (id_high: Int, id_low: Int, found: hrefs): void

implement hrefs_store (id_high, id_low, found) =
  case+ found of
  | ~NoHrefs() => ()
  | ~Hrefs(bytes, size) => let
      val @(bytes_frozen, bytes_borrow) = $A.freeze<byte>(bytes)
      val @(key_frozen, key_bytes) = $A.freeze<byte>(_key_of(id_high, id_low))
      (* ignored: a record not kept costs the next replace its re-anchoring by
         name, which then goes by number *)
      val () = $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 15, bytes_borrow, size), llam(_) => ())
      val () = release_bytes(key_frozen, key_bytes)
    in release_bytes(bytes_frozen, bytes_borrow) end

(* The hrefs kept for the book (id_high, id_low): none when none are
   kept or they could not be read *)
#pub fn hrefs_load (id_high: Int, id_low: Int): $P.promise(hrefs, $P.Chained)

implement hrefs_load (id_high, id_low) = let
  val @(key_frozen, key_bytes) = $A.freeze<byte>(_key_of(id_high, id_low))
  val stored = $IDB.idb_get(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$IDB.lookup><hrefs>(stored, llam(found) =>
    case+ lookup_bytes(found) of
    | ~NothingStored() => $P.ret<hrefs>(NoHrefs())
    | ~StoredUnreadable() => $P.ret<hrefs>(NoHrefs())
    | ~StoredBytes(bytes, size) => $P.ret<hrefs>(Hrefs(bytes, size)))
end

end (* #target wasm *)
