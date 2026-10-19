///|
/// extras 键撞名 → 重复 JSON 键缺陷回归测试
///
/// 缺陷：`merge_extras_json` 把 extras 直接字符串拼接在已编码片段之后。
/// 若 extras 的键与编码器自己发出的键同名，同一 JSON 对象里会出现**重复键**：
/// 严格 JSON 解析器拒绝，宽容解析器静默丢弃先前那个键 —— 两者都不是想要的
/// 语义。触发场景（同源配对即可复现，无需人为构造畸形输入）：
///   - messages 源带 `disable_parallel_tool_use=true`（合法官方参数），
///     解码后该键落入 extras；再编码到 messages 目标时编码器自己也会发出
///     `disable_parallel_tool_use` → 重复键
///   - openai 源带 `parallel_tool_calls` 转 openai 目标同理
///
/// 修复：`@internal.merge_extras_json_dedup` 跳过撞名键，
/// `@lux.push_extras_collisions` 为每个被跳过的键补 Degraded 诊断。

///|
/// 统计 JSON 文本中某顶层键出现次数（简单扫描，仅用于测试断言）。
fn count_key_occurrences(json : String, key : String) -> Int32 {
  let needle = "\"" + key + "\":"
  let mut n = 0
  for _part in json.split(needle) {
    n = n + 1
  }
  // split 后元素数 = 出现次数 + 1
  n - 1
}

///|
/// 非撞名情形：extras 键与编码器自产键不重合时原样透传（Exact，无诊断）。
/// messages 源带 `disable_parallel_tool_use`（合法 Anthropic 参数）→
/// 解码落 extras → 编码时编码器自身不产生该键（它只在 extras 含
/// `parallel_tool_calls` 时才反向生成），故直接透传一次。
test "dupkey - non-colliding extras passes through exactly once" {
  let src = "{\"model\":\"m\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"disable_parallel_tool_use\":true}"
  match @messages.messages_to_lux_request(src) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      match cr.value().options.extras {
        Some(m) => assert_true(m.contains("disable_parallel_tool_use"))
        None => fail("expected disable_parallel_tool_use in extras")
      }
      match @messages.lux_request_to_messages(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          let s = out.value()
          assert_true(s.contains("\"disable_parallel_tool_use\":true"))
          assert_eq(count_key_occurrences(s, "disable_parallel_tool_use"), 1)
        }
      }
    }
  }
}

///|
/// 撞名情形：extras 同时含 `parallel_tool_calls` 与 `disable_parallel_tool_use`。
/// 编码器消费前者并反向生成后者 → 后者与 extras 里的同名键撞名，
/// 必须跳过写入并打诊断（不能产出重复键，也不能静默）。
test "dupkey - colliding extras key is dropped with a diagnostic" {
  let src = "{\"model\":\"m\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"parallel_tool_calls\":true,\"disable_parallel_tool_use\":false}"
  match @messages.messages_to_lux_request(src) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match @messages.lux_request_to_messages(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          let s = out.value()
          assert_eq(count_key_occurrences(s, "disable_parallel_tool_use"), 1)
          let mut has_diag = false
          for d in out.diagnostics() {
            if d.field.contains("extras.disable_parallel_tool_use") {
              has_diag = true
            }
          }
          assert_true(has_diag)
        }
      }
  }
}

///|
/// extras 与编码器自产键同名（parallel_tool_calls）：messages 源 → openai 目标
test "dupkey - messages to openai parallel_tool_calls emits no duplicate keys" {
  let src = "{\"model\":\"m\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"parallel_tool_calls\":false}"
  match @messages.messages_to_lux_request(src) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match @openai.lux_request_to_openai(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          let s = out.value()
          assert_eq(count_key_occurrences(s, "parallel_tool_calls"), 1)
        }
      }
  }
}

///|
/// 同源配对最短复现：messages 源同时带两个键（互为反向语义），
/// 此时其中一个必然与编码器自产键撞名。
test "dupkey - messages to messages with both parallel switches" {
  let src = "{\"model\":\"m\",\"max_tokens\":1024,\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}],\"disable_parallel_tool_use\":true,\"parallel_tool_calls\":false}"
  match @messages.messages_to_lux_request(src) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match @messages.lux_request_to_messages(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          let s = out.value()
          assert_eq(count_key_occurrences(s, "disable_parallel_tool_use"), 1)
          assert_eq(count_key_occurrences(s, "messages"), 1)
          assert_eq(count_key_occurrences(s, "max_tokens"), 1)
        }
      }
  }
}

///|
/// 通用不变式：任意跨端转换的输出中，顶层键都不得重复。
/// 用「含 `messages` 的 body 当作 responses 解码」构造 extras 与自产键撞名
/// 的场景（`messages` 落入 extras，再编码到 messages 目标时撞名）。
test "dupkey - cross-protocol extras never duplicate a key" {
  // responses 解码把 messages 视为未知字段 → 落入 extras；
  // 再编码到 messages 目标时，`messages` 会被编码器自己发出。
  let src = "{\"model\":\"m\",\"input\":\"hi\",\"messages\":[{\"role\":\"user\",\"content\":\"x\"}]}"
  match @responses.responses_to_lux_request(src) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      match @messages.lux_request_to_messages(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          let s = out.value()
          assert_eq(count_key_occurrences(s, "messages"), 1)
        }
      }
      match @gemini.lux_request_to_gemini(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          let s = out.value()
          assert_eq(count_key_occurrences(s, "contents"), 1)
        }
      }
      match @openai.lux_request_to_openai(cr.value()) {
        Err(e) => fail("encode failed: " + e)
        Ok(out) => {
          let s = out.value()
          assert_eq(count_key_occurrences(s, "messages"), 1)
        }
      }
    }
  }
}
