///|
/// 生成器库（L3 属性测试共用）
///
/// 依据：report/20260909-formal-verification-feasibility-report.md（L3）
/// 原则（遵循项目约定）：
///   1. 生成器基于 IR 构造器（@lux.*），不手写 JSON
///   2. gen_text_resp 域 = 公共交集无损子集（供 G5 跨协议差分使用）
///   3. gen_extended_req 域 = 含扩展字段（thinking/audio/native/file_uri/annotations），
///      首条消息必含扩展块，保证 G4 诊断完备性属性输入恒带扩展字段

///|
/// 按随机串长度取模选择池元素（长度恒非负，避免负下标）
fn pick_str(n : Int, pool : Array[String]) -> String {
  pool[n % pool.length()]
}

///|
/// 文本响应生成器：id/model 随机、choices 1~2 条（Assistant 单 Text 块、Stop）、
/// created_at/usage 可选（None 或简单值）
fn gen_text_resp() -> @gen.Gen[@lux.LucentResponse] {
  @gen.Gen(fn(size, r0) {
    let r1 = r0.split()
    let r2 = r1.split()
    let r3 = r2.split()
    let r4 = r3.split()
    let r5 = r4.split()
    let ids = ["resp-1", "chatcmpl-abc", "msg_123"]
    let models = ["gpt-4o", "claude-3-5-sonnet", "gemini-1.5-pro"]
    let idstr : String = @coreqc.Arbitrary::arbitrary(size, r0)
    let mstr : String = @coreqc.Arbitrary::arbitrary(size, r1)
    let has_created : Bool = @coreqc.Arbitrary::arbitrary(size, r2)
    let cint : Int = @coreqc.Arbitrary::arbitrary(size, r3)
    let has_usage : Bool = @coreqc.Arbitrary::arbitrary(size, r4)
    let usint : Int = @coreqc.Arbitrary::arbitrary(size, r5)
    let created_at = if has_created {
      Some(cint.abs() % 2000000000)
    } else {
      None
    }
    let usage = if has_usage {
      let p = usint.abs() % 10000
      Some(@lux.LucentUsage::new(p, p / 2, p + p / 2))
    } else {
      None
    }
    // choices：1~2 条 Assistant 单 Text 块
    let nstr : String = @coreqc.Arbitrary::arbitrary(size, r5.split())
    let n_choices = 1 + nstr.length() % 2
    let choices : Array[@lux.LucentChoice] = []
    let mut i = 0
    while i < n_choices {
      let r = r5.split()
      let r_txt = r.split()
      let txt : String = @coreqc.Arbitrary::arbitrary(size, r_txt)
      let msg = @lux.LucentMessage::new(Assistant, [
        @lux.LucentContent::text(txt),
      ])
      choices.push(@lux.LucentChoice::new(i, msg, Stop, None))
      i = i + 1
    }
    @lux.LucentResponse::new(
      pick_str(idstr.length(), ids),
      pick_str(mstr.length(), models),
      created_at,
      choices,
      usage,
      None,
    )
  })
}

///|
/// 按随机整数选择扩展内容块类型（0=thinking 1=audio 2=native 3=file_uri 图片 4=annotations 文本）
fn ext_block_by(pick : Int, txt : String) -> @lux.LucentContent {
  match pick % 5 {
    0 => @lux.LucentContent::thinking(txt, None)
    1 =>
      @lux.LucentContent::audio(
        "audio/mpeg",
        @lux.LucentMediaSource::url("https://x.com/a.mp3"),
      )
    2 => @lux.LucentContent::native("x-custom", Json::string(txt))
    3 =>
      @lux.LucentContent::image(
        "image/png",
        @lux.LucentMediaSource::file_uri("file:///tmp/a.png"),
      )
    _ =>
      @lux.LucentContent::text_with_annotations(txt, [
        @lux.LucentAnnotation::new(Url, None, Some("https://x.com"), None, None),
      ])
  }
}

///|
/// 扩展字段请求生成器：conversation 1~3 条消息，首条必含 ≥1 个扩展内容块，
/// 其余消息为文本；随机附 reasoning 配置与 capabilities 声明
fn gen_extended_req() -> @gen.Gen[@lux.LucentRequest] {
  @gen.Gen(fn(size, r0) {
    let r1 = r0.split()
    let r2 = r1.split()
    let r3 = r2.split()
    let r4 = r3.split()
    let models = ["gpt-4o", "claude-3-5-sonnet", "gemini-1.5-pro"]
    let mstr : String = @coreqc.Arbitrary::arbitrary(size, r0)
    let nstr : String = @coreqc.Arbitrary::arbitrary(size, r1)
    let n_msgs = 1 + nstr.length() % 3
    let conv : Array[@lux.LucentConversationItem] = []
    let mut i = 0
    while i < n_msgs {
      let r = r2.split()
      let r_blocks = r.split()
      let blocks : Array[@lux.LucentContent] = []
      if i == 0 {
        // 首条消息：1 个扩展块 + 1 个文本块
        let pick : Int = @coreqc.Arbitrary::arbitrary(size, r_blocks)
        let r_txt = r_blocks.split()
        let txt : String = @coreqc.Arbitrary::arbitrary(size, r_txt)
        blocks.push(ext_block_by(pick, txt))
        let r_txt2 = r_blocks.split()
        let txt2 : String = @coreqc.Arbitrary::arbitrary(size, r_txt2)
        blocks.push(@lux.LucentContent::text(txt2))
      } else {
        // 其余消息：1 个文本块
        let r_txt = r_blocks.split()
        let txt : String = @coreqc.Arbitrary::arbitrary(size, r_txt)
        blocks.push(@lux.LucentContent::text(txt))
      }
      let role_pick : String = @coreqc.Arbitrary::arbitrary(size, r.split())
      let role : @lux.LucentRole = if role_pick.length() % 2 == 0 {
        User
      } else {
        Assistant
      }
      conv.push(
        @lux.LucentConversationItem::message(
          @lux.LucentMessage::new(role, blocks),
        ),
      )
      i = i + 1
    }
    // reasoning：随机 None 或 enabled(预算)；capabilities：随机声明
    let rb : Bool = @coreqc.Arbitrary::arbitrary(size, r3)
    let rint : Int = @coreqc.Arbitrary::arbitrary(size, r4)
    let reasoning = if rb {
      Some(@lux.LucentReasoningConfig::enabled(Some(rint.abs() % 1000 + 1)))
    } else {
      None
    }
    let cb : Bool = @coreqc.Arbitrary::arbitrary(size, r4.split())
    let capabilities = if cb {
      Some(@lux.LucentCapabilities::default())
    } else {
      None
    }
    @lux.LucentRequest::new(
      pick_str(mstr.length(), models),
      None,
      conv,
      None,
      None,
      @lux.LucentOptions::default(),
      capabilities,
      reasoning,
      None,
      None,
    )
  })
}

///|
/// 冒烟：两个生成器可被 @qc 消费（trivial 恒真属性，验证不 panic、结构合法）
test "qc generators smoke - resp and extended req" {
  @qc.quick_check(@qc.forall(gen_text_resp(), fn(_) { true }))
  @qc.quick_check(@qc.forall(gen_extended_req(), fn(_) { true }))
}
