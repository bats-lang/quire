(* quire -- EPUB e-reader *)

#target wasm binary
#include "share/atspre_staload.hats"
#use str as S
#use widget as W
#use wasm.bats-packages.dev/dom as D

implement main0 () = let
  var tag = @[char][3]('d', 'i', 'v')
  var mid = @[char][9]('b', 'a', 't', 's', '-', 'r', 'o', 'o', 't')
  val doc = $D.create_document($S.text_of_chars(tag, 3), 3, $S.text_of_chars(mid, 9), 9)

  var lib_c = @[char][3]('l', 'i', 'b')
  val lib_id = $W.Generated($S.text_of_chars(lib_c, 3), 3)
  var empty_c = @[char][5]('e', 'm', 'p', 't', 'y')
  val empty_id = $W.Generated($S.text_of_chars(empty_c, 5), 5)
  var imp_c = @[char][3]('i', 'm', 'p')
  val imp_id = $W.Generated($S.text_of_chars(imp_c, 3), 3)

  val () = render_library_empty(doc, lib_id, empty_id, imp_id)

  val () = $D.destroy(doc)
in end
