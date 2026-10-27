prfn _static_append_swapped {front,back:bytes}{count:nat} (front_len: LEN(front, count)): [joined:bytes] APPEND(back, front, joined) = append_exists(front_len)
