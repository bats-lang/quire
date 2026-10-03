#target native
(* gen-pwa -- generate PWA shell for quire *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use file as F
#use pwa as P
#use result as R

staload "version.sats"

(* Appends to the Android project's android-release.gradle (which
   build-android.sh appends to the app's build.gradle) the version of the
   commit built from (#219): versionName is the version About shows, and
   versionCode that commit's time in minutes since 2025, so it grows from
   release to release. Set after pwa's run-number version code, it is
   the one Gradle takes *)
fn _android_version (): void = let
  var b = $B.create()
  val () = $B.bput(b, "\n// Appended by quire's gen-pwa: the version of the commit built from (#219)\n")
  val () = $B.bput(b, "android {\n    defaultConfig {\n        versionCode ")
  val () = $B.bput(b, quire_version_code())
  val () = $B.bput(b, "\n        versionName '")
  val () = $B.bput(b, quire_version())
  val () = $B.bput(b, "'\n    }\n}\n")
  var path = $B.create()
  val () = $B.bput(path, "dist/android/android-release.gradle")
  val () = $B.put_char(path, 0)
  val @(path_bytes, _) = $B.to_arr(path)
  val @(path_frozen, path_borrow) = $A.freeze<byte>(path_bytes)
  val opened = $F.file_open(path_borrow, 524288, $F.WriteOnly(), $F.CreateOrAppend(), 420)
  val () = $A.drop<byte>(path_frozen, path_borrow)
  val () = $A.free<byte>($A.thaw<byte>(path_frozen))
  val @(content, content_len) = $B.to_arr(b)
  val @(content_frozen, content_borrow) = $A.freeze<byte>(content)
in
  case+ opened of
  | ~$R.ok(fd) => let
      val () = (if content_len > 0 then let
          val @(written, rest) = $A.borrow_split<byte>(content_frozen, content_borrow, content_len)
          val () = $R.discard<int><$F.io_error>((case+ $F.file_write(fd, written, content_len) of
            | ~$R.ok(w) => $R.ok(w) | ~$R.err(e) => $R.err(e)): $R.result(int, $F.io_error))
          val () = $A.drop<byte>(content_frozen, $A.borrow_join<byte>(content_frozen, written, rest))
        in $A.free<byte>($A.thaw<byte>(content_frozen)) end
        else let
          val () = $A.drop<byte>(content_frozen, content_borrow)
        in $A.free<byte>($A.thaw<byte>(content_frozen)) end)
    in $R.discard<int><$F.io_error>($F.file_close(fd)) end
  | ~$R.err(_) => let
      val () = $A.drop<byte>(content_frozen, content_borrow)
    in $A.free<byte>($A.thaw<byte>(content_frozen)) end
end

implement main0 () = let
  (* The bundled fonts (the stylesheet names them) and the app's icons,
     copied next to the page: each path followed by a NUL (the array
     starts zeroed) *)
  val f1 = "assets/fonts/literata-latin.woff2"
  val f2 = "assets/fonts/literata-italic-latin.woff2"
  val f3 = "assets/fonts/inter-latin.woff2"
  val f4 = "assets/icons/icon-192.png"
  val f5 = "assets/icons/icon-512.png"
  val f6 = "assets/fonts/atkinson-400-normal.woff2"
  val f7 = "assets/fonts/atkinson-700-normal.woff2"
  val f8 = "assets/fonts/atkinson-400-italic.woff2"
  val f9 = "assets/fonts/atkinson-700-italic.woff2"
  val n1 = g1u2i(string1_length(f1))
  val n2 = g1u2i(string1_length(f2))
  val n3 = g1u2i(string1_length(f3))
  val n4 = g1u2i(string1_length(f4))
  val n5 = g1u2i(string1_length(f5))
  val n6 = g1u2i(string1_length(f6))
  val n7 = g1u2i(string1_length(f7))
  val n8 = g1u2i(string1_length(f8))
  val n9 = g1u2i(string1_length(f9))
  val n = n1 + n2 + n3 + n4 + n5 + n6 + n7 + n8 + n9 + 9
  val assets = $A.alloc<byte>(n)
  val () = $A.write_text(assets, 0, $A.text_lit(f1), n1)
  val () = $A.write_text(assets, n1 + 1, $A.text_lit(f2), n2)
  val () = $A.write_text(assets, n1 + n2 + 2, $A.text_lit(f3), n3)
  val () = $A.write_text(assets, n1 + n2 + n3 + 3, $A.text_lit(f4), n4)
  val () = $A.write_text(assets, n1 + n2 + n3 + n4 + 4, $A.text_lit(f5), n5)
  val p6 = n1 + n2 + n3 + n4 + n5 + 5
  val () = $A.write_text(assets, p6, $A.text_lit(f6), n6)
  val () = $A.write_text(assets, p6 + n6 + 1, $A.text_lit(f7), n7)
  val () = $A.write_text(assets, p6 + n6 + n7 + 2, $A.text_lit(f8), n8)
  val () = $A.write_text(assets, p6 + n6 + n7 + n8 + 3, $A.text_lit(f9), n9)
  (* installed, the system opens EPUBs with it and shares them with it *)
  val () = $P.create_pwa_opening("Quire", "dev.bats.quire",
    "dist/release/quire.wasm", "app.wasm", "dist/pwa",
    assets, n, n, "application/epub+zip", ".epub")
  val () = $A.free<byte>(assets)
  val () = println! ("PWA generated in dist/pwa/")
  (* The Capacitor project around it; its id is the one Quire is
     published under on Google Play. It opens EPUBs, and is shared
     them; and it is opened at quire:// addresses, as Dropbox's sign-in
     in the system's browser comes back (quire://oauth/dropbox) *)
  val () = $P.create_android_linked("Quire", "dev.middlefield.quire", "../pwa", "dist/android", "application/epub+zip", "quire")
  val () = _android_version()
  val () = println! ("Android project generated in dist/android/")
in end
