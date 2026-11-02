(* How an export ended, with a share the reader closed left out: the
   backup would be called saved when it was not (#362) *)
fn _static_export_said (outcome: export_outcome): string =
  case+ outcome of
  | ExportedByDownload() => "saved"
