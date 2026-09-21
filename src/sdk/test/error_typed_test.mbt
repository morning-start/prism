///|
/// PrismError 类型化错误测试（T7）
///
/// 覆盖：
///   - PrismError::from_string 保守分类（限流/鉴权/内容过滤/非法/服务端/未分类）
///   - is_retryable 重试判定
///   - 类型化入口（encode_request_typed / decode_response_typed /
///     decode_sse_typed / convert_*_typed）成功路径与 String 版一致
///   - 既有 String 错误 API 行为不变（兼容）

///|
/// === 分类器 ===
test "PrismError::from_string - rate limit patterns" {
  assert_eq(@sdk.PrismError::from_string("rate limit exceeded").kind, RateLimit)
  assert_eq(
    @sdk.PrismError::from_string("429 Too Many Requests").kind,
    RateLimit,
  )
  assert_true(@sdk.PrismError::from_string("rate_limit").is_retryable())
}

///|
test "PrismError::from_string - authentication patterns" {
  assert_eq(
    @sdk.PrismError::from_string("invalid api key provided").kind,
    Authentication,
  )
  assert_eq(
    @sdk.PrismError::from_string("401 Unauthorized").kind,
    Authentication,
  )
  assert_false(@sdk.PrismError::from_string("invalid api key").is_retryable())
}

///|
test "PrismError::from_string - content filter patterns" {
  assert_eq(
    @sdk.PrismError::from_string("content filter triggered").kind,
    ContentFilter,
  )
  assert_false(@sdk.PrismError::from_string("safety violation").is_retryable())
}

///|
test "PrismError::from_string - invalid request patterns" {
  assert_eq(
    @sdk.PrismError::from_string("json parse error").kind,
    InvalidRequest,
  )
  assert_eq(
    @sdk.PrismError::from_string("unknown provider: x").kind,
    InvalidRequest,
  )
  assert_eq(
    @sdk.PrismError::from_string("malformed chunk").kind,
    InvalidRequest,
  )
}

///|
test "PrismError::from_string - server error patterns" {
  assert_eq(
    @sdk.PrismError::from_string("internal server error").kind,
    ServerError,
  )
  assert_eq(@sdk.PrismError::from_string("503 unavailable").kind, ServerError)
  assert_true(@sdk.PrismError::from_string("upstream timeout").is_retryable())
}

///|
/// 未分类不猜：绝不误判为可重试
test "PrismError::from_string - unmatched stays unclassified" {
  let err = @sdk.PrismError::from_string("something weird happened")
  assert_eq(err.kind, Native("unclassified"))
  assert_false(err.is_retryable())
  assert_eq(err.provider, None)
}

///|
test "PrismError::with_provider - sets provider field" {
  let err = @sdk.PrismError::from_string("rate limit").with_provider(
    Some("openai"),
  )
  assert_eq(err.provider, Some("openai"))
  assert_eq(err.kind, RateLimit)
  assert_eq(err.message(), "rate limit")
}

///|
/// === 类型化入口：成功路径 ===
test "encode_request_typed - success path unchanged" {
  let p = @sdk.Prism::new().with_provider("openai")
  match p.encode_request_typed("Hi", @sdk.PrismOptions::default()) {
    Ok(json) => assert_true(json.contains("messages"))
    Err(e) => fail("unexpected error: \{e.message()}")
  }
}

///|
test "decode_response_typed - success path unchanged" {
  let p = @sdk.Prism::new().with_provider("openai")
  let resp = @lux.LucentResponse::new(
    "r1",
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
    None,
    None,
  )
  match @openai.lux_response_to_openai(resp) {
    Ok(cr) =>
      match p.decode_response_typed(cr.value()) {
        Ok(decoded) => assert_eq(decoded.text, "Hi back")
        Err(e) => fail("unexpected error: \{e.message()}")
      }
    Err(e) => fail("fixture failed: \{e}")
  }
}

///|
/// === 类型化入口：错误路径 ===
test "decode_response_typed - error is typed with provider" {
  let p = @sdk.Prism::new().with_provider("anthropic")
  match p.decode_response_typed("not-json-at-all") {
    Ok(_) => fail("expected error")
    Err(e) => {
      // anthropic 别名解析为规范名 messages
      assert_eq(e.provider, Some("messages"))
      // 解析失败 → InvalidRequest，不可重试
      assert_eq(e.kind, InvalidRequest)
      assert_false(e.is_retryable())
    }
  }
}

///|
test "decode_sse_typed - unknown provider typed as invalid" {
  let p = @sdk.Prism::new().with_provider("fake-provider")
  match p.decode_sse_typed("data: {}\n\n") {
    Ok(_) => fail("expected error")
    Err(e) => {
      assert_eq(e.kind, InvalidRequest)
      assert_true(e.message().contains("unknown provider"))
    }
  }
}

///|
test "convert_request_typed - unknown source typed with source name" {
  match @sdk.convert_request_typed("no-such", "{}", "messages") {
    Ok(_) => fail("expected error")
    Err(e) => {
      assert_eq(e.provider, Some("no-such"))
      assert_eq(e.kind, InvalidRequest)
    }
  }
}

///|
test "convert_response_typed - success path unchanged" {
  let resp = @lux.LucentResponse::new(
    "r1",
    "gpt-4o",
    None,
    [
      @lux.LucentChoice::new(
        0,
        @lux.LucentMessage::new(Assistant, [@lux.LucentContent::text("Hi")]),
        Stop,
        None,
      ),
    ],
    None,
    None,
  )
  match @openai.lux_response_to_openai(resp) {
    Ok(cr) =>
      match @sdk.convert_response_typed("openai", cr.value(), "messages") {
        Ok(result) => assert_true(result.value().contains("content"))
        Err(e) => fail("unexpected error: \{e.message()}")
      }
    Err(e) => fail("fixture failed: \{e}")
  }
}

///|
test "convert_stream_typed - unknown target typed" {
  match @sdk.convert_stream_typed("openai", "data: [DONE]\n\n", "no-such") {
    Ok(_) => fail("expected error")
    Err(e) => {
      assert_eq(e.kind, InvalidRequest)
      assert_true(e.message().contains("unknown provider"))
    }
  }
}

///|
/// 兼容门禁：String 错误 API 行为不变
test "string error API - unchanged behavior" {
  let p = @sdk.Prism::new().with_provider("anthropic")
  match p.decode_response("not-json") {
    Err(e) => assert_true(e.length() > 0)
    Ok(_) => fail("expected error")
  }
}
