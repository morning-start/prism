///|
/// StreamConverter 增量流转换测试（T5）
///
/// 核心验收：1 字节 chunk 切分喂入，输出与整缓冲 convert_stream
/// 逐字节一致（帧边界半帧缓冲 + 跨帧 ctx 传递共同保证）。

///|
/// 真实形态 openai SSE fixture（id/model/created + 文本 + finish + usage + DONE）
fn openai_sse_fixture() -> String {
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"role\":\"assistant\"}}]}\n\n" +
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"Hello\"}}]}\n\n" +
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\" world\"}}]}\n\n" +
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}\n\n" +
  "data: {\"id\":\"chatcmpl-abc\",\"object\":\"chat.completion.chunk\",\"created\":1700000000,\"model\":\"gpt-4o\",\"choices\":[],\"usage\":{\"prompt_tokens\":10,\"completion_tokens\":2,\"total_tokens\":12}}\n\n" +
  "data: [DONE]\n\n"
}

///|
/// 1 字节切分喂入，收集所有输出帧
fn feed_one_byte_chunks(
  source : String,
  target : String,
  sse : String,
) -> Result[Array[String], String] {
  match @sdk.StreamConverter::new(source, target) {
    Ok(conv) => {
      let out : Array[String] = []
      let mut i = 0
      while i < sse.length() {
        let ch = sse[i:i + 1].to_owned()
        match conv.feed(ch) {
          Ok(frames) =>
            for f in frames {
              out.push(f)
            }
          Err(e) => return Err(e)
        }
        i = i + 1
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
test "StreamConverter - openai to messages 1-byte chunks byte-identical" {
  let sse = openai_sse_fixture()
  match @sdk.convert_stream("openai", sse, "messages") {
    Ok(base) =>
      match feed_one_byte_chunks("openai", "messages", sse) {
        Ok(frames) => {
          assert_true(frames.length() > 0)
          // 每帧编码输出自带 "\n\n" 结尾，拼接后与整缓冲一致
          assert_eq(frames.join(""), base.value())
        }
        Err(e) => fail("feed failed: " + e)
      }
    Err(e) => fail("convert_stream failed: " + e)
  }
}

///|
/// openai → openai：ctx 传递保证后续帧 chunk 的 id/model 不丢
test "StreamConverter - openai to openai preserves stream context" {
  let sse = openai_sse_fixture()
  match @sdk.convert_stream("openai", sse, "openai") {
    Ok(base) =>
      match feed_one_byte_chunks("openai", "openai", sse) {
        Ok(frames) => {
          assert_eq(frames.join(""), base.value())
          // ctx 起效：每个 data chunk 都带源 id
          assert_true(frames.join("").contains("chatcmpl-abc"))
        }
        Err(e) => fail("feed failed: " + e)
      }
    Err(e) => fail("convert_stream failed: " + e)
  }
}

///|
/// responses → messages：response.created 的 id 经 ctx 复用到收尾帧
test "StreamConverter - responses to messages preserves response id" {
  let sse = "event: response.created\ndata: {\"type\":\"response.created\",\"response\":{\"id\":\"resp_xyz\",\"created_at\":1700000000,\"model\":\"gpt-5\"}}\n\n" +
    "event: response.output_text.delta\ndata: {\"type\":\"response.output_text.delta\",\"content_index\":0,\"delta\":\"Hi\"}\n\n" +
    "event: response.completed\ndata: {\"type\":\"response.completed\",\"response\":{\"id\":\"resp_xyz\",\"status\":\"completed\"}}\n\n"
  match @sdk.convert_stream("responses", sse, "messages") {
    Ok(base) =>
      match feed_one_byte_chunks("responses", "messages", sse) {
        Ok(frames) => assert_eq(frames.join(""), base.value())
        Err(e) => fail("feed failed: " + e)
      }
    Err(e) => fail("convert_stream failed: " + e)
  }
}

///|
test "StreamConverter - unknown provider returns error" {
  match @sdk.StreamConverter::new("no-such", "messages") {
    Err(e) => assert_true(e.contains("unknown provider"))
    Ok(_) => fail("expected error")
  }
}

///|
/// finish 冲刷无尾部空行的半帧
test "StreamConverter - finish flushes trailing frame" {
  match @sdk.StreamConverter::new("openai", "messages") {
    Ok(conv) => {
      // 最后一块无尾部空行
      let sse = "data: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{\"content\":\"tail\"}}]}\n\ndata: {\"id\":\"c1\",\"object\":\"chat.completion.chunk\",\"created\":1,\"model\":\"m\",\"choices\":[{\"index\":0,\"delta\":{},\"finish_reason\":\"stop\"}]}"
      match conv.feed(sse) {
        Ok(frames) => {
          // 第一帧完整转换
          assert_true(frames.length() >= 1)
          match conv.finish() {
            Ok(tail) => {
              // 半帧（finish 帧）在 finish 时转换产出
              assert_true(tail.length() >= 1)
              let all = frames.join("") + tail.join("")
              assert_true(all.contains("tail"))
            }
            Err(e) => fail("finish failed: " + e)
          }
        }
        Err(e) => fail("feed failed: " + e)
      }
    }
    Err(e) => fail("new failed: " + e)
  }
}
