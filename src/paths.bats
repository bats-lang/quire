(* paths -- names inside a book: directories, relative paths, types *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

(* Just past the last '/' in buf[p, e), or la if there is none *)
fun _after_last_slash {l:agz}{n:pos}{p,e:nat | p <= e; e <= n}{la:int | la <= p} .<e - p>.
  (buf: !$A.arr(byte, l, n), p: int p, e: int e, la: int la): [r:int | la <= r; r <= e] int r =
  if p >= e then la
  else if byte2int0($A.get<byte>(buf, p)) = 47 then _after_last_slash(buf, p + 1, e, p + 1)
  else _after_last_slash(buf, p + 1, e, la)

(* The end of the segment of buf[i, m): the next '/' at or after i, or m *)
fun _seg_end {l:agz}{m:pos}{i:nat | i <= m} .<m - i>.
  (buf: !$A.arr(byte, l, m), m: int m, i: int i): [j:int | i <= j; j <= m] int j =
  if i >= m then i
  else if byte2int0($A.get<byte>(buf, i)) = 47 then i
  else _seg_end(buf, m, i + 1)

(* Just past the last '/' of buf[0, p], or 0: where ".." leaves a path
   buf[0, p + 2) that ends with '/' *)
fun _back {l:agz}{m:pos}{p:int | p < m} .<max(p + 1, 0)>.
  (buf: !$A.arr(byte, l, m), p: int p): [q:nat | q <= max(p + 1, 0)] int q =
  if p < 0 then 0
  else if byte2int0($A.get<byte>(buf, p)) = 47 then p + 1
  else _back(buf, p - 1)

(* buf[s, s + c) to buf[d, d + c), front first (d <= s) *)
fun _move {l:agz}{m:pos}{s,d,c:nat | d <= s; s + c <= m} .<c>.
  (buf: !$A.arr(byte, l, m), s: int s, d: int d, c: int c): void =
  if c <= 0 then ()
  else let
    val () = $A.set<byte>(buf, d, $A.get<byte>(buf, s))
  in _move(buf, s + 1, d + 1, c - 1) end

(* The path buf[0, m) with its empty, "." and ".." segments resolved,
   in place: the segments read from i on are written from w on (w <= i);
   the resolved length *)
fun _norm {l:agz}{m:pos}{i,w:nat | w <= i; i <= m} .<m - i>.
  (buf: !$A.arr(byte, l, m), m: int m, i: int i, w: int w): [k:nat | k <= m] int k =
  if i >= m then w
  else let
    val [j:int] j = _seg_end(buf, m, i)
    val c = j - i
    val dot1 = (if c >= 1 then byte2int0($A.get<byte>(buf, i)) = 46 else false): bool
    val dot2 = (if c >= 2 then byte2int0($A.get<byte>(buf, i + 1)) = 46 else false): bool
    val up = (if w >= 2 then _back(buf, w - 2) else 0): [q:nat | q <= w] int q
  in
    if j < m then
      (* a segment and its '/': the next one starts at j + 1 *)
      if c = 0 then _norm(buf, m, j + 1, w)
      else if c = 1 && dot1 then _norm(buf, m, j + 1, w)
      else if c = 2 && dot1 && dot2 then _norm(buf, m, j + 1, up)
      else let
        val () = _move(buf, i, w, c)
        val () = $A.set<byte>(buf, w + c, $A.int2byte(47))
      in _norm(buf, m, j + 1, w + c + 1) end
    (* the last segment *)
    else if c = 1 && dot1 then w
    else if c = 2 && dot1 && dot2 then up
    else let
      val () = _move(buf, i, w, c)
    in w + c end
  end

(* The end of an src value data[so, so + e): its first '#', or its end *)
fun _src_end {lb:agz}{n:pos}{so,sl:nat | so + sl <= n}{e:nat | e <= sl} .<sl - e>.
  (data: !$A.borrow(byte, lb, n), so: int so, sl: int sl, e: int e): [r:nat | r <= sl] int r =
  if e >= sl then e
  else if byte2int0($A.read<byte>(data, so + e)) = 35 then e
  else _src_end(data, so, sl, e + 1)

(* Whether path[0, k) ends with pat[0, np), letters in any case *)
fun _ends_with {lp:agz}{k:pos}{np:pos | np <= k}{i:nat | i <= np} .<np - i>.
  (path: !$A.borrow(byte, lp, k), k: int k, pat: &(@[char][np]), np: int np, i: int i): bool =
  if i >= np then true
  else let
    val b = byte2int0($A.read<byte>(path, k - np + i))
    val lb = (if b >= 65 then (if b <= 90 then b + 32 else b) else b): int
  in
    if lb <> char2int0(pat.[i]) then false
    else _ends_with(path, k, pat, np, i + 1)
  end

(* The image type the name path[0, k) says (by its extension) *)
fn _mime_of {lp:agz}{k:pos} (path: !$A.borrow(byte, lp, k), k: int k): [sn:pos | sn <= 24] string sn = let
  var png = @[char][4]('.', 'p', 'n', 'g')
  var jpg = @[char][4]('.', 'j', 'p', 'g')
  var jpeg = @[char][5]('.', 'j', 'p', 'e', 'g')
  var gif = @[char][4]('.', 'g', 'i', 'f')
  var svg = @[char][4]('.', 's', 'v', 'g')
  var webp = @[char][5]('.', 'w', 'e', 'b', 'p')
in
  if k >= 5 && _ends_with(path, k, jpeg, 5, 0) then "image/jpeg"
  else if k >= 5 && _ends_with(path, k, webp, 5, 0) then "image/webp"
  else if k < 4 then "application/octet-stream"
  else if _ends_with(path, k, png, 4, 0) then "image/png"
  else if _ends_with(path, k, jpg, 4, 0) then "image/jpeg"
  else if _ends_with(path, k, gif, 4, 0) then "image/gif"
  else if _ends_with(path, k, svg, 4, 0) then "image/svg+xml"
  else "application/octet-stream"
end


(* ============================================================
   Public API
   ============================================================ *)

(* The length of the directory part of buf[0, e): up to and including
   its last '/', 0 when it has none *)
#pub fn path_dir_end {l:agz}{n:pos}{e:nat | e <= n}
  (buf: !$A.arr(byte, l, n), e: int e): [r:nat | r <= e] int r

implement path_dir_end (buf, e) = _after_last_slash(buf, 0, e, 0)

(* The path buf[0, m) with its empty, "." and ".." segments resolved, in
   place; the resolved length *)
#pub fn path_norm {l:agz}{m:pos} (buf: !$A.arr(byte, l, m), m: int m): [k:nat | k <= m] int k

implement path_norm (buf, m) = _norm(buf, m, 0, 0)

(* The length of an href or src data[so, so + sl) before its '#' *)
#pub fn src_end {lb:agz}{n:pos}{so,sl:nat | so + sl <= n}
  (data: !$A.borrow(byte, lb, n), so: int so, sl: int sl): [r:nat | r <= sl] int r

implement src_end (data, so, sl) = _src_end(data, so, sl, 0)

(* The image type the name path[0, k) says (by its extension) *)
#pub fn mime_of {lp:agz}{k:pos} (path: !$A.borrow(byte, lp, k), k: int k): [sn:pos | sn <= 24] string sn

implement mime_of (path, k) = _mime_of(path, k)

(* The same as a code: 1 png, 2 jpeg, 3 gif, 4 svg, 5 webp, 0 other *)
#pub fn mime_code_of {lp:agz}{k:pos} (path: !$A.borrow(byte, lp, k), k: int k): [c:nat | c <= 5] int c

implement mime_code_of (path, k) = let
  var png = @[char][4]('.', 'p', 'n', 'g')
  var jpg = @[char][4]('.', 'j', 'p', 'g')
  var jpeg = @[char][5]('.', 'j', 'p', 'e', 'g')
  var gif = @[char][4]('.', 'g', 'i', 'f')
  var svg = @[char][4]('.', 's', 'v', 'g')
  var webp = @[char][5]('.', 'w', 'e', 'b', 'p')
in
  if k >= 5 && _ends_with(path, k, jpeg, 5, 0) then 2
  else if k >= 5 && _ends_with(path, k, webp, 5, 0) then 5
  else if k < 4 then 0
  else if _ends_with(path, k, png, 4, 0) then 1
  else if _ends_with(path, k, jpg, 4, 0) then 2
  else if _ends_with(path, k, gif, 4, 0) then 3
  else if _ends_with(path, k, svg, 4, 0) then 4
  else 0
end
