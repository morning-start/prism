///|
/// 会话载体的回退路径与语义完整性（P0/P1 修复配套）。
///
/// 注册表未提供会话工厂时（动态注册的 provider），`StreamConverter` 回退到
/// `events_encode_with_ctx` 的逐帧无状态编码 —— 该路径必须仍然可用。

///|
test "sdk fallback - dynamic provider without session factories still converts" {
  let name = "zzprobe-fallback"
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
    @openai.openai_sse_to_events,
    @openai.lux_events_to_openai_sse,
    @openai.lux_events_to_openai_sse_with_ctx,
    None,
    None,
    None,
  )
  @sdk.register_provider(reg)
  let sse = "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
    "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"hi\"}}]}\n\n" +
    "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n" +
    "data: [DONE]\n\n"
  // 回退编码载体（无 session 工厂）：逐帧 ctx 编码
  match @sdk.StreamConverter::new(name, "openai") {
    Ok(conv) => {
      match conv.feed(sse) {
        Ok(frames) => assert_true(frames.length() > 0)
        Err(e) => fail("feed failed: " + e)
      }
      match conv.finish() {
        Ok(_) => ()
        Err(e) => fail("finish failed: " + e)
      }
    }
    Err(e) => fail("new failed: " + e)
  }
  // 回退解码载体：Prism::stream_session 走同一回退
  let p = @sdk.Prism::new().with_provider(name)
  match p.stream_session() {
    Ok(sess) => {
      match sess.feed(sse) {
        Ok(_) => ()
        Err(e) => fail("session feed failed: " + e)
      }
      match sess.finish() {
        Ok(_) => ()
        Err(e) => fail("session finish failed: " + e)
      }
    }
    Err(e) => fail("stream_session failed: " + e)
  }
  assert_true(@sdk.unregister_provider(name))
}

///|
/// 注册表会话工厂的传递：`with_stream_sessions` 必须保留其余字段，
/// 且 `with_overrides`（薄注册）不得丢掉会话工厂（否则派生的部署态
/// provider 会静默退回无状态编码）。
test "sdk registry - with_overrides preserves stream session factories" {
  let base = @sdk.all_providers()[0]
  // 基座（responses）在 build_providers 里注册了编码会话工厂
  assert_true(base.stream_encoder is Some(_))
  let derived = base.with_overrides(@sdk.RegistrationOverrides::default())
  assert_true(derived.stream_encoder is Some(_))
}
