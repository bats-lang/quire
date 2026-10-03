(* paths -- names inside a book: directories, relative paths, types *)

#include "share/atspre_staload.hats"
#use array as A
#use arith as AR

(* Just past the last '/' in path[position, path_end), or after_slash if
   there is none *)
fun _after_last_slash {l:agz}{n:pos}{position,path_end:nat | position <= path_end; path_end <= n}
  {after_slash:int | after_slash <= position} .<path_end - position>.
  (path: !$A.arr(byte, l, n), position: int position, path_end: int path_end, after_slash: int after_slash)
  : [found:int | after_slash <= found; found <= path_end] int found =
  if position >= path_end then after_slash
  else if byte2int0($A.get<byte>(path, position)) = 47 then _after_last_slash(path, position + 1, path_end, position + 1)
  else _after_last_slash(path, position + 1, path_end, after_slash)

(* The end of the segment of path[start, path_len): the next '/' at or
   after start, or path_len *)
fun _segment_end {l:agz}{path_len:pos}{start:nat | start <= path_len} .<path_len - start>.
  (path: !$A.arr(byte, l, path_len), path_len: int path_len, start: int start)
  : [stop:int | start <= stop; stop <= path_len] int stop =
  if start >= path_len then start
  else if byte2int0($A.get<byte>(path, start)) = 47 then start
  else _segment_end(path, path_len, start + 1)

(* Just past the last '/' of path[0, position], or 0: where ".." leaves a
   path path[0, position + 2) that ends with '/' *)
fun _parent_end {l:agz}{path_len:pos}{position:int | position < path_len} .<max(position + 1, 0)>.
  (path: !$A.arr(byte, l, path_len), position: int position)
  : [parent_end:nat | parent_end <= max(position + 1, 0)] int parent_end =
  if position < 0 then 0
  else if byte2int0($A.get<byte>(path, position)) = 47 then position + 1
  else _parent_end(path, position - 1)

(* path[source, source + count) to path[target, target + count), front
   first (target <= source) *)
fun _move_bytes {l:agz}{path_len:pos}{source,target,count:nat | target <= source; source + count <= path_len} .<count>.
  (path: !$A.arr(byte, l, path_len), source: int source, target: int target, count: int count): void =
  if count <= 0 then ()
  else let
    val () = $A.set<byte>(path, target, $A.get<byte>(path, source))
  in _move_bytes(path, source + 1, target + 1, count - 1) end

(* path[0, path_len) with its empty, "." and ".." segments
   resolved, in place: the segments read from read_at on are written
   from write_at on (write_at <= read_at); the resolved length *)
fun _normalize {l:agz}{path_len:pos}{read_at,write_at:nat | write_at <= read_at; read_at <= path_len} .<path_len - read_at>.
  (path: !$A.arr(byte, l, path_len), path_len: int path_len, read_at: int read_at, write_at: int write_at)
  : [resolved_len:nat | resolved_len <= path_len] int resolved_len =
  if read_at >= path_len then write_at
  else let
    val [segment_end:int] segment_end = _segment_end(path, path_len, read_at)
    val segment_len = segment_end - read_at
    val first_dot = (if segment_len >= 1 then byte2int0($A.get<byte>(path, read_at)) = 46 else false): bool
    val second_dot = (if segment_len >= 2 then byte2int0($A.get<byte>(path, read_at + 1)) = 46 else false): bool
    val parent_end = (if write_at >= 2 then _parent_end(path, write_at - 2) else 0)
      : [parent_end:nat | parent_end <= write_at] int parent_end
  in
    if segment_end < path_len then
      (* a segment and its '/': the next one starts at segment_end + 1 *)
      if segment_len = 0 then _normalize(path, path_len, segment_end + 1, write_at)
      else if segment_len = 1 && first_dot then _normalize(path, path_len, segment_end + 1, write_at)
      else if segment_len = 2 && first_dot && second_dot then _normalize(path, path_len, segment_end + 1, parent_end)
      else let
        val () = _move_bytes(path, read_at, write_at, segment_len)
        val () = $A.set<byte>(path, write_at + segment_len, $A.int2byte(47))
      in _normalize(path, path_len, segment_end + 1, write_at + segment_len + 1) end
    (* the last segment *)
    else if segment_len = 1 && first_dot then write_at
    else if segment_len = 2 && first_dot && second_dot then parent_end
    else let
      val () = _move_bytes(path, read_at, write_at, segment_len)
    in write_at + segment_len end
  end

(* The end of an src value data[src_offset, src_offset + src_len): its
   first '#' at or after position, or its end *)
fun _src_end {l:agz}{n:pos}{src_offset,src_len:nat | src_offset + src_len <= n}{position:nat | position <= src_len} .<src_len - position>.
  (data: !$A.borrow(byte, l, n), src_offset: int src_offset, src_len: int src_len, position: int position)
  : [before_hash:nat | before_hash <= src_len] int before_hash =
  if position >= src_len then position
  else if byte2int0($A.read<byte>(data, src_offset + position)) = 35 then position
  else _src_end(data, src_offset, src_len, position + 1)

(* Whether path[0, path_len) ends with suffix[0, suffix_len), letters in
   any case, compared from position on *)
fun _ends_with {path_loc:agz}{path_len:pos}{suffix_len:pos | suffix_len <= path_len}{position:nat | position <= suffix_len}
  .<suffix_len - position>.
  (path: !$A.borrow(byte, path_loc, path_len), path_len: int path_len,
   suffix: &(@[char][suffix_len]), suffix_len: int suffix_len, position: int position): bool =
  if position >= suffix_len then true
  else let
    val letter = byte2int0($A.read<byte>(path, path_len - suffix_len + position))
    val lower = (if letter >= 65 then (if letter <= 90 then letter + 32 else letter) else letter): int
  in
    if lower <> char2int0(suffix.[position]) then false
    else _ends_with(path, path_len, suffix, suffix_len, position + 1)
  end

(* An audio file's type, by its extension *)
#pub datatype audio_type = AudioMpeg | AudioMp4 | AudioOgg | AudioWav | AudioOther

fn _audio_type {l:agz}{path_len:pos} (path: !$A.borrow(byte, l, path_len), path_len: int path_len): audio_type = let
  var mp3 = @[char][4]('.', 'm', 'p', '3')
  var m4a = @[char][4]('.', 'm', '4', 'a')
  var mp4 = @[char][4]('.', 'm', 'p', '4')
  var ogg = @[char][4]('.', 'o', 'g', 'g')
  var opus = @[char][5]('.', 'o', 'p', 'u', 's')
  var wav = @[char][4]('.', 'w', 'a', 'v')
in
  if path_len >= 5 && _ends_with(path, path_len, opus, 5, 0) then AudioOgg()
  else if path_len < 4 then AudioOther()
  else if _ends_with(path, path_len, mp3, 4, 0) then AudioMpeg()
  else if _ends_with(path, path_len, m4a, 4, 0) then AudioMp4()
  else if _ends_with(path, path_len, mp4, 4, 0) then AudioMp4()
  else if _ends_with(path, path_len, ogg, 4, 0) then AudioOgg()
  else if _ends_with(path, path_len, wav, 4, 0) then AudioWav()
  else AudioOther()
end

(* An audio type's media type *)
fn _audio_mime (kind: audio_type): [type_len:pos | type_len <= 24] string type_len =
  case+ kind of
  | AudioMpeg() => "audio/mpeg"
  | AudioMp4() => "audio/mp4"
  | AudioOgg() => "audio/ogg"
  | AudioWav() => "audio/wav"
  | AudioOther() => "application/octet-stream"

(* The image type the name path[0, path_len) says (by its extension) *)
fn _mime_of {l:agz}{path_len:pos} (path: !$A.borrow(byte, l, path_len), path_len: int path_len)
  : [type_len:pos | type_len <= 24] string type_len = let
  var png = @[char][4]('.', 'p', 'n', 'g')
  var jpg = @[char][4]('.', 'j', 'p', 'g')
  var jpeg = @[char][5]('.', 'j', 'p', 'e', 'g')
  var gif = @[char][4]('.', 'g', 'i', 'f')
  var svg = @[char][4]('.', 's', 'v', 'g')
  var webp = @[char][5]('.', 'w', 'e', 'b', 'p')
in
  if path_len >= 5 && _ends_with(path, path_len, jpeg, 5, 0) then "image/jpeg"
  else if path_len >= 5 && _ends_with(path, path_len, webp, 5, 0) then "image/webp"
  else if path_len < 4 then "application/octet-stream"
  else if _ends_with(path, path_len, png, 4, 0) then "image/png"
  else if _ends_with(path, path_len, jpg, 4, 0) then "image/jpeg"
  else if _ends_with(path, path_len, gif, 4, 0) then "image/gif"
  else if _ends_with(path, path_len, svg, 4, 0) then "image/svg+xml"
  else _audio_mime(_audio_type(path, path_len))
end


(* ============================================================
   Public API
   ============================================================ *)

(* The length of the directory part of path[0, path_len): up to and
   including its last '/', 0 when it has none *)
#pub fn path_dir_end {l:agz}{n:pos}{path_len:nat | path_len <= n}
  (path: !$A.arr(byte, l, n), path_len: int path_len): [dir_len:nat | dir_len <= path_len] int dir_len

implement path_dir_end (path, path_len) = _after_last_slash(path, 0, path_len, 0)

(* path[0, path_len) with its empty, "." and ".." segments
   resolved, in place; the resolved length *)
#pub fn path_norm {l:agz}{path_len:pos} (path: !$A.arr(byte, l, path_len), path_len: int path_len)
  : [resolved_len:nat | resolved_len <= path_len] int resolved_len

implement path_norm (path, path_len) = _normalize(path, path_len, 0, 0)

(* The length of an href or src data[src_offset, src_offset + src_len)
   before its '#' *)
#pub fn src_end {l:agz}{n:pos}{src_offset,src_len:nat | src_offset + src_len <= n}
  (data: !$A.borrow(byte, l, n), src_offset: int src_offset, src_len: int src_len)
  : [before_hash:nat | before_hash <= src_len] int before_hash

implement src_end (data, src_offset, src_len) = _src_end(data, src_offset, src_len, 0)

(* The image type the name path[0, path_len) says (by its extension) *)
#pub fn mime_of {l:agz}{path_len:pos} (path: !$A.borrow(byte, l, path_len), path_len: int path_len)
  : [type_len:pos | type_len <= 24] string type_len

implement mime_of (path, path_len) = _mime_of(path, path_len)

(* An image's type, as a book's cover is kept: NotAnImage for a name of
   no image type (and so for a book with no cover) *)
#pub datatype image_type = PngImage | JpegImage | GifImage | SvgImage | WebpImage | NotAnImage

(* Whether t is an image's type *)
#pub fn is_image (t: image_type): bool

implement is_image (t) = case+ t of NotAnImage() => false | _ => true

(* The mime type of t *)
#pub fn image_mime (t: image_type): [mime_len:pos | mime_len <= 24] string mime_len

implement image_mime (t) =
  case+ t of
  | PngImage() => "image/png" | JpegImage() => "image/jpeg" | GifImage() => "image/gif"
  | SvgImage() => "image/svg+xml" | WebpImage() => "image/webp" | NotAnImage() => "application/octet-stream"

(* t as the library stores it (QLB): 1 png, 2 jpeg, 3 gif, 4 svg, 5
   webp, 0 none *)
#pub fn image_code (t: image_type): [code:nat | code <= 5] int code

implement image_code (t) =
  case+ t of
  | PngImage() => 1 | JpegImage() => 2 | GifImage() => 3 | SvgImage() => 4 | WebpImage() => 5 | NotAnImage() => 0

(* The type a stored code stands for (image_code) *)
#pub fn image_of_code (code: int): image_type

implement image_of_code (code) =
  if code = 1 then PngImage() else if code = 2 then JpegImage() else if code = 3 then GifImage()
  else if code = 4 then SvgImage() else if code = 5 then WebpImage() else NotAnImage()

(* The image type the name path[0, path_len) says (by its extension) *)
#pub fn image_type_of {l:agz}{path_len:pos} (path: !$A.borrow(byte, l, path_len), path_len: int path_len)
  : image_type

implement image_type_of (path, path_len) = let
  var png = @[char][4]('.', 'p', 'n', 'g')
  var jpg = @[char][4]('.', 'j', 'p', 'g')
  var jpeg = @[char][5]('.', 'j', 'p', 'e', 'g')
  var gif = @[char][4]('.', 'g', 'i', 'f')
  var svg = @[char][4]('.', 's', 'v', 'g')
  var webp = @[char][5]('.', 'w', 'e', 'b', 'p')
in
  if path_len >= 5 && _ends_with(path, path_len, jpeg, 5, 0) then JpegImage()
  else if path_len >= 5 && _ends_with(path, path_len, webp, 5, 0) then WebpImage()
  else if path_len < 4 then NotAnImage()
  else if _ends_with(path, path_len, png, 4, 0) then PngImage()
  else if _ends_with(path, path_len, jpg, 4, 0) then JpegImage()
  else if _ends_with(path, path_len, gif, 4, 0) then GifImage()
  else if _ends_with(path, path_len, svg, 4, 0) then SvgImage()
  else NotAnImage()
end

(* The audio type the name path[0, path_len) says: MP3, MP4 (.m4a,
   .mp4), Ogg (.ogg, .opus), WAV, or none of them *)
#pub fn audio_type_of {l:agz}{path_len:pos} (path: !$A.borrow(byte, l, path_len), path_len: int path_len): audio_type

implement audio_type_of (path, path_len) = _audio_type(path, path_len)

(* The media type of an audio type *)
#pub fn audio_mime (kind: audio_type): [type_len:pos | type_len <= 24] string type_len

implement audio_mime (kind) = _audio_mime(kind)
