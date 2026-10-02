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

staload "ui.sats"
staload TM = "wasm.bats-packages.dev/bridge/src/timer.sats"

(* Whether the error banner is up *)
val _banner_up = ref<bool>(false)

fn _banner_show (): void = let
  val () = !_banner_up := true
in ui_show("error-banner", true) end

(* The error banner, saying text *)
#pub fn notice_error {text_len:pos | text_len < 256} (text: string text_len): void

implement notice_error (text) = let
  val () = ui_text("error-text", text)
in _banner_show() end

(* The error banner, saying text[0, text_len) *)
#pub fn notice_error_buf {l:agz}{n:pos}{text_len:nat | text_len <= n; text_len < 65536}
  (text: $A.arr(byte, l, n), text_len: int text_len): void

implement notice_error_buf (text, text_len) = let
  val () = ui_text_buf("error-text", text, text_len)
in _banner_show() end

(* The error banner goes (its Dismiss button, or a new import) *)
#pub fn notice_dismiss (): void

implement notice_dismiss () = let
  val () = !_banner_up := false
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
   a status below 0 (the transaction aborted, as it does when storage
   is full) shows the banner, once a session. It never takes the place
   of a message still up (the failure of a book's own file names the
   book, and says to free space too): it waits for a later failure *)
#pub fn save_checked {s:int} (saving: $P.promise(Int, s)): void

implement save_checked (saving) = $P.finish<Int>(saving, lam(status) =>
  if status >= 0 then ()
  else if !_save_failure_told then ()
  else if !_banner_up then ()
  else let
    val () = !_save_failure_told := true
  in notice_error("Quire could not save your changes. The browser's storage may be full: free some space and try again.") end)

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
  $P.finish<Int>($P.vow($TM.timer_set(COPIED_SHOWN)), lam(_) =>
    if !_copied_serial = serial then ui_show("copy-status", false) else ())
end

end (* #target wasm *)
