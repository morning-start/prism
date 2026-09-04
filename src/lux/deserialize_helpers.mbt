///|
/// Lucent IR — JSON 反序列化

///|
/// Lux IR explicit JSON deserialization
///
/// All `from_json()` inputs match outputs of `to_json()` in serialize.mbt.

///|
/// === Helpers ===
fn get_str(m : Map[String, Json], key : String) -> Result[String, String] {
  match m.get(key) {
    Some(String(s)) => Ok(s)
    Some(_) => Err("expected string for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_str_opt(m : Map[String, Json], key : String) -> String? {
  match m.get(key) {
    Some(String(s)) => Some(s)
    _ => None
  }
}

///|
fn get_int(m : Map[String, Json], key : String) -> Result[Int, String] {
  match m.get(key) {
    Some(Number(n, ..)) => Ok(n.to_int())
    Some(_) => Err("expected number for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_int_opt(m : Map[String, Json], key : String) -> Int? {
  match m.get(key) {
    Some(Number(n, ..)) => Some(n.to_int())
    _ => None
  }
}

///|
fn get_double_opt(m : Map[String, Json], key : String) -> Double? {
  match m.get(key) {
    Some(Number(n, ..)) => Some(n)
    _ => None
  }
}

///|
fn get_bool(m : Map[String, Json], key : String) -> Result[Bool, String] {
  match m.get(key) {
    Some(True) => Ok(true)
    Some(False) => Ok(false)
    Some(_) => Err("expected boolean for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_support_level(
  m : Map[String, Json],
  key : String,
) -> Result[SupportLevel, String] {
  match m.get(key) {
    Some(v) =>
      match SupportLevel::from_json(v) {
        Ok(l) => Ok(l)
        Err(_) => Err("invalid support level for " + key)
      }
    None => Err("missing required field " + key)
  }
}

///|
fn get_bool_opt(m : Map[String, Json], key : String) -> Bool? {
  match m.get(key) {
    Some(True) => Some(true)
    Some(False) => Some(false)
    _ => None
  }
}

///|
fn get_str_arr_opt(m : Map[String, Json], key : String) -> Array[String]? {
  match m.get(key) {
    Some(Array(items)) => {
      let result : Array[String] = []
      let mut i = 0
      while i < items.length() {
        match items[i] {
          String(s) => result.push(s)
          _ => return None
        }
        i = i + 1
      }
      Some(result)
    }
    _ => None
  }
}

///|
fn parse_content_arr(
  items : Array[Json],
) -> Result[Array[LucentContent], String] {
  let result : Array[LucentContent] = []
  let mut i = 0
  while i < items.length() {
    match LucentContent::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_content_opt(items : Array[Json]) -> Array[LucentContent]? {
  match parse_content_arr(items) {
    Ok(v) => Some(v)
    Err(_) => None
  }
}

///|
fn parse_tool_arr(items : Array[Json]) -> Result[Array[LucentTool], String] {
  let result : Array[LucentTool] = []
  let mut i = 0
  while i < items.length() {
    match LucentTool::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_item_arr(
  items : Array[Json],
) -> Result[Array[LucentConversationItem], String] {
  let result : Array[LucentConversationItem] = []
  let mut i = 0
  while i < items.length() {
    match LucentConversationItem::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_choice_arr(items : Array[Json]) -> Result[Array[LucentChoice], String] {
  let result : Array[LucentChoice] = []
  let mut i = 0
  while i < items.length() {
    match LucentChoice::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_annotation_arr(
  items : Array[Json],
) -> Result[Array[LucentAnnotation], String] {
  let result : Array[LucentAnnotation] = []
  let mut i = 0
  while i < items.length() {
    match LucentAnnotation::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_provider_arr(
  items : Array[Json],
) -> Result[Array[ProviderCapability], String] {
  let result : Array[ProviderCapability] = []
  let mut i = 0
  while i < items.length() {
    match ProviderCapability::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_modality_arr(
  items : Array[Json],
) -> Result[Array[LucentModality], String] {
  let result : Array[LucentModality] = []
  let mut i = 0
  while i < items.length() {
    match LucentModality::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn parse_safety_arr(
  items : Array[Json],
) -> Result[Array[LucentSafetyRating], String] {
  let result : Array[LucentSafetyRating] = []
  let mut i = 0
  while i < items.length() {
    match LucentSafetyRating::from_json(items[i]) {
      Ok(v) => result.push(v)
      Err(e) => return Err(e)
    }
    i = i + 1
  }
  Ok(result)
}

///|
fn get_arr_content(
  m : Map[String, Json],
  key : String,
) -> Result[Array[LucentContent], String] {
  match m.get(key) {
    Some(Array(items)) => parse_content_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_arr_content_opt(
  m : Map[String, Json],
  key : String,
) -> Array[LucentContent]? {
  match m.get(key) {
    Some(Array(items)) => parse_content_opt(items)
    _ => None
  }
}

///|
fn get_arr_item(
  m : Map[String, Json],
  key : String,
) -> Result[Array[LucentConversationItem], String] {
  match m.get(key) {
    Some(Array(items)) => parse_item_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_arr_choice(
  m : Map[String, Json],
  key : String,
) -> Result[Array[LucentChoice], String] {
  match m.get(key) {
    Some(Array(items)) => parse_choice_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_arr_annotation(
  m : Map[String, Json],
  key : String,
) -> Result[Array[LucentAnnotation], String] {
  match m.get(key) {
    Some(Array(items)) => parse_annotation_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_arr_provider(
  m : Map[String, Json],
  key : String,
) -> Result[Array[ProviderCapability], String] {
  match m.get(key) {
    Some(Array(items)) => parse_provider_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
fn get_arr_modality(
  m : Map[String, Json],
  key : String,
) -> Result[Array[LucentModality], String] {
  match m.get(key) {
    Some(Array(items)) => parse_modality_arr(items)
    Some(_) => Err("expected array for " + key)
    None => Err("missing required field " + key)
  }
}

///|
/// @deprecated 保留未用
// fn get_arr_safety(
//   m : Map[String, Json],
//   key : String,
// ) -> Result[Array[LucentSafetyRating], String] {
//   match m.get(key) {
//     Some(Array(items)) => parse_safety_arr(items)
//     Some(_) => Err("expected array for " + key)
//     None => Err("missing required field " + key)
//   }
// }
