(* an order and the button that goes round all five *)
datatype order = ByOne | ByTwo | ByThree | ByFour | ByFive

fn order_next (order: order): order =
  case+ order of
  | ByOne() => ByTwo() | ByTwo() => ByThree() | ByThree() => ByFour()
  | ByFour() => ByFive() | ByFive() => ByOne()
