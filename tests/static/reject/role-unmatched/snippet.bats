(* A role's custom property with the second highlight forgotten: a rule
   in that role would name no property *)
fn _static_role_name {role:colour_role} (role: role_value(role)): string =
  case+ role of
  | RoleGround() => "bg"
