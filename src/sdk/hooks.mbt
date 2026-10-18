///|
/// ═══ 功能组：hooks（IR 策略层，T4）═══
/// IR→IR 纯函数钩子 + convert_*_with_hooks 组合入口 + 内置常用钩子。
///
/// 定位（架构审计 P0-6）：IR 不只是转换中间站，更是 middleware 的 policy
/// 落点。此前 convert_* 是 decode→encode 直通，宿主无法在 IR 层插入
/// 审计/脱敏/改写/裁剪逻辑，只能在 Prism 外重新 parse JSON——IR 价值被浪费。
///
/// 护栏（架构文档 §演进护栏）：
/// - 钩子必须是 IR→IR 纯函数，只依赖 lux 类型；禁止反向依赖 provider
/// - 造成数据损失的操作（裁工具、压上限）必须 push Degraded 诊断，
///   遵守"Unsupported capabilities MUST fail explicitly, never silently drop"
/// - 不传 hooks（空数组）时行为与 convert_* 完全一致

///|
/// SdkRequestHook — 请求 IR 钩子
///
/// 入参：(IR, 诊断收集器)；返回变换后的 IR。钩子可向收集器 push
/// ConversionDiagnostic，最终与 decode/encode 两阶段诊断合并返回。
pub type SdkRequestHook = (@lux.LucentRequest, Array[@lux.ConversionDiagnostic]) -> @lux.LucentRequest

///|
/// SdkResponseHook — 响应 IR 钩子（同上）
pub type SdkResponseHook = (
  @lux.LucentResponse,
  Array[@lux.ConversionDiagnostic],
) -> @lux.LucentResponse

///|
/// SdkStreamHook — 流事件 IR 钩子（事件数组整体变换）
pub type SdkStreamHook = (
  Array[@lux.LucentStreamEvent],
  Array[@lux.ConversionDiagnostic],
) -> Array[@lux.LucentStreamEvent]

///|
/// 合并三段诊断：以编码结果为主体，并入解码诊断与钩子诊断
fn merge_hook_diagnostics(
  encoded : @lux.ConversionResult[String],
  decode_diags : Array[@lux.ConversionDiagnostic],
  hook_diags : Array[@lux.ConversionDiagnostic],
) -> @lux.ConversionResult[String] {
  encoded.with_diagnostics(decode_diags).with_diagnostics(hook_diags)
}

///|
/// convert_request_with_hooks — 请求转换 + IR 钩子链（场景 2 策略注入）
///
/// 管线：source decode → hooks(IR) → target encode；诊断按
/// decode/hook/encode 三段合并。hooks 为空数组时与 convert_request 一致。
pub fn convert_request_with_hooks(
  source : String,
  json_str : String,
  target : String,
  hooks : Array[SdkRequestHook],
) -> Result[@lux.ConversionResult[String], String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      match (src.request_decode)(json_str) {
        Ok(dcr) => {
          let hook_diags : Array[@lux.ConversionDiagnostic] = []
          let mut ir = dcr.value()
          for hook in hooks {
            ir = hook(ir, hook_diags)
          }
          match (dst.request_encode)(ir) {
            Ok(ecr) =>
              Ok(merge_hook_diagnostics(ecr, dcr.diagnostics(), hook_diags))
            Err(e) => Err(e)
          }
        }
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// convert_response_with_hooks — 响应转换 + IR 钩子链
pub fn convert_response_with_hooks(
  source : String,
  json_str : String,
  target : String,
  hooks : Array[SdkResponseHook],
) -> Result[@lux.ConversionResult[String], String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      match (src.response_decode)(json_str) {
        Ok(dcr) => {
          let hook_diags : Array[@lux.ConversionDiagnostic] = []
          let mut ir = dcr.value()
          for hook in hooks {
            ir = hook(ir, hook_diags)
          }
          match (dst.response_encode)(ir) {
            Ok(ecr) =>
              Ok(merge_hook_diagnostics(ecr, dcr.diagnostics(), hook_diags))
            Err(e) => Err(e)
          }
        }
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// convert_stream_with_hooks — 流转换 + IR 钩子链（事件级）
///
/// 钩子作用于整个事件数组（可做事件过滤/注入/重排）；
/// 空 hooks 时与 convert_stream 一致。
pub fn convert_stream_with_hooks(
  source : String,
  sse_str : String,
  target : String,
  hooks : Array[SdkStreamHook],
) -> Result[@lux.ConversionResult[String], String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      match (src.events_decode)(sse_str) {
        Ok(dcr) => {
          let hook_diags : Array[@lux.ConversionDiagnostic] = []
          let mut events = dcr.value()
          for hook in hooks {
            events = hook(events, hook_diags)
          }
          match (dst.events_encode)(events) {
            Ok(ecr) =>
              Ok(merge_hook_diagnostics(ecr, dcr.diagnostics(), hook_diags))
            Err(e) => Err(e)
          }
        }
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// ═══ 内置常用钩子（middleware 高频策略开箱即用）═══

///|
/// 钳制 max_output_tokens 上限（成本兜底）
///
/// 实际压价时 push Degraded 诊断（值被改小才算损失）；
/// 原值小于等于 limit 时原样返回、无诊断。
pub fn hook_clamp_max_tokens(limit : Int32) -> SdkRequestHook {
  fn(
    ir : @lux.LucentRequest,
    diags : Array[@lux.ConversionDiagnostic],
  ) -> @lux.LucentRequest {
    match ir.options.max_output_tokens {
      Some(cur) if cur > limit => {
        diags.push(
          @lux.ConversionDiagnostic::degraded(
            "options.max_output_tokens",
            Some("clamped from \{cur} to \{limit} by hook"),
          ),
        )
        let opts = @lux.LucentOptions::new(
          ir.options.temperature,
          ir.options.top_p,
          ir.options.top_k,
          Some(limit),
          ir.options.stop,
          ir.options.stream,
          ir.options.candidate_count,
          ir.options.structured_output,
          ir.options.store,
          ir.options.extras,
        )
        @lux.LucentRequest::new(
          ir.model,
          ir.instructions,
          ir.conversation,
          ir.tools,
          ir.tool_choice,
          opts,
          ir.capabilities,
          ir.reasoning,
          ir.metadata,
          ir.extra,
        )
      }
      _ => ir
    }
  }
}

///|
/// 工具白名单过滤（裁剪越权工具）
///
/// 被裁掉的工具 push Degraded 诊断（数据不静默丢失）；
/// 全部保留时无诊断。allowed 为空数组 = 裁掉所有工具。
pub fn hook_filter_tools(allowed : Array[String]) -> SdkRequestHook {
  fn(
    ir : @lux.LucentRequest,
    diags : Array[@lux.ConversionDiagnostic],
  ) -> @lux.LucentRequest {
    match ir.tools {
      Some(tools) =>
        if tools.length() == 0 {
          ir
        } else {
          let kept : Array[@lux.LucentTool] = []
          let mut dropped = 0
          for t in tools {
            if allowed.contains(t.name) {
              kept.push(t)
            } else {
              dropped = dropped + 1
            }
          }
          if dropped == 0 {
            ir
          } else {
            diags.push(
              @lux.ConversionDiagnostic::degraded(
                "tools",
                Some("\{dropped} tool(s) filtered by allowlist hook"),
              ),
            )
            @lux.LucentRequest::new(
              ir.model,
              ir.instructions,
              ir.conversation,
              Some(kept),
              ir.tool_choice,
              ir.options,
              ir.capabilities,
              ir.reasoning,
              ir.metadata,
              ir.extra,
            )
          }
        }
      None => ir
    }
  }
}

///|
/// 追加系统指令（prompt 注入/改写）
///
/// 有意为之的策略操作，不产生诊断（非损失）。
pub fn hook_append_instructions(text : String) -> SdkRequestHook {
  fn(
    ir : @lux.LucentRequest,
    _diags : Array[@lux.ConversionDiagnostic],
  ) -> @lux.LucentRequest {
    let appended : Array[@lux.LucentContent] = match ir.instructions {
      Some(existing) => {
        let arr = existing.copy()
        arr.push(@lux.LucentContent::text(text))
        arr
      }
      None => [@lux.LucentContent::text(text)]
    }
    @lux.LucentRequest::new(
      ir.model,
      Some(appended),
      ir.conversation,
      ir.tools,
      ir.tool_choice,
      ir.options,
      ir.capabilities,
      ir.reasoning,
      ir.metadata,
      ir.extra,
    )
  }
}

///|
/// 改写模型名（路由/降级：把请求打到指定后端模型）
///
/// 有意为之的路由操作，不产生诊断；同名时无操作。
pub fn hook_set_model(model : String) -> SdkRequestHook {
  fn(
    ir : @lux.LucentRequest,
    _diags : Array[@lux.ConversionDiagnostic],
  ) -> @lux.LucentRequest {
    if ir.model == model {
      ir
    } else {
      @lux.LucentRequest::new(
        model,
        ir.instructions,
        ir.conversation,
        ir.tools,
        ir.tool_choice,
        ir.options,
        ir.capabilities,
        ir.reasoning,
        ir.metadata,
        ir.extra,
      )
    }
  }
}

///|
/// 流钩子示例：丢弃 Error 事件后的所有事件（故障演练/熔断演示用）
///
/// 保留错误事件本身（显式失败原则），只丢弃其后的噪音。
pub fn hook_stream_drop_after_error() -> SdkStreamHook {
  fn(
    events : Array[@lux.LucentStreamEvent],
    _diags : Array[@lux.ConversionDiagnostic],
  ) -> Array[@lux.LucentStreamEvent] {
    let result : Array[@lux.LucentStreamEvent] = []
    for ev in events {
      result.push(ev)
      match ev {
        Error(_) => break
        _ => ()
      }
    }
    result
  }
}
