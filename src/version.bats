(* version -- the version Quire is built as (#219): the commit it is
   built from, never the build's clock, so one commit always gives the
   same version. bats writes the commit's facts (build/src/_bats_facts,
   bats-lang/bats#250) from BATS_COMMIT when set (CI names a pull
   request's own head, not the merge it checks out), else HEAD; this
   module only words them (#499). *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR

staload F = "_bats_facts.sats"

(* The commit's UTC date, YEAR.MONTH.DAY.SECONDS, as bats packages are
   versioned *)
#pub fn quire_version (): [version_len:pos | version_len < 32] string version_len

implement quire_version () = $F.bats_commit_version()

(* The commit's short SHA, its first 7 hex digits *)
#pub fn quire_commit_short (): string 7

implement quire_commit_short () = $F.bats_commit_short()

(* Android's version code is the number of commits reachable from the
   commit built from, plus this offset (#989, #979). A count only grows along
   main, so the queue's merges a minute apart give different codes (the
   minutes scheme gave two of them 955894, and Play refused the second). The
   offset puts the first count's code above 955894, the last code the minutes
   scheme gave Play; it never changes, so one commit always gives one code
   (keyword: version code, .claude/rules/release.md) *)
#pub stadef VERSION_CODE_OFFSET = 955000

(* The code, or that the clone is shallow and cannot count (the answer the
   facts give, kept: a number that is wrong is never made) *)
#pub datavtype version_code =
  | {code:pos | code > VERSION_CODE_OFFSET} VersionCode of int code
  | VersionCodeShallow of ()

#pub fn quire_version_code (): version_code

(* The offset as a number: its type is the stadef above, so the compiler
   holds the two literals equal (keyword: version code) *)
fn _version_code_offset (): int(VERSION_CODE_OFFSET) = 955000

implement quire_version_code () =
  case+ $F.bats_commit_count() of
  | ~$F.CommitCounted(count) => VersionCode(count + _version_code_offset())
  | ~$F.CommitHistoryShallow() => VersionCodeShallow()

(* The longest version text: a version under 32 bytes, " (", the short
   SHA and ")" *)
#pub stadef VERSION_TEXT_MAX = 48

fun _put_from {l:agz}{n:pos}{text_len:nat}{position:nat | position + text_len <= n}{i:nat | i <= text_len}
  .<text_len - i>.
  (buf: !$A.arr(byte, l, n), position: int position, text: string text_len, text_len: int text_len, i: int i)
  : int(position + text_len) =
  if i >= text_len then position + text_len
  else let
    val () = $A.set<byte>(buf, position + i, $A.int2byte($AR.byte_of_char(string_get_at(text, i))))
  in _put_from(buf, position, text, text_len, i + 1) end

fn _put_text {l:agz}{n:pos}{text_len:nat}{position:nat | position + text_len <= n}
  (buf: !$A.arr(byte, l, n), position: int position, text: string text_len): int(position + text_len) =
  _put_from(buf, position, text, g1u2i(string1_length(text)), 0)

(* The version as About shows it and a backup records it,
   "2026.10.2.61373 (f95ce82)": its bytes and their length *)
#pub fn quire_version_text (): [l:agz][text_len:pos | text_len <= VERSION_TEXT_MAX]
  @($A.arr(byte, l, VERSION_TEXT_MAX), int text_len)

implement quire_version_text () = let
  val buf = $A.alloc<byte>(48)
  val at = _put_text(buf, 0, quire_version())
  val at = _put_text(buf, at, " (")
  val at = _put_text(buf, at, quire_commit_short())
  val at = _put_text(buf, at, ")")
in @(buf, at) end
