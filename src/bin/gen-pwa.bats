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
  (* The bundled fonts, copied next to the page (the stylesheet names
     them): each path followed by a NUL (the array starts zeroed) *)
  val f1 = "assets/fonts/literata-latin.woff2"
  val f2 = "assets/fonts/literata-italic-latin.woff2"
  val f3 = "assets/fonts/inter-latin.woff2"
  val n1 = g1u2i(string1_length(f1))
  val n2 = g1u2i(string1_length(f2))
  val n3 = g1u2i(string1_length(f3))
  val n = n1 + n2 + n3 + 3
  val assets = $A.alloc<byte>(n)
  val () = $A.write_text(assets, 0, $A.text_lit(f1), n1)
  val () = $A.write_text(assets, n1 + 1, $A.text_lit(f2), n2)
  val () = $A.write_text(assets, n1 + n2 + 2, $A.text_lit(f3), n3)
  val () = $P.create_pwa("Quire", "dev.bats.quire",
    "dist/release/quire.wasm", "app.wasm", "dist/pwa",
    assets, n, n)
  val () = $A.free<byte>(assets)
  val () = println! ("PWA generated in dist/pwa/")
  (* The Capacitor project around it; its id is the one Quire is
     published under on Google Play *)
  val () = $P.create_android("Quire", "dev.middlefield.quire", "../pwa", "dist/android")
  val () = println! ("Android project generated in dist/android/")
in end
