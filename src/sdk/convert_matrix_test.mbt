///|
/// 三基础协议（anthropic / openai-responses / openai-chat）互相转发矩阵测试。
///
/// 覆盖 5 个新方向 × request/response/stream = 15 条链路；
/// openai-chat → anthropic 方向已由 convert_test.mbt 覆盖，此处不重复。
/// 原则（遵循项目约定）：
///   1. 样本统一由 IR 构造器 + 各协议 lux_*_to_* 编码产生，不手写 JSON
///   2. 断言方式：convert_* 输出 → target 协议 *_to_lux_* 解码回 IR → 语义保持

///|
/// 标准请求 IR（三协议共源样本）
fn std_req() -> @lux.LucentRequest {
  @lux.LucentRequest::new(
    "gpt-4o",
    Some([@lux.LucentContent::text("You are helpful")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("Hi")]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
}

///|
/// 标准响应 IR（三协议共源样本）
fn std_resp() -> @lux.LucentResponse {
  @lux.LucentResponse::new(
    "resp-1",
    "gpt-4o",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("Hi back")]),
        Stop,
        None,
      ),
    ],
    Some(@lux.LucentUsage::new(10, 5, 15)),
    None,
  )
}

///|
/// 标准事件流 IR（三协议共源样本）
fn std_events() -> Array[@lux.LucentStreamEvent] {
  [
    ConversationStart(@lux.LucentConversationMeta::new(None, None, None)),
    BlockStart(0, Text),
    BlockDelta(0, @lux.LucentBlockDelta::text_delta("Hello")),
    BlockEnd(0),
    Finish(Stop),
    Done,
  ]
}

///|
/// source 协议请求编码
fn source_req_json(proto : String) -> Result[String, String] {
  match proto {
    "anthropic" =>
      match @anthropic.lux_request_to_anthropic(std_req()) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai" =>
      match @openai_responses.lux_request_to_openai_responses(std_req()) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai-chat" =>
      match @openai_chat.lux_request_to_openai_chat(std_req()) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    _ => Err("unknown source proto: " + proto)
  }
}

///|
/// source 协议响应编码
fn source_resp_json(proto : String) -> Result[String, String] {
  match proto {
    "anthropic" =>
      match @anthropic.lux_response_to_anthropic(std_resp()) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai" =>
      match @openai_responses.lux_response_to_openai_responses(std_resp()) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai-chat" =>
      match @openai_chat.lux_response_to_openai_chat(std_resp()) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    _ => Err("unknown source proto: " + proto)
  }
}

///|
/// source 协议流式 SSE 编码
fn source_sse(proto : String) -> Result[String, String] {
  match proto {
    "anthropic" =>
      match @anthropic.lux_events_to_anthropic_sse(std_events()) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai" =>
      match @openai_responses.lux_events_to_openai_responses_sse(std_events()) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai-chat" =>
      match @openai_chat.lux_events_to_openai_chat_sse(std_events()) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    _ => Err("unknown source proto: " + proto)
  }
}

///|
/// target 协议请求解码回 IR
fn target_decode_req(
  proto : String,
  json : String,
) -> Result[@lux.LucentRequest, String] {
  match proto {
    "anthropic" =>
      match @anthropic.anthropic_to_lux_request(json) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai" =>
      match @openai_responses.openai_responses_to_lux_request(json) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai-chat" =>
      match @openai_chat.openai_chat_to_lux_request(json) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    _ => Err("unknown target proto: " + proto)
  }
}

///|
/// target 协议响应解码回 IR
fn target_decode_resp(
  proto : String,
  json : String,
) -> Result[@lux.LucentResponse, String] {
  match proto {
    "anthropic" =>
      match @anthropic.anthropic_to_lux_response(json) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai" =>
      match @openai_responses.openai_responses_to_lux_response(json) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai-chat" =>
      match @openai_chat.openai_chat_to_lux_response(json) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    _ => Err("unknown target proto: " + proto)
  }
}

///|
/// target 协议流式 SSE 解码回事件流
fn target_decode_sse(
  proto : String,
  sse : String,
) -> Result[Array[@lux.LucentStreamEvent], String] {
  match proto {
    "anthropic" =>
      match @anthropic.anthropic_sse_to_events(sse) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai" =>
      match @openai_responses.openai_responses_sse_to_events(sse) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    "openai-chat" =>
      match @openai_chat.openai_chat_sse_to_events(sse) {
        Ok(cr) => Ok(cr.value())
        Err(e) => Err(e)
      }
    _ => Err("unknown target proto: " + proto)
  }
}

///|
/// 请求转发验证：source 编码 → convert_request → target 解码 → 语义保持
fn verify_request_forward(
  source : String,
  target : String,
) -> Result[Unit, String] {
  match source_req_json(source) {
    Ok(json) =>
      match convert_request(source, json, target) {
        Ok(cr) =>
          match target_decode_req(target, cr.value()) {
            Ok(req) => {
              if req.model != "gpt-4o" {
                return Err("model mismatch: \{req.model}")
              }
              if req.conversation.length() != 1 {
                return Err("conversation length: \{req.conversation.length()}")
              }
              Ok(())
            }
            Err(e) => Err("target decode failed (\{source}->\{target}): \{e}")
          }
        Err(e) => Err("convert_request failed (\{source}->\{target}): \{e}")
      }
    Err(e) => Err("source encode failed (\{source}): \{e}")
  }
}

///|
/// 响应转发验证：source 编码 → convert_response → target 解码 → 语义保持
fn verify_response_forward(
  source : String,
  target : String,
) -> Result[Unit, String] {
  match source_resp_json(source) {
    Ok(json) =>
      match convert_response(source, json, target) {
        Ok(cr) =>
          match target_decode_resp(target, cr.value()) {
            Ok(resp) => {
              if resp.model != "gpt-4o" {
                return Err("model mismatch: \{resp.model}")
              }
              if resp.choices.length() != 1 {
                return Err("choices length: \{resp.choices.length()}")
              }
              Ok(())
            }
            Err(e) =>
              Err("target response decode failed (\{source}->\{target}): \{e}")
          }
        Err(e) => Err("convert_response failed (\{source}->\{target}): \{e}")
      }
    Err(e) => Err("source response encode failed (\{source}): \{e}")
  }
}

///|
/// 流式转发验证：source SSE → convert_stream → target SSE → 解码 → 语义保持
fn verify_stream_forward(
  source : String,
  target : String,
) -> Result[Unit, String] {
  match source_sse(source) {
    Ok(sse) =>
      match convert_stream(source, sse, target) {
        Ok(cr) =>
          match target_decode_sse(target, cr.value()) {
            Ok(events) => {
              if events.length() == 0 {
                return Err("empty event stream")
              }
              Ok(())
            }
            Err(e) =>
              Err("target sse decode failed (\{source}->\{target}): \{e}")
          }
        Err(e) => Err("convert_stream failed (\{source}->\{target}): \{e}")
      }
    Err(e) => Err("source sse encode failed (\{source}): \{e}")
  }
}

///|
/// === convert_request：5 个新方向（openai-chat→anthropic 见 convert_test.mbt）===

///|
test "convert_request - anthropic to openai-chat" {
  match verify_request_forward("anthropic", "openai-chat") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_request - anthropic to openai" {
  match verify_request_forward("anthropic", "openai") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_request - openai to anthropic" {
  match verify_request_forward("openai", "anthropic") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_request - openai to openai-chat" {
  match verify_request_forward("openai", "openai-chat") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_request - openai-chat to openai" {
  match verify_request_forward("openai-chat", "openai") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
/// === convert_response：5 个新方向 ===

///|
test "convert_response - anthropic to openai-chat" {
  match verify_response_forward("anthropic", "openai-chat") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_response - anthropic to openai" {
  match verify_response_forward("anthropic", "openai") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_response - openai to anthropic" {
  match verify_response_forward("openai", "anthropic") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_response - openai to openai-chat" {
  match verify_response_forward("openai", "openai-chat") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_response - openai-chat to openai" {
  match verify_response_forward("openai-chat", "openai") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
/// === convert_stream：5 个新方向 ===

///|
test "convert_stream - anthropic to openai-chat" {
  match verify_stream_forward("anthropic", "openai-chat") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_stream - anthropic to openai" {
  match verify_stream_forward("anthropic", "openai") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_stream - openai to anthropic" {
  match verify_stream_forward("openai", "anthropic") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_stream - openai to openai-chat" {
  match verify_stream_forward("openai", "openai-chat") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_stream - openai-chat to openai" {
  match verify_stream_forward("openai-chat", "openai") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
/// 响应转发验证（带 D8 信封）：source 编码 → convert_response_with_meta →
/// target 解码语义保持 + meta.source_provider 透出
fn verify_response_meta_forward(
  source : String,
  target : String,
) -> Result[Unit, String] {
  match source_resp_json(source) {
    Ok(json) =>
      match convert_response_with_meta(source, json, target) {
        Ok(cr) => {
          if cr.meta.source_provider != source {
            return Err(
              "meta source_provider mismatch: \{cr.meta.source_provider} != \{source}",
            )
          }
          match target_decode_resp(target, cr.value()) {
            Ok(resp) => {
              if resp.model != "gpt-4o" {
                return Err("model mismatch: \{resp.model}")
              }
              if resp.choices.length() != 1 {
                return Err("choices length: \{resp.choices.length()}")
              }
              Ok(())
            }
            Err(e) =>
              Err("target response decode failed (\{source}->\{target}): \{e}")
          }
        }
        Err(e) =>
          Err("convert_response_with_meta failed (\{source}->\{target}): \{e}")
      }
    Err(e) => Err("source response encode failed (\{source}): \{e}")
  }
}

///|
/// === convert_response_with_meta：5 个新方向（openai-chat→anthropic 见 convert_test.mbt）===

///|
test "convert_response_with_meta - anthropic to openai-chat" {
  match verify_response_meta_forward("anthropic", "openai-chat") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_response_with_meta - anthropic to openai" {
  match verify_response_meta_forward("anthropic", "openai") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_response_with_meta - openai to anthropic" {
  match verify_response_meta_forward("openai", "anthropic") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_response_with_meta - openai to openai-chat" {
  match verify_response_meta_forward("openai", "openai-chat") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "convert_response_with_meta - openai-chat to openai" {
  match verify_response_meta_forward("openai-chat", "openai") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
/// 图片转发：source 编码（含图片）→ convert_request → target 解码 → 图片保留
fn verify_image_forward(
  source : String,
  target : String,
) -> Result[Unit, String] {
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::text("看图"),
          @lux.LucentContent::image("image/png", Url("https://x.com/a.png")),
        ]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let json = match source {
    "openai-chat" =>
      match @openai_chat.lux_request_to_openai_chat(req) {
        Ok(cr) => cr.value()
        Err(e) => return Err("source encode (\{source}): \{e}")
      }
    "openai" =>
      match @openai_responses.lux_request_to_openai_responses(req) {
        Ok(cr) => cr.value()
        Err(e) => return Err("source encode (\{source}): \{e}")
      }
    "anthropic" =>
      match @anthropic.lux_request_to_anthropic(req) {
        Ok(cr) => cr.value()
        Err(e) => return Err("source encode (\{source}): \{e}")
      }
    _ => return Err("unknown source: " + source)
  }
  match convert_request(source, json, target) {
    Ok(cr) =>
      match target_decode_req(target, cr.value()) {
        Ok(out_req) =>
          // 检查首条消息是否含 Image content
          match out_req.conversation[0] {
            Message(m) => {
              let mut has_image = false
              let mut i = 0
              while i < m.content.length() {
                if m.content[i] is Image(_) {
                  has_image = true
                }
                i = i + 1
              }
              if !has_image {
                return Err("image lost (\{source}->\{target})")
              }
              Ok(())
            }
            _ => Err("first item not a message (\{source}->\{target})")
          }
        Err(e) => Err("target decode failed (\{source}->\{target}): \{e}")
      }
    Err(e) => Err("convert_request failed (\{source}->\{target}): \{e}")
  }
}

///|
/// === 图片转发矩阵（4 方向 × 保真断言）===

///|
test "image forward - openai-chat to anthropic preserves image" {
  match verify_image_forward("openai-chat", "anthropic") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "image forward - openai to anthropic preserves image" {
  match verify_image_forward("openai", "anthropic") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "image forward - anthropic to openai-chat preserves image" {
  match verify_image_forward("anthropic", "openai-chat") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}

///|
test "image forward - anthropic to openai preserves image" {
  match verify_image_forward("anthropic", "openai") {
    Ok(_) => ()
    Err(e) => fail(e)
  }
}
