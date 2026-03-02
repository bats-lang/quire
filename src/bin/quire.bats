(* quire -- EPUB e-reader *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use wasm.bats-packages.dev/bridge as BR

(* Write a DOM diff CREATE_ELEMENT opcode into the builder.
   Format: [4:opcode][u16le:nidLen][nidBytes][u16le:pidLen][pidBytes][tag:byte][classCount:byte]
   tag 3 = div *)
fn emit_create_div {sn:nat}{pn:nat}
  (buf: !$B.builder, nid: string sn, nid_len: int sn,
   pid: string pn, pid_len: int pn, class_count: int): void = let
  val () = $B.put_byte(buf, 4) (* opcode: CREATE_ELEMENT *)
  val () = $B.put_byte(buf, nid_len) (* u16le low *)
  val () = $B.put_byte(buf, 0) (* u16le high *)
  val () = $B.bput(buf, nid) (* node id *)
  val () = $B.put_byte(buf, pid_len) (* u16le low *)
  val () = $B.put_byte(buf, 0) (* u16le high *)
  val () = $B.bput(buf, pid) (* parent id *)
  val () = $B.put_byte(buf, 3) (* tag: div *)
  val () = $B.put_byte(buf, class_count) (* class count *)
in end

(* Write a SET_ATTR opcode for class attribute.
   Format: [2:opcode][u16le:nidLen][nidBytes][attr:byte][u16le:valLen][valBytes]
   attr 0 = class *)
fn emit_set_class {sn:nat}{cn:nat}
  (buf: !$B.builder, nid: string sn, nid_len: int sn,
   cls: string cn, cls_len: int cn): void = let
  val () = $B.put_byte(buf, 2) (* opcode: SET_ATTR *)
  val () = $B.put_byte(buf, nid_len) (* u16le low *)
  val () = $B.put_byte(buf, 0) (* u16le high *)
  val () = $B.bput(buf, nid) (* node id *)
  val () = $B.put_byte(buf, 0) (* attr: class *)
  val () = $B.put_byte(buf, cls_len) (* u16le low *)
  val () = $B.put_byte(buf, 0) (* u16le high *)
  val () = $B.bput(buf, cls) (* class value *)
in end

(* Write a SET_TEXT opcode.
   Format: [1:opcode][u16le:nidLen][nidBytes][u16le:textLen][textBytes] *)
fn emit_set_text {sn:nat}{tn:nat}
  (buf: !$B.builder, nid: string sn, nid_len: int sn,
   text: string tn, text_len: int tn): void = let
  val () = $B.put_byte(buf, 1) (* opcode: SET_TEXT *)
  val () = $B.put_byte(buf, nid_len) (* u16le low *)
  val () = $B.put_byte(buf, 0) (* u16le high *)
  val () = $B.bput(buf, nid) (* node id *)
  val () = $B.put_byte(buf, text_len) (* u16le low *)
  val () = $B.put_byte(buf, 0) (* u16le high *)
  val () = $B.bput(buf, text) (* text *)
in end

implement main0 () = let
  val buf = $A.alloc<byte>(524288)
  val db = $B.create()

  (* Create library-list div inside bats-root *)
  val () = emit_create_div(db, "lib", 3, "bats-root", 9, 1)
  val () = emit_set_class(db, "lib", 3, "library-list", 12)

  (* Create empty-lib message div *)
  val () = emit_create_div(db, "empty", 5, "lib", 3, 1)
  val () = emit_set_class(db, "empty", 5, "empty-lib", 9)
  val () = emit_set_text(db, "empty", 5, "No books yet", 12)

  (* Create import button label *)
  val () = emit_create_div(db, "imp", 3, "lib", 3, 1)
  val () = emit_set_class(db, "imp", 3, "import-btn", 10)

  (* Flush DOM diff *)
  val @(da, dl) = $B.to_arr(db)
  val () = $BR.dom_flush(da, dl)
  val () = $A.free<byte>(da)
  val () = $A.free<byte>(buf)
in end
