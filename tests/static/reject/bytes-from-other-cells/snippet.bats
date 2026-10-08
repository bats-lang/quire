fn _static_other_bytes {first,second:bytes} (string: !bstr(first)): [n:nat | n < 256] blist(second, n) = blist_of_bstr(string)
