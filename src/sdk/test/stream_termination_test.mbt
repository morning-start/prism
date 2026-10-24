///|
/// CR-006 批次 1 回归：流式终止/错误事件的保真契约。
///
/// 背景：`response.incomplete` / `response.failed` / 官方扁平 `error` 三个
/// 官方终止事件此前被静默丢弃（response.failed 的流经 Prism 中转后对下游
/// 表现为空流，零诊断）；gemini 流式 `promptFeedback.blockReason` 把拦截
/// 伪装成正常结束。每处修复均已做反向验证。
test "cr006 - responses incomplete streams finish with content_filter" {
  let sse = "event: response.incomplete\ndata: {\"type\":\"response.incomplete\",\"response\":{\"id\":\"r1\",\"object\":\"response\",\"created_at\":1,\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"content_filter\"},\"output\":[]}}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let mut finish : @lux.LucentFinishReason? = None
      let mut done = false
      for ev in cr.value() {
        match ev {
          Finish(f) => finish = Some(f)
          Done => done = true
          _ => ()
        }
      }
      // content_filter 截断 ≠ token 上限，必须与流式/非流式同一 IR 值
      assert_eq(finish, Some(ContentFilter))
      assert_true(done)
    }
  }
}

///|
test "cr006 - responses incomplete max_output_tokens maps to Length" {
  let sse = "data: {\"type\":\"response.incomplete\",\"response\":{\"id\":\"r1\",\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"max_output_tokens\"},\"output\":[]}}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let mut finish : @lux.LucentFinishReason? = None
      for ev in cr.value() {
        match ev {
          Finish(f) => finish = Some(f)
          _ => ()
        }
      }
      assert_eq(finish, Some(Length))
    }
  }
}

///|
test "cr006 - responses incomplete steered preserved as Native" {
  // steered 无 IR 对等值 → 原样保留（编码侧白名单裁决），不丢数据
  let sse = "data: {\"type\":\"response.incomplete\",\"response\":{\"id\":\"r1\",\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"steered\"},\"output\":[]}}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let mut finish : @lux.LucentFinishReason? = None
      for ev in cr.value() {
        match ev {
          Finish(f) => finish = Some(f)
          _ => ()
        }
      }
      assert_eq(finish, Some(Native("steered")))
    }
  }
}

///|
test "cr006 - responses failed streams Error event plus Finish plus diagnostics" {
  let sse = "data: {\"type\":\"response.failed\",\"response\":{\"id\":\"r1\",\"status\":\"failed\",\"error\":{\"code\":\"server_error\",\"message\":\"boom\"},\"output\":[]}}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let mut err_seen = false
      let mut err_kind : @lux.LucentErrorKind? = None
      let mut err_code : String? = None
      let mut finish : @lux.LucentFinishReason? = None
      let mut done = false
      for ev in cr.value() {
        match ev {
          Error(e) => {
            err_seen = true
            err_kind = Some(e.kind)
            err_code = e.provider_code
          }
          Finish(f) => finish = Some(f)
          Done => done = true
          _ => ()
        }
      }
      // failed 必须产生 Error 事件（此前 0 事件）
      assert_true(err_seen)
      assert_eq(err_kind, Some(ServerError))
      assert_eq(err_code, Some("server_error"))
      assert_eq(finish, Some(Error))
      assert_true(done)
      // error 详情必须带诊断
      assert_true(
        cr
        .diagnostics()
        .iter()
        .any(fn(d) { d.field == "response.error" && d.status is Degraded }),
      )
    }
  }
}

///|
test "cr006 - official flat error frame is not swallowed" {
  // 官方 ResponseErrorEvent 是扁平结构（spec 58391 行起）：
  // {type:"error", code, message, param, sequence_number}
  // 此前只读嵌套 jv["error"]，官方帧被吞
  let sse = "data: {\"type\":\"error\",\"code\":\"rate_limit_error\",\"message\":\"slow down\",\"param\":null,\"sequence_number\":3}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let mut err : @lux.LucentError? = None
      for ev in cr.value() {
        match ev {
          Error(e) => err = Some(e)
          _ => ()
        }
      }
      assert_eq(err.map(fn(e) { e.kind }), Some(RateLimit))
      assert_eq(err.map(fn(e) { e.message }), Some("slow down"))
      assert_eq(
        err.map(fn(e) { e.provider_code }),
        Some(Some("rate_limit_error")),
      )
    }
  }
}

///|
test "cr006 - nested error form stays compatible" {
  // 非官方嵌套形态（此前实现假设的形态）保持兼容
  let sse = "data: {\"type\":\"error\",\"error\":\"legacy boom\"}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let mut msg : String? = None
      for ev in cr.value() {
        match ev {
          Error(e) => msg = Some(e.message)
          _ => ()
        }
      }
      assert_eq(msg, Some("legacy boom"))
    }
  }
}

///|
test "cr006 - stream and nonstream agree on incomplete content_filter" {
  // 等价性不变量：同一响应体，流式与非流式必须解出同一 IR finish_reason
  let body = "{\"id\":\"r1\",\"object\":\"response\",\"created_at\":1,\"status\":\"incomplete\",\"incomplete_details\":{\"reason\":\"content_filter\"},\"model\":\"m\",\"output\":[]}"
  let nonstream = match @responses.responses_to_lux_response(body) {
    Ok(cr) => cr.value().choices[0].finish_reason
    Err(e) => fail("nonstream decode failed: " + e)
  }
  let sse = "data: {\"type\":\"response.incomplete\",\"response\":" +
    body +
    "}\n\n"
  let stream = match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("stream decode failed: " + e)
    Ok(cr) => {
      let mut finish : @lux.LucentFinishReason? = None
      for ev in cr.value() {
        match ev {
          Finish(f) => finish = Some(f)
          _ => ()
        }
      }
      finish
    }
  }
  assert_eq(stream, Some(nonstream))
}

///|
test "cr006 - gemini stream promptFeedback blockReason becomes Safety with diagnostic" {
  // 此前：无 candidates finishReason → 不发 Finish → 累加器默认 Stop，
  // 「被拦截」伪装成「正常结束」
  let sse = "data: {\"promptFeedback\":{\"blockReason\":\"PROHIBITED_CONTENT\"},\"usageMetadata\":{\"promptTokenCount\":7,\"candidatesTokenCount\":0,\"totalTokenCount\":7}}\n\n"
  match @gemini.gemini_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let mut finish : @lux.LucentFinishReason? = None
      for ev in cr.value() {
        match ev {
          Finish(f) => finish = Some(f)
          _ => ()
        }
      }
      assert_eq(finish, Some(Safety))
      assert_true(
        cr
        .diagnostics()
        .iter()
        .any(fn(d) {
          d.field == "promptFeedback.blockReason" && d.status is Degraded
        }),
      )
    }
  }
}

///|
test "cr006 - gemini frame with finishReason does not double-finish on blockReason" {
  // candidates 自带 finishReason 时正常发 Finish；blockReason 不重复发
  let sse = "data: {\"candidates\":[{\"content\":{\"parts\":[]},\"finishReason\":\"STOP\"}],\"promptFeedback\":{\"blockReason\":\"PROHIBITED_CONTENT\"}}\n\n"
  match @gemini.gemini_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let mut finish_count = 0
      for ev in cr.value() {
        match ev {
          Finish(_) => finish_count = finish_count + 1
          _ => ()
        }
      }
      assert_eq(finish_count, 1)
    }
  }
}

///|
test "cr006 - safety encodes to official refusal in messages" {
  // Safety → refusal 直通（官方对等值），不再伪装成正常结束；
  // 官方对 refusal 的定义即 "streaming classifiers intervene to handle
  // potential policy violations"
  let resp = @lux.LucentResponse::new(
    "id-1",
    "m-1",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("t")]),
        Safety,
        None,
      ),
    ],
    None,
    None,
  )
  match @messages.lux_response_to_messages(resp) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => assert_true(cr.value().contains("\"stop_reason\":\"refusal\""))
  }
}
