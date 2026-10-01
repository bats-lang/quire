(* url -- web addresses: a reference resolved against the address it
   was read from, a search template filled, and whether an address is
   one the app may fetch or link to *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

staload "paths.sats"

(* The longest address kept *)

#define LONGEST 2048

fn _byte_at {l:agz}{o:addr}{n:nat}{i:nat | i < n} (bytes: !$A.arrx(byte, l, n, o), i: int i): [value:nat | value < 256] int value =
  $AR.low_byte(byte2int0($A.get<byte>(bytes, i)))

(* target[target_at, target_at + count) := source[source_at, source_at + count) *)
fun _copy {source_loc,target_loc:agz}{source_size,target_size:nat}
  {source_at,count:nat | source_at + count <= source_size}{target_at:nat | target_at + count <= target_size}{i:nat | i <= count} .<count - i>.
  (source: !$A.arr(byte, source_loc, source_size), source_at: int source_at,
   target: !$A.arr(byte, target_loc, target_size), target_at: int target_at, count: int count, i: int i): void =
  if i >= count then ()
  else let
    val () = $A.set<byte>(target, target_at + i, $A.get<byte>(source, source_at + i))
  in _copy(source, source_at, target, target_at, count, i + 1) end

fn _lower (code: int): int = if code >= 65 && code <= 90 then code + 32 else code

fn _is_letter (code: int): bool = let val lower = _lower(code) in lower >= 97 && lower <= 122 end

(* Where url[0, url_len)'s scheme ends (its ':'), or -1 when it has none
   (it is relative): a letter, then letters, digits, '+', '-' or '.' *)
fun _scheme_end {l:agz}{n:nat}{url_len:nat | url_len <= n}{i:nat | i <= url_len} .<url_len - i>.
  (url: !$A.arr(byte, l, n), url_len: int url_len, i: int i): [stop:int | ~1 <= stop; stop < url_len] int stop =
  if i >= url_len then ~1
  else let
    val code = _byte_at(url, i)
  in
    if code = 58 then (if i > 0 then i else ~1)
    else if _is_letter(code) then _scheme_end(url, url_len, i + 1)
    else if i = 0 then ~1
    else if (code >= 48 && code <= 57) || code = 43 || code = 45 || code = 46 then _scheme_end(url, url_len, i + 1)
    else ~1
  end

(* The first of the bytes stop_a, stop_b in url[i, url_len), or url_len *)
fun _until {l:agz}{n:nat}{url_len:nat | url_len <= n}{i:nat | i <= url_len} .<url_len - i>.
  (url: !$A.arr(byte, l, n), url_len: int url_len, i: int i, stop_a: int, stop_b: int, stop_c: int)
  : [stop:int | i <= stop; stop <= url_len] int stop =
  if i >= url_len then url_len
  else let
    val code = _byte_at(url, i)
  in
    if code = stop_a || code = stop_b || code = stop_c then i
    else _until(url, url_len, i + 1, stop_a, stop_b, stop_c)
  end

(* Where the authority that follows "//" at start ends: at its first
   '/', '?' or '#'; start when there is no "//" there *)
fn _authority_end {l:agz}{n:nat}{url_len:nat | url_len <= n}{start:nat | start <= url_len}
  (url: !$A.arr(byte, l, n), url_len: int url_len, start: int start): [stop:int | start <= stop; stop <= url_len] int stop =
  if start + 2 > url_len then start
  else if _byte_at(url, start) <> 47 then start
  else if _byte_at(url, start + 1) <> 47 then start
  else _until(url, url_len, start + 2, 47, 63, 35)

(* Just past the last '/' of url[i, stop), or found *)
fun _past_slash {l:agz}{n:nat}{i,stop:nat | i <= stop; stop <= n}{found:nat | found <= i} .<stop - i>.
  (url: !$A.arr(byte, l, n), i: int i, stop: int stop, found: int found)
  : [past:nat | found <= past; past <= stop] int past =
  if i >= stop then found
  else if _byte_at(url, i) = 47 then _past_slash(url, i + 1, stop, i + 1)
  else _past_slash(url, i + 1, stop, found)

(* A resolved address: its bytes out[0, out_len), or none (out_len 0) *)
#pub datavtype resolved =
  | {l:agz}{n:pos}{out_len:nat | out_len <= n; out_len <= 2048} Resolved of ($A.arr(byte, l, n), int out_len)

fn _none (): resolved = Resolved($A.alloc<byte>(1), 0)

(* source[0, count), a whole address *)
fn _whole {l:agz}{n:nat}{count:nat | count <= n} (source: !$A.arr(byte, l, n), count: int count): resolved =
  if count <= 0 then _none()
  else if count > LONGEST then _none()
  else let
    val out = $A.alloc<byte>(count)
    val () = _copy(source, 0, out, 0, count, 0)
  in Resolved(out, count) end

(* first[0, first_len) then second[0, second_len) *)
fn _two {first_loc,second_loc:agz}{first_size,second_size:nat}{first_len:nat | first_len <= first_size}{second_len:nat | second_len <= second_size}
  (first: !$A.arr(byte, first_loc, first_size), first_len: int first_len,
   second: !$A.arr(byte, second_loc, second_size), second_len: int second_len): resolved = let
  val total = first_len + second_len
in
  if total <= 0 then _none()
  else if total > LONGEST then _none()
  else let
    val out = $A.alloc<byte>(total)
    val () = _copy(first, 0, out, 0, first_len, 0)
    val () = _copy(second, 0, out, first_len, second_len, 0)
  in Resolved(out, total) end
end

(* base[0, head_len), '/', the path path[0, path_len) normalized, then
   reference[query_at, reference_end) (its query) *)
fn _join {base_loc,path_loc,reference_loc:agz}{base_size,reference_size:nat}
  {head_len:nat | head_len <= base_size}{path_len:pos}
  {query_at,reference_end:nat | query_at <= reference_end; reference_end <= reference_size}
  (base: !$A.arr(byte, base_loc, base_size), head_len: int head_len,
   path: !$A.arr(byte, path_loc, path_len), path_len: int path_len,
   reference: !$A.arr(byte, reference_loc, reference_size), query_at: int query_at, reference_end: int reference_end): resolved = let
  val normal_len = path_norm(path, path_len)
  val query_len = reference_end - query_at
  val total = head_len + 1 + normal_len + query_len
in
  if total > LONGEST then _none()
  else let
    val out = $A.alloc<byte>(total)
    val () = _copy(base, 0, out, 0, head_len, 0)
    val () = $A.set<byte>(out, head_len, $A.int2byte(47))
    val () = _copy(path, 0, out, head_len + 1, normal_len, 0)
    val () = _copy(reference, query_at, out, head_len + 1 + normal_len, query_len, 0)
  in Resolved(out, total) end
end

(* reference[0, reference_len) resolved against base[0, base_len), an
   absolute address (RFC 3986's resolution, its fragment dropped): an
   absolute reference as it is, "//host..." with base's scheme,
   "/path" on base's host, "?query" on base's path, and any other
   relative path against base's directory, its "." and ".." segments
   resolved. None when base is not absolute or the result is longer
   than 2048 *)
#pub fn url_resolve {base_loc,reference_loc:agz}{base_size,reference_size:nat}
  {base_len:nat | base_len <= base_size; base_len <= 2048}{reference_len:nat | reference_len <= reference_size; reference_len <= 2048}
  (base: !$A.arr(byte, base_loc, base_size), base_len: int base_len,
   reference: !$A.arr(byte, reference_loc, reference_size), reference_len: int reference_len): resolved

implement url_resolve {base_loc,reference_loc}{base_size,reference_size}{base_len}{reference_len} (base, base_len, reference, reference_len) = let
  val reference_end = _until(reference, reference_len, 0, 35, 35, 35)
  val base_end = _until(base, base_len, 0, 35, 35, 35)
  val base_scheme = _scheme_end(base, base_end, 0)
in
  if base_scheme < 0 then _none()
  else if _scheme_end(reference, reference_end, 0) >= 0 then _whole(reference, reference_end)
  else let
    val [authority_end:int] authority_end = _authority_end(base, base_end, base_scheme + 1)
    val [base_path_end:int] base_path_end = _until(base, base_end, authority_end, 63, 63, 63)
  in
    if reference_end <= 0 then _whole(base, base_end)
    else if (if reference_end >= 2 then (if _byte_at(reference, 0) = 47 then _byte_at(reference, 1) = 47 else false) else false) then
      _two(base, base_scheme + 1, reference, reference_end)
    else if _byte_at(reference, 0) = 63 then _two(base, base_path_end, reference, reference_end)
    else let
      val [query_at:int] query_at = _until(reference, reference_end, 0, 63, 63, 63)
      val rooted = _byte_at(reference, 0) = 47
      (* the directory of base's path, after its leading '/' *)
      val [dir_start:int] dir_start = (if authority_end < base_path_end then
        (if _byte_at(base, authority_end) = 47 then authority_end + 1 else authority_end) else authority_end): [dir_start:nat | authority_end <= dir_start; dir_start <= base_path_end] int dir_start
      val [dir_end:int] dir_end = _past_slash(base, dir_start, base_path_end, dir_start)
      val dir_len = (if rooted then 0 else dir_end - dir_start): [dir_len:nat | dir_len <= dir_end - dir_start] int dir_len
      val reference_start = (if rooted then 1 else 0): [reference_start:nat | reference_start <= 1] int reference_start
      val reference_path_len = (if query_at >= reference_start then query_at - reference_start else 0): [path_len:nat | path_len <= query_at] int path_len
      val path_len = dir_len + reference_path_len
    in
      if reference_start + reference_path_len > query_at then _none()
      else if path_len <= 0 then let
        (* no path: base's host, '/', and the query; "." normalizes to
           nothing *)
        val dot = $A.alloc<byte>(1)
        val () = $A.set<byte>(dot, 0, $A.int2byte(46))
        val joined = _join(base, authority_end, dot, 1, reference, query_at, reference_end)
        val () = $A.free<byte>(dot)
      in joined end
      else if path_len > LONGEST then _none()
      else let
        val path = $A.alloc<byte>(path_len)
        val () = _copy(base, dir_start, path, 0, dir_len, 0)
        val () = _copy(reference, reference_start, path, dir_len, reference_path_len, 0)
        val joined = _join(base, authority_end, path, path_len, reference, query_at, reference_end)
        val () = $A.free<byte>(path)
      in joined end
    end
  end
end

(* Whether url[0, url_len) is an http or https address *)
#pub fn url_is_web {l:agz}{n:nat}{url_len:nat | url_len <= n} (url: !$A.arr(byte, l, n), url_len: int url_len): bool

fun _starts {l:agz}{n:nat}{url_len:nat | url_len <= n}{text_len:nat}{i:nat | i <= text_len} .<text_len - i>.
  (url: !$A.arr(byte, l, n), url_len: int url_len, text: string text_len, text_len: int text_len, i: int i): bool =
  if i >= text_len then true
  else if i >= url_len then false
  else if _lower(_byte_at(url, i)) <> char2int0(string_get_at(text, i)) then false
  else _starts(url, url_len, text, text_len, i + 1)

implement url_is_web (url, url_len) =
  if url_len < 8 then false
  else _starts(url, url_len, "https://", 8, 0) || _starts(url, url_len, "http://", 7, 0)

(* ============================================================
   Search templates
   ============================================================ *)

fn _hex (value: int): [digit:nat | digit < 256] int digit = let
  val digit = $AR.low_byte(value)
  val digit = (if digit > 15 then 15 else digit): [digit:nat | digit < 16] int digit
in if digit < 10 then 48 + digit else 55 + digit end

fn _unreserved (code: int): bool =
  _is_letter(code) || (code >= 48 && code <= 57) || code = 45 || code = 46 || code = 95 || code = 126

(* query[i, query_len) percent-encoded at out[at, ...): where it ends *)
fun _encode {query_loc,out_loc:agz}{query_size,out_size:nat}{query_len:nat | query_len <= query_size}{i:nat | i <= query_len}{at:nat | at + 3 * (query_len - i) <= out_size} .<query_len - i>.
  (query: !$A.arr(byte, query_loc, query_size), query_len: int query_len, i: int i,
   out: !$A.arr(byte, out_loc, out_size), at: int at): [stop:nat | stop <= at + 3 * (query_len - i)] int stop =
  if i >= query_len then at
  else let
    val code = _byte_at(query, i)
  in
    if _unreserved(code) then let
      val () = $A.write_byte(out, at, code)
    in _encode(query, query_len, i + 1, out, at + 1) end
    else let
      val () = $A.write_byte(out, at, 37)
      val () = $A.write_byte(out, at + 1, _hex(code / 16))
      val () = $A.write_byte(out, at + 2, _hex(code - (code / 16) * 16))
    in _encode(query, query_len, i + 1, out, at + 3) end
  end

(* Whether template[at, at + text_len) is text *)
fun _text_at {l:agz}{n:nat}{template_len:nat | template_len <= n}{at:nat}{text_len:nat}{i:nat | i <= text_len} .<text_len - i>.
  (template: !$A.arr(byte, l, n), template_len: int template_len, at: int at, text: string text_len, text_len: int text_len, i: int i): bool =
  if i >= text_len then true
  else if at + i >= template_len then false
  else if _byte_at(template, at + i) <> char2int0(string_get_at(text, i)) then false
  else _text_at(template, template_len, at, text, text_len, i + 1)

(* Whether template[0, before) has a '?' *)
fun _has_query {l:agz}{n:nat}{before:nat | before <= n}{i:nat | i <= before} .<before - i>.
  (template: !$A.arr(byte, l, n), before: int before, i: int i): bool =
  if i >= before then false
  else if _byte_at(template, i) = 63 then true
  else _has_query(template, before, i + 1)

(* template[i, template_len) filled into out[at, ...): "{searchTerms}"
   becomes the encoded query encoded[0, encoded_len), "{?query}" (an
   OPDS 2 template) "?query=" (or "&query=") and it, and any other
   parameter in braces nothing; where it ends, or -1 when out is full *)
fun _fill {template_loc,encoded_loc,out_loc:agz}{template_size,encoded_size,out_size:nat}
  {template_len:nat | template_len <= template_size}{encoded_len:nat | encoded_len <= encoded_size}{i:nat | i <= template_len}{at:nat | at <= out_size} .<template_len - i>.
  (template: !$A.arr(byte, template_loc, template_size), template_len: int template_len, i: int i,
   encoded: !$A.arr(byte, encoded_loc, encoded_size), encoded_len: int encoded_len,
   out: !$A.arr(byte, out_loc, out_size), out_size: int out_size, at: int at): [stop:int | ~1 <= stop; stop <= out_size] int stop =
  if i >= template_len then at
  else if _byte_at(template, i) <> 123 then
    (if at + 1 > out_size then ~1
     else let
       val () = $A.set<byte>(out, at, $A.get<byte>(template, i))
     in _fill(template, template_len, i + 1, encoded, encoded_len, out, out_size, at + 1) end)
  else let
    val closing = _until(template, template_len, i, 125, 125, 125)
  in
    if closing >= template_len then
      (if at + 1 > out_size then ~1
       else let
         val () = $A.set<byte>(out, at, $A.get<byte>(template, i))
       in _fill(template, template_len, i + 1, encoded, encoded_len, out, out_size, at + 1) end)
    else if _text_at(template, template_len, i, "{searchTerms}", 13, 0) then
      (if at + encoded_len > out_size then ~1
       else let
         val () = _copy(encoded, 0, out, at, encoded_len, 0)
       in _fill(template, template_len, closing + 1, encoded, encoded_len, out, out_size, at + encoded_len) end)
    else if _text_at(template, template_len, i, "{?query}", 8, 0) then
      (if at + 7 + encoded_len > out_size then ~1
       else let
         val () = $A.write_byte(out, at, (if _has_query(template, i, 0) then 38 else 63): [joiner:nat | joiner < 256] int joiner)
         val () = $A.write_byte(out, at + 1, 113)
         val () = $A.write_byte(out, at + 2, 117)
         val () = $A.write_byte(out, at + 3, 101)
         val () = $A.write_byte(out, at + 4, 114)
         val () = $A.write_byte(out, at + 5, 121)
         val () = $A.write_byte(out, at + 6, 61)
         val () = _copy(encoded, 0, out, at + 7, encoded_len, 0)
       in _fill(template, template_len, closing + 1, encoded, encoded_len, out, out_size, at + 7 + encoded_len) end)
    else _fill(template, template_len, closing + 1, encoded, encoded_len, out, out_size, at)
  end

(* The search template template[0, template_len) filled with the
   query query[0, query_len) (at most 256 bytes): an address, or none
   when it would be longer than 2048 *)
#pub fn url_fill {template_loc,query_loc:agz}{template_size,query_size:nat}
  {template_len:nat | template_len <= template_size; template_len <= 2048}{query_len:nat | query_len <= query_size; query_len <= 256}
  (template: !$A.arr(byte, template_loc, template_size), template_len: int template_len,
   query: !$A.arr(byte, query_loc, query_size), query_len: int query_len): resolved

implement url_fill (template, template_len, query, query_len) = let
  val encoded = $A.alloc<byte>(3 * query_len + 1)
  val encoded_len = _encode(query, query_len, 0, encoded, 0)
  val out = $A.alloc<byte>(LONGEST)
  val stop = _fill(template, template_len, 0, encoded, encoded_len, out, LONGEST, 0)
  val () = $A.free<byte>(encoded)
in
  if stop <= 0 then let val () = $A.free<byte>(out) in _none() end
  else Resolved(out, stop)
end
