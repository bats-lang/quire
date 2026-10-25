fn _static_find_other_quote {l:agz}{n:pos}{cells:$A.cells}{quote,other:int}{from:nat | from <= n} (length: $A.CLEN(cells, n) | data: !$A.cborrow(l, n, cells), n: int n, from: int from, quote: int quote)
  : [to:nat | from <= to; to <= n] (FINDQUOTE(cells, other, from, to) | int to) = text_find_quote(length | data, n, from, quote)
