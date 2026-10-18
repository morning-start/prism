///|
/// 会话载体的直接单元测试（`src/lux/stream_codec.mbt`）。
///
/// 会话载体是 P0/P1 修复的机制基础：provider 用工厂闭包捕获可变状态，
/// 经它把「同一份实现」暴露给整批与增量两条路径。本文件直测其契约：
///   - encode 复用状态、finish 冲刷、set_ctx 注入
///   - decode 复用状态、finish 产出收尾事件
///   - 两个会话对象互不共享状态（工厂每次调用产生独立状态）

///|
/// 记录调用次序的探针状态：验证方法与状态确实被会话持有
priv struct CodecProbe {
  mut encodes : Int32
  mut finishes : Int32
  mut decodes : Int32
  mut ctx_calls : Int32
  mut last_ctx_id : String
  mut counter : Int32
}

///|
fn CodecProbe::new() -> CodecProbe {
  {
    encodes: 0,
    finishes: 0,
    decodes: 0,
    ctx_calls: 0,
    last_ctx_id: "",
    counter: 0,
  }
}

///|
test "lux stream encoder - encode/finish/set_ctx reach the captured state" {
  let p = CodecProbe::new()
  let enc = @lux.LucentStreamEncoder::new(
    fn(events) -> Result[@lux.ConversionResult[String], String] {
      p.encodes = p.encodes + 1
      p.counter = p.counter + events.length()
      Ok(
        @lux.ConversionResult::new(
          "n=" + p.counter.to_string() + ";ev=" + events.length().to_string(),
        ),
      )
    },
    fn() -> Result[@lux.ConversionResult[String], String] {
      p.finishes = p.finishes + 1
      Ok(@lux.ConversionResult::new("finish"))
    },
    fn(ctx) {
      p.ctx_calls = p.ctx_calls + 1
      match ctx {
        Some(meta) =>
          p.last_ctx_id = match meta.id {
            Some(id) => id
            None => "<nil>"
          }
        None => p.last_ctx_id = "<none>"
      }
    },
  )
  // encode 复用同一状态：两次调用的累积值递增
  match enc.encode([Done]) {
    Ok(r) => assert_eq(r.value(), "n=1;ev=1")
    Err(e) => fail(e)
  }
  match enc.encode([Done, Done]) {
    Ok(r) => assert_eq(r.value(), "n=3;ev=2")
    Err(e) => fail(e)
  }
  // set_ctx 注入会话元信息
  let meta : @lux.LucentConversationMeta = @lux.LucentConversationMeta::new(
    Some("resp_abc"),
    Some("m"),
    None,
  )
  enc.set_ctx(Some(meta))
  assert_eq(p.ctx_calls, 1)
  assert_eq(p.last_ctx_id, "resp_abc")
  enc.set_ctx(None)
  assert_eq(p.last_ctx_id, "<none>")
  // finish 冲刷编码器自身状态
  match enc.finish() {
    Ok(r) => assert_eq(r.value(), "finish")
    Err(e) => fail(e)
  }
  assert_eq(p.finishes, 1)
}

///|
test "lux stream encoder - two sessions from same factory do not share state" {
  let make = fn() -> @lux.LucentStreamEncoder {
    let p = CodecProbe::new()
    @lux.LucentStreamEncoder::new(
      fn(events) -> Result[@lux.ConversionResult[String], String] {
        p.counter = p.counter + events.length()
        Ok(@lux.ConversionResult::new(p.counter.to_string()))
      },
      fn() -> Result[@lux.ConversionResult[String], String] {
        Ok(@lux.ConversionResult::new("f"))
      },
      fn(_ctx) { () },
    )
  }
  let a = make()
  let b = make()
  match a.encode([Done]) {
    Ok(r) => assert_eq(r.value(), "1")
    Err(e) => fail(e)
  }
  match a.encode([Done]) {
    Ok(r) => assert_eq(r.value(), "2")
    Err(e) => fail(e)
  }
  // b 是独立会话，计数器从 0 起
  match b.encode([Done]) {
    Ok(r) => assert_eq(r.value(), "1")
    Err(e) => fail(e)
  }
}

///|
test "lux stream decoder - decode reuses state and finish yields closing events" {
  let p = CodecProbe::new()
  let dec = @lux.LucentStreamDecoder::new(
    fn(
      _s,
    ) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
      p.decodes = p.decodes + 1
      Ok(@lux.ConversionResult::new([BlockStart(0, Text)]))
    },
    fn() -> Array[@lux.LucentStreamEvent] {
      p.finishes = p.finishes + 1
      [BlockEnd(0), Done]
    },
  )
  match dec.decode("frame") {
    Ok(cr) => assert_eq(cr.value().length(), 1)
    Err(e) => fail(e)
  }
  match dec.decode("frame2") {
    Ok(cr) => assert_eq(cr.value().length(), 1)
    Err(e) => fail(e)
  }
  assert_eq(p.decodes, 2)
  let closing = dec.finish()
  assert_eq(closing.length(), 2)
  assert_eq(p.finishes, 1)
}
