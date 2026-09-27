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
  val assets = $A.alloc<byte>(1)
  val () = $P.create_pwa("Quire", "dev.bats.quire",
    "dist/release/quire.wasm", "app.wasm", "dist/pwa",
    assets, 0, 1)
  val () = $A.free<byte>(assets)
  val () = println! ("PWA generated in dist/pwa/")
  (* The Capacitor project around it; its id is the one Quire is
     published under on Google Play *)
  val () = $P.create_android("Quire", "dev.middlefield.quire", "../pwa", "dist/android")
  val () = println! ("Android project generated in dist/android/")
in end
