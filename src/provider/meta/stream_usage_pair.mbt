///|
/// 流式 Usage/Finish 配对 —— 协议无关的 IR 层预扫描，供多个 stream encoder 共用。
///
/// ## 为什么放在 `meta`
///
/// 输入输出全部是 `@lux` 类型（`LucentStreamEvent` / `LucentUsage`），不需要
/// 任何 wire 知识；但它服务于**多个协议**的流编码器（messages 与 gemini），
/// 放在单个 provider 里就会复制一份或在 provider 间交叉引用。`meta` 是
/// provider 共享叶子包，与 `finish` / `termination` / `extras` 同一落点原则：
/// **多端共用的语义只写一份**（「两路径各写一份映射」失败模式的收口）。
///
/// ## 背景（CR-002 A3 语义，协议无关化）
///
/// 官方流里 usage 与终止信号的相对位置因协议而异：
/// - Anthropic：`message_delta` 同帧携带 `stop_reason` + `usage`；
/// - Gemini：`usageMetadata` 携带在带 `finishReason` 的**最后一个 chunk** 上，
///   之后不再有数据帧；
/// - OpenAI Chat：usage 在 finish 之后的独立 chunk（`stream_options.include_usage`），
///   这一路**不使用本配对**（openai 官方形态就是分离帧）。
///
/// IR 事件序里 `Usage` 可能出现在 `Finish` 之前或之后；本函数按窗口把每个
/// `Finish` 与一个 `Usage` 配对，编码器据此决定「同帧合并」还是「独立发射」。
///
/// ## 规则
///
/// 每个 Finish 与它所在窗口（上一个 Finish 与下一个 Finish 之间，开区间）内的
/// Usage 配对：优先取 Finish **之后**的最后一个 Usage，否则回退到 Finish
/// **之前**窗口内最后一个未被消费的 Usage。被配对的 Usage 由该 Finish 合并
/// 发射，其余 Usage 独立发射。
///
/// 返回：(每个 Usage 是否已被消费, 每个 Finish 配对的 Usage)

///|
pub fn pair_usages_with_finish(
  events : Array[@lux.LucentStreamEvent],
) -> (Array[Bool], Array[@lux.LucentUsage?]) {
  let n = events.length()
  let consumed : Array[Bool] = []
  let paired : Array[@lux.LucentUsage?] = []
  let mut k = 0
  while k < n {
    consumed.push(false)
    paired.push(None)
    k = k + 1
  }
  let mut i = 0
  while i < n {
    match events[i] {
      Finish(_, _) => {
        // 窗口下界：上一个 Finish 之后
        let mut lower = 0
        let mut prev = i - 1
        let mut prev_done = false
        while prev >= 0 && !prev_done {
          match events[prev] {
            Finish(_, _) => {
              lower = prev + 1
              prev_done = true
            }
            _ => prev = prev - 1
          }
        }
        // 窗口上界：下一个 Finish 之前
        let mut upper = n
        let mut nxt = i + 1
        let mut next_done = false
        while nxt < n && !next_done {
          match events[nxt] {
            Finish(_, _) => {
              upper = nxt
              next_done = true
            }
            _ => nxt = nxt + 1
          }
        }
        // 1) Finish 之后窗口内最后一个 Usage。
        // 此处无需 consumed 守卫：窗口上界是下一个 Finish，两个 Finish 的
        // after 窗口互不重叠，同一 Usage 不会同时落在两个 after 窗口内。
        let mut after_last = -1
        let mut j = i + 1
        while j < upper {
          match events[j] {
            Usage(_) => after_last = j
            _ => ()
          }
          j = j + 1
        }
        // 2) 否则取 Finish 之前窗口内最后一个 Usage。
        // 此处**必须**判 consumed：before 窗口的下界只是「上一个 Finish」，
        // 其间的 Usage 可能已被上一个 Finish 通过 after 窗口取走 —— 不判重
        // 会让同一个 usage 跟着两个 Finish 各发一遍。
        let mut before_last = -1
        if after_last < 0 {
          let mut j2 = lower
          while j2 < i {
            match events[j2] {
              Usage(_) => if !consumed[j2] { before_last = j2 }
              _ => ()
            }
            j2 = j2 + 1
          }
        }
        let chosen = if after_last >= 0 { after_last } else { before_last }
        if chosen >= 0 {
          consumed[chosen] = true
          match events[chosen] {
            Usage(u) => paired[i] = Some(u)
            _ => ()
          }
        }
      }
      _ => ()
    }
    i = i + 1
  }
  (consumed, paired)
}
