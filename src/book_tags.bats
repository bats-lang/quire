(* book_tags -- the tag of a book element, from its name in the document (keyword: book container) *)

#target wasm begin

#include "share/atspre_staload.hats"

#use array as A

staload DB = "wasm.bats-packages.dev/dom/src/book.sats"

(* The name's bytes are the text, from i on *)
fun _is_at {l:agz}{n:pos}{cs:$A.cells}{o,k:nat | o + k <= n}{i:nat | i <= k} .<k - i>.
  (bytes: !$A.cborrow(l, n, cs), offset: int o, text: string k, length: int k, i: int i): bool =
  if i >= length then true
  else let
    val (_ | value) = $A.cborrow_get(bytes, offset + i)
    val letter = char2int1(string_get_at(text, i))
  in
    if byte2int0(value) = letter then _is_at(bytes, offset, text, length, i + 1) else false
  end

fn _is {l:agz}{n:pos}{cs:$A.cells}{o,k:nat | o + k <= n}{m:nat}
  (bytes: !$A.cborrow(l, n, cs), offset: int o, length: int k, text: string m): bool = let
  val text_length = g1u2i(string1_length(text))
in
  if length = text_length then _is_at(bytes, offset, text, text_length, 0) else false
end

(* The tag a name is, or none when the book's tags do not include it (an element of another name is not a book element) *)
#pub datatype book_tag_found =
  | TagFound of ($DB.book_tag)
  | TagNone of ()

#pub fn book_tag_of {l:agz}{n:pos}{cs:$A.cells}{o,k:nat | o + k <= n}
  (bytes: !$A.cborrow(l, n, cs), offset: int o, length: int k): book_tag_found

implement book_tag_of {l}{n}{cs}{o,k} (bytes, offset, length) =
  if false then TagNone()
  else if _is(bytes, offset, length, "a") then TagFound($DB.BookTagA())
  else if _is(bytes, offset, length, "abbr") then TagFound($DB.BookTagAbbr())
  else if _is(bytes, offset, length, "article") then TagFound($DB.BookTagArticle())
  else if _is(bytes, offset, length, "aside") then TagFound($DB.BookTagAside())
  else if _is(bytes, offset, length, "audio") then TagFound($DB.BookTagAudio())
  else if _is(bytes, offset, length, "b") then TagFound($DB.BookTagB())
  else if _is(bytes, offset, length, "bdi") then TagFound($DB.BookTagBdi())
  else if _is(bytes, offset, length, "bdo") then TagFound($DB.BookTagBdo())
  else if _is(bytes, offset, length, "blockquote") then TagFound($DB.BookTagBlockquote())
  else if _is(bytes, offset, length, "br") then TagFound($DB.BookTagBr())
  else if _is(bytes, offset, length, "caption") then TagFound($DB.BookTagCaption())
  else if _is(bytes, offset, length, "cite") then TagFound($DB.BookTagCite())
  else if _is(bytes, offset, length, "code") then TagFound($DB.BookTagCode())
  else if _is(bytes, offset, length, "dd") then TagFound($DB.BookTagDd())
  else if _is(bytes, offset, length, "del") then TagFound($DB.BookTagDel())
  else if _is(bytes, offset, length, "details") then TagFound($DB.BookTagDetails())
  else if _is(bytes, offset, length, "dfn") then TagFound($DB.BookTagDfn())
  else if _is(bytes, offset, length, "div") then TagFound($DB.BookTagDiv())
  else if _is(bytes, offset, length, "dl") then TagFound($DB.BookTagDl())
  else if _is(bytes, offset, length, "dt") then TagFound($DB.BookTagDt())
  else if _is(bytes, offset, length, "em") then TagFound($DB.BookTagEm())
  else if _is(bytes, offset, length, "figcaption") then TagFound($DB.BookTagFigcaption())
  else if _is(bytes, offset, length, "figure") then TagFound($DB.BookTagFigure())
  else if _is(bytes, offset, length, "footer") then TagFound($DB.BookTagFooter())
  else if _is(bytes, offset, length, "h1") then TagFound($DB.BookTagH1())
  else if _is(bytes, offset, length, "h2") then TagFound($DB.BookTagH2())
  else if _is(bytes, offset, length, "h3") then TagFound($DB.BookTagH3())
  else if _is(bytes, offset, length, "h4") then TagFound($DB.BookTagH4())
  else if _is(bytes, offset, length, "h5") then TagFound($DB.BookTagH5())
  else if _is(bytes, offset, length, "h6") then TagFound($DB.BookTagH6())
  else if _is(bytes, offset, length, "header") then TagFound($DB.BookTagHeader())
  else if _is(bytes, offset, length, "hr") then TagFound($DB.BookTagHr())
  else if _is(bytes, offset, length, "i") then TagFound($DB.BookTagI())
  else if _is(bytes, offset, length, "img") then TagFound($DB.BookTagImg())
  else if _is(bytes, offset, length, "ins") then TagFound($DB.BookTagIns())
  else if _is(bytes, offset, length, "kbd") then TagFound($DB.BookTagKbd())
  else if _is(bytes, offset, length, "li") then TagFound($DB.BookTagLi())
  else if _is(bytes, offset, length, "main") then TagFound($DB.BookTagMain())
  else if _is(bytes, offset, length, "mark") then TagFound($DB.BookTagMark())
  else if _is(bytes, offset, length, "nav") then TagFound($DB.BookTagNav())
  else if _is(bytes, offset, length, "ol") then TagFound($DB.BookTagOl())
  else if _is(bytes, offset, length, "p") then TagFound($DB.BookTagP())
  else if _is(bytes, offset, length, "pre") then TagFound($DB.BookTagPre())
  else if _is(bytes, offset, length, "q") then TagFound($DB.BookTagQ())
  else if _is(bytes, offset, length, "rb") then TagFound($DB.BookTagRb())
  else if _is(bytes, offset, length, "rp") then TagFound($DB.BookTagRp())
  else if _is(bytes, offset, length, "rt") then TagFound($DB.BookTagRt())
  else if _is(bytes, offset, length, "rtc") then TagFound($DB.BookTagRtc())
  else if _is(bytes, offset, length, "ruby") then TagFound($DB.BookTagRuby())
  else if _is(bytes, offset, length, "s") then TagFound($DB.BookTagS())
  else if _is(bytes, offset, length, "samp") then TagFound($DB.BookTagSamp())
  else if _is(bytes, offset, length, "section") then TagFound($DB.BookTagSection())
  else if _is(bytes, offset, length, "small") then TagFound($DB.BookTagSmall())
  else if _is(bytes, offset, length, "source") then TagFound($DB.BookTagSource())
  else if _is(bytes, offset, length, "span") then TagFound($DB.BookTagSpan())
  else if _is(bytes, offset, length, "strong") then TagFound($DB.BookTagStrong())
  else if _is(bytes, offset, length, "sub") then TagFound($DB.BookTagSub())
  else if _is(bytes, offset, length, "summary") then TagFound($DB.BookTagSummary())
  else if _is(bytes, offset, length, "sup") then TagFound($DB.BookTagSup())
  else if _is(bytes, offset, length, "table") then TagFound($DB.BookTagTable())
  else if _is(bytes, offset, length, "tbody") then TagFound($DB.BookTagTbody())
  else if _is(bytes, offset, length, "td") then TagFound($DB.BookTagTd())
  else if _is(bytes, offset, length, "tfoot") then TagFound($DB.BookTagTfoot())
  else if _is(bytes, offset, length, "th") then TagFound($DB.BookTagTh())
  else if _is(bytes, offset, length, "thead") then TagFound($DB.BookTagThead())
  else if _is(bytes, offset, length, "time") then TagFound($DB.BookTagTime())
  else if _is(bytes, offset, length, "tr") then TagFound($DB.BookTagTr())
  else if _is(bytes, offset, length, "track") then TagFound($DB.BookTagTrack())
  else if _is(bytes, offset, length, "u") then TagFound($DB.BookTagU())
  else if _is(bytes, offset, length, "ul") then TagFound($DB.BookTagUl())
  else if _is(bytes, offset, length, "var") then TagFound($DB.BookTagVar())
  else if _is(bytes, offset, length, "video") then TagFound($DB.BookTagVideo())
  else if _is(bytes, offset, length, "wbr") then TagFound($DB.BookTagWbr())
  else TagNone()

end (* #target wasm *)
