///|
/// 契约矩阵 4/5/6/7：含工具调用的流，增量路径必须与整批路径逐字节一致。
///
/// 背景：`stream_converter_test.mbt` 的逐字节断言只覆盖纯文本 fixture，
/// 工具调用（多帧累积参数、多块闭合）从未被验证。工具块的 done 事件依赖
/// 编码侧的块级簿记（累积参数、块→output_index 映射），若该状态放在编码
/// 函数的局部变量里，逐帧调用即丢失 —— 而整批调用因整条事件数组一次性
/// 传入而保留。本文件把"逐帧 == 整批"不变量扩展到工具调用场景。

///|
/// 多帧工具调用 fixture：2 个工具，参数各跨 1 帧（openai 的 tool_calls
/// 首帧带 id/name、续帧只带 arguments）。
fn openai_tool_stream_fixture() -> String {
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"city\\\"\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\":\\\"SH\\\"}\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":1,\"id\":\"call_2\",\"type\":\"function\",\"function\":{\"name\":\"get_time\",\"arguments\":\"\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":1,\"function\":{\"arguments\":\"{\\\"tz\\\":\\\"UTC\\\"}\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
  "data: [DONE]\n\n"
}

///|
/// 单工具调用 fixture（最小化 P0：一个工具块跨多帧）
fn openai_single_tool_stream_fixture() -> String {
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"function\":{\"arguments\":\"{\\\"city\\\":\\\"SH\\\"}\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
  "data: [DONE]\n\n"
}

///|
/// 文本 + 工具 + 文本 混合流（块闭合顺序两路径不一致的触发形态）
fn openai_text_tool_text_fixture() -> String {
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"tool_calls\":[{\"index\":0,\"id\":\"call_1\",\"type\":\"function\",\"function\":{\"name\":\"get_weather\",\"arguments\":\"{\\\"city\\\":\\\"SH\\\"}\"}}]}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"after\"}}]}\n\n" +
  "data: {\"id\":\"cc1\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"tool_calls\"}]}\n\n" +
  "data: [DONE]\n\n"
}

///|
/// 断言：增量输出（1 字节切分）与整批输出逐字节一致；不一致时给出可读差异。
fn assert_stream_equivalent(
  source : String,
  target : String,
  sse : String,
  label : String,
) -> Unit raise {
  let batch = match @sdk.convert_stream(source, sse, target) {
    Ok(r) => r.value()
    Err(e) => fail(label + ": batch convert failed: " + e)
  }
  let inc = match feed_one_byte_chunks(source, target, sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail(label + ": incremental failed: " + e)
  }
  if inc != batch {
    fail(
      label +
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

///|
/// gemini 源：多帧增量文本（gemini 用单个 \n 分隔消息）
fn gemini_text_stream_fixture() -> String {
  "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"Hel\"}]}}],\"responseId\":\"rid1\",\"modelVersion\":\"gemini-2.0\"}\n" +
  "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"lo\"}]}}]}\n" +
  "data: {\"candidates\":[{\"content\":{\"parts\":[]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":5,\"candidatesTokenCount\":2,\"totalTokenCount\":7}}\n"
}

///|
/// gemini 源：多帧文本 + 工具调用
fn gemini_tool_stream_fixture() -> String {
  "data: {\"candidates\":[{\"content\":{\"parts\":[{\"text\":\"hi\"}]}}],\"responseId\":\"rid2\",\"modelVersion\":\"gemini-2.0\"}\n" +
  "data: {\"candidates\":[{\"content\":{\"parts\":[{\"functionCall\":{\"name\":\"get_weather\",\"id\":\"fc_1\",\"args\":{\"city\":\"SH\"}}}]}}]}\n" +
  "data: {\"candidates\":[{\"content\":{\"parts\":[]},\"finishReason\":\"STOP\"}],\"usageMetadata\":{\"promptTokenCount\":5,\"candidatesTokenCount\":2,\"totalTokenCount\":7}}\n"
}

///|
/// messages 源：工具块（index 0）跨帧累积参数 + message_delta 用量
fn messages_tool_stream_fixture() -> String {
  "event: message_start\ndata: {\"type\":\"message_start\",\"message\":{\"id\":\"msg_1\",\"model\":\"claude\",\"usage\":{\"input_tokens\":10,\"output_tokens\":1}}}\n\n" +
  "event: content_block_start\ndata: {\"type\":\"content_block_start\",\"index\":0,\"content_block\":{\"type\":\"tool_use\",\"id\":\"tu_1\",\"name\":\"f\"}}\n\n" +
  "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\"{\\\"a\\\"\"}}\n\n" +
  "event: content_block_delta\ndata: {\"type\":\"content_block_delta\",\"index\":0,\"delta\":{\"type\":\"input_json_delta\",\"partial_json\":\":1}\"}}\n\n" +
  "event: content_block_stop\ndata: {\"type\":\"content_block_stop\",\"index\":0}\n\n" +
  "event: message_delta\ndata: {\"type\":\"message_delta\",\"delta\":{\"stop_reason\":\"tool_use\"},\"usage\":{\"output_tokens\":5}}\n\n" +
  "event: message_stop\ndata: {\"type\":\"message_stop\"}\n\n"
}

///|
/// responses 源：function_call 参数跨帧 + completed 用量
fn responses_tool_stream_fixture() -> String {
  "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_1\",\"created_at\":1,\"model\":\"gpt-5\"}}\n\n" +
  "event: response.output_item.added\ndata: {\"type\":\"response.output_item.added\",\"output_index\":0,\"item\":{\"type\":\"function_call\",\"id\":\"fc_1\",\"call_id\":\"fc_1\",\"name\":\"f\",\"arguments\":\"\"}}\n\n" +
  "event: response.function_call_arguments.delta\ndata: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"delta\":\"{\\\"a\\\"\"}\n\n" +
  "event: response.function_call_arguments.delta\ndata: {\"type\":\"response.function_call_arguments.delta\",\"output_index\":0,\"delta\":\":1}\"}\n\n" +
  "event: response.function_call_arguments.done\ndata: {\"type\":\"response.function_call_arguments.done\",\"output_index\":0}\n\n" +
  "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_1\",\"status\":\"completed\",\"usage\":{\"input_tokens\":3,\"output_tokens\":4,\"total_tokens\":7}}}\n\n"
}

///|
test "stream equivalence - openai to responses single tool call" {
  assert_stream_equivalent(
    "openai",
    "responses",
    openai_single_tool_stream_fixture(),
    "openai->responses single tool",
  )
}

///|
test "stream equivalence - openai to responses two tool calls" {
  assert_stream_equivalent(
    "openai",
    "responses",
    openai_tool_stream_fixture(),
    "openai->responses two tools",
  )
}

///|
test "stream equivalence - openai to messages two tool calls" {
  assert_stream_equivalent(
    "openai",
    "messages",
    openai_tool_stream_fixture(),
    "openai->messages two tools",
  )
}

///|
test "stream equivalence - openai to messages text then tool" {
  assert_stream_equivalent(
    "openai",
    "messages",
    openai_text_tool_text_fixture(),
    "openai->messages text/tool",
  )
}

///|
test "stream equivalence - openai to gemini two tool calls" {
  assert_stream_equivalent(
    "openai",
    "gemini",
    openai_tool_stream_fixture(),
    "openai->gemini two tools",
  )
}

///|
test "stream equivalence - openai to openai two tool calls" {
  assert_stream_equivalent(
    "openai",
    "openai",
    openai_tool_stream_fixture(),
    "openai->openai two tools",
  )
}

///|
test "stream equivalence - gemini to messages text (multi-frame)" {
  assert_stream_equivalent(
    "gemini",
    "messages",
    gemini_text_stream_fixture(),
    "gemini->messages text",
  )
}

///|
test "stream equivalence - gemini to responses text (multi-frame)" {
  assert_stream_equivalent(
    "gemini",
    "responses",
    gemini_text_stream_fixture(),
    "gemini->responses text",
  )
}

///|
test "stream equivalence - gemini to openai text (multi-frame)" {
  assert_stream_equivalent(
    "gemini",
    "openai",
    gemini_text_stream_fixture(),
    "gemini->openai text",
  )
}

///|
test "stream equivalence - gemini to messages tool call" {
  assert_stream_equivalent(
    "gemini",
    "messages",
    gemini_tool_stream_fixture(),
    "gemini->messages tool",
  )
}

///|
test "stream equivalence - messages to responses tool call" {
  assert_stream_equivalent(
    "messages",
    "responses",
    messages_tool_stream_fixture(),
    "messages->responses tool",
  )
}

///|
test "stream equivalence - messages to openai tool call" {
  assert_stream_equivalent(
    "messages",
    "openai",
    messages_tool_stream_fixture(),
    "messages->openai tool",
  )
}

///|
test "stream equivalence - messages to gemini tool call" {
  assert_stream_equivalent(
    "messages",
    "gemini",
    messages_tool_stream_fixture(),
    "messages->gemini tool",
  )
}

///|
test "stream equivalence - responses to messages tool call" {
  assert_stream_equivalent(
    "responses",
    "messages",
    responses_tool_stream_fixture(),
    "responses->messages tool",
  )
}

///|
test "stream equivalence - responses to responses tool call" {
  assert_stream_equivalent(
    "responses",
    "responses",
    responses_tool_stream_fixture(),
    "responses->responses tool",
  )
}

///|
test "stream equivalence - responses to openai tool call" {
  assert_stream_equivalent(
    "responses",
    "openai",
    responses_tool_stream_fixture(),
    "responses->openai tool",
  )
}

///|
/// P0 直接断言：openai→responses 增量路径必须产出 function_call_arguments.done
/// （整批路径有；状态丢失时该事件整体消失）。
test "stream equivalence - responses tool args done event survives incrementally" {
  let sse = openai_single_tool_stream_fixture()
  let batch = match @sdk.convert_stream("openai", sse, "responses") {
    Ok(r) => r.value()
    Err(e) => fail("batch failed: " + e)
  }
  let inc = match feed_one_byte_chunks("openai", "responses", sse) {
    Ok(frames) => frames.join("")
    Err(e) => fail("incremental failed: " + e)
  }
  assert_true(batch.contains("response.function_call_arguments.done"))
  if !inc.contains("response.function_call_arguments.done") {
    fail(
      "incremental openai->responses dropped function_call_arguments.done; got:\n" +
      inc,
    )
  }
}
