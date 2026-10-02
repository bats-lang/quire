(* import -- EPUB files into the library, and stored books reopened *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR
#use promise as P
#use result as R
#use sha256 as SHA
#use str as S
#use xml-tree as X
#use zip as Z

staload "ui.sats"
staload "notice.sats"
staload "modal.sats"
staload "book.sats"
staload "paths.sats"
staload "epub_xml.sats"
staload "entity.sats"
staload "library.sats"
staload "backup.sats"
staload "mem.sats"
staload "clock.sats"
staload "app.sats"
staload "platform.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload "storage.sats"
staload BF = "wasm.bats-packages.dev/bridge/src/file.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload BD = "wasm.bats-packages.dev/bridge/src/decompress.sats"
staload BE = "wasm.bats-packages.dev/bridge/src/external.sats"

(* ============================================================
   What the open book is
   ============================================================ *)

(* The key of the library book in the book cell (0 when it holds none
   of them): an import leaves its book there, and opening a book from
   the library puts it there *)
val _open_key = ref<int>(0)

#pub fn open_key_get (): int
implement open_key_get () = !_open_key

#pub fn open_key_set (key: int): void
implement open_key_set (key) = !_open_key := key

(* ============================================================
   Progress and errors
   ============================================================ *)

(* The name of the file being imported (for its error banner) *)
datavtype kept_name =
  | {l:agz}{n:pos | n <= 200} KeptName of ($A.arr(byte, l, n), int n)
  | NoKeptName of ()

val _kept_name = ref<kept_name>(NoKeptName())

fn _kept_name_put (name: kept_name): void = let
  var previous: kept_name = name
  val () = ref_exch_elt<kept_name>(_kept_name, previous)
in
  case+ previous of
  | ~KeptName(name_bytes, _) => $A.free<byte>(name_bytes)
  | ~NoKeptName() => ()
end

fn _kept_name_take (): kept_name = let
  var name: kept_name = NoKeptName()
  val () = ref_exch_elt<kept_name>(_kept_name, name)
in name end

fn _at_most_200 {name_len:pos} (name_len: int name_len): [kept_len:pos | kept_len <= 200; kept_len <= name_len] int kept_len =
  if name_len > 200 then 200 else name_len

(* Keeps book_file's name (its first 200 bytes) for the banner *)
fn _keep_name (name: $R.option([name_size:nat] $BD.dblob(name_size))): void =
  case+ name of
  | ~$R.none() => _kept_name_put(NoKeptName())
  | ~$R.some(blob) => let
      val name_len = $BD.blob_len(blob)
    in
      if name_len <= 0 then let val () = $BD.blob_free(blob) in _kept_name_put(NoKeptName()) end
      else let
        val kept_len = _at_most_200(name_len)
        val name_bytes = $A.alloc<byte>(kept_len)
        val () = $BD.blob_read(blob, 0, name_bytes, kept_len)
        val () = $BD.blob_free(blob)
      in _kept_name_put(KeptName(name_bytes, kept_len)) end
    end

fn _keep_name_of {file_size:nat} (book_file: !$BF.infile(file_size)): void =
  _keep_name($BF.file_name(book_file))

(* text's bytes at buffer[start, start + text_len), from position on *)
fun _put_text {l:agz}{n:pos}{text_len:nat}{start:nat | start + text_len <= n}{position:nat | position <= text_len} .<text_len - position>.
  (buffer: !$A.arr(byte, l, n), start: int start, text: string text_len, text_len: int text_len, position: int position): int(start + text_len) =
  if position >= text_len then start + text_len
  else let
    val () = $A.set<byte>(buffer, start + position, $A.int2byte($AR.byte_of_char(string_get_at(text, position))))
  in _put_text(buffer, start, text, text_len, position + 1) end

fn _put_string {l:agz}{n:pos}{text_len:nat}{start:nat | start + text_len <= n}
  (buffer: !$A.arr(byte, l, n), start: int start, text: string text_len): int(start + text_len) =
  _put_text(buffer, start, text, g1u2i(string1_length(text)), 0)

(* source[0, count) to target[start, start + count), from position on *)
fun _copy_into {source_loc,target_loc:agz}{source_size,count:nat | count <= source_size}{target_size:nat}{start:nat | start + count <= target_size}{position:nat | position <= count} .<count - position>.
  (source: !$A.arr(byte, source_loc, source_size), count: int count, target: !$A.arr(byte, target_loc, target_size), start: int start, position: int position): void =
  if position >= count then ()
  else let
    val () = $A.set<byte>(target, start + position, $A.get<byte>(source, position))
  in _copy_into(source, count, target, start, position + 1) end

(* The kept name at buffer[0, name_len), or "The file"; name_len *)
fn _kept_name_into {l:agz} (buffer: !$A.arr(byte, l, 512)): [name_len:nat | name_len <= 200] int name_len =
  case+ _kept_name_take() of
  | ~KeptName(name_bytes, name_len) => let
      val () = _copy_into(name_bytes, name_len, buffer, 0, 0)
      val () = $A.free<byte>(name_bytes)
    in name_len end
  | ~NoKeptName() => _put_string(buffer, 0, "The file")

(* Shows the error banner for the file being imported *)
fn _error (): void = let
  val message = $A.alloc<byte>(512)
  val name_end = _kept_name_into(message)
  val text_end = _put_string(message, name_end, " could not be imported. Quire supports .epub files without DRM.")
  val () = notice_error_buf(message, text_end)
in ui_show("import-progress", false) end

(* The import card: stage text and progress in percent *)
fn _stage {text_len:pos | text_len < 256} (text: string text_len, percent: [percent:nat | percent <= 100] int percent): void = let
  val () = ui_show("import-progress", true)
  val () = ui_text("import-status", text)
in ui_place("import-fill", PWidth, percent * 10) end

fn _stage_name (): void =
  case+ _kept_name_take() of
  | ~KeptName(name_bytes, name_len) => let
      val name_copy = $A.alloc<byte>(name_len)
      val () = _copy_into(name_bytes, name_len, name_copy, 0, 0)
      val () = ui_text_buf("import-count", name_copy, name_len)
    in _kept_name_put(KeptName(name_bytes, name_len)) end
  | ~NoKeptName() => let
      val () = ui_text("import-count", "EPUB")
    in _kept_name_put(NoKeptName()) end

(* ============================================================
   The file's identity: its SHA-256
   ============================================================ *)

fun _hash_loop {l:agz}{file_size:nat}{offset:nat | offset <= file_size} .<file_size - offset>.
  (book_file: !$BF.infile(file_size), file_size: int file_size, offset: int offset, hasher: !$SHA.ctx, chunk: !$A.arr(byte, l, 1048576)): void =
  if offset >= file_size then ()
  else let
    val chunk_len = (if file_size - offset < 1048576 then file_size - offset else 1048576): [chunk_len:pos | chunk_len <= 1048576; offset + chunk_len <= file_size] int chunk_len
    val () = $BF.file_read(book_file, offset, chunk, chunk_len)
    val () = $SHA.update(hasher, chunk, chunk_len)
  in _hash_loop(book_file, file_size, offset + chunk_len, hasher, chunk) end

fn _file_id {file_size:nat} (book_file: !$BF.infile(file_size), file_size: int file_size): @(Int, Int) = let
  val hasher = $SHA.init()
  val chunk = $A.alloc<byte>(1048576)
  val () = _hash_loop(book_file, file_size, 0, hasher, chunk)
  val () = $A.free<byte>(chunk)
  val hex_digest = $A.alloc<byte>(64)
  val () = $SHA.finish(hasher, hex_digest)
  val id = lib_id_of_hex(hex_digest)
  val () = $A.free<byte>(hex_digest)
in id end

(* ============================================================
   Opening the archive: container.xml, then the OPF
   ============================================================ *)

(* What to do with the OPF once it is read: nothing (a stored book
   reopened), add a new book to the library, or replace the stored file
   of library book library_index *)
datatype import_mode = Reopen | AddNew | Replace

fn _is_reopen (mode: import_mode): bool =
  case+ mode of Reopen() => true | AddNew() => false | Replace() => false

(* Why an archive could not be opened: no container.xml, or one that
   could not be read; no package (OPF) path in it, no package there, or
   one that could not be read; the book not finished, or not put in the
   library *)
datatype archive_failure =
  | NoContainer | ContainerNotRead | NoPackagePath | NoPackage | PackageNotRead | NotFinished | NotInLibrary

(* How opening an archive went: a book added or replaced (its key), a
   stored book reopened, or a failure *)
datavtype archive_outcome =
  | BookAdded of Int
  | BookReopened of ()
  | ArchiveFailed of archive_failure

implement $P.dispose<archive_outcome>(outcome) =
  case+ outcome of ~BookAdded(_) => () | ~BookReopened() => () | ~ArchiveFailed(_) => ()

(* target[6 + position, 6 + count) := source[position, count) *)
fun _put_after_head {source_loc,target_loc:agz}{source_size,target_size:pos}{count:nat | count <= source_size; count + 6 <= target_size}{position:nat | position <= count} .<count - position>.
  (source: !$A.arr(byte, source_loc, source_size), target: !$A.arr(byte, target_loc, target_size), count: int count, position: int position): void =
  if position >= count then ()
  else let
    val () = $A.set<byte>(target, 6 + position, $A.get<byte>(source, position))
  in _put_after_head(source, target, count, position + 1) end

(* The accessibility metadata, stored under 'y' for book
   (id_high, id_low): "Y1",
   its flags (opf_a11y's, 4 bytes), then its summary's text with its
   references decoded *)
fn _store_a11y {l:agz}{n:pos}
  (data: !$A.borrow(byte, l, n), flags: int, summary: xspan(n), id_high: Int, id_low: Int): void = let
  val @(summary_offset, summary_len) = (case+ summary of
    | ~xspan_at(offset, span_len) => (if span_len < 65536 then @(offset, span_len) else @(0, 0))
    | ~xspan_none() => @(0, 0)): [offset,span_len:nat | offset + span_len <= n; span_len < 65536] @(int offset, int span_len)
  val decoded = $A.alloc<byte>(summary_len + 1)
  val decoded_len = decode_text(data, summary_offset, summary_len, decoded)
  val record = $A.alloc<byte>(decoded_len + 6)
  val () = $A.write_text(record, 0, $A.text_lit("Y1"), 2)
  val () = $A.write_i32(record, 2, flags)
  val () = _put_after_head(decoded, record, decoded_len, 0)
  val () = $A.free<byte>(decoded)
  val @(record_frozen, record_bytes) = $A.freeze<byte>(record)
  val key = lib_key(121, id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  (* ignored: losing the summary only hides it until the next import,
     and a full storage is told by the saves that matter *)
  val () = $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 15, record_bytes, decoded_len + 6), llam(_) => ())
  val () = release_bytes(key_frozen, key_bytes)
in release_bytes(record_frozen, record_bytes) end

(* The cover, the entry named dir(opf) + href, stored under 'c' for book
   (id_high, id_low); its type, NotAnImage when there is none *)
fn _store_cover {file_size:pos}{l:agz}{n:pos}{href_offset,href_len:nat | href_offset + href_len <= n}{opf_name_offset:nat}{opf_name_len:pos | opf_name_offset + opf_name_len <= file_size; opf_name_len < 65536}
  (serial: int, file_size: int file_size, opf_name_offset: int opf_name_offset, opf_name_len: int opf_name_len,
   data: !$A.borrow(byte, l, n), n: int n, href_offset: int href_offset, href_len: int href_len, id_high: Int, id_low: Int): image_type = let
  val href_path_len = src_end(data, href_offset, href_len)
in
  if href_path_len <= 0 then NotAnImage()
  else if href_path_len >= 65536 then NotAnImage()
  else let
    val opf_name = $A.alloc<byte>(opf_name_len)
    val _ = book_read(serial, file_size, opf_name_offset, opf_name, opf_name_len)
    val dir_len = path_dir_end(opf_name, opf_name_len)
    val () = $A.free<byte>(opf_name)
    val path_size = dir_len + href_path_len
    val path = $A.alloc<byte>(path_size)
    val _ = book_read(serial, file_size, opf_name_offset, path, dir_len)
    val () = $S.copy_from_borrow(data, href_offset, n, path, dir_len, path_size, href_path_len)
    val resolved_len = path_norm(path, path_size)
  in
    if resolved_len <= 0 then let val () = $A.free<byte>(path) in NotAnImage() end
    else let
      val exact = $A.alloc<byte>(resolved_len)
      val path = $S.copy_arr_region(path, 0, path_size, exact, resolved_len, resolved_len)
      val () = $A.free<byte>(path)
      val @(exact_frozen, exact_bytes) = $A.freeze<byte>(exact)
      val image = image_type_of(exact_bytes, resolved_len)
      val got = book_zip_read(serial, file_size, exact_bytes, resolved_len)
      val () = release_bytes(exact_frozen, exact_bytes)
    in
      case+ got of
      | ~ZipMissing() => NotAnImage()
      | ~ZipGot(owner, cover_data, cover_size, cover_method, _, _, _) =>
        case+ cover_method of
        | $Z.Stored() => let
          val @(cover_frozen, cover_bytes) = $A.freeze<byte>(cover_data)
          val key = lib_key(99, id_high, id_low)
          val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
          (* ignored: a cover not stored shows as the placeholder *)
          val () = $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 15, cover_bytes, cover_size), llam(_) => ())
          val () = release_bytes(key_frozen, key_bytes)
          val () = $A.drop<byte>(cover_frozen, cover_bytes)
          val () = piece_free(owner, $A.thaw<byte>(cover_frozen))
        in image end
        | $Z.Deflated() => let
          val @(cover_frozen, cover_bytes) = $A.freeze<byte>(cover_data)
          val decompressing = decompress(cover_bytes, cover_size, zip_compression(cover_method))
          val () = $A.drop<byte>(cover_frozen, cover_bytes)
          val () = piece_free(owner, $A.thaw<byte>(cover_frozen))
          val () = $P.finish<decompressed>(decompressing, llam(cover_inflated) =>
            case+ take_decompressed(cover_inflated) of
            | ~NoContentBytes() => ()
            | ~ContentBytes(content_owner, content, content_size) => let
                val @(content_frozen, content_bytes) = $A.freeze<byte>(content)
                val key = lib_key(99, id_high, id_low)
                val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
                (* ignored: a cover not stored shows as the placeholder *)
                val () = $P.finish<$IDB.stored>($IDB.idb_put(key_bytes, 15, content_bytes, content_size), llam(_) => ())
                val () = release_bytes(key_frozen, key_bytes)
                val () = $A.drop<byte>(content_frozen, content_bytes)
              in piece_free(content_owner, $A.thaw<byte>(content_frozen)) end)
        in image end
    end
  end
end

fn _cover_of {file_size:pos}{l:agz}{n:pos}{tree_size:nat}{opf_name_offset:nat}{opf_name_len:pos | opf_name_offset + opf_name_len <= file_size; opf_name_len < 65536}
  (mode: import_mode, serial: int, file_size: int file_size, opf_name_offset: int opf_name_offset, opf_name_len: int opf_name_len, opf_bytes: !$A.borrow(byte, l, n), n: int n,
   nodes: !$X.xml_node_list(n, tree_size), id_high: Int, id_low: Int): image_type =
  if _is_reopen(mode) then NotAnImage()
  else case+ find_cover_href(opf_bytes, n, nodes) of
  | ~xspan_at(href_offset, href_len) => _store_cover(serial, file_size, opf_name_offset, opf_name_len, opf_bytes, n, href_offset, href_len, id_high, id_low)
  | ~xspan_none() => NotAnImage()

(* The store of the book of key's file (in a new import, or over its
   old one) has ended: when it failed, the banner says so by its title.
   The book is open, but nothing can open it again once it is closed,
   so this is said each time *)
fn _title_into {l:agz} (buffer: !$A.arr(byte, l, 512), key: Int): [name_len:nat | name_len < 256] int name_len = let
  val @(title, title_len) = lib_text(lib_index_of_key(key), TitleText())
in
  if title_len > 0 then let
    val () = _copy_into(title, title_len, buffer, 0, 0)
    val () = $A.free<byte>(title)
  in title_len end
  else let
    val () = $A.free<byte>(title)
  in _put_string(buffer, 0, "This book") end
end

fn _book_store_checked (storing: $P.promise($IDB.stored, $P.Chained), key: Int): void =
  $P.finish<$IDB.stored>(storing, llam(status) =>
    case+ status of
    | $IDB.Stored() => ()
    | $IDB.NotStored() => let
      val message = $A.alloc<byte>(512)
      val name_end = _title_into(message, key)
      val text_end = _put_string(message, name_end, " is open, but could not be stored, so it will not open next time. Free some space and import it again.")
    in notice_error_buf(message, text_end) end)

(* The book's file, stored from the JS side under 'b' *)
fn _store_file (id_high: Int, id_low: Int): $P.promise($IDB.stored, $P.Chained) = let
  val key = lib_key(98, id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(key)
  val storing = book_idb_put(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in storing end

(* After the OPF of book `serial` (file_size bytes) is read: in AddNew
   adds the book to the library, in Replace updates library book
   library_index; stores the file under 'b' in both *)
fn _opf_done {file_size:pos}{l:agz}{n:pos}{compressed_offset:nat}{compressed_size:pos | compressed_offset + compressed_size <= file_size; compressed_size <= 268435456}{opf_name_offset:nat}{opf_name_len:pos | opf_name_offset + opf_name_len <= file_size; opf_name_len < 65536}
  (serial: int, file_size: int file_size, opf_bytes: !$A.borrow(byte, l, n), n: int n,
   compressed_offset: int compressed_offset, compressed_size: int compressed_size, method: $Z.compression, opf_name_offset: int opf_name_offset, opf_name_len: int opf_name_len,
   mode: import_mode, library_index: Int, id_high: Int, id_low: Int): archive_outcome = let
  val nodes = $X.parse_document(opf_bytes, n)
  val @(title, author) = walk_opf_metadata(opf_bytes, nodes)
  val cover = _cover_of(mode, serial, file_size, opf_name_offset, opf_name_len, opf_bytes, n, nodes, id_high, id_low)
  (* its series, for the library's order *)
  val @(series, series_number_found) = opf_series(opf_bytes, nodes)
  val series_number = g1ofg0(series_number_found)
  (* its accessibility metadata, for Book info *)
  val @(a11y_flags, summary) = opf_a11y(opf_bytes, nodes)
  val () = (if ~_is_reopen(mode) then _store_a11y(opf_bytes, a11y_flags, summary, id_high, id_low) else xspan_free(summary))
  val () = $X.free_nodes(nodes)
  val finished = book_finish(serial, file_size, compressed_offset, compressed_size, method, opf_name_offset, opf_name_len)
  val @(series_offset, series_len) = (case+ series of ~xspan_at(offset, span_len) => @(offset, span_len) | ~xspan_none() => @(0, 0)): [offset,span_len:nat | offset + span_len <= n] @(int offset, int span_len)
in
  if ~finished then let
    val () = xspan_free(title)
    val () = xspan_free(author)
  in ArchiveFailed(NotFinished()) end
  else case+ mode of
  | Reopen() => let
      val () = xspan_free(title)
      val () = xspan_free(author)
    in BookReopened() end
  | AddNew() => let
      val storing = _store_file(id_high, id_low)
      val @(title_offset, title_len) = (case+ title of ~xspan_at(offset, span_len) => @(offset, span_len) | ~xspan_none() => @(0, 0)): [offset,span_len:nat | offset + span_len <= n] @(int offset, int span_len)
      val @(author_offset, author_len) = (case+ author of ~xspan_at(offset, span_len) => @(offset, span_len) | ~xspan_none() => @(0, 0)): [offset,span_len:nat | offset + span_len <= n] @(int offset, int span_len)
      val key = lib_add(id_high, id_low, opf_bytes, n, title_offset, title_len, author_offset, author_len, series_offset, series_len, series_number, file_size, cover, $TM.epoch_minutes())
      val () = _book_store_checked(storing, key)
      (* the record a backup kept for it, if any *)
      val () = (if key > 0 then backup_claim(id_high, id_low) else ())
      (* the storage holds a book of the reader's now: asked to be kept *)
      val () = (if key > 0 then platform_keep_storage() else ())
    in if key > 0 then BookAdded(key) else ArchiveFailed(NotInLibrary()) end
  | Replace() => let
      val storing = _store_file(id_high, id_low)
      val () = xspan_free(title)
      val () = xspan_free(author)
      val () = (case+ lib_nums(library_index) of ~$R.none() => () | ~$R.some(record) => lib_nums_set(library_index, @{
        key = record.key, id_high = record.id_high, id_low = record.id_low, shelf = OnShelf(), added = record.added, opened = record.opened,
        chapter = record.chapter, chapters = record.chapters, page = record.page, pages = record.pages, anchor = record.anchor,
        file_size = file_size, cover = (if is_image(cover) then cover else record.cover), done = record.done, series_number = series_number, collections = record.collections, minutes_read = record.minutes_read, pages_read = record.pages_read, finished_at = record.finished_at,
        (* back on the shelf: a change sync passes on *)
        shelf_modified = (if same_shelf(record.shelf, OnShelf()) then record.shelf_modified else stamp_now()), collections_modified = record.collections_modified,
        finished_modified = record.finished_modified, minutes_elsewhere = record.minutes_elsewhere, pages_elsewhere = record.pages_elsewhere }))
      val () = lib_series_set(library_index, opf_bytes, n, series_offset, series_len)
      val key = (case+ lib_nums(library_index) of
        | ~$R.some(record) => record.key
        | ~$R.none() => ~21): Int
      val () = _book_store_checked(storing, key)
    in if key > 0 then BookAdded(key) else ArchiveFailed(NotInLibrary()) end
end

(* Reads the container.xml and OPF of book `serial` (the file_size-byte
   file just put in the book cell), then _opf_done; the promise resolves with
   how that went *)
fn _open_archive {file_size:pos} (serial: int, file_size: int file_size, mode: import_mode, library_index: Int, id_high: Int, id_low: Int)
  : $P.promise(archive_outcome, $P.Chained) = let
  var container_chars = @[char][22]('M', 'E', 'T', 'A', '-', 'I', 'N', 'F', '/', 'c', 'o', 'n', 't', 'a', 'i', 'n', 'e', 'r', '.', 'x', 'm', 'l')
  val container_name = $S.from_char_array(container_chars, 22)
  val @(name_frozen, name_bytes) = $A.freeze<byte>(container_name)
  val container = book_zip_read(serial, file_size, name_bytes, 22)
  val () = release_bytes(name_frozen, name_bytes)
in
  case+ container of
  | ~ZipMissing() => let val () = book_abandon(serial) in $P.ret<archive_outcome>(ArchiveFailed(NoContainer())) end
  | ~ZipGot(container_owner, container_data, container_size, container_method, _, _, _) => let
      val @(data_frozen, data_bytes) = $A.freeze<byte>(container_data)
      val decompressing = decompress(data_bytes, container_size, zip_compression(container_method))
      val () = $A.drop<byte>(data_frozen, data_bytes)
      val () = piece_free(container_owner, $A.thaw<byte>(data_frozen))
    in
      $P.and_then<decompressed><archive_outcome>(decompressing, llam(container_inflated) =>
        case+ take_decompressed(container_inflated) of
        | ~NoContentBytes() => let val () = book_abandon(serial) in $P.ret<archive_outcome>(ArchiveFailed(ContainerNotRead())) end
        | ~ContentBytes(xml_owner, xml_buffer, xml_size) => let
            val @(xml_frozen, xml_bytes) = $A.freeze<byte>(xml_buffer)
            val nodes = $X.parse_document(xml_bytes, xml_size)
            val opf_path = walk_rootfile_nodes(xml_bytes, nodes)
            val () = $X.free_nodes(nodes)
          in
            case+ opf_path of
            | ~xspan_none() => let
                val () = $A.drop<byte>(xml_frozen, xml_bytes)
                val () = piece_free(xml_owner, $A.thaw<byte>(xml_frozen))
                val () = book_abandon(serial)
              in $P.ret<archive_outcome>(ArchiveFailed(NoPackagePath())) end
            | ~xspan_at(opf_path_offset, opf_path_len) =>
              (* The OPF's path names a zip entry, so it is shorter than
                 65536 bytes (a zip name's limit): checked here *)
              if opf_path_len <= 0 then let
                val () = $A.drop<byte>(xml_frozen, xml_bytes)
                val () = piece_free(xml_owner, $A.thaw<byte>(xml_frozen))
                val () = book_abandon(serial)
              in $P.ret<archive_outcome>(ArchiveFailed(NoPackagePath())) end
              else if opf_path_len >= 65536 then let
                val () = $A.drop<byte>(xml_frozen, xml_bytes)
                val () = piece_free(xml_owner, $A.thaw<byte>(xml_frozen))
                val () = book_abandon(serial)
              in $P.ret<archive_outcome>(ArchiveFailed(NoPackagePath())) end
              else let
                val path_buffer = $A.alloc<byte>(opf_path_len)
                val () = $S.copy_from_borrow(xml_bytes, opf_path_offset, xml_size, path_buffer, 0, opf_path_len, opf_path_len)
                val () = $A.drop<byte>(xml_frozen, xml_bytes)
                val () = piece_free(xml_owner, $A.thaw<byte>(xml_frozen))
                val @(path_frozen, path_bytes) = $A.freeze<byte>(path_buffer)
                val opf_entry = book_zip_read(serial, file_size, path_bytes, opf_path_len)
                val () = release_bytes(path_frozen, path_bytes)
                val () = (if ~_is_reopen(mode) then _stage("Reading metadata", 60) else ())
              in
                case+ opf_entry of
                | ~ZipMissing() => let val () = book_abandon(serial) in $P.ret<archive_outcome>(ArchiveFailed(NoPackage())) end
                | ~ZipGot(opf_owner, opf_data, opf_compressed_size, opf_method, opf_offset, opf_name_offset, opf_name_len) => let
                    val @(opf_data_frozen, opf_data_bytes) = $A.freeze<byte>(opf_data)
                    val opf_decompressing = decompress(opf_data_bytes, opf_compressed_size, zip_compression(opf_method))
                    val () = $A.drop<byte>(opf_data_frozen, opf_data_bytes)
                    val () = piece_free(opf_owner, $A.thaw<byte>(opf_data_frozen))
                  in
                    $P.and_then<decompressed><archive_outcome>(opf_decompressing, llam(opf_inflated) =>
                      case+ take_decompressed(opf_inflated) of
                      | ~NoContentBytes() => let val () = book_abandon(serial) in $P.ret<archive_outcome>(ArchiveFailed(PackageNotRead())) end
                      | ~ContentBytes(opf_content_owner, opf_content, opf_size) => let
                          val @(opf_frozen, opf_bytes) = $A.freeze<byte>(opf_content)
                          val outcome = _opf_done(serial, file_size, opf_bytes, opf_size, opf_offset, opf_compressed_size, opf_method, opf_name_offset, opf_name_len, mode, library_index, id_high, id_low)
                          val () = $A.drop<byte>(opf_frozen, opf_bytes)
                          val () = piece_free(opf_content_owner, $A.thaw<byte>(opf_frozen))
                        in $P.ret<archive_outcome>(outcome) end)
                  end
              end
          end)
    end
end

(* ============================================================
   Import
   ============================================================ *)

(* A file waiting for the answer to "already in the library": the file,
   its size, id and the library book it matches, with the resolver the
   answer resolves while it is asked (Asked), and without it once it
   is answered (Answered). The resolver is linear: it is resolved once,
   by the answer, and there is no id that could name a resolver no
   longer there. *)
(* The answer to "already in the library" *)
datatype duplicate_answer = ReplaceIt | SkipIt

implement $P.dispose<duplicate_answer>(_) = ()

(* How an import went: the book added (or put back over its old file),
   by its key; it was already in the library and kept as it was; or it
   failed (why is already said) *)
#pub datavtype import_outcome = Added of Int | Kept of () | Failed of ()

(* An import's outcome let go: what it was is already reported *)
#pub fn import_outcome_free (outcome: import_outcome): void
implement import_outcome_free (outcome) =
  case+ outcome of ~Added(_) => () | ~Kept() => () | ~Failed() => ()

implement $P.dispose<import_outcome>(outcome) = import_outcome_free(outcome)

datavtype duplicate =
  | {file_size:pos} Asked of ($BF.infile(file_size), int file_size, Int, Int, Int, $P.resolver(duplicate_answer))
  | {file_size:pos} Answered of ($BF.infile(file_size), int file_size, Int, Int, Int)
  | NoDuplicate of ()

val _duplicate = ref<duplicate>(NoDuplicate())

fn _duplicate_take (): duplicate = let
  var waiting: duplicate = NoDuplicate()
  val () = ref_exch_elt<duplicate>(_duplicate, waiting)
in waiting end

(* Puts waiting in; a file still held there is closed (imports go one after
   another, so none is) *)
fn _duplicate_put (waiting: duplicate): void = let
  var previous: duplicate = waiting
  val () = ref_exch_elt<duplicate>(_duplicate, previous)
in
  case+ previous of
  | ~Asked(book_file, _, _, _, _, resolver) => let
      val () = $BF.file_close(book_file)
    in $P.resolve<duplicate_answer>(resolver, SkipIt()) end
  | ~Answered(book_file, _, _, _, _) => $BF.file_close(book_file)
  | ~NoDuplicate() => ()
end

(* The answer to "already in the library": replace (true) or skip *)
fn _duplicate_answer (replace: bool): void = let
  (* skipped: the file's import card goes at once *)
  val () = (if replace then () else ui_show("import-progress", false))
in
  case+ _duplicate_take() of
  | ~Asked(book_file, file_size, id_high, id_low, library_index, resolver) => let
      val () = _duplicate_put(Answered(book_file, file_size, id_high, id_low, library_index))
    in $P.resolve<duplicate_answer>(resolver, (if replace then ReplaceIt() else SkipIt())) end
  | other => _duplicate_put(other)
end

(* The library changed: kept and shown *)
fn _library_changed (): void = let
  val () = lib_sort(lib_sort_get())
  val () = lib_save()
in lib_render() end

(* Imports the file_size-byte book_file with id (id_high, id_low) as a
   new book (library_index < 0) or over library book library_index *)
fn _import_go {file_size:pos} (book_file: $BF.infile(file_size), file_size: int file_size, id_high: Int, id_low: Int, library_index: Int): $P.promise(import_outcome, $P.Chained) = let
  val () = _stage("Opening archive", 30)
  val serial = book_begin(book_file, file_size)
  val mode = (if library_index < 0 then AddNew() else Replace()): import_mode
in
  $P.and_then<archive_outcome><import_outcome>(_open_archive(serial, file_size, mode, library_index, id_high, id_low), llam(outcome) =>
    case+ outcome of
    | ~BookAdded(key) => let
        val () = _stage("Adding to library", 90)
        val () = open_key_set(key)
        val () = _library_changed()
        val () = ui_show("import-progress", false)
        val () = _kept_name_put(NoKeptName())
      in $P.ret<import_outcome>(Added(key)) end
    (* an import neither reopens nor fails silently *)
    | ~BookReopened() => let
        val () = _error()
      in $P.ret<import_outcome>(Failed()) end
    | ~ArchiveFailed(_) => let
        val () = _error()
      in $P.ret<import_outcome>(Failed()) end)
end

(* Imports book_file, of file_size bytes, whose name is kept *)
fn _import_file {file_size:nat} (book_file: $BF.infile(file_size), file_size: int file_size): $P.promise(import_outcome, $P.Chained) =
  (* a book added to a library that could not be read could not be kept
     without saving that library over the one stored (#174) *)
  if ~storage_savable(LibraryRecord()) then let
    val () = $BF.file_close(book_file)
    val () = _kept_name_put(NoKeptName())
    val () = notice_error("Books cannot be added: Quire could not read your library. Reopen Quire to try again.")
  in $P.ret<import_outcome>(Failed()) end
  else let
  val () = _stage_name()
  val () = _stage("Reading file", 10)
  val () = notice_dismiss()
in
  if file_size <= 0 then let
    val () = $BF.file_close(book_file)
    val () = _error()
  in $P.ret<import_outcome>(Failed()) end
  else let
    val @(id_high, id_low) = _file_id(book_file, file_size)
    val library_index = lib_find(id_high, id_low)
  in
    if library_index < 0 then _import_go(book_file, file_size, id_high, id_low, ~1)
    else (case+ lib_nums(library_index) of
      | ~$R.none() => _import_go(book_file, file_size, id_high, id_low, ~1)
      | ~$R.some(record) =>
        (* An archived book is restored by importing it again *)
        if same_shelf(record.shelf, Archived()) then _import_go(book_file, file_size, id_high, id_low, library_index)
        else let
          val @(answer_promise, resolver) = $P.create<duplicate_answer>()
          val () = _duplicate_put(Asked(book_file, file_size, id_high, id_low, library_index, resolver))
          val @(title, title_len) = lib_text(library_index, TitleText())
          val message = $A.alloc<byte>(320)
          val () = _copy_into(title, title_len, message, 0, 0)
          val () = $A.free<byte>(title)
          val text_end = _put_string(message, title_len, " is already in your library.")
          val () = $P.finish<reply>(modal_open(QDuplicate(), "Already in library"), llam(reply_given) =>
            case+ reply_given of
            | Accepted() => _duplicate_answer(true)
            | Declined() => _duplicate_answer(false))
          val () = modal_text(message, text_end)
        in
          $P.and_then<duplicate_answer><import_outcome>($P.vow(answer_promise), llam(answer) =>
            case+ _duplicate_take() of
            | ~NoDuplicate() => let
                val () = ui_show("import-progress", false)
              in $P.ret<import_outcome>(Failed()) end
            | ~Asked(waiting_file, _, _, _, _, waiting_resolver) => let
                val () = $BF.file_close(waiting_file)
                val () = $P.resolve<duplicate_answer>(waiting_resolver, SkipIt())
                val () = ui_show("import-progress", false)
              in $P.ret<import_outcome>(Failed()) end
            | ~Answered(waiting_file, waiting_size, waiting_high, waiting_low, waiting_index) =>
              (case+ answer of
              | ReplaceIt() => _import_go(waiting_file, waiting_size, waiting_high, waiting_low, waiting_index)
              | SkipIt() => let
                  val () = $BF.file_close(waiting_file)
                  val () = ui_show("import-progress", false)
                in $P.ret<import_outcome>(Kept()) end))
        end)
  end
end

(* "<name> could not be read.", for a file that came but could not be
   read (its name is the one kept) *)
fn _unread (): void = let
  val message = $A.alloc<byte>(512)
  val name_end = _kept_name_into(message)
  val text_end = _put_string(message, name_end, " could not be read.")
  val () = notice_error_buf(message, text_end)
in ui_show("import-progress", false) end

(* Imports the file an open promise resolved with *)
fn _import_opened (opened: $BF.opened): $P.promise(import_outcome, $P.Chained) =
  case+ opened of
  (* gone from the input before it was read: nothing to import *)
  | ~$BF.NotOpened() => $P.ret<import_outcome>(Failed())
  | ~$BF.OpenFailed() => let
      val () = _kept_name_put(NoKeptName())
      val () = _unread()
    in $P.ret<import_outcome>(Failed()) end
  | ~$BF.Opened(book_file) => let
      val file_size = $BF.file_size(book_file)
      val () = _keep_name_of(book_file)
    in _import_file(book_file, file_size) end

(* Imports book_file, of file_size bytes, fetched from a catalogue: its
   name (for its progress and errors) is name[0, name_len), the book's
   title there. The promise resolves with how the import went *)
#pub fn import_fetched {file_size:nat}{l:agz}{n:pos}{name_len:nat | name_len <= n}
  (book_file: $BF.infile(file_size), file_size: int file_size, name: !$A.arr(byte, l, n), name_len: int name_len): $P.promise(import_outcome, $P.Chained)

implement import_fetched (book_file, file_size, name, name_len) = let
  val () = (if name_len <= 0 then _kept_name_put(NoKeptName())
    else let
      val kept_len = _at_most_200(name_len)
      val name_bytes = $A.alloc<byte>(kept_len)
      val () = _copy_into(name, kept_len, name_bytes, 0, 0)
    in _kept_name_put(KeptName(name_bytes, kept_len)) end)
in _import_file(book_file, file_size) end

(* Where picked files come from: the file input import-file, or the
   last drop *)
datatype import_source = FileInput | Dropped

(* Imports files file_index to file_count - 1 of source, one after
   another *)
fun _import_seq {file_index,file_count:nat | file_index <= file_count} .<file_count - file_index>.
  (source: import_source, file_index: int file_index, file_count: int file_count): void =
  if file_index >= file_count then
    (* the input's files are all read: its choice is cleared *)
    (case+ source of FileInput() => app_import_input() | Dropped() => ())
  else let
    val opened = (case+ source of
      | FileInput() => let
        val input_id = $A.alloc<byte>(11)
        val () = $A.write_text(input_id, 0, $A.text_lit("import-file"), 11)
        val @(id_frozen, id_bytes) = $A.freeze<byte>(input_id)
        val opened = $BF.file_open_at(id_bytes, 11, file_index)
        val () = release_bytes(id_frozen, id_bytes)
      in opened end
      | Dropped() => $BF.dropped_open_at(file_index)): $P.promise($BF.opened, $P.Chained)
  in
    (* each import's result is already reported (_import_opened shows
       the error banner on a failure, and a duplicate is answered in its
       own dialog): the next file is imported whatever it was *)
    $P.finish<import_outcome>($P.and_then<$BF.opened><import_outcome>(opened, llam(opened) => _import_opened(opened)), llam(outcome) => let
      val () = import_outcome_free(outcome)
    in
      _import_seq(source, file_index + 1, file_count) end)
  end

(* Imports the files picked in the file input import-file *)
#pub fn import_picked (): void

implement import_picked () = let
  val input_id = $A.alloc<byte>(11)
  val () = $A.write_text(input_id, 0, $A.text_lit("import-file"), 11)
  val @(id_frozen, id_bytes) = $A.freeze<byte>(input_id)
  val file_count = $BF.file_count(id_bytes, 11)
  val () = release_bytes(id_frozen, id_bytes)
in _import_seq(FileInput(), 0, file_count) end

(* Imports the files of the last drop *)
#pub fn import_dropped (): void

implement import_dropped () = _import_seq(Dropped(), 0, $BF.dropped_count())

(* Imports a file handed to the app from outside it; the promise
   resolves when its import is done, as an import's does *)
#pub fn import_external (handed: $BE.external): $P.promise(import_outcome, $P.Chained)

(* ignored: the import's result is already reported, as each one's of
   _import_seq *)
implement import_external (handed) =
  case+ handed of
  | ~$BE.ExternalUnreadable(name) => let
      val () = _keep_name(name)
      val () = _unread()
    in $P.ret<import_outcome>(Failed()) end
  | ~$BE.External(book_file, name) => let
      val file_size = $BF.file_size(book_file)
      val () = _keep_name(name)
    in _import_file(book_file, file_size) end

(* ============================================================
   Reopening a stored book
   ============================================================ *)

(* How a stored book's opening went: opened; its file not stored (an
   archived book) or not a book quire can open; or its file could not be
   read from storage, which another try may mend (#174) *)
#pub datatype book_opening = BookOpened | BookFileMissing | BookFileUnreadable

implement $P.dispose<book_opening>(_) = ()

(* Puts library book (id_high, id_low), whose key is key, in the book cell from
   its stored file *)
#pub fn open_stored (key: int, id_high: Int, id_low: Int): $P.promise(book_opening, $P.Chained)

implement open_stored (key, id_high, id_low) = let
  val file_key = lib_key(98, id_high, id_low)
  val @(key_frozen, key_bytes) = $A.freeze<byte>(file_key)
  val stored = $BF.file_idb_get(key_bytes, 15)
  val () = release_bytes(key_frozen, key_bytes)
in
  $P.and_then<$BF.file_lookup><book_opening>(stored, llam(found) =>
    case+ found of
    | ~$BF.FileAbsent() => $P.ret<book_opening>(BookFileMissing())
    | ~$BF.FileUnreadable() => $P.ret<book_opening>(BookFileUnreadable())
    | ~$BF.FileFound(book_file) => let
        val file_size = $BF.file_size(book_file)
      in
        if file_size <= 0 then let val () = $BF.file_close(book_file) in $P.ret<book_opening>(BookFileMissing()) end
        else let
          val serial = book_begin(book_file, file_size)
        in
          $P.and_then<archive_outcome><book_opening>(_open_archive(serial, file_size, Reopen(), ~1, id_high, id_low), llam(outcome) =>
            case+ outcome of
            | ~BookReopened() => let val () = open_key_set(key) in $P.ret<book_opening>(BookOpened()) end
            | ~BookAdded(_) => $P.ret<book_opening>(BookFileMissing())
            | ~ArchiveFailed(_) => $P.ret<book_opening>(BookFileMissing()))
        end
      end)
end

end (* #target wasm *)
