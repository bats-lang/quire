(* quire -- EPUB e-reader *)

#include "share/atspre_staload.hats"

#use array as A
#use arith as AR
#use builder as B
#use wasm.bats-packages.dev/bridge as BR

(* Write u16le to builder *)
fn put_u16le(buf: !$B.builder, v: int): void = let
  val () = $B.put_byte(buf, v - (v / 256) * 256)
  val () = $B.put_byte(buf, v / 256)
in end

(* Write a string with u16le length prefix *)
fn put_str {sn:nat}
  (buf: !$B.builder, s: string sn, slen: int sn): void = let
  val () = put_u16le(buf, slen)
  val () = $B.bput(buf, s)
in end

(* Write CREATE_ELEMENT: [4][u16:nidLen][nid][u16:pidLen][pid][tagLen:1][tag] *)
fn emit_create {sn:nat}{pn:nat}{tn:nat}
  (buf: !$B.builder, nid: string sn, nlen: int sn,
   pid: string pn, plen: int pn,
   tag: string tn, tlen: int tn): void = let
  val () = $B.put_byte(buf, 4)
  val () = put_str(buf, nid, nlen)
  val () = put_str(buf, pid, plen)
  val () = $B.put_byte(buf, tlen)
  val () = $B.bput(buf, tag)
in end

(* Write SET_ATTR: [2][u16:nidLen][nid][nameLen:1][name][u16:valLen][val] *)
fn emit_attr {sn:nat}{an:nat}{vn:nat}
  (buf: !$B.builder, nid: string sn, nlen: int sn,
   attr_name: string an, alen: int an,
   attr_val: string vn, vlen: int vn): void = let
  val () = $B.put_byte(buf, 2)
  val () = put_str(buf, nid, nlen)
  val () = $B.put_byte(buf, alen) (* 1-byte name length *)
  val () = $B.bput(buf, attr_name)
  val () = put_u16le(buf, vlen)
  val () = $B.bput(buf, attr_val)
in end

(* Write SET_TEXT: [1][u16:nidLen][nid][u16:textLen][text] *)
fn emit_text {sn:nat}{tn:nat}
  (buf: !$B.builder, nid: string sn, nlen: int sn,
   text: string tn, tlen: int tn): void = let
  val () = $B.put_byte(buf, 1)
  val () = put_str(buf, nid, nlen)
  val () = put_str(buf, text, tlen)
in end

implement main0 () = let
  val db = $B.create()

  (* Create library-list div inside bats-root *)
  val () = emit_create(db, "lib", 3, "bats-root", 9, "div", 3)
  val () = emit_attr(db, "lib", 3, "class", 5, "library-list", 12)

  (* Create empty-lib message div *)
  val () = emit_create(db, "empty", 5, "lib", 3, "div", 3)
  val () = emit_attr(db, "empty", 5, "class", 5, "empty-lib", 9)
  val () = emit_text(db, "empty", 5, "No books yet", 12)

  (* Create import button label *)
  val () = emit_create(db, "imp", 3, "lib", 3, "label", 5)
  val () = emit_attr(db, "imp", 3, "class", 5, "import-btn", 10)

  (* Flush DOM diff *)
  val @(da, dl) = $B.to_arr(db)
  val () = $BR.dom_flush(da, dl)
  val () = $A.free<byte>(da)
in end
