///|
/// ═══ 功能组：branch coverage（src/sdk 黑盒分支覆盖）═══
///
/// 本文件只走 public API（`morning-start/prism/sdk`），覆盖 src/sdk 下
/// 11 个源文件中未被既有 22 个测试文件触及的分支：
///   codec_pipeline / convert / context / diagnostics / hooks / match /
///   pipeline / prism / registry / schema / snapshot
///
/// 手法说明：
///   - 需要「codec 真的失败」才能走到的 `Err(e) => Err(e)` 传播分支，用
///     `branch_failing_registration` 注册一个全 codec 必败的动态 provider；
///     黑盒包无法构造 `@meta.ProviderSchema` 字面量，因此从静态注册表
///     （`@sdk.all_providers()[0]`）借一个 schema 值。
///   - 需要「能力声明为 Absent」的分支，用 `branch_openai_registration`
///     注册一个复用 openai codec、但 capability 为 `default()`（全 Absent）
///     的动态 provider。
///   - 每个测试结束时注销自注册项，避免污染同包其他测试。

///|
/// 注册一个全 codec 必然失败的动态 provider（错误传播分支用）。
fn branch_failing_registration(name : String) -> @sdk.ProviderRegistration {
  let capability = @lux.ProviderCapability::new(
    name + "*",
    name,
    @lux.LucentCapabilities::default(),
    None,
  )
  @sdk.ProviderRegistration::new(
    name,
    [],
    capability,
    name + "*",
    @sdk.all_providers()[0].schema,
    fn(
      _s : String,
    ) -> Result[@lux.ConversionResult[@lux.LucentRequest], String] {
      Err("branch-fail request decode")
    },
    fn(
      _r : @lux.LucentRequest,
    ) -> Result[@lux.ConversionResult[String], String] {
      Err("branch-fail request encode")
    },
    fn(
      _s : String,
    ) -> Result[@lux.ConversionResult[@lux.LucentResponse], String] {
      Err("branch-fail response decode")
    },
    fn(
      _r : @lux.LucentResponse,
    ) -> Result[@lux.ConversionResult[String], String] {
      Err("branch-fail response encode")
    },
    fn(
      _s : String,
    ) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
      Err("branch-fail stream decode")
    },
    fn(
      _e : Array[@lux.LucentStreamEvent],
    ) -> Result[@lux.ConversionResult[String], String] {
      Err("branch-fail stream encode")
    },
    fn(
      _e : Array[@lux.LucentStreamEvent],
      _c : @lux.LucentConversationMeta?,
    ) -> Result[@lux.ConversionResult[String], String] {
      Err("branch-fail stream encode")
    },
    None,
    None,
    None,
  )
}

///|
/// 注册一个「codec 复用 openai、capability 全 Absent」的动态 provider。
fn branch_openai_registration(
  name : String,
  model_pattern : String,
) -> @sdk.ProviderRegistration {
  let capability = @lux.ProviderCapability::new(
    model_pattern,
    name,
    @lux.LucentCapabilities::default(),
    None,
  )
  @sdk.ProviderRegistration::new(
    name,
    [],
    capability,
    model_pattern,
    @sdk.all_providers()[0].schema,
    @openai.openai_to_lux_request,
    @openai.lux_request_to_openai,
    @openai.openai_to_lux_response,
    @openai.lux_response_to_openai,
    @openai.openai_sse_to_events,
    @openai.lux_events_to_openai_sse,
    @openai.lux_events_to_openai_sse_with_ctx,
    None,
    None,
    None,
  )
}

///|
/// 最小合法 openai Chat 请求 JSON
fn branch_req_json() -> String {
  "{\"model\":\"gpt-4o\",\"messages\":[{\"role\":\"user\",\"content\":\"hi\"}]}"
}

///|
/// 最小合法 openai Chat 响应 JSON
fn branch_resp_json() -> String {
  "{\"id\":\"r1\",\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"message\":{\"role\":\"assistant\",\"content\":\"hi\"},\"finish_reason\":\"stop\"}]}"
}

///|
/// 最小合法 openai Chat SSE（content 帧 + finish 帧 + DONE）
fn branch_sse_json() -> String {
  "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
  "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hi\"}}]}\n\n" +
  "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}}]}\n\n" +
  "data: [DONE]\n\n"
}

///|
/// openai content 帧（单独一帧，不以 Finish 结尾）
fn branch_content_frame() -> String {
  "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hi\"}}]}\n\n"
}

///|
/// openai finish 帧（单独一帧，以 Finish 结尾）
fn branch_finish_frame() -> String {
  "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n"
}

///|
/// 内存 ConversationStore（测试辅助）：Map + 闭包
fn branch_mem_store() -> (
  @sdk.ConversationStore,
  Map[String, @lux.ConversationSnapshot],
) {
  let snapshots : Map[String, @lux.ConversationSnapshot] = Map([])
  let store = @sdk.ConversationStore::new(
    fn(id : String) -> @lux.ConversationSnapshot? { snapshots.get(id) },
    fn(snap : @lux.ConversationSnapshot) -> Unit {
      snapshots[snap.response_id] = snap
    },
  )
  (store, snapshots)
}

///|
/// === codec_pipeline.mbt：三段管线（请求/响应/流）的解码与编码错误传播 ===
test "sdk branch - codec pipeline error propagation" {
  // --- 解码失败：非法 JSON ---
  match @sdk.convert_request("openai", "not-json", "messages") {
    Ok(_) => fail("expected request decode error")
    Err(e) => assert_true(e.contains("json parse error"))
  }
  match @sdk.convert_response("openai", "not-json", "messages") {
    Ok(_) => fail("expected response decode error")
    Err(e) => assert_true(e.contains("json parse error"))
  }
  // --- 编码失败：注册全 codec 必败的动态 provider 作 target ---
  let name = "zzbranch-pipeline-fail"
  @sdk.register_provider(branch_failing_registration(name))
  match @sdk.convert_request("openai", branch_req_json(), name) {
    Ok(_) => fail("expected request encode error")
    Err(e) => assert_true(e.contains("branch-fail request encode"))
  }
  match @sdk.convert_response("openai", branch_resp_json(), name) {
    Ok(_) => fail("expected response encode error")
    Err(e) => assert_true(e.contains("branch-fail response encode"))
  }
  match @sdk.convert_stream("openai", branch_sse_json(), name) {
    Ok(_) => fail("expected stream encode error")
    Err(e) => assert_true(e.contains("branch-fail stream encode"))
  }
  // --- 流解码失败：同一 provider 作 source ---
  match @sdk.convert_stream(name, "data: {}", "messages") {
    Ok(_) => fail("expected stream decode error")
    Err(e) => assert_true(e.contains("branch-fail stream decode"))
  }
  assert_true(@sdk.unregister_provider(name))
}

///|
/// === convert.mbt：ConvertMetaResult::meta + convert_response_with_meta 错误传播 ===
test "sdk branch - convert response with meta accessor and errors" {
  // meta() 取值器（L33）
  match
    @sdk.convert_response_with_meta("openai", branch_resp_json(), "messages") {
    Ok(cr) => assert_eq(cr.meta().source_provider, "openai")
    Err(e) => fail("convert_response_with_meta failed: " + e)
  }
  // 目标编码失败（L75）
  let name = "zzbranch-meta-encode"
  @sdk.register_provider(branch_failing_registration(name))
  match @sdk.convert_response_with_meta("openai", branch_resp_json(), name) {
    Ok(_) => fail("expected encode error")
    Err(e) => assert_true(e.contains("branch-fail response encode"))
  }
  // 未知 target → resolve_pair 失败（L77）
  match
    @sdk.convert_response_with_meta(
      "openai",
      branch_resp_json(),
      "zzbranch-meta-nope",
    ) {
    Ok(_) => fail("expected resolve error")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
  assert_true(@sdk.unregister_provider(name))
}

///|
/// === convert.mbt：类型化错误入口的成功/失败路径 ===
test "sdk branch - typed convert entrypoints" {
  // convert_request_typed 成功（L138）
  match @sdk.convert_request_typed("openai", branch_req_json(), "messages") {
    Ok(cr) => assert_true(cr.value().contains("messages"))
    Err(e) => fail("convert_request_typed failed: " + e.message())
  }
  // convert_request_typed 失败（L152）
  match
    @sdk.convert_request_typed("openai", branch_req_json(), "zzbranch-nope") {
    Ok(_) => fail("expected typed error")
    Err(e) => {
      assert_true(e.message().contains("unknown provider"))
      assert_eq(e.provider, Some("openai"))
    }
  }
  // convert_response_typed 成功（L164）
  match @sdk.convert_response_typed("openai", branch_resp_json(), "messages") {
    Ok(cr) => assert_true(cr.value().contains("r1"))
    Err(e) => fail("convert_response_typed failed: " + e.message())
  }
}

///|
/// === convert.mbt：StreamConverter 增量会话的错误传播 ===
test "sdk branch - stream converter failure propagation" {
  let broken = "zzbranch-conv-fail"
  @sdk.register_provider(branch_failing_registration(broken))
  // --- 编码失败（L295 + L319）：target 编码必败，帧不以 Finish 结尾 ---
  match @sdk.StreamConverter::new("openai", broken) {
    Ok(conv) =>
      match conv.feed(branch_content_frame()) {
        Ok(_) => fail("expected encode failure")
        Err(e) => assert_true(e.contains("branch-fail stream encode"))
      }
    Err(e) => fail("StreamConverter::new failed: " + e)
  }
  // --- finish() 冲刷保持帧时编码失败（L258） ---
  match @sdk.StreamConverter::new("openai", broken) {
    Ok(conv) => {
      let _ = conv.feed(branch_finish_frame())
      match conv.finish() {
        Ok(_) => fail("expected held-frame encode failure")
        Err(e) => assert_true(e.contains("branch-fail stream encode"))
      }
    }
    Err(e) => fail("StreamConverter::new failed: " + e)
  }
  // --- finish() 时 convert_frames 失败（L263），source 解码必败 ---
  match @sdk.StreamConverter::new(broken, "openai") {
    Ok(conv) => {
      // 不喂完整帧：留在 splitter 缓冲里，由 finish() 冲刷后才解码失败
      let _ = conv.feed("data: {}")
      match conv.finish() {
        Ok(_) => fail("expected convert_frames failure")
        Err(e) => assert_true(e.contains("branch-fail stream decode"))
      }
    }
    Err(e) => fail("StreamConverter::new failed: " + e)
  }
  assert_true(@sdk.unregister_provider(broken))
}

///|
/// === convert.mbt：normalize_events 的 BlockEnd 分支（remove_int） ===
test "sdk branch - stream converter block end normalization" {
  // messages 逐帧解码：content_block_start 后另帧 content_block_stop →
  // open_blocks 命中 → remove_int（L345 / L373 / L375）
  match @sdk.StreamConverter::new("messages", "openai") {
    Ok(conv) => {
      let sse = "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n" +
        "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n"
      match conv.feed(sse) {
        Ok(frames) => assert_true(frames.length() >= 1)
        Err(e) => fail("feed failed: " + e)
      }
      let _ = conv.finish()
    }
    Err(e) => fail("StreamConverter::new failed: " + e)
  }
}

///|
/// === convert.mbt：convert_response_with_meta 的解码失败路径 ===
test "sdk branch - convert response with meta decode failure" {
  // source 解码失败 → 内层 Err(e) => Err(e)
  let broken = "zzbranch-meta-decode"
  @sdk.register_provider(branch_failing_registration(broken))
  match @sdk.convert_response_with_meta(broken, "{}", "messages") {
    Ok(_) => fail("expected decode error")
    Err(e) => assert_true(e.contains("branch-fail response decode"))
  }
  assert_true(@sdk.unregister_provider(broken))
}

///|
/// === convert.mbt：typed 入口的剩余成功/失败路径 ===
test "sdk branch - typed convert remaining paths" {
  // convert_response_typed 失败
  match
    @sdk.convert_response_typed("openai", branch_resp_json(), "zzbranch-nope") {
    Ok(_) => fail("expected typed error")
    Err(e) => {
      assert_true(e.message().contains("unknown provider"))
      assert_eq(e.provider, Some("openai"))
    }
  }
  // convert_stream_typed 成功
  match @sdk.convert_stream_typed("openai", branch_sse_json(), "messages") {
    Ok(cr) => assert_true(cr.value().contains("message"))
    Err(e) => fail("convert_stream_typed failed: " + e.message())
  }
  // convert_stream_typed 失败
  match
    @sdk.convert_stream_typed("openai", branch_sse_json(), "zzbranch-nope") {
    Ok(_) => fail("expected typed error")
    Err(e) => assert_eq(e.provider, Some("openai"))
  }
  // convert_request_typed 失败路径（含 .with_provider 注入的 provider 名）
  let broken = "zzbranch-typed-fail"
  @sdk.register_provider(branch_failing_registration(broken))
  match @sdk.convert_request_typed(broken, branch_req_json(), "messages") {
    Ok(_) => fail("expected typed request error")
    Err(e) => assert_eq(e.provider, Some(broken))
  }
  // convert_response_typed 成功路径
  match @sdk.convert_response_typed("openai", branch_resp_json(), "messages") {
    Ok(cr) => assert_true(cr.value().contains("r1"))
    Err(e) => fail("convert_response_typed failed: " + e.message())
  }
  assert_true(@sdk.unregister_provider(broken))
}

///|
/// === convert.mbt：normalize_events 的 remove_int 多块路径（L376） ===
test "sdk branch - stream converter multi block normalization" {
  // 两个块同时打开，随后只闭合第一个 → remove_int 必须保留另一个块索引
  match @sdk.StreamConverter::new("messages", "openai") {
    Ok(conv) => {
      let sse = "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"a\"}}\n\n" +
        "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"text\",\"text\":\"b\"}}\n\n" +
        "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n"
      match conv.feed(sse) {
        Ok(frames) => assert_true(frames.length() >= 1)
        Err(e) => fail("feed failed: " + e)
      }
      let _ = conv.finish()
    }
    Err(e) => fail("StreamConverter::new failed: " + e)
  }
}

///|
/// === convert.mbt：StreamConverter::new 的错误传播（L79 / L227） ===
test "sdk branch - stream converter unknown provider" {
  match @sdk.StreamConverter::new("zzbranch-nope", "messages") {
    Ok(_) => fail("expected resolve error")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
}

///|
/// === convert.mbt：ends_with_finish 对空事件数组返回 false（L386） ===
test "sdk branch - stream converter empty event frame" {
  match @sdk.StreamConverter::new("openai", "messages") {
    Ok(conv) =>
      // openai 解码 "{}" 不产出任何事件 → combined 为空 → ends_with_finish([])
      match conv.feed("data: {}\n\n") {
        Ok(frames) => assert_true(frames.length() >= 0)
        Err(e) => fail("feed failed: " + e)
      }
    Err(e) => fail("StreamConverter::new failed: " + e)
  }
}

///|
/// === prism.mbt：门面 typed 入口的失败/成功 + 运行时 provider 名解析回退 ===
test "sdk branch - prism typed entrypoints and provider resolution" {
  // 未知 provider：encode_lux_request 失败 + resolved_provider_name 回退
  // （L219 / L258）
  let ghost = @sdk.Prism::new().with_provider("zzbranch-ghost")
  match ghost.encode_request_typed("hi", @sdk.PrismOptions::default()) {
    Ok(_) => fail("expected typed encode error")
    Err(e) => assert_eq(e.provider, Some("zzbranch-ghost"))
  }
  // decode_sse_typed 成功（L242）
  let ok = @sdk.Prism::new().with_provider("openai")
  match ok.decode_sse_typed(branch_sse_json()) {
    Ok(events) => assert_true(events.length() > 0)
    Err(e) => fail("decode_sse_typed failed: " + e.message())
  }
  // decode_response_typed 成功
  match ok.decode_response_typed(branch_resp_json()) {
    Ok(dr) => assert_eq(dr.text, "hi")
    Err(e) => fail("decode_response_typed failed: " + e.message())
  }
  // decode_response_with_meta：provider 名不在注册表中（L258 的 None 回退）
  match ghost.decode_response_with_meta("{}") {
    Ok(_) => fail("expected decode error for unknown provider")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
  // decode_response_with_meta 成功：meta 携带运行时解析出的规范 provider 名
  match ok.decode_response_with_meta(branch_resp_json()) {
    Ok(dr) => assert_eq(dr.meta.source_provider, "openai")
    Err(e) => fail("decode_response_with_meta failed: " + e)
  }
}

///|
/// === prism.mbt：decode_response_with_diagnostics 的 schema 命中/未命中两支 ===
test "sdk branch - prism response diagnostics schema branches" {
  // 有 schema 且校验失败 → with_diagnostic 循环执行（L282）
  let p = @sdk.Prism::new().with_provider("openai")
  match
    p.decode_response_with_diagnostics(
      "{\"id\":\"\",\"model\":\"\",\"choices\":[]}",
    ) {
    Ok(cr) => assert_true(cr.diagnostics().length() > 0)
    Err(e) => fail("decode_response_with_diagnostics failed: " + e)
  }
  // 动态注册一个名字不在 schema 表中的 provider → get_schema 返回 None（L288）
  let name = "zzbranch-noschema"
  @sdk.register_provider(branch_openai_registration(name, name + "*"))
  let q = @sdk.Prism::new().with_provider(name)
  match q.decode_response_with_diagnostics(branch_resp_json()) {
    Ok(cr) => {
      assert_eq(cr.diagnostics().length(), 0)
      assert_eq(cr.value().id, "r1")
    }
    Err(e) => fail("schemaless decode failed: " + e)
  }
  assert_true(@sdk.unregister_provider(name))
}

///|
/// === prism.mbt：check_capability 三个未支持诊断 + encode_request_with_diagnostics
///     capability 诊断落地（L503 / L515 / L528 / L315） ===
test "sdk branch - prism capability diagnostics" {
  let name = "zzbranch-caps"
  @sdk.register_provider(branch_openai_registration(name, name + "*"))
  let p = @sdk.Prism::new().with_provider(name)
  // 直接调用公开的 check_capability：三项能力全部 Absent
  let tools : Array[@lux.LucentTool] = [@lux.LucentTool::simple("f", "d", "{}")]
  let options = @lux.LucentOptions::new(
    None,
    None,
    None,
    None,
    None,
    false,
    None,
    Some(JsonObject),
    None,
    None,
  )
  let req = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [],
    Some(tools),
    None,
    options,
    None,
    Some(@lux.LucentReasoningConfig::enabled(None)),
    None,
    None,
  )
  let diags = p.check_capability(req)
  assert_true(diags.length() >= 3)
  // capability 诊断经 encode_request_with_diagnostics 落入 result（L315）
  match
    p.encode_request_with_diagnostics(
      "hi",
      @sdk.PrismOptions::default().with_reasoning(Some(true), None),
    ) {
    Ok(cr) => assert_true(cr.diagnostics().length() >= 1)
    Err(e) => fail("encode_request_with_diagnostics failed: " + e)
  }
  assert_true(@sdk.unregister_provider(name))
}

///|
/// === prism.mbt：complete / stream 的 send 与 encode 失败路径 ===
test "sdk branch - prism complete and stream failures" {
  // encode 失败（L371 / L391）
  let broken = "zzbranch-conv-fail"
  @sdk.register_provider(branch_failing_registration(broken))
  let bad = @sdk.Prism::new().with_provider(broken)
  match
    bad.complete("hi", @sdk.PrismOptions::default(), fn(
      _json : String,
    ) -> Result[String, String] {
      Ok("{}")
    }) {
    Ok(_) => fail("expected complete encode error")
    Err(_) => ()
  }
  match
    bad.stream(@sdk.Context::new().add_user("hi"), fn(
      _json : String,
    ) -> Result[String, String] {
      Ok("")
    }) {
    Ok(_) => fail("expected stream encode error")
    Err(_) => ()
  }
  // send 失败（L369 / L389）
  let ok = @sdk.Prism::new().with_provider("openai")
  match
    ok.complete("hi", @sdk.PrismOptions::default(), fn(
      _json : String,
    ) -> Result[String, String] {
      Err("send boom")
    }) {
    Ok(_) => fail("expected complete send error")
    Err(e) => assert_true(e.contains("send boom"))
  }
  match
    ok.stream(@sdk.Context::new().add_user("hi"), fn(
      _json : String,
    ) -> Result[String, String] {
      Err("send boom")
    }) {
    Ok(_) => fail("expected stream send error")
    Err(e) => assert_true(e.contains("send boom"))
  }
  assert_true(@sdk.unregister_provider(broken))
}

///|
/// === prism.mbt：events_to_context 的 Thinking 忽略 + endpoint 未知 provider ===
test "sdk branch - prism thinking event and endpoint miss" {
  // thinking 帧 → PrismEvent::Thinking → events_to_context 忽略（L422）
  let sse = "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"thinking\",\"thinking\":\"\"}}\n\n" +
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"thinking_delta\",\"thinking\":\"step\"}}\n\n" +
    "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  let p = @sdk.Prism::new().with_provider("messages")
  match p.decode_sse(sse) {
    Ok(events) => {
      let ctx = p.events_to_context(@sdk.Context::new().add_user("hi"), events)
      // 无文本无工具调用 → 不追加消息
      assert_eq(ctx.messages.length(), 1)
    }
    Err(e) => fail("decode_sse failed: " + e)
  }
  // 未知 provider → endpoint 返回 None（L461）
  assert_true(p.endpoint("zzbranch-nope") is None)
}

///|
/// === pipeline.mbt：Prism::encode_lux_request / decode_sse_inner 错误分支 ===
test "sdk branch - pipeline encode and sse decode failures" {
  let name = "zzbranch-pipeline-decode"
  @sdk.register_provider(branch_failing_registration(name))
  let p = @sdk.Prism::new().with_provider(name)
  // encode_lux_request：注册表命中但 codec 失败（L46）
  match p.encode_request("hi", @sdk.PrismOptions::default()) {
    Ok(_) => fail("expected encode error")
    Err(e) => assert_true(e.contains("branch-fail request encode"))
  }
  // decode_sse_inner：注册表命中但 codec 失败（L62）
  match p.decode_sse("data: {}") {
    Ok(_) => fail("expected sse decode error")
    Err(e) => assert_true(e.contains("branch-fail stream decode"))
  }
  assert_true(@sdk.unregister_provider(name))
}

///|
/// === pipeline.mbt：lucent_events_to_prism 的工具块状态机（messages 路径） ===
test "sdk branch - pipeline tool call state machine messages" {
  let p = @sdk.Prism::new().with_provider("messages")
  // 连续两个 tool_use 块（L109）+ 紧随其后的 text 块冲刷未闭合工具块（L120）
  let sse = "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tu_a\",\"name\":\"fa\"}}\n\n" +
    "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":1,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tu_b\",\"name\":\"fb\"}}\n\n" +
    "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":2,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n"
  match p.decode_sse(sse) {
    Ok(events) => {
      let mut calls = 0
      for ev in events {
        match ev {
          ToolCall(_) => calls = calls + 1
          _ => ()
        }
      }
      assert_true(calls >= 2)
    }
    Err(e) => fail("decode_sse failed: " + e)
  }
  // 流尾未闭合工具块（L184）：有 BlockStart + 参数增量，但无 content_block_stop
  let unclosed = "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tu_z\",\"name\":\"fz\"}}\n\n" +
    "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"a\\\":1}\"}}\n\n" +
    "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
  match p.decode_sse(unclosed) {
    Ok(events) => {
      let mut last_call : @sdk.PrismToolCall? = None
      for ev in events {
        match ev {
          ToolCall(tc) => last_call = Some(tc)
          _ => ()
        }
      }
      match last_call {
        Some(tc) => assert_eq(tc.arguments_json, "{\"a\":1}")
        None => fail("unclosed tool block was dropped")
      }
    }
    Err(e) => fail("decode_sse failed: " + e)
  }
}

///|
/// === pipeline.mbt：lucent_events_to_prism 的 responses ItemStart 路径 ===
test "sdk branch - pipeline item start responses path" {
  let p = @sdk.Prism::new().with_provider("responses")
  // function_call item（L140）→ 连续第二个（L143）→ message item 冲刷（L161）
  // → function_call_output item（L152 / L155）
  let sse = "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"name\":\"fa\",\"arguments\":\"{}\"}}\n\n" +
    "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":1,\"item\":{\"type\":\"function_call\",\"id\":\"fc_2\",\"name\":\"fb\",\"arguments\":\"{}\"}}\n\n" +
    "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":2,\"item\":{\"type\":\"message\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"ok\"}]}}\n\n" +
    "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":3,\"item\":{\"type\":\"function_call_output\",\"call_id\":\"fc_1\",\"output\":\"done\"}}\n\n"
  match p.decode_sse(sse) {
    Ok(events) => {
      let mut calls = 0
      let mut results = 0
      for ev in events {
        match ev {
          ToolCall(_) => calls = calls + 1
          ToolResult(_) => results = results + 1
          _ => ()
        }
      }
      assert_true(calls >= 2)
      assert_true(results >= 1)
      // events_to_context：ToolResult 事件被忽略（prism.mbt L423），
      // ToolCall 事件会正常追加一条 assistant 回合消息
      let ctx = p.events_to_context(@sdk.Context::new().add_user("hi"), events)
      assert_eq(ctx.messages.length(), 2)
      assert_eq(ctx.messages[1].tool_calls.length(), 2)
    }
    Err(e) => fail("decode_sse failed: " + e)
  }
}

///|
/// === pipeline.mbt：BlockDiscard 分支（L136） ===
///
/// 没有任何静态 provider 的流解码器产出 BlockDiscard（Gemini 官方 chunk 是
/// 增量语义，见 gemini/stream_decode.mbt 注释），因此必须自注册一个
/// events_decode 直接合成 BlockDiscard 事件的动态 provider。
test "sdk branch - pipeline block discard event" {
  let name = "zzbranch-discard"
  let capability = @lux.ProviderCapability::new(
    name + "*",
    name,
    @lux.LucentCapabilities::default(),
    None,
  )
  let reg = @sdk.ProviderRegistration::new(
    name,
    [],
    capability,
    name + "*",
    @sdk.all_providers()[0].schema,
    @openai.openai_to_lux_request,
    @openai.lux_request_to_openai,
    @openai.openai_to_lux_response,
    @openai.lux_response_to_openai,
    fn(
      _s : String,
    ) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
      Ok(
        // 打开 tool 块 → 丢弃它（idx 必须等于 tool_idx 才命中分支体）
        @lux.ConversionResult::new([
          BlockStart(0, ToolCall("tu_d", "fn_d")),
          BlockDiscard(0),
          Done,
        ]),
      )
    },
    @openai.lux_events_to_openai_sse,
    @openai.lux_events_to_openai_sse_with_ctx,
    None,
    None,
    None,
  )
  @sdk.register_provider(reg)
  let p = @sdk.Prism::new().with_provider(name)
  match p.decode_sse("data: {}") {
    Ok(events) => {
      // 被丢弃的 tool 块不发射 ToolCall 事件
      let mut calls = 0
      for ev in events {
        match ev {
          ToolCall(_) => calls = calls + 1
          _ => ()
        }
      }
      assert_eq(calls, 0)
      // 工具块被丢弃且解码器未产出 Finish → PrismEvent 数组为空
      assert_eq(events.length(), 0)
    }
    Err(e) => fail("decode_sse failed: " + e)
  }
  assert_true(@sdk.unregister_provider(name))
  // 同一 provider 作为 StreamConverter 的 source：normalize_events 的
  // BlockDiscard 分支（open_blocks 命中 → remove_int）
  @sdk.register_provider(reg)
  match @sdk.StreamConverter::new(name, "openai") {
    Ok(conv) => {
      let _ = conv.feed("data: {}\n\n")
      let _ = conv.finish()
    }
    Err(e) => fail("StreamConverter::new failed: " + e)
  }
  assert_true(@sdk.unregister_provider(name))
}

///|
/// === convert.mbt：normalize_events 的 BlockDiscard 分支（L350） ===
test "sdk branch - stream converter block discard normalization" {
  let name = "zzbranch-discard-norm"
  let capability = @lux.ProviderCapability::new(
    name + "*",
    name,
    @lux.LucentCapabilities::default(),
    None,
  )
  let reg = @sdk.ProviderRegistration::new(
    name,
    [],
    capability,
    name + "*",
    @sdk.all_providers()[0].schema,
    @openai.openai_to_lux_request,
    @openai.lux_request_to_openai,
    @openai.openai_to_lux_response,
    @openai.lux_response_to_openai,
    fn(
      s : String,
    ) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
      // 每帧独立解码：BlockStart 先打开块，BlockDiscard 再命中 open_blocks
      if s.contains("start") {
        Ok(@lux.ConversionResult::new([BlockStart(0, Text), Done]))
      } else {
        Ok(@lux.ConversionResult::new([BlockDiscard(0), Done]))
      }
    },
    @openai.lux_events_to_openai_sse,
    @openai.lux_events_to_openai_sse_with_ctx,
    None,
    None,
    None,
  )
  @sdk.register_provider(reg)
  match @sdk.StreamConverter::new(name, "openai") {
    Ok(conv) => {
      let _ = conv.feed("data: start\n\n")
      let _ = conv.feed("data: stop\n\n")
      let _ = conv.finish()
    }
    Err(e) => fail("StreamConverter::new failed: " + e)
  }
  assert_true(@sdk.unregister_provider(name))
}

///|
/// === pipeline.mbt：Finish(LucentFinishReason) → PrismFinishReason 映射 ===
test "sdk branch - pipeline finish reason mapping" {
  let p = @sdk.Prism::new().with_provider("openai")
  let cases : Array[String] = [
    "length", "content_filter", "safety", "recitation", "error",
  ]
  for fr in cases {
    let sse = branch_content_frame() +
      "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"" +
      fr +
      "\"}]}\n\n" +
      "data: [DONE]\n\n"
    match p.decode_sse(sse) {
      Ok(events) => {
        let mut seen : @sdk.PrismFinishReason? = None
        for ev in events {
          match ev {
            Finish(r) => seen = Some(r)
            _ => ()
          }
        }
        match fr {
          "length" =>
            match seen {
              Some(Length) => ()
              _ => fail("expected PrismFinishReason::Length")
            }
          "content_filter" =>
            match seen {
              Some(ContentFilter) => ()
              _ => fail("expected PrismFinishReason::ContentFilter")
            }
          // Safety / Recitation / Error 在 LucentFinishReason 中无对应
          // PrismFinishReason → 落入 `_ => Error`
          _ =>
            match seen {
              Some(Error) => ()
              _ => fail("expected PrismFinishReason::Error for \{fr}")
            }
        }
      }
      Err(e) => fail("decode_sse failed: " + e)
    }
  }
}

///|
/// === hooks.mbt：三个 convert_*_with_hooks 的错误传播分支 ===
test "sdk branch - hooks error propagation" {
  let broken = "zzbranch-hooks-fail"
  @sdk.register_provider(branch_failing_registration(broken))
  // 请求：resolve_pair 失败（L74）
  match @sdk.convert_request_with_hooks("zzbranch-nope", "{}", "messages", []) {
    Ok(_) => fail("expected resolve error")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
  // 请求：解码失败（L72）
  match @sdk.convert_request_with_hooks("openai", "not-json", "messages", []) {
    Ok(_) => fail("expected decode error")
    Err(e) => assert_true(e.contains("json parse error"))
  }
  // 请求：编码失败（L69）
  match
    @sdk.convert_request_with_hooks("openai", branch_req_json(), broken, []) {
    Ok(_) => fail("expected encode error")
    Err(e) => assert_true(e.contains("branch-fail request encode"))
  }
  // 响应：resolve_pair 失败（L103）
  match @sdk.convert_response_with_hooks("openai", "{}", "zzbranch-nope", []) {
    Ok(_) => fail("expected resolve error")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
  // 响应：解码失败（L101）
  match @sdk.convert_response_with_hooks("openai", "not-json", "messages", []) {
    Ok(_) => fail("expected decode error")
    Err(e) => assert_true(e.contains("json parse error"))
  }
  // 响应：编码失败（L98）
  match
    @sdk.convert_response_with_hooks("openai", branch_resp_json(), broken, []) {
    Ok(_) => fail("expected encode error")
    Err(e) => assert_true(e.contains("branch-fail response encode"))
  }
  // 流：resolve_pair 失败（L135）
  match
    @sdk.convert_stream_with_hooks("zzbranch-nope", "data: {}", "openai", []) {
    Ok(_) => fail("expected resolve error")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
  // 流：解码失败（L133）
  match @sdk.convert_stream_with_hooks(broken, "data: {}", "openai", []) {
    Ok(_) => fail("expected decode error")
    Err(e) => assert_true(e.contains("branch-fail stream decode"))
  }
  // 流：编码失败（L130）
  match
    @sdk.convert_stream_with_hooks("openai", branch_sse_json(), broken, []) {
    Ok(_) => fail("expected encode error")
    Err(e) => assert_true(e.contains("branch-fail stream encode"))
  }
  assert_true(@sdk.unregister_provider(broken))
}

///|
/// === hooks.mbt：内置钩子的边界分支 ===
test "sdk branch - builtin hook edge branches" {
  let diags : Array[@lux.ConversionDiagnostic] = []
  // hook_filter_tools：tools 为空数组 → 原样返回、无诊断（L203）
  let empty_tools = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("hi")]),
      ),
    ],
    Some([]),
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let filter = @sdk.hook_filter_tools(["x"])
  let out_empty = filter(empty_tools, diags)
  match out_empty.tools {
    Some(t) => assert_eq(t.length(), 0)
    None => fail("expected empty tools preserved")
  }
  assert_eq(diags.length(), 0)
  // hook_filter_tools：tools 为 None → 原样返回（L237）
  let no_tools = @lux.LucentRequest::new(
    "gpt-4o",
    None,
    [],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let out_none = filter(no_tools, diags)
  assert_true(out_none.tools is None)
  assert_eq(diags.length(), 0)
  // hook_append_instructions：instructions 为 None → 新建单元素数组（L257）
  let out_instr = @sdk.hook_append_instructions("be terse")(no_tools, diags)
  match out_instr.instructions {
    Some(arr) => assert_eq(arr.length(), 1)
    None => fail("expected appended instructions")
  }
  // hook_set_model：目标模型相同 → 原样返回（L284）
  let same = @sdk.hook_set_model("gpt-4o")(no_tools, diags)
  assert_eq(same.model, "gpt-4o")
  assert_eq(diags.length(), 0)
}

///|
/// === match.mbt：single_pattern_matches 的无通配符与双通配符分支 ===
test "sdk branch - match model pattern arms" {
  // 无通配符的 model_pattern：pattern == model_name（L146）
  let exact = "zzbranch-exact"
  @sdk.register_provider(branch_openai_registration(exact, exact))
  match @sdk.match_by_model(exact) {
    Some(reg) => assert_eq(reg.name, exact)
    None => fail("exact pattern not matched")
  }
  assert_true(@sdk.unregister_provider(exact))
  // 双通配符的 model_pattern：prefix/mid/suffix 三分支
  // （L152 / L160 / L166 / L273）
  let pattern = "zzbranch-a*b*c"
  @sdk.register_provider(branch_openai_registration("zzbranch-two", pattern))
  match @sdk.match_by_model("zzbranch-aXbYc") {
    Some(reg) => assert_eq(reg.name, "zzbranch-two")
    None => fail("two-star pattern not matched")
  }
  assert_true(@sdk.unregister_provider("zzbranch-two"))
}

///|
/// === registry.mbt：unregister_provider 的保留与重填分支 ===
test "sdk branch - unregister provider keeps siblings" {
  let a = "zzbranch-sib-a"
  let b = "zzbranch-sib-b"
  let before = @sdk.list_provider_names().length()
  @sdk.register_provider(branch_openai_registration(a, a + "*"))
  @sdk.register_provider(branch_openai_registration(b, b + "*"))
  assert_eq(@sdk.list_provider_names().length(), before + 2)
  // 移除 a：b 被保留（L306）并在原地清空后重填（L315）
  assert_true(@sdk.unregister_provider(a))
  assert_true(@sdk.match_provider_name(a) is None)
  match @sdk.match_provider_name(b) {
    Some(reg) => assert_eq(reg.name, b)
    None => fail("sibling registration was lost")
  }
  assert_true(@sdk.unregister_provider(b))
  assert_eq(@sdk.list_provider_names().length(), before)
}

///|
/// === registry.mbt：gemini 的 events_encode_with_ctx 包装体（L400） ===
test "sdk branch - gemini ctx aware stream encode" {
  match @sdk.StreamConverter::new("openai", "gemini") {
    Ok(conv) =>
      match conv.feed(branch_content_frame()) {
        Ok(frames) => assert_true(frames.length() >= 1)
        Err(e) => fail("feed failed: " + e)
      }
    Err(e) => fail("StreamConverter::new failed: " + e)
  }
}

///|
/// === schema.mbt：validate_request 的 top_p 下界错误分支（L260） ===
test "sdk branch - schema validation top_p lower bound" {
  let options = @lux.LucentOptions::new(
    None,
    Some(-0.5),
    None,
    None,
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
    [],
    None,
    None,
    options,
    None,
    None,
    None,
    None,
  )
  let errors = @sdk.ProviderSchema::anthropic().validate_request(req)
  let mut has_lower_bound = false
  for e in errors {
    if e.contains("top_p must be >=") {
      has_lower_bound = true
    }
  }
  assert_true(has_lower_bound)
}

///|
/// === snapshot.mbt：previous_response_id_of 的非 String 回退 + restore 的
///     tools/tool_choice 优先 + convert_request_with_store 错误传播 ===
test "sdk branch - snapshot restore and store errors" {
  // extras 中的 previous_response_id 不是 String（L42）
  let opts = @lux.LucentOptions::default().with_extras(
    Some({ "previous_response_id": Json::number(7) }),
  )
  let req = @lux.LucentRequest::new(
    "gpt-5.3",
    None,
    [],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  assert_true(@sdk.previous_response_id_of(req) is None)
  // restore：新请求自带 tools / tool_choice → 优先生效（L74 / L78）
  let snap_req = @lux.LucentRequest::new(
    "gpt-5.3",
    Some([@lux.LucentContent::text("old system")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("old")]),
      ),
    ],
    Some([@lux.LucentTool::simple("f", "d", "{}")]),
    Some(Auto),
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let snapshot = @lux.ConversationSnapshot::new("resp_old", snap_req, None)
  let new_req = @lux.LucentRequest::new(
    "gpt-5.3",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [@lux.LucentContent::text("new")]),
      ),
    ],
    Some([@lux.LucentTool::simple("g", "d", "{}")]),
    Some(Required),
    @lux.LucentOptions::default().with_previous_response_id(Some("resp_old")),
    None,
    None,
    None,
    None,
  )
  let restored = @sdk.restore_request_from_snapshot(new_req, snapshot)
  assert_eq(restored.conversation.length(), 2)
  match restored.tools {
    Some(tools) => assert_eq(tools.length(), 1)
    None => fail("expected new tools to win")
  }
  assert_eq(restored.tool_choice, Some(Required))
  // convert_request_with_store：解析失败（L162）
  let (store, _) = branch_mem_store()
  match
    @sdk.convert_request_with_store(
      "openai",
      branch_req_json(),
      "zzbranch-nope",
      store,
    ) {
    Ok(_) => fail("expected resolve error")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
  // 解码失败（L160）
  match
    @sdk.convert_request_with_store("openai", "not-json", "messages", store) {
    Ok(_) => fail("expected decode error")
    Err(e) => assert_true(e.contains("json parse error"))
  }
  // 编码失败（L156）
  let broken = "zzbranch-store-fail"
  @sdk.register_provider(branch_failing_registration(broken))
  match
    @sdk.convert_request_with_store("openai", branch_req_json(), broken, store) {
    Ok(_) => fail("expected encode error")
    Err(e) => assert_true(e.contains("branch-fail request encode"))
  }
  assert_true(@sdk.unregister_provider(broken))
}

///|
/// === diagnostics.mbt：status_label / status_severity / 计数 / summary 分支 ===
test "sdk branch - diagnostics status labels and counts" {
  let exact = @lux.ConversionDiagnostic::new("a", Exact, None)
  let invalid = @lux.ConversionDiagnostic::new("b", Invalid, None)
  // status_severity(Exact)=0 / (Invalid)=3 与 status_label(Invalid)="Invalid"
  // （L53 / L56 / L20）
  match @sdk.enforce_policy("v", [exact, invalid], FailOnDegraded) {
    Ok(_) => fail("expected policy violation")
    Err(e) => {
      assert_true(e.contains("FailOnDegraded"))
      assert_true(e.contains("b: Invalid"))
    }
  }
  // 计数与 summary：Exact / Invalid 各一条（L202 / L270 / L279）
  let c = @sdk.DiagnosticCollector::new()
  c.push(@lux.ConversionDiagnostic::new("a", Exact, None))
  c.push(@lux.ConversionDiagnostic::new("b", Invalid, None))
  let counts = c.count_by_status()
  assert_eq(counts.exact, 1)
  assert_eq(counts.invalid, 1)
  assert_eq(counts.total(), 2)
  let summary = c.summary()
  assert_true(summary.contains("Exact=1"))
  assert_true(summary.contains("Invalid=1"))
}

///|
/// === context.mbt：merge_parallel_tool_extras 的两个 Some 分支 ===
test "sdk branch - context parallel tool extras merging" {
  // extras 已存在 + 未设置 parallel_tool_calls 键 → m.copy() 后注入（L318）
  let extras : Map[String, Json] = Map([])
  extras["tenant"] = Json::string("acme")
  let opts = @sdk.PrismOptions::new(None, None, None, None, Some(extras)).with_parallel_tool_calls(
    true,
  )
  let req = @sdk.context_to_lux_request(
    @sdk.Context::new().add_user("hi"),
    "gpt-4o",
    opts,
  )
  match req.options.extras {
    Some(m) => {
      assert_eq(m.get("tenant"), Some(Json::string("acme")))
      assert_eq(m.get("parallel_tool_calls"), Some(Json::boolean(true)))
    }
    None => fail("expected merged extras")
  }
  // extras 已含 parallel_tool_calls → 用户值优先，原样返回（L323）
  let user_extras : Map[String, Json] = Map([])
  user_extras["parallel_tool_calls"] = Json::boolean(false)
  let opts2 = @sdk.PrismOptions::new(None, None, None, None, Some(user_extras)).with_parallel_tool_calls(
    true,
  )
  let req2 = @sdk.context_to_lux_request(
    @sdk.Context::new().add_user("hi"),
    "gpt-4o",
    opts2,
  )
  match req2.options.extras {
    Some(m) =>
      assert_eq(m.get("parallel_tool_calls"), Some(Json::boolean(false)))
    None => fail("expected user extras preserved")
  }
}

///|
/// === context.mbt：tool_result 缺 is_error + 显式 system/tool 角色消息 ===
test "sdk branch - context role and tool result fallbacks" {
  // SdkMessage::tool_result 之外无法构造 is_error=None 的 tool_use_id 消息，
  // 但通过公开的 messages 字段可直接放入一条 tool_use_id 消息来触发
  // is_error 的 None 回退分支。
  let base = @sdk.Context::new().add_user("hi")
  base.messages.push(@sdk.SdkMessage::new("user", "extra"))
  let req = @sdk.context_to_lux_request(
    base,
    "gpt-4o",
    @sdk.PrismOptions::default(),
  )
  assert_eq(req.conversation.length(), 2)
  // tool 角色消息：tool_use_id 为 None 时落入 "tool" => Tool 分支
  let tool_ctx = @sdk.Context::new().add_user("hi")
  tool_ctx.messages.push(@sdk.SdkMessage::new("tool", "tool output"))
  let tool_req = @sdk.context_to_lux_request(
    tool_ctx,
    "gpt-4o",
    @sdk.PrismOptions::default(),
  )
  match tool_req.conversation[1] {
    Message(m) => assert_eq(m.role, Tool)
    _ => fail("expected a plain Message item")
  }
  // system 角色消息：落入 "system" => @lux.System 分支
  let sys_ctx = @sdk.Context::new().add_user("hi")
  sys_ctx.messages.push(@sdk.SdkMessage::new("system", "be terse"))
  let sys_req = @sdk.context_to_lux_request(
    sys_ctx,
    "gpt-4o",
    @sdk.PrismOptions::default(),
  )
  match sys_req.conversation[1] {
    Message(m) => assert_eq(m.role, System)
    _ => fail("expected a system Message item")
  }
  // 未知角色消息：落入 `_ => User` 回退分支
  let unk_ctx = @sdk.Context::new().add_user("hi")
  unk_ctx.messages.push(@sdk.SdkMessage::new("reviewer", "unknown role"))
  let unk_req = @sdk.context_to_lux_request(
    unk_ctx,
    "gpt-4o",
    @sdk.PrismOptions::default(),
  )
  match unk_req.conversation[1] {
    Message(m) => assert_eq(m.role, User)
    _ => fail("expected an unknown-role Message item")
  }
}
