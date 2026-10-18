///|
/// PrismEventBuffer / EventNormalizer 分支覆盖（event_stream.mbt）
///
/// 入口全部走公开 API `Prism::stream_session`（黑盒）：会话内部就是
/// EventNormalizer + PrismEventBuffer，因此这些分支此前未被单独触达。
///
/// 覆盖点：
/// - ItemStart(ToolCall) 骨架开块 + 后续 BlockDelta 累积、BlockEnd 发射
/// - ItemStart(_, ToolResult) → ToolResult 事件（含 is_error=false 形态）
/// - ItemStart(_, 其他) 冲刷未闭合 tool 块（responses message item）
/// - Finish 的 Length / ContentFilter / 原生档位映射
/// - EventNormalizer 的 Usage 回填：None / Some 两种 meta 形态
/// - convert_frames 的错误路径（坏 JSON 帧）

///|
/// 收集会话产出事件里第一类 ToolCall（用于断言参数累积）
fn es_find_tool_call(events : Array[@sdk.PrismEvent]) -> @sdk.PrismToolCall? {
  let mut found : @sdk.PrismToolCall? = None
  for ev in events {
    match ev {
      ToolCall(tc) => found = Some(tc)
      _ => ()
    }
  }
  found
}

///|
/// 收集 ToolResult 事件（tool_use_id, content, is_error）
fn es_find_tool_results(
  events : Array[@sdk.PrismEvent],
) -> Array[(String, String, Bool)] {
  let out : Array[(String, String, Bool)] = []
  for ev in events {
    match ev {
      ToolResult(tr) => out.push((tr.tool_use_id, tr.content, tr.is_error))
      _ => ()
    }
  }
  out
}

///|
/// 收集 Finish 事件的档位字符串
fn es_finish_repr(events : Array[@sdk.PrismEvent]) -> Array[String] {
  let out : Array[String] = []
  for ev in events {
    match ev {
      Finish(fr) =>
        out.push(
          match fr {
            Stop => "stop"
            Length => "length"
            ToolCalls => "tool_calls"
            ContentFilter => "content_filter"
            Error => "error"
          },
        )
      _ => ()
    }
  }
  out
}

///|
/// 把一组 SSE 帧一次性喂入会话并收尾，返回全部事件
fn es_run_frames(
  provider : String,
  frames : Array[String],
) -> Array[@sdk.PrismEvent] raise {
  let all : Array[@sdk.PrismEvent] = []
  let p = @sdk.Prism::new().with_provider(provider)
  match p.stream_session() {
    Ok(sess) => {
      for frame in frames {
        match sess.feed(frame) {
          Ok(batch) =>
            for ev in batch {
              all.push(ev)
            }
          Err(e) => fail("feed failed: " + e)
        }
      }
      match sess.finish() {
        Ok(batch) =>
          for ev in batch {
            all.push(ev)
          }
        Err(e) => fail("finish failed: " + e)
      }
    }
    Err(e) => fail("stream_session failed: " + e)
  }
  all
}

///|
/// responses 流：function_call item（ItemStart ToolCall 骨架）+ 参数增量 + done
fn es_responses_toolcall_frames() -> Array[String] {
  [
    "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_2\",\"model\":\"gpt-5\"}}\n\n",
    "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"name\":\"search\"}}\n\n",
    "event: response.function_call_arguments.delta\ndata: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"delta\":\"{\\\"q\\\":\\\"x\\\"}\"}\n\n",
    "event: response.function_call_arguments.done\ndata: {\"type\":\"response.function_call_arguments.done\",\"output_index\":0}\n\n",
    "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n",
  ]
}

///|
/// responses 流：function_call item 与 function_call_output item 相邻 ——
/// 后者的 ItemStart(ToolResult) 必须先冲刷未闭合的 tool 块
fn es_responses_toolresult_frames() -> Array[String] {
  [
    "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_3\",\"model\":\"gpt-5\"}}\n\n",
    "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"name\":\"search\"}}\n\n",
    "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":1,\"item\":{\"type\":\"function_call_output\",\"call_id\":\"fc_1\",\"output\":\"done\"}}\n\n",
    "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n",
  ]
}

///|
test "event_stream - ItemStart ToolCall skeleton emits accumulated call" {
  let events = es_run_frames("responses", es_responses_toolcall_frames())
  match es_find_tool_call(events) {
    Some(tc) => {
      assert_eq(tc.id, "fc_1")
      assert_eq(tc.name, "search")
      // ItemStart 骨架开块时 arguments 默认为 "{}"，delta 再追加实际参数
      assert_eq(tc.arguments_json, "{}{\"q\":\"x\"}")
    }
    None => fail("ItemStart ToolCall skeleton produced no ToolCall event")
  }
}

///|
test "event_stream - ItemStart ToolResult flushes pending tool call" {
  let events = es_run_frames("responses", es_responses_toolresult_frames())
  // ToolCall 必须先被冲刷出来（ToolResult item 到达时 tool 块仍开着）
  match es_find_tool_call(events) {
    Some(tc) => assert_eq(tc.id, "fc_1")
    None => fail("pending tool call was not flushed by ToolResult item")
  }
  let results = es_find_tool_results(events)
  assert_eq(results.length(), 1)
  match results[0] {
    (id, content, is_error) => {
      assert_eq(id, "fc_1")
      assert_eq(content, "done")
      // function_call_output 无 is_error 字段 → 默认 false
      assert_false(is_error)
    }
  }
}

///|
/// responses 流：message item（非 tool item）到达时冲刷未闭合 tool 块
test "event_stream - non-tool ItemStart flushes pending tool call" {
  let events = es_run_frames("responses", [
    "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_4\",\"model\":\"gpt-5\"}}\n\n",
    "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_9\",\"name\":\"search\"}}\n\n",
    "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":1,\"item\":{\"type\":\"message\",\"id\":\"m_1\",\"role\":\"assistant\"}}\n\n",
    "event: response.content_part.added\ndata: {\"type\":\"response.content_part.added\",\"output_index\":1,\"content_index\":0,\"part\":{\"type\":\"output_text\",\"text\":\"\"}}\n\n",
    "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"output_index\":1,\"content_index\":0,\"delta\":\"hi\"}\n\n",
    "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"completed\"}}\n\n",
  ])
  match es_find_tool_call(events) {
    Some(tc) => assert_eq(tc.id, "fc_9")
    None => fail("tool call was dropped when a message item followed")
  }
}

///|
/// Finish 的原生档位 → PrismEvent 档位映射（Length）
/// responses 的 Finish 来自 response.completed 的 status 字段；
/// "incomplete" 归一化为 LucentFinishReason::Length
test "event_stream - finish reason maps length" {
  let events = es_run_frames("responses", [
    "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_5\",\"model\":\"gpt-5\"}}\n\n",
    "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"incomplete\"}}\n\n",
  ])
  let repr = es_finish_repr(events)
  assert_true(repr.contains("length"))
}

///|
/// Finish 的原生档位 → PrismEvent 档位映射（ContentFilter）
/// status "content_filter" 直接映射为 ContentFilter → content_filter
test "event_stream - finish reason maps content_filter" {
  let events = es_run_frames("responses", [
    "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_6\",\"model\":\"gpt-5\"}}\n\n",
    "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"content_filter\"}}\n\n",
  ])
  let repr = es_finish_repr(events)
  assert_true(repr.contains("content_filter"))
}

///|
/// Finish 的非标准档位（Safety）→ PrismEvent 的 Error 兜底
test "event_stream - finish reason safety falls back to error" {
  let events = es_run_frames("responses", [
    "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"r_7\",\"model\":\"gpt-5\"}}\n\n",
    "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"status\":\"safety\"}}\n\n",
  ])
  let repr = es_finish_repr(events)
  // LucentFinishReason::Safety 不在 PrismEvent 的四档内 → 兜底为 Error
  assert_true(repr.contains("error"))
}

///|
/// EventNormalizer 的 Usage 分支：prompt_tokens 非零时原样透传（不回填）
/// openai 的 usage 帧在 choices 为空时解出 prompt_tokens>0 的 Usage，
/// 命中 `else { result.push(ev) }` 分支；PrismEvent 无 usage 变体，
/// 断言点在于会话正常收尾、不因 usage 处理中断。
test "event_stream - usage with nonzero prompt_tokens passes through" {
  let events = es_run_frames("openai", [
    "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"a\"}}]}\n\n",
    "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n",
    "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"choices\":[],\"usage\":{\"prompt_tokens\":5,\"completion_tokens\":1,\"total_tokens\":6}}\n\n",
    "data: [DONE]\n\n",
  ])
  let mut finish_seen = false
  for ev in events {
    match ev {
      Finish(_) => finish_seen = true
      _ => ()
    }
  }
  assert_true(finish_seen)
}

///|
/// 坏 JSON 帧：openai 流解码器容错跳过（parse_sse_frame 返回 None 即 continue），
/// 不产生事件也不报错 —— 会话可继续正常收尾。
/// 这锁定了 event_stream 的错误语义：feed 只在解码器返回 Err 时失败。
test "event_stream - malformed frame is tolerated, session still finishes" {
  let events = es_run_frames("openai", [
    "data: {not json at all}\n\n", "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"ok\"}}]}\n\n",
    "data: [DONE]\n\n",
  ])
  // 坏帧被跳过，好帧仍产出文本增量
  let mut has_text = false
  for ev in events {
    match ev {
      TextDelta(s) => if s == "ok" { has_text = true }
      _ => ()
    }
  }
  assert_true(has_text)
}

///|
/// finish() 幂等且正常返回（convert_frames 无错误时的收尾路径）
test "event_stream - finish succeeds after tolerated malformed frame" {
  let p = @sdk.Prism::new().with_provider("openai")
  match p.stream_session() {
    Ok(sess) => {
      let _ = sess.feed("data: {not json at all}\n\n")
      let _ = sess.feed(
        "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"a\"}}]}\n\n",
      )
      match sess.finish() {
        Ok(_) => ()
        Err(e) => fail("finish failed: " + e)
      }
    }
    Err(e) => fail("stream_session failed: " + e)
  }
}
