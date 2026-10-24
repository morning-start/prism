///|
/// 5. responses_sse_to_events — 流解码
///
/// 使用逐行状态机解析 SSE 流，正确处理：
/// - 多行 data: 字段（SSE 规范：用换行符合并）
/// - 心跳注释行（: keep-alive 等）
/// - data: 值内含换行符的 JSON（pretty-printed）
/// - CRLF 行尾
pub fn responses_sse_to_events(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  responses_decode_frames(sse_str)
}

///|
/// 解码一帧 SSE（responses 源无跨帧标量状态：各事件的索引由帧自身携带，
/// 故此处不额外持有会话状态；保留帧级入口以便与会话载体统一）
fn responses_decode_frames(
  sse_str : String,
) -> Result[@lux.ConversionResult[Array[@lux.LucentStreamEvent]], String] {
  let events : Array[@lux.LucentStreamEvent] = []
  let diagnostics : Array[@lux.ConversionDiagnostic] = []
  // 统一换行符：CRLF → LF，再用统一 SSE 解析
  // 必须 replace_all：String::replace 只替换首次出现，残留 CRLF 会让多帧并块
  let normalized = sse_str
    .replace_all(old="\r\n", new="\n")
    .replace_all(old="\r", new="\n")
  let messages = @internal.parse_sse_messages(normalized)
  let mut i = 0
  while i < messages.length() {
    let event_type_raw = messages[i].event_type.unwrap_or("")
    let data_raw = messages[i].data.trim().to_owned()
    // 统一帧预处理（iteration-008 方向 B）：与 messages/openai/gemini
    // 共用 internal 管线，保留"失败必诊断"语义
    let (jv_opt, fail_reason) = @internal.parse_sse_frame_with_reason(data_raw)
    match jv_opt {
      None =>
        match fail_reason {
          Some(reason) =>
            diagnostics.push(
              @lux.ConversionDiagnostic::new("sse.data", Invalid, Some(reason)),
            )
          None => ()
        }
      Some(jv) => {
        // event: 行缺失时，从 JSON 的 type 字段回退推断事件类型
        let event_type = if event_type_raw == "" {
          @internal.field_str(jv, "type").unwrap_or(event_type_raw)
        } else {
          event_type_raw
        }
        match event_type {
          "response.created" =>
            match @internal.obj_get(jv, "response") {
              Some(r) => {
                let rid = @internal.field_str(r, "id")
                let rmodel = @internal.field_str(r, "model")
                let created_at = @internal.field_int(r, "created_at")
                let extra = build_extra(r, ["id", "model", "created_at"])
                events.push(
                  ConversationStart(
                    @lux.LucentConversationMeta::new_full(
                      rid,
                      rmodel,
                      None,
                      created_at,
                      extra,
                    ),
                  ),
                )
              }
              None => ()
            }
          "response.output_item.added" => {
            let idx = @internal.field_int(jv, "output_index").unwrap_or(0)
            match @internal.obj_get(jv, "item") {
              Some(item) =>
                match parse_input_item(item, diagnostics) {
                  Some(ci) => {
                    events.push(ItemStart(idx, ci))
                    // reasoning item 需要额外发出 BlockStart，让编码器生成 thinking content block
                    match @internal.field_str(item, "type") {
                      Some("reasoning") =>
                        events.push(BlockStart(idx, Thinking))
                      _ => ()
                    }
                  }
                  None => ()
                }
              None => ()
            }
          }
          "response.content_part.added" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            match @internal.obj_get(jv, "part") {
              Some(part) =>
                match @internal.field_str(part, "type") {
                  Some("output_text") => events.push(BlockStart(idx, Text))
                  Some("refusal") => events.push(BlockStart(idx, Refusal))
                  _ => ()
                }
              None => ()
            }
          }
          "response.output_text.delta" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            match @internal.field_str(jv, "delta") {
              Some(t) =>
                events.push(
                  BlockDelta(idx, @lux.LucentBlockDelta::text_delta(t)),
                )
              None => ()
            }
          }
          "response.output_text.done" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            events.push(BlockEnd(idx))
          }
          "response.output_item.done" => {
            // 官方 output_item.done 携带该 item 的终态（status / 完整 content）。
            // 此前该帧被完全丢弃：item 的终态信息（status=completed/failed 等）
            // 与整帧载荷无从恢复。映射为 IR 的 ItemEnd —— IR 用 BlockEnd 承载
            // 内容块边界，item 级边界由 ItemEnd 表达，语义一一对应。
            let idx = @internal.field_int(jv, "output_index").unwrap_or(0)
            events.push(ItemEnd(idx))
          }
          "response.output_text.annotation.added" => {
            // 官方注解帧：annotation 对象为 url_citation / file_citation /
            // container_file_citation / file_path 之一。此前被完全丢弃 →
            // 引用来源（citation）在流式路径整体消失。映射为 IR 的
            // Annotations 事件（lux 侧已有 LucentAnnotation 模型）。
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            match @internal.obj_get(jv, "annotation") {
              Some(ann) =>
                match parse_annotation(ann) {
                  Some(a) => events.push(Annotations(idx, [a]))
                  None => ()
                }
              None => ()
            }
          }
          "response.refusal.delta" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            match @internal.field_str(jv, "delta") {
              Some(t) =>
                events.push(
                  BlockDelta(idx, @lux.LucentBlockDelta::refusal_delta(t)),
                )
              None => ()
            }
          }
          "response.refusal.done" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            events.push(BlockEnd(idx))
          }
          "response.reasoning_summary_text.delta"
          | "response.reasoning_text.delta" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            match @internal.field_str(jv, "delta") {
              Some(t) =>
                events.push(
                  BlockDelta(idx, @lux.LucentBlockDelta::thinking_delta(t)),
                )
              None => ()
            }
          }
          "response.reasoning_summary_text.done"
          | "response.reasoning_text.done" => {
            let idx = @internal.field_int(jv, "content_index").unwrap_or(0)
            events.push(BlockEnd(idx))
          }
          "response.function_call_arguments.delta" => {
            let idx = @internal.field_int(jv, "output_index").unwrap_or(0)
            match @internal.field_str(jv, "delta") {
              Some(a) =>
                events.push(
                  BlockDelta(
                    idx,
                    @lux.LucentBlockDelta::tool_arguments_delta(a),
                  ),
                )
              None => ()
            }
          }
          "response.function_call_arguments.done" => {
            let idx = @internal.field_int(jv, "output_index").unwrap_or(0)
            events.push(BlockEnd(idx))
          }
          "response.completed" | "response.incomplete" | "response.failed" => {
            // CR-006：三个官方终止事件此前只有 completed 被处理，incomplete /
            // failed 连同 Done 一起静默消失——response.failed 的流经 Prism 中转
            // 后对下游表现为「什么都没发生」（实测 0 事件，零诊断）。
            // status 映射走 @meta.responses_termination_reason，与非流式共用
            // 同一函数（incomplete_details.reason 的 content_filter 细分等
            // 语义两侧一致）。
            match @internal.obj_get(jv, "response") {
              Some(r) => {
                match @internal.field_str(r, "status") {
                  Some(s) => {
                    let reason = match
                      @internal.obj_get(r, "incomplete_details") {
                      Some(d) => @internal.field_str(d, "reason")
                      None => None
                    }
                    events.push(
                      Finish(@meta.responses_termination_reason(s, reason)),
                    )
                  }
                  None => ()
                }
                match @internal.obj_get(r, "usage") {
                  Some(u) => {
                    let pt = @internal.field_int(u, "input_tokens").unwrap_or(0)
                    let ct = @internal.field_int(u, "output_tokens").unwrap_or(
                      0,
                    )
                    let tt = @internal.field_int(u, "total_tokens").unwrap_or(
                      pt + ct,
                    )
                    let reasoning = @internal.parse_reasoning_tokens(u, [
                      "output_tokens_details",
                    ])
                    let cached = @internal.parse_cached_tokens(u, [
                      "input_tokens_details",
                    ])
                    events.push(
                      Usage(
                        @lux.LucentUsage::full(
                          pt,
                          ct,
                          tt,
                          reasoning,
                          cached,
                          None,
                        ),
                      ),
                    )
                  }
                  None => ()
                }
                // failed 时的 error 对象（{code, message}）：与非流式同形带出，
                // 产生显式 Error 事件 + 诊断。调用方只知道失败不够，得知道为什么。
                if @internal.field_str(r, "status") == Some("failed") {
                  match @internal.obj_get(r, "error") {
                    Some(err) => {
                      let code = @internal.field_str(err, "code").unwrap_or("")
                      let message = @internal.field_str(err, "message").unwrap_or(
                        "",
                      )
                      if code != "" || message != "" {
                        events.push(
                          Error(
                            @lux.LucentError::new(
                              @lux.LucentErrorKind::from_string(code),
                              message,
                              if code == "" {
                                None
                              } else {
                                Some(code)
                              },
                            ),
                          ),
                        )
                        diagnostics.push(
                          @lux.ConversionDiagnostic::degraded(
                            "response.error",
                            Some(
                              "response failed (code: " + code + "): " + message,
                            ),
                          ),
                        )
                      }
                    }
                    None => ()
                  }
                }
              }
              None => ()
            }
            events.push(Done)
          }
          "error" => {
            // 官方 ResponseErrorEvent 是扁平结构（spec 58391 行起）：
            // {type:"error", code, message, param, sequence_number}
            // 此前只读嵌套 jv["error"]（非官方形态），官方帧被静默吞掉。
            // 顺序：先官方扁平（code/message 顶层），再兼容非官方嵌套形态。
            let flat_code = @internal.field_str(jv, "code")
            let flat_msg = @internal.field_str(jv, "message")
            match (flat_code, flat_msg) {
              (Some(_), Some(_)) => {
                let kind = @lux.LucentErrorKind::from_string(
                  flat_code.unwrap_or(""),
                )
                events.push(
                  Error(
                    @lux.LucentError::new(
                      kind,
                      flat_msg.unwrap_or(""),
                      flat_code,
                    ),
                  ),
                )
              }
              _ =>
                match @internal.field_str(jv, "error") {
                  Some(err_msg) =>
                    events.push(Error(@lux.LucentError::simple(err_msg)))
                  None => ()
                }
            }
          }
          _ => ()
        }
      }
    }
    i = i + 1
  }
  let result = @lux.ConversionResult::new(events)
  Ok(result.with_diagnostics(diagnostics))
}

///|
/// 解析 Responses 注解对象 → LucentAnnotation
///
/// 官方 `Annotation` 是 four-way oneOf（schemas/endpoints/openai-openapi.yaml
/// `Annotation`）：url_citation / file_citation / container_file_citation /
/// file_path。前两者有 IR 原生 kind；后两者退化为 Native(type) 保留类型标签。
/// `annotation` 本身可为 null（官方 anyOf 含 null），此时返回 None。
fn parse_annotation(ann : Json) -> @lux.LucentAnnotation? {
  let ann_type = @internal.field_str(ann, "type").unwrap_or("")
  match ann_type {
    "url_citation" =>
      Some(
        @lux.LucentAnnotation::new(
          Url,
          @internal.field_str(ann, "title"),
          @internal.field_str(ann, "url"),
          @internal.field_int(ann, "start_index"),
          @internal.field_int(ann, "end_index"),
        ),
      )
    "file_citation" =>
      Some(
        @lux.LucentAnnotation::new(
          FileCitation,
          @internal.field_str(ann, "filename"),
          @internal.field_str(ann, "file_id"),
          None,
          None,
        ),
      )
    "container_file_citation" | "file_path" =>
      Some(
        @lux.LucentAnnotation::new(
          Native(ann_type),
          @internal.field_str(ann, "filename"),
          None,
          None,
          None,
        ),
      )
    _ => None
  }
}
