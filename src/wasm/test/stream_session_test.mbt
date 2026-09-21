///|
/// 增量流转换会话 ABI 测试（T5）
///
/// 覆盖 wasm_stream_new / feed / finish / free：
///   - 1 字节 chunk 喂入与整缓冲 wasm_convert_stream 输出逐字节一致
///   - 句柄错误（越界/重复释放）
///   - free 后槽位复用

///|
/// 从信封取 number 字段
fn envelope_num(envelope : String, key : String) -> Double? {
  let jv = @json.parse(envelope) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get(key) {
        Some(Number(n, ..)) => Some(n)
        _ => None
      }
    _ => None
  }
}

///|
/// 从信封取 string 字段
fn envelope_str(envelope : String, key : String) -> String? {
  let jv = @json.parse(envelope) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get(key) {
        Some(String(s)) => Some(s)
        _ => None
      }
    _ => None
  }
}

///|
/// 从信封取字符串数组字段
fn envelope_str_arr(envelope : String, key : String) -> Array[String]? {
  let jv = @json.parse(envelope) catch { _ => Json::null() }
  match jv {
    Object(map) =>
      match map.get(key) {
        Some(Array(items)) => {
          let result : Array[String] = []
          for item in items {
            match item {
              String(s) => result.push(s)
              _ => ()
            }
          }
          Some(result)
        }
        _ => None
      }
    _ => None
  }
}

///|
/// openai SSE fixture（与 sdk 侧测试同形态）
fn openai_sse_fixture() -> String {
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"}}]}\n\n" +
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n" +
  "data: [DONE]\n\n"
}

///|
test "wasm_stream session - 1-byte chunks byte-identical to whole buffer" {
  let sse = openai_sse_fixture()
  // 整缓冲基准
  let base = @wasm.wasm_convert_stream("openai", sse, "messages")
  let base_value = match envelope_str(base, "value") {
    Some(v) => v
    None => fail("expected base value")
  }
  // 增量会话
  let new_env = @wasm.wasm_stream_new("openai", "messages")
  let handle = match envelope_num(new_env, "value") {
    Some(n) => n.to_int()
    None => fail("expected handle")
  }
  let out : Array[String] = []
  let mut i = 0
  while i < sse.length() {
    let ch = sse[i:i + 1].to_owned()
    let feed_env = @wasm.wasm_stream_feed(handle, ch)
    match envelope_str_arr(feed_env, "value") {
      Some(frames) =>
        for f in frames {
          out.push(f)
        }
      None => fail("expected frames array")
    }
    i = i + 1
  }
  let fin_env = @wasm.wasm_stream_finish(handle)
  match envelope_str_arr(fin_env, "value") {
    Some(frames) =>
      for f in frames {
        out.push(f)
      }
    None => fail("expected frames array")
  }
  assert_eq(out.join(""), base_value)
  // 清理（value 为 JSON boolean）
  assert_true(@wasm.wasm_stream_free(handle).contains("\"value\":true"))
}

///|
test "wasm_stream session - invalid handle returns error" {
  let result = @wasm.wasm_stream_feed(999, "data: x\n\n")
  assert_true(result.contains("\"error\""))
  let fin = @wasm.wasm_stream_finish(-1)
  assert_true(fin.contains("\"error\""))
}

///|
test "wasm_stream session - double free returns error" {
  let new_env = @wasm.wasm_stream_new("openai", "messages")
  let handle = match envelope_num(new_env, "value") {
    Some(n) => n.to_int()
    None => fail("expected handle")
  }
  let _ = @wasm.wasm_stream_free(handle)
  let again = @wasm.wasm_stream_free(handle)
  assert_true(again.contains("\"error\""))
}

///|
test "wasm_stream session - freed slot is reused" {
  let sse = "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hi\"}}]}\n\n"
  let env1 = @wasm.wasm_stream_new("openai", "messages")
  let h1 = match envelope_num(env1, "value") {
    Some(n) => n.to_int()
    None => fail("expected handle")
  }
  let _ = @wasm.wasm_stream_free(h1)
  let env2 = @wasm.wasm_stream_new("openai", "messages")
  let h2 = match envelope_num(env2, "value") {
    Some(n) => n.to_int()
    None => fail("expected handle")
  }
  // 槽位复用：h2 == h1
  assert_eq(h2, h1)
  // 复用后的会话可正常工作
  let feed_env = @wasm.wasm_stream_feed(h2, sse)
  match envelope_str_arr(feed_env, "value") {
    Some(frames) => assert_true(frames.join("").contains("content_block_delta"))
    None => fail("expected frames array")
  }
  let _ = @wasm.wasm_stream_free(h2)
}

///|
test "wasm_stream_new - unknown provider returns error" {
  let result = @wasm.wasm_stream_new("no-such", "messages")
  assert_true(result.contains("\"error\""))
}
