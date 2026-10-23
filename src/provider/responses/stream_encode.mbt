///|
/// 6. lux_events_to_responses_sse — 流编码
pub fn lux_events_to_responses_sse(
  events : Array[@lux.LucentStreamEvent],
) -> Result[@lux.ConversionResult[String], String] {
  lux_events_to_responses_sse_with_ctx(events, None)
}

///|
/// 带流上下文的 responses 流编码（T5 增量转换入口）
///
/// ctx 提供跨帧会话元信息：逐帧转换时后续帧不含 ConversationStart，
/// 用 ctx 的 id 保证 response.completed 等收尾帧的 id 与首帧一致；
/// 帧内 ConversationStart 优先覆盖 ctx。
/// ctx=None 时与 lux_events_to_responses_sse 行为逐字节一致。

///|
/// Responses 流编码的跨帧状态（P0 修复）。
///
/// 块级簿记（block → output_index/content_index/item_id 映射、跨帧累积的
/// 工具参数、计数器）必须**跨帧存活**：BlockStart 在首帧、BlockEnd 可能在
/// 数帧之后，done 事件要向映射里反查完整参数。此前这些状态是编码函数的
/// 局部变量，逐帧调用（StreamConverter 每帧调一次）时每帧重建 → BlockEnd
/// 查不到工具块 → `function_call_arguments.done` 整体消失、item_id 退化为
/// 占位符。整批调用因整条事件数组一次传入而恰好保留 → 两路径不一致。
/// 会话化后两条路径共享同一份状态机。
pub struct ResponsesStreamState {
  block_output : Map[Int32, Int32]
  block_content : Map[Int32, Int32]
  block_is_tool : Map[Int32, Bool]
  block_is_thinking : Map[Int32, Bool]
  block_tool_args : Map[Int32, StringBuilder]
  block_tool_name : Map[Int32, String]
  block_item_id : Map[Int32, String]
  mut next_output_index : Int32
  mut message_output_index : Int32
  mut cur_content_index : Int32
  mut item_counter : Int32
  mut resp_id : String
  /// 跨帧会话元信息（逐帧转换时后续帧不含 ConversationStart）
  mut ctx : @lux.LucentConversationMeta?
}

///|
pub fn ResponsesStreamState::new() -> ResponsesStreamState {
  {
    block_output: Map([]),
    block_content: Map([]),
    block_is_tool: Map([]),
    block_is_thinking: Map([]),
    block_tool_args: Map([]),
    block_tool_name: Map([]),
    block_item_id: Map([]),
    next_output_index: 0,
    message_output_index: -1,
    cur_content_index: 0,
    item_counter: 0,
    resp_id: "resp_0",
    ctx: None,
  }
}

///|
/// 整批入口：每条事件数组用**全新**状态编码（行为与修复前逐字节一致）
pub fn lux_events_to_responses_sse_with_ctx(
  events : Array[@lux.LucentStreamEvent],
  ctx : @lux.LucentConversationMeta?,
) -> Result[@lux.ConversionResult[String], String] {
  let st = ResponsesStreamState::new()
  st.ctx = ctx
  responses_encode_frames(events, st)
}

///|
/// 编码一帧事件（复用会话内跨帧状态）
fn responses_encode_frames(
  events : Array[@lux.LucentStreamEvent],
  st : ResponsesStreamState,
) -> Result[@lux.ConversionResult[String], String] {
  let lines : Array[String] = []
  // Responses 流状态（标准 §10.2）：output_index 与 content_index 是独立空间。
  // - output_index：output item 索引（ItemStart 提供，或自动分配）
  // - content_index：单个 message item 内部 content part 索引，从 0 起独立计数
  // 维护 block index → (output_index, content_index, is_tool) 映射供 delta/end 反查。
  // Map 是引用类型，别名即共享同一份状态；标量在函数末尾写回。
  let ctx = st.ctx
  let block_output = st.block_output
  let block_content = st.block_content
  let block_is_tool = st.block_is_tool
  let block_is_thinking = st.block_is_thinking
  // 工具块累积：BlockEnd 的 function_call_arguments.done / output_item.done
  // 需要完整 arguments 与函数名（官方 done 帧携带完整载荷，AI SDK 由此收尾
  // function_call item；此前恒发空串且从不发 output_item.done）。
  let block_tool_args = st.block_tool_args
  let block_tool_name = st.block_tool_name
  let mut next_output_index = st.next_output_index
  let mut message_output_index : Int32 = st.message_output_index
  let mut cur_content_index = st.cur_content_index
  // item_id 生成：AI SDK 要求 output_item 必须有 id、delta 事件必须有 item_id。
  // 用固定前缀 + 递增计数器保证流内唯一（不依赖系统时间/随机数）。
  let mut item_counter = st.item_counter
  let block_item_id = st.block_item_id // block idx → item id
  let mut resp_id = st.resp_id // response.created 生成的 id，Finish 时复用
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // ctx 预置（逐帧转换跨帧复用 id）：帧内 ConversationStart 会覆盖
  match ctx {
    Some(meta) =>
      match meta.id {
        Some(id) => resp_id = id
        None => ()
      }
    None => ()
  }
  let mut i = 0
  while i < events.length() {
    // Track output_index for item_start events
    match events[i] {
      ConversationStart(meta) => {
        // AI SDK 要求 response.created 必须含 id/created_at/model。
        // meta 缺失时用 fallback 值（resp_<计数>、0、unknown）保证校验通过。
        let rid = match meta.id {
          Some(id) => id
          None => {
            let r = "resp_" + item_counter.to_string()
            item_counter = item_counter + 1
            r
          }
        }
        let created_at = meta.created_at.unwrap_or(0)
        let model = meta.model.unwrap_or("unknown")
        resp_id = rid
        let mut fields = "\"id\":\"" + @internal.json_escape(rid) + "\""
        fields = fields + ",\"created_at\":" + created_at.to_string()
        fields = fields + ",\"model\":\"" + @internal.json_escape(model) + "\""
        // 元数据扩展载体按归属门控合并：此前是**无门控直接展开** —— 源协议
        // 的专属字段（如 openai 的 system_fingerprint）会被原样写进
        // response.created，目标收到不认识的字段可能 400。现只写 responses
        // 原生键（moderation）与未知键，外来键剔除并诊断。
        fields = fields +
          @meta.payload_fragments(
            meta.extra,
            "responses",
            [
              "id", "object", "created_at", "status", "model", "output", "usage",
              "incomplete_details",
            ],
            diagnostics,
          )
        lines.push(
          "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{" +
          fields +
          "}}",
        )
      }
      ItemStart(idx, item) => {
        // ItemStart 提供 output_index；message item 重置 content 计数
        next_output_index = idx + 1
        cur_content_index = 0
        // AI SDK 要求 item 必须有 id（message/reasoning 等均校验）
        let item_id = "msg_" + item_counter.to_string()
        item_counter = item_counter + 1
        let item_json = match item {
          Message(m) => {
            let role_str = m.role.to_string()
            let cparts : Array[String] = []
            let mut k = 0
            while k < m.content.length() {
              match m.content[k] {
                Text(t, _) =>
                  cparts.push(
                    "{\"type\":\"input_text\",\"text\":\"" +
                    @internal.json_escape(t) +
                    "\"}",
                  )
                _ => ()
              }
              k = k + 1
            }
            "{\"id\":\"" +
            @internal.json_escape(item_id) +
            "\",\"type\":\"message\",\"role\":\"" +
            @internal.json_escape(role_str) +
            "\",\"content\":[" +
            cparts.join(",") +
            "]}"
          }
          ToolCall(tu) =>
            "{\"id\":\"" +
            @internal.json_escape(tu.id) +
            "\",\"type\":\"function_call\",\"call_id\":\"" +
            @internal.json_escape(tu.id) +
            "\",\"name\":\"" +
            @internal.json_escape(tu.name) +
            "\",\"arguments\":\"\"}"
          ToolResult(tr) =>
            "{\"type\":\"function_call_output\",\"call_id\":\"" +
            @internal.json_escape(tr.tool_use_id) +
            "\",\"output\":\"" +
            @internal.json_escape(@lux.lucent_content_to_text(tr.content)) +
            "\"}"
          Reasoning(th) => {
            // summary/signature 片段与 request_encode/response 共享 helper，
            // 保证三处 reasoning 序列化转义一致
            let summary = match th.summary {
              Some(arr) => {
                let parts : Array[String] = []
                let mut k = 0
                while k < arr.length() {
                  match arr[k] {
                    Text(t, _) => parts.push(summary_text_item(t))
                    _ => ()
                  }
                  k = k + 1
                }
                ",\"summary\":[" + parts.join(",") + "]"
              }
              None => ""
            }
            let sig = match th.signature {
              Some(s) => thinking_signature_field(s)
              None => ""
            }
            "{\"id\":\"" +
            @internal.json_escape(item_id) +
            "\",\"type\":\"reasoning\"" +
            summary +
            sig +
            "}"
          }
          AgentAction(aa) =>
            "{\"id\":\"" +
            @internal.json_escape(aa.id) +
            "\",\"type\":\"computer_call\"}"
        }
        block_item_id[idx] = item_id
        lines.push(
          "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":" +
          idx.to_string() +
          ",\"item\":" +
          item_json +
          "}",
        )
      }
      ItemEnd(_) => ()
      BlockStart(idx, bt) =>
        // 记录 block → (output_index, content_index) 映射；文本类块按 message item
        // 内独立 content 计数分配，ToolCall 块不产生 content part（独立 function_call item）。
        match bt {
          ToolCall(tid, tname) => {
            block_output[idx] = next_output_index
            block_is_tool[idx] = true
            block_tool_name[idx] = tname
            // AI SDK 依赖 output_item.added 注册 tool call（ongoingToolCalls），
            // 缺少则后续 function_call_arguments.delta 无法归属到工具调用
            let out = next_output_index
            next_output_index = next_output_index + 1
            let fid = if tid == "" {
              "fc_" + item_counter.to_string()
            } else {
              tid
            }
            if tid == "" {
              item_counter = item_counter + 1
            }
            block_item_id[idx] = fid
            lines.push(
              "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":" +
              out.to_string() +
              ",\"item\":{\"id\":\"" +
              @internal.json_escape(fid) +
              "\",\"type\":\"function_call\",\"call_id\":\"" +
              @internal.json_escape(fid) +
              "\",\"name\":\"" +
              @internal.json_escape(tname) +
              "\",\"arguments\":\"\"}}",
            )
          }
          Thinking => {
            // reasoning item 的 BlockStart
            // 分配独立的 output_index（不修改 cur_message_output，保留给 Text 块）
            let out = next_output_index
            next_output_index = next_output_index + 1
            // AI SDK 要求 reasoning item 必须有 id
            let rid = "rs_" + item_counter.to_string()
            item_counter = item_counter + 1
            block_item_id[idx] = rid
            lines.push(
              "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":" +
              out.to_string() +
              ",\"item\":{\"id\":\"" +
              @internal.json_escape(rid) +
              "\",\"type\":\"reasoning\"}}",
            )
            block_output[idx] = out
            block_is_thinking[idx] = true
          }
          _ => {
            // 非 ToolCall 块（Text/Refusal 等）：属于 message item
            if message_output_index < 0 {
              // 首次出现 Text 块：分配 message item 的 output_index
              message_output_index = next_output_index
              next_output_index = next_output_index + 1
              // AI SDK 要求 message item 必须有 id
              let mid = "msg_" + item_counter.to_string()
              item_counter = item_counter + 1
              block_item_id[idx] = mid
              lines.push(
                "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":" +
                message_output_index.to_string() +
                ",\"item\":{\"id\":\"" +
                @internal.json_escape(mid) +
                "\",\"type\":\"message\",\"role\":\"assistant\",\"content\":[]}}",
              )
            }
            let out = message_output_index
            block_output[idx] = out
            block_content[idx] = cur_content_index
            block_is_tool[idx] = false
            block_is_thinking[idx] = false
            let part_json = match bt {
              Text => "{\"type\":\"output_text\",\"text\":\"\"}"
              Refusal => "{\"type\":\"refusal\",\"refusal\":\"\"}"
              _ => "{\"type\":\"output_text\",\"text\":\"\"}"
            }
            lines.push(
              "event: response.content_part.added\ndata: {\"type\":\"response.content_part.added\",\"output_index\":" +
              out.to_string() +
              ",\"content_index\":" +
              cur_content_index.to_string() +
              ",\"part\":" +
              part_json +
              "}",
            )
            cur_content_index = cur_content_index + 1
          }
        }
      BlockDelta(idx, delta) => {
        // 用 BlockStart 记录的 output_index / content_index（缺失时回退 idx）
        let out = match block_output.get(idx) {
          Some(o) => o
          None => idx
        }
        let ci = match block_content.get(idx) {
          Some(c) => c
          None => idx
        }
        // AI SDK 要求 delta 事件必须带 item_id（对应所属 output item 的 id）
        let item_id = match block_item_id.get(idx) {
          Some(id) => id
          None => "item_" + out.to_string()
        }
        match delta {
          TextDelta(s) =>
            lines.push(
              "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"item_id\":\"" +
              @internal.json_escape(item_id) +
              "\",\"output_index\":" +
              out.to_string() +
              ",\"content_index\":" +
              ci.to_string() +
              ",\"delta\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          ThinkingDelta(s) =>
            lines.push(
              // AI SDK 只消费 response.reasoning_summary_text.delta（reasoning_text.delta 会被
              // 当作 unknown_chunk 忽略），summary_index=0 对应 output_item.added 已隐含的 reasoning-start
              "event: response.reasoning_summary_text.delta\ndata: {\"type\":\"response.reasoning_summary_text.delta\",\"item_id\":\"" +
              @internal.json_escape(item_id) +
              "\",\"output_index\":" +
              out.to_string() +
              ",\"summary_index\":0,\"delta\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          ToolArgumentsDelta(s) => {
            // 工具块：跨帧累积参数，供 BlockEnd 的 function_call_arguments.done
            // 与 output_item.done 携带完整 arguments（官方 done 帧携带完整
            // 载荷；此前恒为空串）
            match block_is_tool.get(idx) {
              Some(true) => {
                let sb = match block_tool_args.get(idx) {
                  Some(b) => b
                  None => {
                    let b = StringBuilder()
                    block_tool_args[idx] = b
                    b
                  }
                }
                sb.write_string(s)
              }
              _ => ()
            }
            lines.push(
              "event: response.function_call_arguments.delta\ndata: {\"type\":\"response.function_call_arguments.delta\",\"item_id\":\"" +
              @internal.json_escape(item_id) +
              "\",\"output_index\":" +
              out.to_string() +
              ",\"delta\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          }
          SignatureDelta(s) =>
            // thinking signature → reasoning item 的 encrypted-style signature 字段：
            // Responses 推理延续凭证，不丢弃（标准 §10.2 reasoning signature）。
            // event 名与 data.type 必须一致：AI SDK / OpenAI SDK 按 SSE event 名
            // 分派，不一致会被当作 unknown event 丢弃。
            lines.push(
              "event: response.reasoning_summary_part.done\ndata: {\"type\":\"response.reasoning_summary_part.done\",\"item_id\":\"" +
              @internal.json_escape(item_id) +
              "\",\"output_index\":" +
              out.to_string() +
              ",\"summary_index\":0,\"signature\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          RefusalDelta(s) =>
            lines.push(
              "event: response.refusal.delta\ndata: {\"type\":\"response.refusal.delta\",\"item_id\":\"" +
              @internal.json_escape(item_id) +
              "\",\"output_index\":" +
              out.to_string() +
              ",\"content_index\":" +
              ci.to_string() +
              ",\"delta\":\"" +
              @internal.json_escape(s) +
              "\"}",
            )
          _ => ()
        }
      }
      BlockEnd(idx) => {
        let out = match block_output.get(idx) {
          Some(o) => o
          None => idx
        }
        let ci = match block_content.get(idx) {
          Some(c) => c
          None => idx
        }
        let item_id = match block_item_id.get(idx) {
          Some(id) => id
          None => "item_" + out.to_string()
        }
        // 按块类型发对应 done 事件（标准 §10.2）：
        // tool 块 → function_call_arguments.done + output_item.done；thinking 块 →
        // reasoning_summary_part.done + output_item.done；文本块 → output_text.done + output_item.done
        if block_is_tool.get(idx) == Some(true) {
          // BlockStart 起累积的完整参数（此前恒为空串——只读 delta 的消费方
          // 在 done 帧拿不到任何参数）
          let args = match block_tool_args.get(idx) {
            Some(b) => b.to_string()
            None => ""
          }
          let tname = match block_tool_name.get(idx) {
            Some(n) => n
            None => ""
          }
          lines.push(
            "event: response.function_call_arguments.done\ndata: {\"type\":\"response.function_call_arguments.done\",\"item_id\":\"" +
            @internal.json_escape(item_id) +
            "\",\"output_index\":" +
            out.to_string() +
            ",\"arguments\":\"" +
            @internal.json_escape(args) +
            "\"}",
          )
          // output_item.done：AI SDK 依赖它结束 function_call item（发 tool-input-end）。
          // 此前 tools 分支只发 arguments.done，item 悬空永不收尾。
          lines.push(
            "event: response.output_item.done\ndata: {\"type\":\"response.output_item.done\",\"output_index\":" +
            out.to_string() +
            ",\"item\":{\"id\":\"" +
            @internal.json_escape(item_id) +
            "\",\"type\":\"function_call\",\"call_id\":\"" +
            @internal.json_escape(item_id) +
            "\",\"name\":\"" +
            @internal.json_escape(tname) +
            "\",\"arguments\":\"" +
            @internal.json_escape(args) +
            "\"}}",
          )
        } else if block_is_thinking.get(idx) == Some(true) {
          lines.push(
            // AI SDK 消费 reasoning_summary_part.done（reasoning_text.done 会被忽略）
            "event: response.reasoning_summary_part.done\ndata: {\"type\":\"response.reasoning_summary_part.done\",\"item_id\":\"" +
            @internal.json_escape(item_id) +
            "\",\"output_index\":" +
            out.to_string() +
            ",\"summary_index\":0}",
          )
          // output_item.done：AI SDK 依赖它结束 reasoning part（发 reasoning-end）
          lines.push(
            "event: response.output_item.done\ndata: {\"type\":\"response.output_item.done\",\"output_index\":" +
            out.to_string() +
            ",\"item\":{\"id\":\"" +
            @internal.json_escape(item_id) +
            "\",\"type\":\"reasoning\"}}",
          )
        } else {
          lines.push(
            "event: response.output_text.done\ndata: {\"type\":\"response.output_text.done\",\"item_id\":\"" +
            @internal.json_escape(item_id) +
            "\",\"output_index\":" +
            out.to_string() +
            ",\"content_index\":" +
            ci.to_string() +
            "}",
          )
          // output_item.done：AI SDK 依赖它结束 text part（发 text-end）
          lines.push(
            "event: response.output_item.done\ndata: {\"type\":\"response.output_item.done\",\"output_index\":" +
            out.to_string() +
            ",\"item\":{\"id\":\"" +
            @internal.json_escape(item_id) +
            "\",\"type\":\"message\",\"role\":\"assistant\"}}",
          )
        }
      }
      BlockDiscard(_) | Annotations(_, _) => ()
      Finish(fr) => {
        let status_str = match fr {
          Stop => "\"completed\""
          Length => "\"incomplete\""
          Error => "\"failed\""
          _ => "\"completed\""
        }
        // 向后查找 Usage 事件，合并到 response.completed 中
        let mut pt = 0
        let mut ct = 0
        let mut tt = 0
        let mut has_usage = false
        let mut last_usage_reasoning : Int32? = None
        let mut last_usage_cached : Int32? = None
        let mut j = i + 1
        while j < events.length() {
          match events[j] {
            Usage(u) => {
              pt = u.prompt_tokens
              ct = u.completion_tokens
              tt = u.total_tokens
              last_usage_reasoning = u.reasoning_tokens
              last_usage_cached = u.cached_tokens
              has_usage = true
            }
            _ => ()
          }
          j = j + 1
        }
        let usage_json = if has_usage {
          let mut s = ",\"usage\":{\"input_tokens\":" +
            pt.to_string() +
            ",\"output_tokens\":" +
            ct.to_string() +
            ",\"total_tokens\":" +
            tt.to_string()
          match last_usage_reasoning {
            Some(n) =>
              s = s +
                ",\"output_tokens_details\":{\"reasoning_tokens\":" +
                n.to_string() +
                "}"
            None => ()
          }
          match last_usage_cached {
            Some(n) =>
              s = s +
                ",\"input_tokens_details\":{\"cached_tokens\":" +
                n.to_string() +
                "}"
            None => ()
          }
          s + "}"
        } else {
          ""
        }
        lines.push(
          "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"" +
          @internal.json_escape(resp_id) +
          "\",\"status\":" +
          status_str +
          usage_json +
          "}}",
        )
      }
      Usage(_) => () // Usage 已合并到 Finish 的 response.completed 中，不再单独输出
      Error(e) => {
        // 官方错误帧：{"type":"error","code":"...","message":"..."}（error 为平铺字段）
        let error_code = match e.kind {
          RateLimit => "rate_limit_exceeded"
          InvalidRequest => "invalid_request_error"
          Authentication => "invalid_api_key"
          ServerError => "server_error"
          ContentFilter => "content_filter"
          Native(tag) => tag
        }
        lines.push(
          "event: error\ndata: {\"type\":\"error\",\"code\":\"" +
          @internal.json_escape(error_code) +
          "\",\"message\":\"" +
          @internal.json_escape(e.message) +
          "\"}",
        )
      }
      Done => () // Responses 流以 response.completed 结束，无独立 done 事件
    }
    i = i + 1
  }
  // 标量状态写回会话（Map 是引用类型，已就地生效）
  st.next_output_index = next_output_index
  st.message_output_index = message_output_index
  st.cur_content_index = cur_content_index
  st.item_counter = item_counter
  st.resp_id = resp_id
  Ok(
    @lux.ConversionResult::new(lines.join("\n\n") + "\n\n").with_diagnostics(
      diagnostics,
    ),
  )
}

///|
/// 创建 responses 流编码会话（T5 增量转换入口，跨帧状态由会话持有）
///
/// `encode` 每次调用复用同一状态：BlockStart 在首帧、BlockEnd 可能在后续帧，
/// done 事件仍能反查到累积参数与 item_id。`set_ctx` 注入跨帧会话元信息。
pub fn responses_stream_encoder() -> @lux.LucentStreamEncoder {
  let st = ResponsesStreamState::new()
  @lux.LucentStreamEncoder::new(
    fn(events) { responses_encode_frames(events, st) },
    fn() {
      // responses 编码器无未闭合的自身状态（块闭合由解码侧规整器补齐）
      Ok(@lux.ConversionResult::new(""))
    },
    fn(ctx) { st.ctx = ctx },
  )
}

///|
/// 创建 responses 流解码会话（跨帧状态由会话持有）
///
/// responses 源逐帧解码本身无跨帧状态（FrameEnd 由各自事件携带索引），
/// 会话化只是把「一帧 = 一条 SSE 消息」的入口统一到会话载体。
pub fn responses_stream_decoder() -> @lux.LucentStreamDecoder {
  @lux.LucentStreamDecoder::new(
    fn(frame) {
      let r = responses_sse_to_events(frame)
      match r {
        Ok(cr) => Ok(cr)
        Err(e) => Err(e)
      }
    },
    fn() { [] },
  )
}
