(* book -- the open book: its file, and where its OPF is inside it *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A
#use result as R
#use wasm.bats-packages.dev/decompress as DC
#use wasm.bats-packages.dev/file-input as FI
#use zip as Z

(* The open book's file and its size; its OPF's
   compressed data [opf_data, opf_data + opf_size) (at most 1 MiB) and compression
   method; the OPF's name [opf_name, opf_name + opf_name_len) in the
   central directory. The regions are proven inside the file, so the
   reader uses them with no check. *)
#pub datatype open_book =
  | {n:pos}{d:nat}{s:pos | d + s <= n; s <= 1048576}{m:int | m == 0 || m == 8}{no,nl:nat | no + nl <= n; nl < 65536}
    OpenBook of ($FI.infile(n), int n, int d, int s, int m, int no, int nl)
  | NoBook of ()

#pub fun book_get(): open_book

(* A decompressed blob's bytes, at most 1 MiB *)
#pub datavtype blob_bytes =
  | {l:agz}{n:pos | n <= 1048576} BlobBytes of ($A.arr(byte, l, n), int n)
  | NoBlobBytes of ()

(* The blob a decompress promise resolved with, read whole and freed:
   none when decompression failed, or the result is empty or over 1 MiB
   (the book's data, checked here once) *)
#pub fn take_blob (handle: Int): blob_bytes

#pub fun book_set(b: open_book): void

(* An entry of a z-byte archive, read by ranges: its compressed bytes
   (at most 1 MiB), method, where they are [d, d + s) and where its
   name is [no, no + nl), both proven inside the archive *)
#pub datavtype zip_got(z:int) =
  | {l:agz}{s:pos | s <= 1048576}{m:int | m == 0 || m == 8}{d:nat | d + s <= z}{no,nl:nat | no + nl <= z; nl < 65536}
    ZipGot(z) of ($A.arr(byte, l, s), int s, int m, int d, int no, int nl)
  | ZipMissing(z) of ()

(* The entry named name[0, nb) of the z-byte file f, reading only the
   archive's end, its central directory, the entry's local header and
   its data; missing when there is none, or when the directory or the
   data is over 1 MiB (the book's data, checked here once) *)
#pub fn zip_read {z:pos}{lb:agz}{nb:pos}
  (f: $FI.infile(z), z: int z, name: !$A.borrow(byte, lb, nb), nb: int nb): zip_got(z)

val _book = ref<open_book>(NoBook())

implement book_get() = !_book

implement take_blob (handle) =
  case+ $DC.blob_claim(handle) of
  | ~$R.none() => NoBlobBytes()
  | ~$R.some(b) => let
      val n = $DC.blob_len(b)
    in
      if n <= 0 then let val () = $DC.blob_free(b) in NoBlobBytes() end
      else if n > 1048576 then let val () = $DC.blob_free(b) in NoBlobBytes() end
      else let
        val buf = $A.alloc<byte>(n)
        val () = $DC.blob_read(b, 0, buf, n)
        val () = $DC.blob_free(b)
      in BlobBytes(buf, n) end
    end

implement book_set(b) = !_book := b

implement zip_read {z}{lb}{nb} (f, z, name, nb) = let
  val t = (if z < 65557 then z else 65557): [t:pos | t <= z; t <= 65557] int t
  val tail = $A.alloc<byte>(t)
  val () = $FI.file_read(f, z - t, tail, t)
  val found = $Z.find_cd(tail, t, z)
  val () = $A.free<byte>(tail)
in
  case+ found of
  | ~$R.none() => ZipMissing()
  | ~$R.some(dir) => let
      val s = $Z.cd_size(dir)
      val c = $Z.cd_offset(dir)
    in
      if s > 1048576 then ZipMissing()
      else let
        val cd = $A.alloc<byte>(s)
        val () = $FI.file_read(f, c, cd, s)
        val r = $Z.find_ref(cd, dir, z, name, nb)
        val () = $A.free<byte>(cd)
      in
        case+ r of
        | ~$R.none() => ZipMissing()
        | ~$R.some(e) => let
            val+ $Z.zip_ref_mk(h, _, _, _, no, nl) = e
            val hdr = $A.alloc<byte>(30)
            val () = $FI.file_read(f, h, hdr, 30)
            val sp = $Z.find_data(hdr, e, z)
            val () = $A.free<byte>(hdr)
          in
            case+ sp of
            | ~$R.none() => ZipMissing()
            | ~$R.some($Z.zip_span_mk(d, cs, m, _)) =>
              if cs <= 0 then ZipMissing()
              else if cs > 1048576 then ZipMissing()
              else let
                val buf = $A.alloc<byte>(cs)
                val () = $FI.file_read(f, d, buf, cs)
              in ZipGot(buf, cs, m, d, no, nl) end
          end
      end
    end
end

(* The reader's font size in px: 8 to 48, the range the A- and A+
   buttons step through. *)
#pub typedef font_px = [s:int | 8 <= s; s <= 48] int s

#pub fun font_get(): font_px

#pub fun font_set(s: font_px): void

val _font = ref<font_px>(16)

implement font_get() = !_font

implement font_set(s) = !_font := s

(* Where the reader is: page p of the chapter's t pages (at least one),
   in chapter c (counted from 1; 0 before one loads) of the book's tc. *)
#pub datatype reading =
  | {t:pos}{p:nat | p < t}{c,tc:nat}
    Reading of (int p, int t, int c, int tc)

#pub fun reading_get(): reading

#pub fun reading_set(r: reading): void

val _reading = ref<reading>(Reading(0, 1, 0, 0))

implement reading_get() = !_reading

implement reading_set(r) = !_reading := r

end (* #target wasm *)
