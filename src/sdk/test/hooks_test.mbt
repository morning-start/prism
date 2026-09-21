///|
/// IR 钩子链测试（T4，架构审计 P0-6）
///
/// 覆盖：
///   - convert_*_with_hooks：空 hooks 与 convert_* 行为一致
///   - 内置钩子：hook_set_model / hook_append_instructions /
///     hook_filter_tools / hook_clamp_max_tokens / hook_stream_drop_after_error
///   - 自定义闭包钩子（扩展点演示）
///   - 诊断三段合并（decode + hook）

///|
/// 标准请求（含两个工具）→ openai JSON
fn openai_req_json_with_tools() -> Result[String, String] {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    Some([@lux.LucentContent::text("You are helpful")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    Some([
      @lux.LucentTool::simple("get_weather", "Get weather", "{}"),
      @lux.LucentTool::simple("send_email", "Send email", "{}"),
    ]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  match @openai.lux_request_to_openai(req) {
    Ok(cr) => Ok(cr.value())
    Err(e) => Err(e)
  }
}

///|
/// 带 max_output_tokens 的标准请求 → openai JSON
fn openai_req_json_max_tokens(max_tokens : Int) -> Result[String, String] {
  let opts = @lux.LucentOptions::new(
    None,
    None,
    None,
    Some(max_tokens),
    None,
    false,
    None,
    None,
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  match @openai.lux_request_to_openai(req) {
    Ok(cr) => Ok(cr.value())
    Err(e) => Err(e)
  }
}

///|
/// === 空 hooks 等价性 ===
test "convert_request_with_hooks - empty hooks equals convert_request" {
  match openai_req_json_with_tools() {
    Ok(json) =>
      match @sdk.convert_request("openai", json, "messages") {
        Ok(base) =>
          match
            @sdk.convert_request_with_hooks("openai", json, "messages", []) {
            Ok(with_hooks) => {
              assert_eq(with_hooks.value(), base.value())
              assert_eq(
                with_hooks.diagnostics().length(),
                base.diagnostics().length(),
              )
            }
            Err(e) => fail("with_hooks failed: " + e)
          }
        Err(e) => fail("convert_request failed: " + e)
      }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
test "convert_response_with_hooks - empty hooks equals convert_response" {
  match openai_resp_json() {
    Ok(json) =>
      match @sdk.convert_response("openai", json, "messages") {
        Ok(base) =>
          match
            @sdk.convert_response_with_hooks("openai", json, "messages", []) {
            Ok(with_hooks) => assert_eq(with_hooks.value(), base.value())
            Err(e) => fail("with_hooks failed: " + e)
          }
        Err(e) => fail("convert_response failed: " + e)
      }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
/// === hook_set_model（路由改写）===
test "hook_set_model - rewrites target model" {
  match openai_req_json_with_tools() {
    Ok(json) =>
      match
        @sdk.convert_request_with_hooks("openai", json, "messages", [
          @sdk.hook_set_model("claude-sonnet-4-5"),
        ]) {
        Ok(cr) =>
          match @messages.messages_to_lux_request(cr.value()) {
            Ok(cr2) => assert_eq(cr2.value().model, "claude-sonnet-4-5")
            Err(e) => fail("target decode failed: " + e)
          }
        Err(e) => fail("convert failed: " + e)
      }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
/// === hook_append_instructions（prompt 注入）===
test "hook_append_instructions - injects into target system" {
  match openai_req_json_with_tools() {
    Ok(json) =>
      match
        @sdk.convert_request_with_hooks("openai", json, "messages", [
          @sdk.hook_append_instructions("Always answer in Chinese"),
        ]) {
        Ok(cr) => {
          assert_true(cr.value().contains("Always answer in Chinese"))
          match @messages.messages_to_lux_request(cr.value()) {
            Ok(cr2) =>
              // instructions 含原文 + 注入文本
              match cr2.value().instructions {
                Some(instr) => {
                  let joined = instr
                    .map(fn(c) { @lux.lucent_content_to_text([c]) })
                    .join("|")
                  assert_true(joined.contains("You are helpful"))
                  assert_true(joined.contains("Always answer in Chinese"))
                }
                None => fail("expected instructions")
              }
            Err(e) => fail("target decode failed: " + e)
          }
        }
        Err(e) => fail("convert failed: " + e)
      }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
/// === hook_filter_tools（工具裁剪 + 诊断）===
test "hook_filter_tools - drops tools with Degraded diagnostic" {
  match openai_req_json_with_tools() {
    Ok(json) =>
      match
        @sdk.convert_request_with_hooks("openai", json, "messages", [
          @sdk.hook_filter_tools(["get_weather"]),
        ]) {
        Ok(cr) => {
          // 目标 JSON 只剩 get_weather
          assert_true(cr.value().contains("get_weather"))
          assert_false(cr.value().contains("send_email"))
          // 诊断中存在一条 field=tools 的 Degraded（转换基线诊断可能另有其他）
          let mut found = false
          for d in cr.diagnostics() {
            if d.field == "tools" && d.status == Degraded {
              found = true
            }
          }
          assert_true(found)
        }
        Err(e) => fail("convert failed: " + e)
      }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
test "hook_filter_tools - all kept yields no tools diagnostic" {
  match openai_req_json_with_tools() {
    Ok(json) =>
      match
        @sdk.convert_request_with_hooks("openai", json, "messages", [
          @sdk.hook_filter_tools(["get_weather", "send_email"]),
        ]) {
        Ok(cr) => {
          assert_true(cr.value().contains("send_email"))
          // 无裁剪 → 无 field=tools 的诊断
          let mut found = false
          for d in cr.diagnostics() {
            if d.field == "tools" {
              found = true
            }
          }
          assert_false(found)
        }
        Err(e) => fail("convert failed: " + e)
      }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
/// === hook_clamp_max_tokens（成本兜底 + 诊断）===
test "hook_clamp_max_tokens - clamps with Degraded diagnostic" {
  match openai_req_json_max_tokens(4000) {
    Ok(json) =>
      match
        @sdk.convert_request_with_hooks("openai", json, "messages", [
          @sdk.hook_clamp_max_tokens(1000),
        ]) {
        Ok(cr) => {
          assert_true(cr.value().contains("\"max_tokens\":1000"))
          assert_false(cr.value().contains("4000"))
          let diags = cr.diagnostics()
          assert_eq(diags.length(), 1)
          assert_eq(diags[0].field, "options.max_output_tokens")
          assert_eq(diags[0].status, Degraded)
        }
        Err(e) => fail("convert failed: " + e)
      }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
test "hook_clamp_max_tokens - under limit passthrough without diagnostic" {
  match openai_req_json_max_tokens(500) {
    Ok(json) =>
      match
        @sdk.convert_request_with_hooks("openai", json, "messages", [
          @sdk.hook_clamp_max_tokens(1000),
        ]) {
        Ok(cr) => {
          assert_true(cr.value().contains("\"max_tokens\":500"))
          assert_eq(cr.diagnostics().length(), 0)
        }
        Err(e) => fail("convert failed: " + e)
      }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
/// === 自定义闭包钩子（扩展点演示：租户标记）===
test "custom closure hook - stamps metadata into IR" {
  // 自定义钩子：向 metadata 注入租户标记（演示宿主自有策略）
  let tenant_hook : (@lux.LucentRequest, Array[@lux.ConversionDiagnostic]) -> @lux.LucentRequest = fn(
    ir,
    _diags,
  ) {
    let meta : Map[String, String] = match ir.metadata {
      Some(m) => {
        let copy = m.copy()
        copy["tenant"] = "acme"
        copy
      }
      None => {
        let m : Map[String, String] = Map([])
        m["tenant"] = "acme"
        m
      }
    }
    @lux.LucentRequest::new(
      ir.model,
      ir.instructions,
      ir.conversation,
      ir.tools,
      ir.tool_choice,
      ir.options,
      ir.capabilities,
      ir.reasoning,
      Some(meta),
      ir.extra,
    )
  }
  match openai_req_json_with_tools() {
    Ok(json) =>
      match
        @sdk.convert_request_with_hooks("openai", json, "messages", [
          tenant_hook,
        ]) {
        Ok(cr) =>
          match @messages.messages_to_lux_request(cr.value()) {
            Ok(cr2) =>
              match cr2.value().metadata {
                Some(m) => assert_eq(m.get("tenant"), Some("acme"))
                None => fail("expected metadata")
              }
            Err(e) => fail("target decode failed: " + e)
          }
        Err(e) => fail("convert failed: " + e)
      }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
/// === 响应钩子 ===
test "convert_response_with_hooks - custom hook appends suffix text" {
  let suffix_hook : (@lux.LucentResponse, Array[@lux.ConversionDiagnostic]) -> @lux.LucentResponse = fn(
    resp,
    _diags,
  ) {
    let choices : Array[@lux.LucentChoice] = []
    for ch in resp.choices {
      let content : Array[@lux.LucentContent] = []
      for c in ch.message.content {
        match c {
          Text(s, anns) => content.push(Text(s + " [audited]", anns))
          other => content.push(other)
        }
      }
      let msg = @lux.LucentMessage::new(ch.message.role, content)
      choices.push(
        @lux.LucentChoice::new(ch.index, msg, ch.finish_reason, None),
      )
    }
    @lux.LucentResponse::new(
      resp.id,
      resp.model,
      resp.created_at,
      choices,
      resp.usage,
      resp.provider_payload,
    )
  }
  match openai_resp_json() {
    Ok(json) =>
      match
        @sdk.convert_response_with_hooks("openai", json, "messages", [
          suffix_hook,
        ]) {
        Ok(cr) => {
          assert_true(cr.value().contains("[audited]"))
          match @messages.messages_to_lux_response(cr.value()) {
            Ok(cr2) => assert_true(cr2.value().get_text().contains("[audited]"))
            Err(e) => fail("target decode failed: " + e)
          }
        }
        Err(e) => fail("convert failed: " + e)
      }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
/// === 流钩子 ===
test "convert_stream_with_hooks - empty hooks equals convert_stream" {
  let events : Array[@lux.LucentStreamEvent] = [
    ConversationStart(@lux.LucentConversationMeta::new(None, None, None)),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
  match @openai.lux_events_to_openai_sse(events) {
    Ok(cr) => {
      let sse = cr.value()
      match @sdk.convert_stream("openai", sse, "messages") {
        Ok(base) =>
          match @sdk.convert_stream_with_hooks("openai", sse, "messages", []) {
            Ok(with_hooks) => assert_eq(with_hooks.value(), base.value())
            Err(e) => fail("with_hooks failed: " + e)
          }
        Err(e) => fail("convert_stream failed: " + e)
      }
    }
    Err(e) => fail("fixture failed: " + e)
  }
}

///|
/// 注意：openai 流解码不产出 Error 事件（error chunk 被静默忽略），
/// 故 source 用 messages（其 error 事件正确解码为 LucentError）。
test "hook_stream_drop_after_error - keeps error event drops trailing" {
  let sse = "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"m1\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[],\"model\":\"claude\",\"stop_reason\":null,\"usage\":{\"input_tokens\":1,\"output_tokens\":1}}}\n\n" +
    "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n" +
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"partial\"}}\n\n" +
    "event: error\ndata: {\"type\":\"error\",\"error\":{\"type\":\"overloaded_error\",\"message\":\"boom\"}}\n\n" +
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"text_delta\",\"text\":\"after error\"}}\n\n" +
    "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match
    @sdk.convert_stream_with_hooks("messages", sse, "openai", [
      @sdk.hook_stream_drop_after_error(),
    ]) {
    Ok(out) => {
      // 错误事件保留（openai 编码为 error 帧），其后的事件被丢弃
      assert_true(out.value().contains("boom"))
      assert_false(out.value().contains("after error"))
    }
    Err(e) => fail("convert failed: " + e)
  }
}
