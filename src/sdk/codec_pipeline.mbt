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
/// CR-002 A5 / P1：整缓冲路径的块收尾改由共享的 `EventNormalizer` 完成。
///
/// 历史上这里另写了一套 `close_open_blocks`（按插入顺序升序闭合），而增量
/// 路径用 normalizer 的 Finish 分支（逆序闭合）—— 两套实现对同一语义各写
/// 一遍，结果混合流的 `content_block_stop` 顺序在两条路径上相反。现在两条
/// 路径共用同一实现：逐帧 == 整批由构造保证，而非靠对齐两个算法。

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
      // P1：与增量路径共用同一规整器（块去重/孤儿过滤/Finish 合成 BlockEnd）。
      // 截断流仍打开的块由 Finish 分支逆序补齐，且排在终止符之前。
      let normalizer = EventNormalizer::new()
      let closed = normalizer.normalize(kept)
      // 整场无 Finish（截断流）：规整器不会合成 BlockEnd，这里显式收尾，
      // 与 StreamConverter::finish 的截断流分支同构。
      if !normalizer.finish_seen {
        let mut k = normalizer.open_blocks.length() - 1
        while k >= 0 {
          closed.push(BlockEnd(normalizer.open_blocks[k]))
          k = k - 1
        }
      }
      closed.push(Done)
      match encode(closed) {
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
