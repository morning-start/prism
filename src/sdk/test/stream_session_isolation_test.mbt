///|
/// 流式会话化的强化回归（P0/P1 修复配套）。
///
/// `stream_tool_equivalence_test.mbt` 用 1 字节切分验证了"逐帧 == 整批"；
/// 本文件补三类会话化特有问题：
///   1. **任意切分点**：1 字节之外还测 3/7/13 字节等错位边界（跨帧半帧、
///      跨 \r|\n 切分）—— 会话状态在帧边界之外不得泄漏。
///   2. **截断流**：整场无 Finish 时，两条路径都必须闭合仍打开的块。
///   3. **会话复用**：一个会话对象的 finish() 幂等；新建会话不继承旧状态。

///|
/// 按固定步长切分喂入，收集全部输出帧
fn feed_chunked(
  source : String,
  target : String,
  sse : String,
  step : Int32,
) -> Result[Array[String], String] {
  match @sdk.StreamConverter::new(source, target) {
    Ok(conv) => {
      let out : Array[String] = []
      let mut i = 0
      while i < sse.length() {
        let end = if i + step < sse.length() { i + step } else { sse.length() }
        match conv.feed(sse[i:end].to_owned()) {
          Ok(frames) =>
            for f in frames {
              out.push(f)
            }
          Err(e) => return Err(e)
        }
        i = end
      }
      match conv.finish() {
        Ok(frames) =>
          for f in frames {
            out.push(f)
          }
        Err(e) => return Err(e)
      }
      Ok(out)
    }
    Err(e) => Err(e)
  }
}

///|
/// 多工具 + 文本混合流（工具索引切换 + 块复用，会话状态压力最大）
fn openai_rich_stream_fixture() -> String {
  "data: {\"id\":\"cc9\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
  "data: {\"id\":\"cc9\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"plan: \"}}]}\n\n" +
  "data: {\"id\":\"cc9\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f1\",\"arguments\":\"{\\\"a\\\"\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc9\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\":1}\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc9\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" then \"}}]}\n\n" +
  "data: {\"id\":\"cc9\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":1,\"id\":\"c2\",\"type\":\"function\",\"function\":{\"name\":\"f2\",\"arguments\":\"{\\\"b\\\":2}\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc9\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
  "data: {\"id\":\"cc9\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[],\"usage\":{\"prompt_tokens\":7,\"completion_tokens\":9,\"total_tokens\":16}}\n\n" +
  "data: [DONE]\n\n"
}

///|
/// 任意切分点下逐帧输出必须与整批一致（4 个目标 × 5 种步长）
test "chunked splitting - rich openai stream equals batch at every step" {
  let sse = openai_rich_stream_fixture()
  let targets = ["responses", "openai", "messages", "gemini"]
  let steps = [1, 3, 7, 13, 64]
  for target in targets {
    let batch = match @sdk.convert_stream("openai", sse, target) {
      Ok(r) => r.value()
      Err(e) => fail("batch " + target + " failed: " + e)
    }
    for step in steps {
      match feed_chunked("openai", target, sse, step) {
        Ok(frames) => {
          let inc = frames.join("")
          if inc != batch {
            fail(
              "openai->" +
              target +
              " step=" +
              step.to_string() +
              ": incremental != batch\n--- batch (" +
              batch.length().to_string() +
              ") ---\n" +
              batch +
              "\n--- incremental (" +
              inc.length().to_string() +
              ") ---\n" +
              inc,
            )
          }
        }
        Err(e) =>
          fail("openai->" + target + " step=" + step.to_string() + ": " + e)
      }
    }
  }
}

///|
/// 截断流（无 finish_reason / 无 [DONE]）：工具块未闭合，两条路径都必须
/// 闭合它（否则下游留下悬挂的 content_block / function_call item）
fn openai_truncated_tool_fixture() -> String {
  "data: {\"id\":\"ccT\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
  "data: {\"id\":\"ccT\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"c1\",\"type\":\"function\",\"function\":{\"name\":\"f1\",\"arguments\":\"{\\\"a\\\"\"}}]}}]}\n\n" +
  "data: {\"id\":\"ccT\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\":1}\"}}]}}]}\n"
}

///|
test "truncated stream - openai to messages closes open tool block in both paths" {
  let sse = openai_truncated_tool_fixture()
  let batch = match @sdk.convert_stream("openai", sse, "messages") {
    Ok(r) => r.value()
    Err(e) => fail("batch failed: " + e)
  }
  let inc = match feed_one_byte_chunks("openai", "messages", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("incremental failed: " + e)
  }
  assert_true(batch.contains("event: content_block_stop"))
  assert_true(inc.contains("event: content_block_stop"))
  if inc != batch {
    fail(
      "truncated openai->messages: incremental != batch\n--- batch ---\n" +
      batch +
      "\n--- incremental ---\n" +
      inc,
    )
  }
}

///|
test "truncated stream - openai to responses closes open tool block in both paths" {
  let sse = openai_truncated_tool_fixture()
  let batch = match @sdk.convert_stream("openai", sse, "responses") {
    Ok(r) => r.value()
    Err(e) => fail("batch failed: " + e)
  }
  let inc = match feed_one_byte_chunks("openai", "responses", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("incremental failed: " + e)
  }
  assert_true(batch.contains("response.output_item.done"))
  assert_true(inc.contains("response.output_item.done"))
  if inc != batch {
    fail(
      "truncated openai->responses: incremental != batch\n--- batch ---\n" +
      batch +
      "\n--- incremental ---\n" +
      inc,
    )
  }
}

///|
/// 截断流 + gemini 目标：工具块参数已跨帧累积但上游未给 BlockEnd ——
/// 增量路径必须在 finish() 时把累积参数发出（否则工具调用随流尾静默丢失）。
test "truncated stream - openai to gemini flushes pending tool args" {
  let sse = openai_truncated_tool_fixture()
  let inc = match feed_one_byte_chunks("openai", "gemini", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("incremental failed: " + e)
  }
  // 累积参数 {"a":1} 必须出现在某个 functionCall 中
  if !inc.contains("\"args\":{\"a\":1}") {
    fail("pending gemini tool args lost at stream end; got:\n" + inc)
  }
  // 不得输出空的 args（参数丢失的特征）
  assert_false(inc.contains("\"args\":{}"))
}

///|
/// finish() 幂等：二次调用不得重复产出终止符或内容
test "session - finish is idempotent" {
  let sse = openai_single_tool_stream_fixture()
  match @sdk.StreamConverter::new("openai", "messages") {
    Ok(conv) => {
      let first : Array[String] = []
      match conv.feed(sse) {
        Ok(f) =>
          for x in f {
            first.push(x)
          }
        Err(e) => fail("feed failed: " + e)
      }
      let tail1 = match conv.finish() {
        Ok(f) => f
        Err(e) => fail("finish failed: " + e)
      }
      let tail2 = match conv.finish() {
        Ok(f) => f
        Err(e) => fail("second finish failed: " + e)
      }
      assert_true(tail1.length() > 0)
      // 二次 finish 只返回本次冲刷（无尾部半帧 → 空），不得重复 message_stop
      assert_eq(tail2.length(), 0)
      let joined = first.join("") + tail1.join("")
      let stops = joined.split("event: message_stop").to_array().length() - 1
      assert_eq(stops, 1)
    }
    Err(e) => fail("new failed: " + e)
  }
}

///|
/// 会话隔离：同一 (source,target) 的新会话不得继承旧会话的跨帧状态
/// （块映射/计数器/累积参数必须是会话私有）
test "session - new session does not inherit previous state" {
  let sse = openai_single_tool_stream_fixture()
  let baseline = match feed_one_byte_chunks("openai", "responses", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("first run failed: " + e)
  }
  // 第二个独立会话必须产出与第一个逐字节相同的输出
  let second = match feed_one_byte_chunks("openai", "responses", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("second run failed: " + e)
  }
  assert_eq(second, baseline)
}
