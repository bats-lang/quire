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

(* Where the error banner sits: at the top of the window (the reader with
   its bars away, and before any view is shown), in the library's flow
   above its header, or under the reader's top bar. The view says it
   (banner_place_set) as it changes, instead of the stylesheet asking
   `#bats-root:has(...)`: a :has() on the root that holds the chapter is
   re-evaluated over its whole subtree at every change of the page's
   chrome, which cost 16 to 27 ms a change on a 5 MB chapter, four times a
   page turn (#423) *)
#pub datatype banner_place = BannerAtTop | BannerInLibrary | BannerUnderBars

#pub fn banner_place_set (place: banner_place): void

implement banner_place_set (place) =
  case+ place of
  | BannerAtTop() => ui_attr("error-banner", AClass, "banner")
  | BannerInLibrary() => ui_attr("error-banner", AClass, "banner in-library")
  | BannerUnderBars() => ui_attr("error-banner", AClass, "banner under-bars")

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

(* The reader's next step shows as the banner's Reopen Quire button only
   when reopening is the step *)
fn _reopen_show (shown: bool): void = ui_show("error-reopen", shown)

(* The error banner, saying text[0, text_len): a sync's result, whose
   words and next step sync makes from its own `sync_result` *)
#pub fn notice_sync_said {l:agz}{n:pos}{text_len:nat | text_len <= n; text_len < 65536}
  (text: $A.arr(byte, l, n), text_len: int text_len): void

(* The error banner, saying text[0, text_len), and Reopen Quire when
   reopen. Private: what the banner says is a failure, in words made here
   (notice_say), so a message cannot go without a next step (#360) *)
fn _error_buf {l:agz}{n:pos}{text_len:nat | text_len <= n; text_len < 65536}
  (text: $A.arr(byte, l, n), text_len: int text_len, reopen: bool): void = let
  val () = _details_buttons(false)
  val () = _reopen_show(reopen)
  val () = ui_text_buf("error-text", text, text_len)
in _banner_show() end

implement notice_sync_said (text, text_len) = _error_buf(text, text_len, false)

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
  val () = _reopen_show(false)
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

(* Where Quire runs: its words say "the browser" only in one *)
#pub datatype host =
  | InBrowser
  | InApp

fn _host (): host = if $BAPP.is_native_platform() then InApp() else InBrowser()

(* What failed. Every banner says one of these, and its words and its
   next step are made from it by two total matches (_what_put,
   remedy_of), so a failure added without either does not type-check *)
#pub datatype failure =
  | LibraryNotAdded
  | HandedBookNotAdded
  | SettingsNotRead
  | CataloguesNotRead
  | DictionariesNotRead
  | AnnotationsNotRead
  | BookFileLost
  | BookStorageFailed
  | PartNotRead
  | StorageFull
  | RecordFromNewerQuire
  | RecordDamaged
  | RecordNotQuires
  | BooksNotRead
  | BooksNotReadCanSetAside
  | AsideNotRead
  | AsideIncomplete
  | DetailsDamaged
  | CollectionsNotRead
  | CollectionsNotReadCanSetAside
  | NarrationNotPlayable
  | RotationNotLockable
  | GrantNotTaken
  | GrantNoAnswer
  | TextNotCopied
  | DetailsNotCopied

(* What failed to a file or book that has a name *)
#pub datatype named_failure =
  | NotAnEpub
  | ContainerDamaged
  | PackageMissing
  | PackageDamaged
  | ReadingNotFinished
  | NotKeptInLibrary
  | FileEmpty
  | FileNotRead
  | BookFileNotStored

(* The next step a banner offers: words, and for ReopenQuire a button *)
#pub datatype remedy =
  | ReopenQuire
  | LibraryScreenSays
  | ImportAgain
  | OtherChapterOrReplace
  | ChooseAnotherFile
  | UpdateQuire
  | FreeSpace
  | OpenAgain
  | RemoveGrantByHand
  | UseDeviceRotation
  | CopyByHand
  | RestoreBackup
  | SetAsideInSettings
  | SetAsideAgain
  | TryNextPhrase

fn remedy_of (failed: failure): remedy =
  case+ failed of
  | LibraryNotAdded() => LibraryScreenSays()
  | HandedBookNotAdded() => LibraryScreenSays()
  | SettingsNotRead() => ReopenQuire()
  | CataloguesNotRead() => ReopenQuire()
  | DictionariesNotRead() => ReopenQuire()
  | AnnotationsNotRead() => ReopenQuire()
  | BookFileLost() => ImportAgain()
  | BookStorageFailed() => OpenAgain()
  | PartNotRead() => OtherChapterOrReplace()
  | StorageFull() => FreeSpace()
  | RecordFromNewerQuire() => UpdateQuire()
  | RecordDamaged() => RestoreBackup()
  | RecordNotQuires() => RestoreBackup()
  | BooksNotRead() => RestoreBackup()
  | BooksNotReadCanSetAside() => SetAsideInSettings()
  | AsideNotRead() => ReopenQuire()
  | AsideIncomplete() => SetAsideAgain()
  | DetailsDamaged() => RestoreBackup()
  | CollectionsNotRead() => RestoreBackup()
  | CollectionsNotReadCanSetAside() => SetAsideInSettings()
  | NarrationNotPlayable() => TryNextPhrase()
  | RotationNotLockable() => UseDeviceRotation()
  | GrantNotTaken() => RemoveGrantByHand()
  | GrantNoAnswer() => RemoveGrantByHand()
  | TextNotCopied() => CopyByHand()
  | DetailsNotCopied() => CopyByHand()

fn named_remedy_of (failed: named_failure): remedy =
  case+ failed of
  | NotAnEpub() => ChooseAnotherFile()
  | ContainerDamaged() => ChooseAnotherFile()
  | PackageMissing() => ChooseAnotherFile()
  | PackageDamaged() => ChooseAnotherFile()
  | ReadingNotFinished() => ImportAgain()
  | NotKeptInLibrary() => ReopenQuire()
  | FileEmpty() => ChooseAnotherFile()
  | FileNotRead() => ChooseAnotherFile()
  | BookFileNotStored() => FreeSpace()

fn _put_number_at {l:agz}{cap:pos}{at:nat | at <= cap}
  (out: !$A.arr(byte, l, cap), cap: int cap, at: int at, v: int): [stop:nat | at <= stop; stop <= cap] int stop = let
  val digits = $A.alloc<byte>(12)
  val start = _digits_put(digits, 12, v)
  fun copy {d,o:agz}{c:pos}{j:nat | j <= 12}{k:nat | k <= c} .<12 - j>.
    (out: !$A.arr(byte, o, c), cap: int c, at: int k, digits: !$A.arr(byte, d, 12), j: int j)
    : [stop:nat | k <= stop; stop <= c] int stop =
    if j >= 12 then at
    else if at >= cap then at
    else let
      val () = $A.set<byte>(out, at, $A.get<byte>(digits, j))
    in copy(out, cap, at + 1, digits, j + 1) end
  val stop = copy(out, cap, at, digits, start)
  val () = $A.free<byte>(digits)
in stop end

fun _copy_name {l,o:agz}{n,c:pos}{name_len:nat | name_len <= n; name_len < 256}{at:nat | at + name_len <= c}{j:nat | j <= name_len} .<name_len - j>.
  (name: !$A.arr(byte, l, n), name_len: int name_len, out: !$A.arr(byte, o, c), at: int at, j: int j)
  : int(at + name_len) =
  if j >= name_len then at + name_len
  else let
    val () = $A.set<byte>(out, at + j, $A.get<byte>(name, j))
  in _copy_name(name, name_len, out, at, j + 1) end

(* What happened, without its next step and without a final period;
   part is the chapter (from 1) a PartNotRead names, 0 for the contents *)
fn _what_put {l:agz}{at:nat | at <= 512}
  (out: !$A.arr(byte, l, 512), at: int at, failed: failure, where_: host, part: int)
  : [stop:nat | at <= stop; stop <= 512] int stop =
  case+ failed of
  | LibraryNotAdded() => _put_text(out, 512, at, "Books cannot be added until Quire can read your library")
  | HandedBookNotAdded() => _put_text(out, 512, at, "This book was not added: Quire could not read your library")
  | SettingsNotRead() => _put_text(out, 512, at, "Quire could not read your settings, so it is using the defaults and changes will not be saved")
  | CataloguesNotRead() => _put_text(out, 512, at, "Quire could not read your catalogues, so changes to them will not be saved")
  | DictionariesNotRead() => _put_text(out, 512, at, "Quire could not read your dictionaries, so changes to them will not be saved")
  | AnnotationsNotRead() => _put_text(out, 512, at, "This book's highlights and notes could not be read, so new ones cannot be made and the old ones are kept")
  | BookFileLost() => _put_text(out, 512, at, "This book's file could not be read")
  | BookStorageFailed() => _put_text(out, 512, at, "This book could not be read from storage")
  | PartNotRead() =>
    if part > 0 then let
      val at = _put_text(out, 512, at, "Chapter ")
      val at = _put_number_at(out, 512, at, part)
    in _put_text(out, 512, at, " of this book could not be read") end
    else _put_text(out, 512, at, "The contents of this book could not be read")
  | StorageFull() =>
    (case+ where_ of
    | InBrowser() => _put_text(out, 512, at, "Quire could not save your changes: the browser's storage may be full")
    | InApp() => _put_text(out, 512, at, "Quire could not save your changes: the device's storage may be full"))
  | RecordFromNewerQuire() => _put_text(out, 512, at, "A book's stored record was written by a newer Quire, so changes to it are not saved")
  | RecordDamaged() => _put_text(out, 512, at, "A book's stored record is damaged, so changes to it are not saved and your other books are saved")
  | RecordNotQuires() => _put_text(out, 512, at, "A book's stored record is not one Quire wrote, so changes to it are not saved")
  | BooksNotRead() => _put_text(out, 512, at, "Some books in your library could not be read, so they are left as they are and not shown")
  | AsideNotRead() => _put_text(out, 512, at, "Quire could not read your library to set those records aside, so nothing was changed")
  | AsideIncomplete() => _put_text(out, 512, at, "Some records could not be set aside, and nothing was lost")
  | BooksNotReadCanSetAside() => _put_text(out, 512, at, "Some books in your library could not be read, so they are left as they are and not shown")
  | DetailsDamaged() => _put_text(out, 512, at, "Some details of your library were damaged and show as defaults, and the rest of it is intact")
  | CollectionsNotRead() => _put_text(out, 512, at, "Your collections could not be read, so they are left as they are and not shown")
  | CollectionsNotReadCanSetAside() => _put_text(out, 512, at, "Your collections could not be read, so they are left as they are and not shown")
  | NarrationNotPlayable() => _put_text(out, 512, at, "This narration cannot be played")
  | RotationNotLockable() => _put_text(out, 512, at, "This device does not let Quire lock the rotation, so Lock rotation is no longer offered")
  | GrantNotTaken() => _put_text(out, 512, at, "Google didn't take back Quire's access to Drive")
  | GrantNoAnswer() => _put_text(out, 512, at, "Google didn't answer when Quire took back its access to Drive")
  | TextNotCopied() =>
    (case+ where_ of
    | InBrowser() => _put_text(out, 512, at, "The text could not be copied: the browser did not allow it")
    | InApp() => _put_text(out, 512, at, "The text could not be copied: the device did not allow it"))
  | DetailsNotCopied() =>
    (case+ where_ of
    | InBrowser() => _put_text(out, 512, at, "The details could not be copied: the browser did not allow it")
    | InApp() => _put_text(out, 512, at, "The details could not be copied: the device did not allow it"))

(* What happened to the file or book named, after its name *)
fn _named_what_put {l:agz}{at:nat | at <= 512}
  (out: !$A.arr(byte, l, 512), at: int at, failed: named_failure): [stop:nat | at <= stop; stop <= 512] int stop =
  case+ failed of
  | NotAnEpub() => _put_text(out, 512, at, " is not an EPUB: it has no container.xml, so it could not be imported")
  | ContainerDamaged() => _put_text(out, 512, at, " has a damaged container.xml, so it could not be imported")
  | PackageMissing() => _put_text(out, 512, at, " has no package document (.opf), so it could not be imported")
  | PackageDamaged() => _put_text(out, 512, at, " has a damaged package document (.opf), so it could not be imported")
  | ReadingNotFinished() => _put_text(out, 512, at, " was not finished being read, so it was not imported")
  | NotKeptInLibrary() => _put_text(out, 512, at, " could not be added to your library")
  | FileEmpty() => _put_text(out, 512, at, " is empty, so it could not be imported")
  | FileNotRead() => _put_text(out, 512, at, " could not be read")
  | BookFileNotStored() => _put_text(out, 512, at, " is open, but its file could not be stored, so it will not open next time")

(* The next step, after the sentence it follows: it starts with its
   own separator *)
fn _remedy_put {l:agz}{at:nat | at <= 512}
  (out: !$A.arr(byte, l, 512), at: int at, next: remedy, where_: host): [stop:nat | at <= stop; stop <= 512] int stop =
  case+ next of
  | ReopenQuire() => _put_text(out, 512, at, ". Reopen Quire to try again.")
  | LibraryScreenSays() => _put_text(out, 512, at, ". The library screen says why and what to do; then open or share the book again.")
  | ImportAgain() => _put_text(out, 512, at, ". Import the book again and choose Replace when Quire says it is already in your library.")
  | OtherChapterOrReplace() => _put_text(out, 512, at, ". Choose another chapter in the contents, or import the book again and choose Replace.")
  | ChooseAnotherFile() => _put_text(out, 512, at, ". Choose another file, or get the book again from where you had it.")
  | UpdateQuire() => _put_text(out, 512, at, ". Update Quire.")
  | FreeSpace() =>
    (case+ where_ of
    | InBrowser() => _put_text(out, 512, at, ". Free some space in the browser and try again.")
    | InApp() => _put_text(out, 512, at, ". Free some space on the device and try again."))
  | OpenAgain() => _put_text(out, 512, at, ". Quire tried three times; the book is still stored, so try opening it again in a moment.")
  | RemoveGrantByHand() => _put_text(out, 512, at, ": remove it in your Google account, under Security, Your connections to third-party apps.")
  | UseDeviceRotation() => _put_text(out, 512, at, ". Turn the device's own rotation lock on instead.")
  | CopyByHand() => _put_text(out, 512, at, ". Select the text and copy it yourself.")
  | RestoreBackup() => _put_text(out, 512, at, ". Restore a backup in Settings to bring back what is missing.")
  | SetAsideAgain() => _put_text(out, 512, at, ". Press Set aside unreadable records in Settings to try those again.")
  | SetAsideInSettings() => _put_text(out, 512, at, ". Settings can set them aside.")
  | TryNextPhrase() => _put_text(out, 512, at, ". Try Next phrase, or read the book without the narration.")

fn _reopens (next: remedy): bool =
  case+ next of
  | ReopenQuire() => true
  | LibraryScreenSays() => false
  | ImportAgain() => false
  | OtherChapterOrReplace() => false
  | ChooseAnotherFile() => false
  | UpdateQuire() => false
  | FreeSpace() => false
  | OpenAgain() => false
  | RemoveGrantByHand() => false
  | UseDeviceRotation() => false
  | CopyByHand() => false
  | RestoreBackup() => false
  | SetAsideInSettings() => false
  | SetAsideAgain() => false
  | TryNextPhrase() => false

(* The error banner, saying what failed and what to do next (the one
   place the reader's words for a failure are made, #360) *)
#pub fn notice_say (failed: failure): void

(* The same for a chapter (from 1) that could not be read, which it
   names; 0 is the contents *)
#pub fn notice_say_part (chapter: int): void

fn _say (failed: failure, part: int): void = let
  val where_ = _host()
  val next = remedy_of(failed)
  val out = $A.alloc<byte>(512)
  val at = _what_put(out, 0, failed, where_, part)
  val at = _remedy_put(out, at, next, where_)
in _error_buf(out, at, _reopens(next)) end

implement notice_say (failed) = _say(failed, 0)

implement notice_say_part (chapter) = _say(PartNotRead(), chapter)

(* The same, for the file or book whose name is name[0, name_len) *)
#pub fn notice_say_named {l:agz}{n:pos}{name_len:nat | name_len <= n; name_len < 256}
  (name: !$A.arr(byte, l, n), name_len: int name_len, failed: named_failure): void

implement notice_say_named (name, name_len, failed) = let
  val where_ = _host()
  val next = named_remedy_of(failed)
  val out = $A.alloc<byte>(512)
  val at = _copy_name(name, name_len, out, 0, 0)
  val at = _named_what_put(out, at, failed)
  val at = _remedy_put(out, at, next, where_)
in _error_buf(out, at, _reopens(next)) end

(* The error banner goes (its Dismiss button, or a new import) *)
#pub fn notice_dismiss (): void

implement notice_dismiss () = let
  val () = !_banner_up := false
  val () = _details_buttons(false)
in ui_show("error-banner", false) end

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
  in notice_say(StorageFull()) end

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
        | $CB.NotCopied() => notice_say(DetailsNotCopied()))
    in release_bytes(frozen, bytes) end

end (* #target wasm *)
