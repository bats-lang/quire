(* The register after the bytes read and one more, by the step of another byte than the one read *)
prfn _static_loop_step_of_another_byte {count:nat}{high,low,mid_high,mid_low,end_high,end_low:nat}{octets,joined:bytes}{octet:nat}
  (octets_len: LEN(octets, count), appended: APPEND(octets, bcons(octet, bnil()), joined),
   done: CRCFROM(high, low, octets, mid_high, mid_low), step: BSTEP(mid_high, mid_low, octet + 1, end_high, end_low))
  : CRCFROM(high, low, joined, end_high, end_low) =
  crcfrom_snoc(octets_len, appended, done, step)
