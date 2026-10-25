prfn _static_mark_before_the_end {cells:$A.cells}{source:tsrc}{mark:int}{n:nat} (detect: DETECT(cells, source, mark), length: $A.CLEN(cells, n)): [mark < n] void = detect_mark_in_len(detect, length)
