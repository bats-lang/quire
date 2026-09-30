#target native
(* gen-pwa -- generate PWA shell for quire *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use file as F
#use pwa as P
#use result as R

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
     them. *)
  val () = $P.create_android("Quire", "dev.middlefield.quire", "../pwa", "dist/android", "application/epub+zip")
  val () = println! ("Android project generated in dist/android/")
in end
