///|
test "substring works at string boundary" {
  fn substring(s : String, start : Int, end : Int) -> String {
    if start < 0 || end > s.length() || start > end {
      return ""
    }
    s[start:end].to_owned()
  }
  let s = "claude-sonnet"
  let prefix = substring(s, 0, 6) // "claude"
  assert_eq(prefix, "claude")
  let suffix = substring(s, 6, s.length()) // "-sonnet"
  assert_eq(suffix, "-sonnet")
}

///|
test "find_first_star" {
  fn find_first_star(s : String) -> Int {
    let mut i = 0
    while i < s.length() {
      if s[i] == '*' {
        return i
      }
      i = i + 1
    }
    -1
  }
  let pos = find_first_star("claude-*")
  assert_eq(pos, 7)
  let pos2 = find_first_star("gpt-*")
  assert_eq(pos2, 4)
}
