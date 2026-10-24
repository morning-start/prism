///|
/// Responses 终止状态 → IR 的共用映射（流式与非流式必须解出同一 IR 值）。
///
/// 来源背景（CR-006 §2.1）：非流式 `response.mbt` 的映射是对的，流式
/// `stream_decode.mbt` 只处理 `response.completed`，`response.incomplete` /
/// `response.failed` / 官方扁平 `error` 三个官方终止事件全部静默丢弃。
/// 根因是「两路径各写一份映射」的又一次出现——流式里根本不存在这份逻辑。
/// 抽到这里共用，杜绝再次漂移。
///
/// ## 映射依据（vendored 官方 OpenAPI，`Response.status` 与
/// `incomplete_details.reason` 两个封闭枚举）
///
/// | status | reason | IR |
/// |---|---|---|
/// | completed | — | Stop |
/// | incomplete | content_filter | ContentFilter（内容截断 ≠ token 上限） |
/// | incomplete | max_output_tokens / max_messages | Length |
/// | incomplete | steered 等其它 | Native(reason)（原样保留，编码侧白名单裁决） |
/// | incomplete | 缺失 | Length（保守默认，同非流式） |
/// | failed | — | Error |
/// | 其它/缺失 | — | Native(status) / Stop（同非流式） |
///
/// `error` 对象（{code, message}）与 blockReason 类似，由调用方带诊断——
/// 本函数返回 IR 值，错误详情的诊断在调用方做（那里的 field 名更准确）。

///|
/// Responses `status` + `incomplete_details.reason` → IR 终止原因。
/// 与非流式 `response.mbt` 的映射逐值一致。
/// `status` 缺失（空串）→ Stop，与非流式原 `None => Stop` 行为一致。
pub fn responses_termination_reason(
  status : String,
  incomplete_reason : String?,
) -> @lux.LucentFinishReason {
  match status {
    // status 缺失（Response.status 理论必填但历史样本可能缺）→ 保守视为完成
    "" => Stop
    "completed" => Stop
    "incomplete" =>
      match incomplete_reason {
        // 内容过滤截断 ≠ token 上限截断
        Some("content_filter") => ContentFilter
        // 官方 reason 枚举里其余的「限额」类原因都是 Length 语义
        Some("max_output_tokens") => Length
        Some("max_messages") => Length
        // `steered`（安全边界主动停）等无 IR 对等值 → 原样保留，不丢数据
        Some(other) => @lux.LucentFinishReason::from_string(other)
        // reason 缺失（Response 级为可选字段）→ 保持保守默认 Length
        None => Length
      }
    "failed" => Error
    other => @lux.LucentFinishReason::from_string(other)
  }
}
