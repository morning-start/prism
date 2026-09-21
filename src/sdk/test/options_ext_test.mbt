///|
/// PrismOptions 扩面测试（T3）
///
/// 覆盖：
///   - with_tool_choice / with_reasoning / with_structured_output /
///     with_parallel_tool_calls builder
///   - 回归门禁：缺省 None 时编码输出不含任何扩展字段（与扩展前逐字节一致）
///   - 各扩展字段对 openai / messages 的编码落位
///   - parallel_tool_calls 语义反传 + 用户 extras 不被覆盖

///|
/// === 回归门禁：缺省值与扩展前一致 ===
test "options default - openai encode has no extension fields" {
  let p = @sdk.Prism::new().with_provider("openai")
  match p.encode_request("Hi", @sdk.PrismOptions::default()) {
    Ok(json) => {
      assert_false(json.contains("\"tool_choice\""))
      assert_false(json.contains("\"reasoning_effort\""))
      assert_false(json.contains("\"response_format\""))
      assert_false(json.contains("\"parallel_tool_calls\""))
      assert_false(json.contains("\"extras\""))
    }
    Err(e) => fail("encode failed: " + e)
  }
}

///|
test "options default - messages encode has no extension fields" {
  let p = @sdk.Prism::new().with_provider("messages")
  match p.encode_request("Hi", @sdk.PrismOptions::default()) {
    Ok(json) => {
      assert_false(json.contains("\"tool_choice\""))
      assert_false(json.contains("\"thinking\""))
      assert_false(json.contains("\"output_config\""))
      assert_false(json.contains("\"disable_parallel_tool_use\""))
    }
    Err(e) => fail("encode failed: " + e)
  }
}

///|
/// === tool_choice ===
test "with_tool_choice - Required maps per protocol" {
  let opts = @sdk.PrismOptions::default().with_tool_choice(Required)
  let p_openai = @sdk.Prism::new().with_provider("openai")
  match p_openai.encode_request("Hi", opts) {
    Ok(json) => assert_true(json.contains("\"tool_choice\":\"required\""))
    Err(e) => fail("openai encode failed: " + e)
  }
  let p_msg = @sdk.Prism::new().with_provider("messages")
  match p_msg.encode_request("Hi", opts) {
    Ok(json) => assert_true(json.contains("\"tool_choice\":{\"type\":\"any\"}"))
    Err(e) => fail("messages encode failed: " + e)
  }
}

///|
test "with_tool_choice - SpecificTool maps to named tool" {
  let opts = @sdk.PrismOptions::default().with_tool_choice(
    SpecificTool("get_weather"),
  )
  let p = @sdk.Prism::new().with_provider("messages")
  match p.encode_request("Hi", opts) {
    Ok(json) =>
      assert_true(
        json.contains(
          "\"tool_choice\":{\"type\":\"tool\",\"name\":\"get_weather\"}",
        ),
      )
    Err(e) => fail("encode failed: " + e)
  }
}

///|
/// === reasoning ===
test "with_reasoning - effort maps to reasoning_effort / adaptive thinking" {
  let opts = @sdk.PrismOptions::default().with_reasoning(None, Some(High))
  let p_openai = @sdk.Prism::new().with_provider("openai")
  match p_openai.encode_request("Hi", opts) {
    Ok(json) => assert_true(json.contains("\"reasoning_effort\":\"high\""))
    Err(e) => fail("openai encode failed: " + e)
  }
  let p_msg = @sdk.Prism::new().with_provider("messages")
  match p_msg.encode_request("Hi", opts) {
    Ok(json) => {
      assert_true(json.contains("\"thinking\":{\"type\":\"adaptive\"}"))
      assert_true(json.contains("\"effort\":\"high\""))
    }
    Err(e) => fail("messages encode failed: " + e)
  }
}

///|
test "with_reasoning - explicit disabled maps to thinking disabled" {
  let opts = @sdk.PrismOptions::default().with_reasoning(Some(false), None)
  let p = @sdk.Prism::new().with_provider("messages")
  match p.encode_request("Hi", opts) {
    Ok(json) =>
      assert_true(json.contains("\"thinking\":{\"type\":\"disabled\"}"))
    Err(e) => fail("encode failed: " + e)
  }
}

///|
/// === structured_output ===
test "with_structured_output - JsonSchema maps to response_format / format" {
  let opts = @sdk.PrismOptions::default().with_structured_output(
    JsonSchema("{\"type\":\"object\"}"),
  )
  let p_openai = @sdk.Prism::new().with_provider("openai")
  match p_openai.encode_request("Hi", opts) {
    Ok(json) =>
      assert_true(
        json.contains("\"response_format\":{\"type\":\"json_schema\""),
      )
    Err(e) => fail("openai encode failed: " + e)
  }
  let p_msg = @sdk.Prism::new().with_provider("messages")
  match p_msg.encode_request("Hi", opts) {
    Ok(json) =>
      assert_true(json.contains("\"format\":{\"type\":\"json_schema\""))
    Err(e) => fail("messages encode failed: " + e)
  }
}

///|
test "with_structured_output - JsonObject maps to json_object" {
  let opts = @sdk.PrismOptions::default().with_structured_output(JsonObject)
  let p = @sdk.Prism::new().with_provider("openai")
  match p.encode_request("Hi", opts) {
    Ok(json) =>
      assert_true(
        json.contains("\"response_format\":{\"type\":\"json_object\"}"),
      )
    Err(e) => fail("encode failed: " + e)
  }
}

///|
/// === parallel_tool_calls（extras 语义反传）===
test "with_parallel_tool_calls - false inverts per target" {
  let opts = @sdk.PrismOptions::default().with_parallel_tool_calls(false)
  let p_openai = @sdk.Prism::new().with_provider("openai")
  match p_openai.encode_request("Hi", opts) {
    Ok(json) => assert_true(json.contains("\"parallel_tool_calls\":false"))
    Err(e) => fail("openai encode failed: " + e)
  }
  // messages 语义反向：parallel_tool_calls=false → disable_parallel_tool_use=true
  let p_msg = @sdk.Prism::new().with_provider("messages")
  match p_msg.encode_request("Hi", opts) {
    Ok(json) => assert_true(json.contains("\"disable_parallel_tool_use\":true"))
    Err(e) => fail("messages encode failed: " + e)
  }
}

///|
test "with_parallel_tool_calls - true inverts per target" {
  let opts = @sdk.PrismOptions::default().with_parallel_tool_calls(true)
  let p_openai = @sdk.Prism::new().with_provider("openai")
  match p_openai.encode_request("Hi", opts) {
    Ok(json) => assert_true(json.contains("\"parallel_tool_calls\":true"))
    Err(e) => fail("openai encode failed: " + e)
  }
  let p_msg = @sdk.Prism::new().with_provider("messages")
  match p_msg.encode_request("Hi", opts) {
    Ok(json) =>
      assert_true(json.contains("\"disable_parallel_tool_use\":false"))
    Err(e) => fail("messages encode failed: " + e)
  }
}

///|
/// === builder 保留其余字段 ===
test "options builders - preserve base fields" {
  let base = @sdk.PrismOptions::new(
    Some("gpt-4o-mini"),
    Some(0.5),
    Some(100),
    None,
    None,
  )
  let opts = base.with_tool_choice(Auto).with_reasoning(None, Some(Low))
  assert_eq(opts.model, Some("gpt-4o-mini"))
  assert_eq(opts.temperature, Some(0.5))
  assert_eq(opts.max_tokens, Some(100))
  assert_eq(opts.tool_choice, Some(Auto))
  assert_eq(opts.reasoning_effort, Some(Low))
  // 缺省项仍为 None
  assert_true(opts.structured_output is None)
  assert_true(opts.parallel_tool_calls is None)
}
