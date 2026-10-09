(* notice -- what the reader is told when something fails, and that a
   copy was made: the error banner (role alert, over both views, until
   it is dismissed) and the copy status (role status, for a moment).
   WCAG 2.2 SC 4.1.3 puts errors in an alert and success in a status;
   the copy status is apart from the Undo toast, so it never makes an
   Undo offer final *)

#target wasm begin

#include "share/atspre_staload.hats"
#use array as A
#use promise as P
#use result as R

staload "ui.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"
staload IDB = "wasm.bats-packages.dev/bridge/src/idb.sats"
staload BAPP = "wasm.bats-packages.dev/bridge/src/app.sats"
staload CB = "wasm.bats-packages.dev/bridge/src/clipboard.sats"
staload "version.sats"
staload "mem.sats"

(* Whether the error banner is up *)
val _banner_up = ref<bool>(false)

#define DETAILS_MAX 1048576
datavtype details =
  | NoDetails
  | {l:agz}{details_len:pos | details_len <= DETAILS_MAX} Details of ($A.arr(byte, l, DETAILS_MAX), int details_len)

fn _details_free (held: details): void =
  case+ held of
  | ~NoDetails() => ()
  | ~Details(text, _) => $A.free<byte>(text)

val _details = ref<details>(NoDetails())

fn _details_swap (held: details): details = let
  var previous: details = held
  val () = ref_exch_elt<details>(_details, previous)
in previous end

(* The banner's Copy details and Report, shown or hidden *)
fn _details_buttons (shown: bool): void = let
  val () = ui_show("error-copy", shown)
in ui_show("error-report", shown) end

(* The details of the last unexpected failure are kept after its banner
   goes (a plain error, its Dismiss, a new import), so the reader can
   still copy them from About (quire#374; Firefox keeps its troubleshooting
   information on about:support, with a Copy text to clipboard button,
   apart from whatever raised the problem, and Radiacode's and Zoho's
   Android apps attach diagnostics from their settings: a settings or
   About place, not the alert): a later failure's details replace them, and
   they are held in memory only, never stored *)
fn _details_set (held: details): void = let
  val shown = (case+ held of Details(_, _) => true | NoDetails() => false): bool
  val () = _details_free(_details_swap(held))
in _details_buttons(shown) end

(* Whether the details of an unexpected failure are kept *)
#pub fn notice_details_kept (): bool

implement notice_details_kept () = let
  val held = _details_swap(NoDetails())
  val kept = (case+ held of Details(_, _) => true | NoDetails() => false): bool
  val () = _details_free(_details_swap(held))
in kept end

fn _banner_show (): void = let
  val () = !_banner_up := true
in ui_show("error-banner", true) end

(* The error banner, saying text *)
#pub fn notice_error {text_len:pos | text_len < 256} (text: string text_len): void

implement notice_error (text) = let
  val () = _details_buttons(false)
  val () = ui_text("error-text", text)
in _banner_show() end

(* The error banner, saying text[0, text_len) *)
#pub fn notice_error_buf {l:agz}{n:pos}{text_len:nat | text_len <= n; text_len < 65536}
  (text: $A.arr(byte, l, n), text_len: int text_len): void

implement notice_error_buf (text, text_len) = let
  val () = _details_buttons(false)
  val () = ui_text_buf("error-text", text, text_len)
in _banner_show() end

fn _put_text {l:agz}{cap:pos}{n:nat}{at:nat | at <= cap}
  (out: !$A.arr(byte, l, cap), cap: int cap, at: int at, text: string n)
  : [stop:nat | at <= stop; stop <= cap] int stop = let
  val n = g1u2i(string1_length(text))
in
  if at + n > cap then at
  else let
    val () = $A.write_text(out, at, $A.text_lit(text), n)
  in at + n end
end

fun _put_bytes {l,b:agz}{size:nat}{bytes_len:nat | bytes_len <= size}{at:nat | at <= DETAILS_MAX}{j:nat | j <= bytes_len} .<bytes_len - j>.
  (out: !$A.arr(byte, l, DETAILS_MAX), at: int at, bytes: !$A.arr(byte, b, size), bytes_len: int bytes_len, j: int j)
  : [stop:nat | at <= stop; stop <= DETAILS_MAX] int stop =
  if j >= bytes_len then at
  else if at >= DETAILS_MAX then at
  else let
    val () = $A.set<byte>(out, at, $A.get<byte>(bytes, j))
  in _put_bytes(out, at + 1, bytes, bytes_len, j + 1) end

fn _put_detail {l:agz}{n:nat}{at:nat | at <= DETAILS_MAX}
  (out: !$A.arr(byte, l, DETAILS_MAX), at: int at, text: string n)
  : [stop:nat | at <= stop; stop <= DETAILS_MAX] int stop =
  _put_text(out, DETAILS_MAX, at, text)

#pub datavtype unexpected_case =
  | {n:pos | n < 64} CaseNamed of string n
  | {n:pos | n < 64} CaseNumbered of (string n, int)
  | {n,e:pos | n < 64; e < 64} CaseUnparsed of (string n, string e, int)
  | {n,f:pos | n < 64; f < 64} CaseFlawed of (string n, string f)

#pub datavtype answer_shown =
  | NoAnswer
  | {l:agz}{size:pos}{n:nat | n <= size}{f:pos | f < 64} AnswerShown of (string f, $A.arr(byte, l, size), int n)
  | {l:agz}{size:pos}{n:nat | n <= size}{f:pos | f < 64} AnswerCut of (string f, $A.arr(byte, l, size), int n, int)

#pub fn answer_shown_free (answer: answer_shown): void

implement answer_shown_free (answer) =
  case+ answer of
  | ~NoAnswer() => ()
  | ~AnswerShown(_, bytes, _) => $A.free<byte>(bytes)
  | ~AnswerCut(_, bytes, _, _) => $A.free<byte>(bytes)

fun _digits_put {l:agz}{at:pos | at <= 12} .<at>. (out: !$A.arr(byte, l, 12), at: int at, v: int): [start:nat | start < at] int start = let
  val rest = v - (v / 10) * 10
  val digit = (if rest < 0 then 0 - rest else rest): int
  val () = $A.set<byte>(out, at - 1, int2byte0(48 + digit))
in if at <= 1 then at - 1 else if v / 10 = 0 then at - 1 else _digits_put(out, at - 1, v / 10) end

fn _put_minus {l:agz}{at:nat | at <= DETAILS_MAX}
  (out: !$A.arr(byte, l, DETAILS_MAX), at: int at, negative: bool)
  : [stop:nat | at <= stop; stop <= DETAILS_MAX] int stop =
  if negative then _put_detail(out, at, "-") else at

fn _put_number {l:agz}{at:nat | at <= DETAILS_MAX}
  (out: !$A.arr(byte, l, DETAILS_MAX), at: int at, v: int)
  : [stop:nat | at <= stop; stop <= DETAILS_MAX] int stop = let
  val digits = $A.alloc<byte>(12)
  val start = _digits_put(digits, 12, v)
  val at = _put_detail(out, at, " ")
  val at = _put_minus(out, at, v < 0)
  val stop = _put_bytes(out, at, digits, 12, start)
  val () = $A.free<byte>(digits)
in stop end

fn _put_case {l:agz}{at:nat | at <= DETAILS_MAX}
  (out: !$A.arr(byte, l, DETAILS_MAX), at: int at, which: $R.option(unexpected_case))
  : [stop:nat | at <= stop; stop <= DETAILS_MAX] int stop =
  case+ which of
  | ~$R.none() => at
  | ~$R.some(~CaseNamed(name)) => _put_detail(out, _put_detail(out, at, "\nCase: "), name)
  | ~$R.some(~CaseNumbered(name, number)) =>
    _put_number(out, _put_detail(out, _put_detail(out, at, "\nCase: "), name), number)
  | ~$R.some(~CaseFlawed(name, flaw)) =>
    _put_detail(out, _put_detail(out, _put_detail(out, _put_detail(out, at, "\nCase: "), name), ", "), flaw)
  | ~$R.some(~CaseUnparsed(name, error, place)) => let
      val at = _put_detail(out, _put_detail(out, at, "\nCase: "), name)
      val at = _put_detail(out, _put_detail(out, at, ", json: "), error)
    in _put_number(out, _put_detail(out, at, " at"), place) end

fun _key_from {b:agz}{size:nat}{n:nat | n <= size}{j:nat}{k:nat | k <= 13} .<13 - k>.
  (bytes: !$A.arr(byte, b, size), n: int n, j: int j, k: int k): bool =
  if k >= 13 then true
  else if j + k >= n then false
  else if byte2int0($A.get<byte>(bytes, j + k)) <> char2int0(string_get_at("\"accessToken\"", k)) then false
  else _key_from(bytes, n, j, k + 1)

fun _past_colon {b:agz}{size:nat}{n:nat | n <= size}{j:nat | j <= n} .<n - j>.
  (bytes: !$A.arr(byte, b, size), n: int n, j: int j): [k:nat | j <= k; k <= n] int k =
  if j >= n then j
  else let
    val c = byte2int0($A.get<byte>(bytes, j))
  in if c = 32 || c = 9 || c = 10 || c = 13 || c = 58 then _past_colon(bytes, n, j + 1) else j end

fun _string_end {b:agz}{size:nat}{n:nat | n <= size}{j:nat | j <= n} .<n - j>.
  (bytes: !$A.arr(byte, b, size), n: int n, j: int j): [k:nat | j <= k; k <= n] int k =
  if j >= n then j
  else let
    val c = byte2int0($A.get<byte>(bytes, j))
  in
    if c = 34 then j
    else if c = 92 then (if j + 2 <= n then _string_end(bytes, n, j + 2) else n)
    else _string_end(bytes, n, j + 1)
  end

fun _put_range {l,b:agz}{size:nat}{k:nat | k <= size}{at:nat | at <= DETAILS_MAX}{j:nat | j <= k} .<k - j>.
  (out: !$A.arr(byte, l, DETAILS_MAX), at: int at, bytes: !$A.arr(byte, b, size), j: int j, k: int k)
  : [stop:nat | at <= stop; stop <= DETAILS_MAX] int stop =
  if j >= k then at
  else if at >= DETAILS_MAX then at
  else let
    val () = $A.set<byte>(out, at, $A.get<byte>(bytes, j))
  in _put_range(out, at + 1, bytes, j + 1, k) end

(* An accessToken's string value is hidden: it is a credential, and
   the details are pasted into issues *)
fun _put_hiding {l,b:agz}{size:nat}{n:nat | n <= size}{at:nat | at <= DETAILS_MAX}{j:nat | j <= n} .<n - j>.
  (out: !$A.arr(byte, l, DETAILS_MAX), at: int at, bytes: !$A.arr(byte, b, size), n: int n, j: int j)
  : [stop:nat | at <= stop; stop <= DETAILS_MAX] int stop =
  if j >= n then at
  else if at >= DETAILS_MAX then at
  else if j + 13 > n then let
    val () = $A.set<byte>(out, at, $A.get<byte>(bytes, j))
  in _put_hiding(out, at + 1, bytes, n, j + 1) end
  else if ~_key_from(bytes, n, j, 0) then let
    val () = $A.set<byte>(out, at, $A.get<byte>(bytes, j))
  in _put_hiding(out, at + 1, bytes, n, j + 1) end
  else let
    val at = _put_detail(out, at, "\"accessToken\"")
    val k = _past_colon(bytes, n, j + 13)
    val at = _put_range(out, at, bytes, j + 13, k)
  in
    if k >= n then at
    else if byte2int0($A.get<byte>(bytes, k)) <> 34 then _put_hiding(out, at, bytes, n, k)
    else let
      val e = _string_end(bytes, n, k + 1)
      val at = _put_detail(out, at, "\"[hidden,")
      val at = _put_number(out, at, e - k - 1)
      val at = _put_detail(out, at, " bytes]\"")
    in if e >= n then at else _put_hiding(out, at, bytes, n, e + 1) end
  end

fn _put_answer {l:agz}{at:nat | at <= DETAILS_MAX}
  (out: !$A.arr(byte, l, DETAILS_MAX), at: int at, answer: answer_shown)
  : [stop:nat | at <= stop; stop <= DETAILS_MAX] int stop =
  case+ answer of
  | ~NoAnswer() => _put_detail(out, at, "\nAnswer: none")
  | ~AnswerShown(form, bytes, n) => let
      val at = _put_detail(out, at, "\nAnswer, ")
      val at = _put_detail(out, at, form)
      val at = _put_detail(out, at, ": ")
      val stop = _put_hiding(out, at, bytes, n, 0)
      val () = $A.free<byte>(bytes)
    in stop end
  | ~AnswerCut(form, bytes, n, whole) => let
      val at = _put_detail(out, at, "\nAnswer, ")
      val at = _put_detail(out, at, form)
      val at = _put_detail(out, at, ", cut: its first")
      val at = _put_number(out, at, n)
      val at = _put_detail(out, at, " bytes of")
      val at = _put_number(out, at, whole)
      val at = _put_detail(out, at, ": ")
      val stop = _put_hiding(out, at, bytes, n, 0)
      val () = $A.free<byte>(bytes)
    in stop end

fn _put_code {l:agz}{at:nat | at <= DETAILS_MAX}
  (out: !$A.arr(byte, l, DETAILS_MAX), at: int at, code: $R.option([c:pos | c < 64] string c))
  : [stop:nat | at <= stop; stop <= DETAILS_MAX] int stop =
  case+ code of
  | ~$R.some(name) => _put_detail(out, _put_detail(out, at, "\nCode: "), name)
  | ~$R.none() => at

fn _details_end {l:agz}{at:nat | at <= DETAILS_MAX}
  (out: !$A.arr(byte, l, DETAILS_MAX), at: int at): [stop:nat | stop <= DETAILS_MAX] int stop =
  if at < DETAILS_MAX then at
  else let
    val () = $A.write_text(out, DETAILS_MAX - 44, $A.text_lit("\n[the details are cut here: they hold 1 MiB]"), 44)
  in DETAILS_MAX end

#pub fn notice_failure {said_loc:agz}{said_size:pos}
  {said_len:nat | said_len <= said_size; said_len < 65536}{doing_len:pos | doing_len < 128}{call_len:pos | call_len < 64}{code_len:pos | code_len < 64}
  (said: $A.arr(byte, said_loc, said_size), said_len: int said_len, doing: string doing_len, call: string call_len,
   code: string code_len, answer: answer_shown): void

fn _failure_said {said_loc:agz}{said_size:pos}
  {said_len:nat | said_len <= said_size; said_len < 65536}{doing_len:pos | doing_len < 128}{call_len:pos | call_len < 64}
  (said: $A.arr(byte, said_loc, said_size), said_len: int said_len, doing: string doing_len, call: string call_len,
   which: $R.option(unexpected_case), code: $R.option([c:pos | c < 64] string c), answer: answer_shown): void = let
  val out = $A.alloc<byte>(DETAILS_MAX)
  val at = _put_detail(out, 0, "Quire ")
  val at = _put_detail(out, at, quire_version())
  val at = _put_detail(out, at, "\nPlatform: ")
  val at = _put_detail(out, at, (if $BAPP.is_native_platform() then "Android app" else "web browser"))
  val at = _put_detail(out, at, "\nWhile: ")
  val at = _put_detail(out, at, doing)
  val at = _put_detail(out, at, "\nCall: ")
  val at = _put_detail(out, at, call)
  val at = _put_case(out, at, which)
  val at = _put_code(out, at, code)
  val at = _put_answer(out, at, answer)
  val at = _details_end(out, at)
  val () = (if at > 0 then _details_set(Details(out, at))
    else let val () = $A.free<byte>(out) in _details_set(NoDetails()) end)
  val () = ui_text_buf("error-text", said, said_len)
in _banner_show() end

implement notice_failure (said, said_len, doing, call, code, answer) =
  _failure_said(said, said_len, doing, call, $R.none(), $R.some(code), answer)

#pub fn notice_unexpected {doing_len:pos | doing_len < 128}{call_len:pos | call_len < 64}
  (doing: string doing_len, call: string call_len, which: unexpected_case, answer: answer_shown): void

implement notice_unexpected (doing, call, which, answer) = let
  val said = $A.alloc<byte>(512)
  val at = _put_text(said, 512, 0, "An unexpected error occurred while ")
  val at = _put_text(said, 512, at, doing)
  val at = _put_text(said, 512, at, ". Copy the details and post them in a report.")
in _failure_said(said, at, doing, call, $R.some(which), $R.none(), answer) end

(* The error banner goes (its Dismiss button, or a new import) *)
#pub fn notice_dismiss (): void

implement notice_dismiss () = let
  val () = !_banner_up := false
  val () = _details_buttons(false)
in ui_show("error-banner", false) end

(* A part of the open book (a chapter, or the list of them) could not
   be read *)
#pub fn notice_part_unread (): void

implement notice_part_unread () =
  notice_error("This part of the book could not be read. Its file may be damaged: import the book again.")

(* Whether this session has said that a save failed: when storage is
   full every later save fails too, and a banner at each page turn is
   the overuse of alerts SC 4.1.3 warns about, so it is said once *)
val _save_failure_told = ref<bool>(false)

(* Ends a write of the reader's own data to storage (an IndexedDB put):
   NotStored (the transaction aborted, as it does when storage is full)
   shows the banner, once a session. It never takes the place
   of a message still up (the failure of a book's own file names the
   book, and says to free space too): it waits for a later failure *)
#pub fn save_failed (): void

#pub fn save_checked {s:$P.promise_state} (saving: $P.promise($IDB.stored, s)): void

implement save_failed () =
  if !_save_failure_told then ()
  else if !_banner_up then ()
  else let
    val () = !_save_failure_told := true
  in notice_error("Quire could not save your changes. The browser's storage may be full: free some space and try again.") end

implement save_checked (saving) = $P.finish<$IDB.stored>(saving, llam(status) =>
  case+ status of
  | $IDB.Stored() => ()
  | $IDB.NotStored() => save_failed())

(* How long the copy status stays, in milliseconds *)
#define COPIED_SHOWN 2000

(* The number of the last copy said: a later one keeps the status up *)
val _copied_serial = ref<int>(0)

(* The copy status says "Copied", for a moment *)
#pub fn notice_copied (): void

implement notice_copied () = let
  val serial = !_copied_serial + 1
  val () = !_copied_serial := serial
  val () = ui_text("copy-status", "Copied")
  val () = ui_show("copy-status", true)
in
  (* a timer's status carries nothing *)
  $P.finish<Int>($P.vow($TM.timer_set(COPIED_SHOWN)), llam(_) =>
    if !_copied_serial = serial then ui_show("copy-status", false) else ())
end

fn _details_copied {l:agz}{count:pos | count <= DETAILS_MAX} (text: !$A.arr(byte, l, DETAILS_MAX), count: int count)
  : [c:agz] $A.arr(byte, c, count) = let
  val copy = $A.alloc<byte>(count)
  fun fill {c:agz}{j:nat | j <= count} .<count - j>.
    (copy: !$A.arr(byte, c, count), text: !$A.arr(byte, l, DETAILS_MAX), j: int j): void =
    if j >= count then ()
    else let val () = $A.set<byte>(copy, j, $A.get<byte>(text, j)) in fill(copy, text, j + 1) end
  val () = fill(copy, text, 0)
in copy end

#pub fn notice_details_copy (): void

implement notice_details_copy () =
  case+ _details_swap(NoDetails()) of
  | ~NoDetails() => ()
  | ~Details(text, text_len) => let
      val copy = _details_copied(text, text_len)
      val () = _details_free(_details_swap(Details(text, text_len)))
      val @(frozen, bytes) = $A.freeze<byte>(copy)
      (* a copy that failed is said: the reader would otherwise paste
         something stale *)
      val () = $P.finish<$CB.copied>($CB.clipboard_write(bytes, text_len), llam(copied) =>
        case+ copied of
        | $CB.Copied() => notice_copied()
        | $CB.NotCopied() => notice_error("The details could not be copied: the browser did not allow it."))
    in release_bytes(frozen, bytes) end

end (* #target wasm *)
