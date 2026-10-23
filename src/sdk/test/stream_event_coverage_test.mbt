///|
/// 流式事件「有生产者但无消费者 / 有消费者但无生产者」的逐格契约。
///
/// ## 背景（矩阵审计）
///
/// 前几轮审计逐格检查了内容、文本、工具、流式帧序，但从未把
/// **IR 流事件 × provider 的生产者/消费者矩阵**整体铺开。铺开后三类缺陷
/// 暴露出来（本文件锁定全部三类）：
///
/// 1. **`BlockDiscard` 死事件**——IR 定义并序列化了它，但四个 provider 的
///    `stream_decode` 零生产。治理文档 CR-003 已记录（选 B：保留+标记）。
///    本轮不重复治理，只锁定「无生产者」这个事实不被悄悄改变。
/// 2. **`ItemEnd` / `Annotations` 无生产者**——responses 是唯一产者
///    （`output_item.done` / `output_text.annotation.added` 官方帧），
///    此前两帧都被 `_ => ()` 完全丢弃。本文件锁定 decode 产出。
/// 3. **`Error` 的生产者缺口**——openai 源的官方错误帧
///    `data: {"error":{...}}` 不包 chunk 外壳，`stream_decode` 整帧丢弃，
///    流式错误链路断在解码侧（encode 侧与响应侧一直有 error 映射）。
///
/// 编码侧的对应契约（openai / messages / responses / gemini 无流式注解载体
/// → 显式 Degraded）在 stream_encode 各文件内，本文件锁定其诊断可观测。

///|
/// openai 流式错误帧必须解出 Error 事件。
///
/// 官方错误帧不包 chunk 外壳：`data: {"error":{"type":"rate_limit_error",
/// "message":"...","code":"429"}}`。此前 openai 源不识别该帧 → 整帧静默丢弃。
test "stream events - openai decodes the official error frame" {
  let sse = "data: {\"error\":{\"type\":\"rate_limit_error\",\"message\":\"slow down\",\"code\":\"429\"}}\n\n"
  match @openai.openai_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      assert_eq(cr.value().length(), 1)
      match cr.value()[0] {
        Error(e) => {
          assert_eq(e.kind, RateLimit)
          assert_eq(e.message, "slow down")
          assert_eq(e.provider_code, Some("429"))
        }
        _ => fail("expected Error event")
      }
    }
  }
}

///|
/// openai 错误帧缺失 type/code 时不得崩：退化为 Unknown kind + 兜底 message。
test "stream events - openai error frame degrades when type/code missing" {
  let sse = "data: {\"error\":{\"message\":\"boom\"}}\n\n"
  match @openai.openai_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match cr.value()[0] {
        Error(e) => {
          assert_eq(e.kind, Native(""))
          assert_eq(e.message, "boom")
        }
        _ => fail("expected Error event")
      }
  }
}

///|
/// 官方 error.type 的全集映射：openai 官方 `error.type` 常量必须落到达 IR
/// 语义 kind，而不是 Native 字符串透传。
test "stream events - openai error type maps to semantic kind" {
  let cases : Array[(String, @lux.LucentErrorKind)] = [
    ("rate_limit_error", RateLimit),
    ("invalid_request_error", InvalidRequest),
    ("authentication_error", Authentication),
    ("server_error", ServerError),
  ]
  for c in cases {
    let (etype, kind) = c
    let sse = "data: {\"error\":{\"type\":\"" +
      etype +
      "\",\"message\":\"m\"}}\n\n"
    match @openai.openai_sse_to_events(sse) {
      Err(e) => fail("decode failed: " + e)
      Ok(cr) =>
        match cr.value()[0] {
          Error(e) => assert_eq(e.kind, kind)
          _ => fail("expected Error event")
        }
    }
  }
}

///|
/// openai 错误帧的两种兜底形态：
/// 1) `error` 是对象但缺 `message` → message 回落到 type；
/// 2) `error` 是字符串（非官方但上游常见的扁平形态）→ simple 构造。
/// 两者都必须产出 Error 事件而非静默丢弃。
test "stream events - openai error frame fallback shapes" {
  let obj_no_msg = "data: {\"error\":{\"type\":\"server_error\"}}\n\n"
  match @openai.openai_sse_to_events(obj_no_msg) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match cr.value()[0] {
        Error(e) => {
          assert_eq(e.kind, ServerError)
          assert_eq(e.message, "server_error")
        }
        _ => fail("expected Error event")
      }
  }
  let str_form = "data: {\"error\":\"boom\"}\n\n"
  match @openai.openai_sse_to_events(str_form) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match cr.value()[0] {
        Error(e) => assert_eq(e.message, "boom")
        _ => fail("expected Error event")
      }
  }
}

///|
/// 普通内容帧不得被误判为错误帧（error 键缺失时不产出 Error 事件）。
test "stream events - openai content frame is not an error frame" {
  let sse = "data: {\"id\":\"c1\",\"model\":\"m\",\"created\":1,\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"hi\"}}]}\n\ndata: [DONE]\n\n"
  match @openai.openai_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      for ev in cr.value() {
        assert_false(ev is Error(_))
      }
  }
}

///|
/// responses 官方 `output_item.done` 帧必须解出 ItemEnd。
///
/// 该帧携带 item 的终态（status / 完整 content），此前被 `_ => ()` 丢弃：
/// item 级边界与终态信息在流式路径整体消失。
test "stream events - responses decodes output_item.done to ItemEnd" {
  let sse = "event: response.output_item.done\n" +
    "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"id\":\"msg_0\",\"type\":\"message\",\"status\":\"completed\",\"role\":\"assistant\",\"content\":[]}}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      assert_eq(cr.value().length(), 1)
      match cr.value()[0] {
        ItemEnd(0) => ()
        _ => fail("expected ItemEnd(0)")
      }
    }
  }
}

///|
/// responses 官方 `output_text.annotation.added` 帧必须解出 Annotations。
///
/// 注解是引用来源（citation）。此前整帧丢弃 → 流式路径的 citation 全失。
/// 官方 Annotation 是 four-way oneOf：url_citation / file_citation /
/// container_file_citation / file_path（schemas/endpoints/openai-openapi.yaml）。
test "stream events - responses decodes annotation.added to Annotations" {
  let sse = "event: response.output_text.annotation.added\n" +
    "data: {\"type\":\"response.output_text.annotation.added\",\"output_index\":0,\"content_index\":0,\"annotation_index\":0,\"annotation\":{\"type\":\"url_citation\",\"url\":\"https://x.com\",\"title\":\"X\",\"start_index\":0,\"end_index\":5}}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      assert_eq(cr.value().length(), 1)
      match cr.value()[0] {
        Annotations(0, anns) => {
          assert_eq(anns.length(), 1)
          let a = anns[0]
          assert_eq(a.kind, Url)
          assert_eq(a.text, Some("X"))
          assert_eq(a.reference, Some("https://x.com"))
          assert_eq(a.start, Some(0))
          assert_eq(a.end, Some(5))
        }
        _ => fail("expected Annotations(0, _)")
      }
    }
  }
}

///|
/// file_citation 映射到 IR 原生 FileCitation kind，不丢引用目标。
test "stream events - responses decodes file_citation annotation" {
  let sse = "event: response.output_text.annotation.added\n" +
    "data: {\"type\":\"response.output_text.annotation.added\",\"output_index\":0,\"content_index\":0,\"annotation\":{\"type\":\"file_citation\",\"file_id\":\"file_1\",\"index\":3,\"filename\":\"a.txt\"}}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) =>
      match cr.value()[0] {
        Annotations(0, anns) => {
          let a = anns[0]
          assert_eq(a.kind, FileCitation)
          assert_eq(a.text, Some("a.txt"))
          assert_eq(a.reference, Some("file_1"))
        }
        _ => fail("expected Annotations(0, _)")
      }
  }
}

///|
/// 无 IR 原生 kind 的注解变体（container_file_citation / file_path）退化为
/// Native(type) 保留类型标签，而不是丢弃整条注解。
test "stream events - responses decodes native annotation variants" {
  let cases : Array[String] = ["container_file_citation", "file_path"]
  for at in cases {
    let sse = "event: response.output_text.annotation.added\n" +
      "data: {\"type\":\"response.output_text.annotation.added\",\"output_index\":0,\"content_index\":0,\"annotation\":{\"type\":\"" +
      at +
      "\",\"filename\":\"f.txt\"}}\n\n"
    match @responses.responses_sse_to_events(sse) {
      Err(e) => fail("decode failed: " + e)
      Ok(cr) =>
        match cr.value()[0] {
          Annotations(0, anns) => assert_eq(anns[0].kind, Native(at))
          _ => fail("expected Annotations(0, _)")
        }
    }
  }
}

///|
/// annotation 为 null（官方 anyOf 含 null）时不产出事件、不崩。
test "stream events - responses null annotation yields no event" {
  let sse = "event: response.output_text.annotation.added\n" +
    "data: {\"type\":\"response.output_text.annotation.added\",\"output_index\":0,\"content_index\":0,\"annotation\":null}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => assert_eq(cr.value().length(), 0)
  }
}

///|
/// 完整 responses 流：output_item.done 与 annotation.added 在真实帧序中
/// 各就各位（与 delta/done 帧共存时不互相吞掉）。
test "stream events - responses full stream keeps item end and annotations" {
  let sse = "event: response.created\n" +
    "data: {\"type\":\"response.created\",\"response\":{\"id\":\"r_1\",\"model\":\"gpt-5\"}}\n\n" +
    "event: response.output_item.added\n" +
    "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"msg_0\",\"role\":\"assistant\"}}\n\n" +
    "event: response.content_part.added\n" +
    "data: {\"type\":\"response.content_part.added\",\"output_index\":0,\"content_index\":0,\"part\":{\"type\":\"output_text\",\"text\":\"\"}}\n\n" +
    "event: response.output_text.delta\n" +
    "data: {\"type\":\"response.output_text.delta\",\"output_index\":0,\"content_index\":0,\"delta\":\"Hello\"}\n\n" +
    "event: response.output_text.done\n" +
    "data: {\"type\":\"response.output_text.done\",\"output_index\":0,\"content_index\":0}\n\n" +
    "event: response.output_item.done\n" +
    "data: {\"type\":\"response.output_item.done\",\"output_index\":0,\"item\":{\"id\":\"msg_0\",\"type\":\"message\",\"status\":\"completed\",\"role\":\"assistant\",\"content\":[{\"type\":\"output_text\",\"text\":\"Hello\"}]}}\n\n" +
    "event: response.output_text.annotation.added\n" +
    "data: {\"type\":\"response.output_text.annotation.added\",\"output_index\":0,\"content_index\":0,\"annotation_index\":0,\"annotation\":{\"type\":\"url_citation\",\"url\":\"https://x.com\",\"title\":\"X\",\"start_index\":0,\"end_index\":5}}\n\n" +
    "event: response.completed\n" +
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
  match @responses.responses_sse_to_events(sse) {
    Err(e) => fail("decode failed: " + e)
    Ok(cr) => {
      let evs = cr.value()
      // created / item.added / block.start / delta / block.end /
      // item.done / annotations / finish / done
      assert_eq(evs.length(), 9)
      assert_true(evs[5] is ItemEnd(_))
      assert_true(evs[6] is Annotations(_, _))
    }
  }
}

///|
/// IR → openai-chat 流编码：Annotations 无载体，必须显式 Degraded
/// （与请求侧 request_encode.mbt 的 content.annotations 同一口径）。
test "stream events - openai encode degrades annotations explicitly" {
  let events : Array[@lux.LucentStreamEvent] = [
    Annotations(0, [@lux.LucentAnnotation::new(Url, None, None, None, None)]),
    Done,
  ]
  match @openai.lux_events_to_openai_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      let mut found = false
      for d in cr.diagnostics() {
        if d.field == "stream.annotations" {
          assert_eq(d.status(), Degraded)
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// 空注解数组不制造噪音诊断（上游没给数据就不该报降级）。
test "stream events - openai encode stays silent for empty annotations" {
  let events : Array[@lux.LucentStreamEvent] = [Annotations(0, []), Done]
  match @openai.lux_events_to_openai_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) =>
      for d in cr.diagnostics() {
        assert_false(d.field == "stream.annotations")
      }
  }
}

///|
/// IR → messages 流编码：Annotations 同样无载体 → 显式 Degraded。
test "stream events - messages encode degrades annotations explicitly" {
  let events : Array[@lux.LucentStreamEvent] = [
    Annotations(0, [@lux.LucentAnnotation::new(Url, None, None, None, None)]),
    Done,
  ]
  match @messages.lux_events_to_messages_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      let mut found = false
      for d in cr.diagnostics() {
        if d.field == "stream.annotations" {
          assert_eq(d.status(), Degraded)
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// IR → gemini 流编码：Annotations 无载体 → 显式 Degraded。
test "stream events - gemini encode degrades annotations explicitly" {
  let events : Array[@lux.LucentStreamEvent] = [
    Annotations(0, [@lux.LucentAnnotation::new(Url, None, None, None, None)]),
    Done,
  ]
  match @gemini.lux_events_to_gemini_sse(events) {
    Err(e) => fail("encode failed: " + e)
    Ok(cr) => {
      let mut found = false
      for d in cr.diagnostics() {
        if d.field == "stream.annotations" {
          assert_eq(d.status(), Degraded)
          found = true
        }
      }
      assert_true(found)
    }
  }
}

///|
/// BlockDiscard 死事件事实锁定：四个 provider 的流解码器都不生产它。
///
/// CR-003 决策 B（保留+标记，不移除）后，「无生产者」必须保持为事实，
/// 否则 fidelity-matrix 的 `❌ 未实现` 标注失真。此处用「正常流不产出
/// BlockDiscard」锁定该事实。
test "stream events - no provider decoder emits BlockDiscard" {
  let openai_sse = "data: {\"id\":\"c1\",\"model\":\"m\",\"created\":1,\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\",\"content\":\"hi\"},\"finish_reason\":\"stop\"}]}\n\ndata: [DONE]\n\n"
  match @openai.openai_sse_to_events(openai_sse) {
    Err(e) => fail("openai decode failed: " + e)
    Ok(cr) =>
      for ev in cr.value() {
        assert_false(ev is BlockDiscard(_))
      }
  }
  let resp_sse = "event: response.output_item.added\n" +
    "data: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"message\",\"id\":\"m0\",\"role\":\"assistant\"}}\n\n" +
    "event: response.completed\n" +
    "data: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n"
  match @responses.responses_sse_to_events(resp_sse) {
    Err(e) => fail("responses decode failed: " + e)
    Ok(cr) =>
      for ev in cr.value() {
        assert_false(ev is BlockDiscard(_))
      }
  }
  let msg_sse = "event: message_start\n" +
    "data: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"model\":\"claude\"}}\n\n" +
    "event: content_block_start\n" +
    "data: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"text\",\"text\":\"\"}}\n\n" +
    "event: content_block_stop\n" +
    "data: {\"type\":\"content_block_stop\",\"index\":0}\n\n" +
    "event: message_stop\n" +
    "data: {\"type\":\"message_stop\"}\n\n"
  match @messages.messages_sse_to_events(msg_sse) {
    Err(e) => fail("messages decode failed: " + e)
    Ok(cr) =>
      for ev in cr.value() {
        assert_false(ev is BlockDiscard(_))
      }
  }
  let gem_sse = "data: {\"responseId\":\"g1\",\"modelVersion\":\"gemini-2\",\"candidates\":[{\"index\":0,\"content\":{\"role\":\"model\",\"parts\":[{\"text\":\"hi\"}]},\"finishReason\":\"STOP\"}]}\n\n"
  match @gemini.gemini_sse_to_events(gem_sse) {
    Err(e) => fail("gemini decode failed: " + e)
    Ok(cr) =>
      for ev in cr.value() {
        assert_false(ev is BlockDiscard(_))
      }
  }
}
