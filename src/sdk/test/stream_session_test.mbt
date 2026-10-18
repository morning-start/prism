///|
/// Prism::stream_session 拉式增量解码会话测试（首字实时性）
///
/// 验收基准：与整批 decode_sse 的最终事件序列一致；
/// 增量验收：首字事件在最短前缀 feed 后即可产出。

///|
/// 查找从 from 开始的第一个 "\n\n" 位置（返回第一个 \n 的下标），未找到返回 None
fn find_frame_end(s : String, from : Int32) -> Int32? {
  let mut i = from
  while i + 1 < s.length() {
    if s[i] == '\n' && s[i + 1] == '\n' {
      return Some(i)
    }
    i = i + 1
  }
  None
}

///|
/// PrismEvent 序列的稳定字符串表示（用于与整批 decode_sse 对比）
fn events_repr(events : Array[@sdk.PrismEvent]) -> Array[String] {
  let out : Array[String] = []
  for ev in events {
    let s = match ev {
      TextDelta(s) => "T:" + s
      ToolCall(tc) => "C:" + tc.id + ":" + tc.name + ":" + tc.arguments_json
      ToolResult(tr) =>
        "R:" + tr.tool_use_id + ":" + tr.content + ":" + tr.is_error.to_string()
      Thinking(t) => "K:" + t.text
      Finish(fr) =>
        "F:" +
        (match fr {
          Stop => "stop"
          Length => "length"
          ToolCalls => "tool_calls"
          ContentFilter => "content_filter"
          Error => "error"
        })
    }
    out.push(s)
  }
  out
}

///|
/// 真实形态 openai SSE fixture（role → 文本×2 → finish → usage → DONE）
fn stream_session_openai_fixture() -> String {
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"}}]}\n\n" +
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"}}]}\n\n" +
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n" +
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}\n\n" +
  "data: [DONE]\n\n"
}

///|
test "stream_session - openai events match batch decode_sse" {
  let p = @sdk.Prism::new().with_provider("openai")
  match p.stream_session() {
    Ok(sess) => {
      // 逐 chunk 喂入（按完整帧切，每帧独立 feed）
      let sse = stream_session_openai_fixture()
      let batch_events : Array[@sdk.PrismEvent] = []
      let mut total = 0
      let mut pos = 0
      while pos < sse.length() {
        match find_frame_end(sse, pos) {
          Some(end) => {
            let piece = sse[pos:end + 2].to_owned()
            match sess.feed(piece) {
              Ok(events) =>
                for ev in events {
                  batch_events.push(ev)
                  total = total + 1
                }
              Err(e) => fail("feed failed: " + e)
            }
            pos = end + 2
          }
          None => {
            // 剩余尾部（不完整帧）留给 finish() 冲刷
            match sess.feed(sse[pos:].to_owned()) {
              Ok(events) =>
                for ev in events {
                  batch_events.push(ev)
                  total = total + 1
                }
              Err(e) => fail("feed failed: " + e)
            }
            pos = sse.length()
          }
        }
      }
      match sess.finish() {
        Ok(events) =>
          for ev in events {
            batch_events.push(ev)
            total = total + 1
          }
        Err(e) => fail("finish failed: " + e)
      }
      assert_true(total > 0)
      // 与整批 decode_sse 一致（Finish 段内配对等价）
      match p.decode_sse(stream_session_openai_fixture()) {
        Ok(batch) => assert_eq(events_repr(batch_events), events_repr(batch))
        Err(e) => fail("decode_sse failed: " + e)
      }
    }
    Err(e) => fail("stream_session failed: " + e)
  }
}

///|
test "stream_session - first text delta arrives on first complete frame" {
  let p = @sdk.Prism::new().with_provider("openai")
  match p.stream_session() {
    Ok(sess) => {
      // 喂入首帧（role 帧）+ 第二帧（首个 content 帧）作为一个 chunk
      let first_frame = "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
        "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hi\"}}]}\n\n"
      match sess.feed(first_frame) {
        Ok(events) => {
          // 首次 feed 即拿到文本增量 —— 无需等待流结束（首字实时性）
          let mut has_text = false
          for ev in events {
            match ev {
              TextDelta(s) => if s == "Hi" { has_text = true }
              _ => ()
            }
          }
          assert_true(has_text)
        }
        Err(e) => fail("feed failed: " + e)
      }
      let _ = sess.finish()
    }
    Err(e) => fail("stream_session failed: " + e)
  }
}

///|
test "stream_session - 1 byte chunks byte-identical to batch decode" {
  let sse = stream_session_openai_fixture()
  let p = @sdk.Prism::new().with_provider("openai")
  match p.stream_session() {
    Ok(sess) => {
      let events : Array[@sdk.PrismEvent] = []
      let mut i = 0
      while i < sse.length() {
        let ch = sse[i:i + 1].to_owned()
        match sess.feed(ch) {
          Ok(batch) =>
            for ev in batch {
              events.push(ev)
            }
          Err(e) => fail("feed failed: " + e)
        }
        i = i + 1
      }
      match sess.finish() {
        Ok(batch) =>
          for ev in batch {
            events.push(ev)
          }
        Err(e) => fail("finish failed: " + e)
      }
      match p.decode_sse(sse) {
        Ok(batch) => assert_eq(events_repr(events), events_repr(batch))
        Err(e) => fail("decode_sse failed: " + e)
      }
    }
    Err(e) => fail("stream_session failed: " + e)
  }
}

///|
/// openai 流式 tool call 跨 chunk 参数累积
test "stream_session - openai tool call arguments accumulate across feeds" {
  let p = @sdk.Prism::new().with_provider("openai")
  match p.stream_session() {
    Ok(sess) => {
      let frames : Array[String] = [
        "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"\"}}]}}]}\n\n",
        "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"city\\\"\"}}]}}]}\n\n",
        "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\":\\\"SH\\\"}\"}}]}}]}\n\n",
        "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n",
        "data: [DONE]\n\n",
      ]
      let events : Array[@sdk.PrismEvent] = []
      for frame in frames {
        match sess.feed(frame) {
          Ok(batch) =>
            for ev in batch {
              events.push(ev)
            }
          Err(e) => fail("feed failed: " + e)
        }
      }
      match sess.finish() {
        Ok(batch) =>
          for ev in batch {
            events.push(ev)
          }
        Err(e) => fail("finish failed: " + e)
      }
      let mut tool_call : @sdk.PrismToolCall? = None
      for ev in events {
        match ev {
          ToolCall(tc) => tool_call = Some(tc)
          _ => ()
        }
      }
      match tool_call {
        Some(tc) => {
          assert_eq(tc.id, "call_1")
          assert_eq(tc.name, "get_weather")
          assert_eq(tc.arguments_json, "{\"city\":\"SH\"}")
        }
        None => fail("streaming tool call was dropped in session mode")
      }
    }
    Err(e) => fail("stream_session failed: " + e)
  }
}

///|
test "stream_session - unknown provider rejected at session creation" {
  let p = @sdk.Prism::new().with_provider("nonexistent")
  match p.stream_session() {
    Ok(_) => fail("expected error for unknown provider")
    Err(e) => assert_true(e.contains("unknown provider"))
  }
}

///|
test "stream_session - finish is idempotent" {
  let p = @sdk.Prism::new().with_provider("openai")
  match p.stream_session() {
    Ok(sess) => {
      let _ = sess.feed(
        "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"a\"}}]}\n\n",
      )
      match sess.finish() {
        Ok(_) => ()
        Err(e) => fail("first finish failed: " + e)
      }
      match sess.finish() {
        Ok(again) => assert_eq(again.length(), 0)
        Err(e) => fail("second finish failed: " + e)
      }
    }
    Err(e) => fail("stream_session failed: " + e)
  }
}
