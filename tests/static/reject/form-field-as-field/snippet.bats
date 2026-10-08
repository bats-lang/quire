(* A password field made as a plain field, named by a placeholder alone:
   only ui_form_field makes one, with a visible label *)
fn _static_password_as_field (): void =
  ui_field("sync-fields", "sync-password", FPassword, "mname", "Password")
