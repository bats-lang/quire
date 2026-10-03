(* A theme chosen with the grey one forgotten: the root would be given
   no theme's class when it is chosen *)
fn _static_theme_class (choice: !theme_choice): string =
  case+ choice of
  | Auto() => "app"
  | Fixed(Light()) => "app th-light"
  | Fixed(Sepia()) => "app th-sepia"
  | Fixed(Dark()) => "app th-dark"
  | Fixed(Night()) => "app th-night"
