(* A role's custom property with the second highlight forgotten: a rule
   in that role would name no property *)
fn _static_role_name {role:colour_role} (role: role_value(role)): string =
  case+ role of
  | RoleGround() => "bg" | RoleText() => "fg" | RoleMuted() => "muted" | RoleCard() => "card"
  | RoleLine() => "line" | RoleEdge() => "edge" | RoleBar() => "bar" | RoleBarText() => "barfg"
  | RoleAccent() => "accent" | RoleAccentText() => "accentfg" | RoleHighlight() => "hl"
  | RoleBarHigh() => "barhi" | RoleBanner() => "banner" | RoleBannerText() => "bannerfg"
  | RoleMark() => "mark" | RoleMarkText() => "markfg" | RoleDanger() => "danger"
