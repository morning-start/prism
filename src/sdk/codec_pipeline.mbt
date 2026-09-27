///|
/// codec_pipeline.mbt — 共享 decode → IR → encode 管线
///
/// 只负责协议无关的转换编排和诊断合并；Provider codec 由注册表注入。
/// （命名：与 pipeline.mbt（Prism 门面内部方法）语义区分，本文件为
/// 通用 source→target 管线，见 docs/rules/naming-conventions.md §6）

///|
/// 通用：source 解码 → target 编码（合并解码+编码诊断，返回带诊断结果）
fn decode_encode_request(
  json_str : String,
  decode : (String) -> Result[@lux.ConversionResult[@lux.LucentRequest], String],
  encode : (@lux.LucentRequest) -> Result[@lux.ConversionResult[String], String],
) -> Result[@lux.ConversionResult[String], String] {
  match decode(json_str) {
    Ok(dcr) =>
      match encode(dcr.value()) {
        Ok(ecr) => Ok(merge_diagnostics(ecr, dcr.diagnostics()))
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// 通用：source 解码 → target 编码（合并诊断）
fn decode_encode_response(
  json_str : String,
  decode : (String) -> Result[
    @lux.ConversionResult[@lux.LucentResponse],
    String,
  ],
  encode : (@lux.LucentResponse) -> Result[
    @lux.ConversionResult[String],
    String,
  ],
) -> Result[@lux.ConversionResult[String], String] {
  match decode(json_str) {
    Ok(dcr) =>
      match encode(dcr.value()) {
        Ok(ecr) => Ok(merge_diagnostics(ecr, dcr.diagnostics()))
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}

///|
/// 通用：source 事件解码 → target 事件编码（合并诊断）
fn decode_encode_stream(
  sse_str : String,
  decode : (String) -> Result[
    @lux.ConversionResult[Array[@lux.LucentStreamEvent]],
    String,
  ],
  encode : (Array[@lux.LucentStreamEvent]) -> Result[
    @lux.ConversionResult[String],
    String,
  ],
) -> Result[@lux.ConversionResult[String], String] {
  match decode(sse_str) {
    Ok(dcr) => {
      // CR-002 D5：IR 流的终止符由会话层唯一产生 —— 丢弃解码器在流中途发出的
      // Done（Gemini 的帧级兜底 Done 会落在 usage / 后续内容之前），末尾统一补
      // 一个，保证终止符恰好一次且位于最后。
      let events = dcr.value()
      let kept : Array[@lux.LucentStreamEvent] = []
      for ev in events {
        match ev {
          Done => ()
          _ => kept.push(ev)
        }
      }
      kept.push(Done)
      match encode(kept) {
        Ok(ecr) => Ok(merge_diagnostics(ecr, dcr.diagnostics()))
        Err(e) => Err(e)
      }
    }
    Err(e) => Err(e)
  }
}

///|
/// 合并两组诊断：以编码结果为主体，把解码诊断并入
fn merge_diagnostics(
  main : @lux.ConversionResult[String],
  other_diags : Array[@lux.ConversionDiagnostic],
) -> @lux.ConversionResult[String] {
  main.with_diagnostics(other_diags)
}
