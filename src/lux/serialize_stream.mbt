///|
/// LucentStreamEvent JSON 序列化
pub fn LucentBlockType::to_json(self : LucentBlockType) -> Json {
  match self {
    Text => Json::string("text")
    ToolCall(id, name) =>
      Json::object({
        "type": Json::string("tool_call"),
        "id": Json::string(id),
        "name": Json::string(name),
      })
    Thinking => Json::string("thinking")
    Refusal => Json::string("refusal")
    Image => Json::string("image")
    Audio => Json::string("audio")
    Video => Json::string("video")
    Native(tag) => Json::string(tag)
  }
}

///|
pub fn LucentBlockDelta::to_json(self : LucentBlockDelta) -> Json {
  match self {
    TextDelta(s) =>
      Json::object({ "type": Json::string("text"), "text": Json::string(s) })
    ThinkingDelta(s) =>
      Json::object({ "type": Json::string("thinking"), "text": Json::string(s) })
    SignatureDelta(s) =>
      Json::object({
        "type": Json::string("signature"),
        "signature": Json::string(s),
      })
    ToolArgumentsDelta(s) =>
      Json::object({
        "type": Json::string("tool_arguments"),
        "arguments": Json::string(s),
      })
    RefusalDelta(s) =>
      Json::object({ "type": Json::string("refusal"), "text": Json::string(s) })
    NativeDelta(tag, raw) =>
      Json::object({
        "type": Json::string("native"),
        "native_tag": Json::string(tag),
        "native_payload": raw,
      })
  }
}

///|
pub fn LucentStreamEvent::to_json(self : LucentStreamEvent) -> Json {
  match self {
    ConversationStart(meta) =>
      Json::object({
        "event": Json::string("conversation_start"),
        "meta": meta.to_json(),
      })
    ItemStart(idx, item) =>
      Json::object({
        "event": Json::string("item_start"),
        "index": Json(idx),
        "item": item.to_json(),
      })
    BlockStart(idx, bt) =>
      Json::object({
        "event": Json::string("block_start"),
        "index": Json(idx),
        "block_type": bt.to_json(),
      })
    BlockDelta(idx, delta) =>
      Json::object({
        "event": Json::string("block_delta"),
        "index": Json(idx),
        "delta": delta.to_json(),
      })
    BlockEnd(idx) =>
      Json::object({ "event": Json::string("block_end"), "index": Json(idx) })
    ItemEnd(idx) =>
      Json::object({ "event": Json::string("item_end"), "index": Json(idx) })
    BlockDiscard(idx) =>
      Json::object({
        "event": Json::string("block_discard"),
        "index": Json(idx),
      })
    Annotations(idx, anns) =>
      Json::object({
        "event": Json::string("annotations"),
        "index": Json(idx),
        "annotations": Json::array(anns.map(fn(a) { a.to_json() })),
      })
    Finish(fr, ss) => {
      let m : Map[String, Json] = Map([])
      m["event"] = Json::string("finish")
      m["finish_reason"] = fr.to_json()
      // CR-006 批次 2：命中序列可选键。None 时不输出 —— 与 0.1.x 字节形态
      // 兼容（治理 §5 迁移策略第 3 条：只读 finish_reason 的旧消费端不受影响）。
      match ss {
        Some(v) => m["stop_sequence"] = Json::string(v)
        None => ()
      }
      Json::object(m)
    }
    Usage(u) =>
      Json::object({ "event": Json::string("usage"), "usage": u.to_json() })
    Error(e) =>
      Json::object({ "event": Json::string("error"), "error": e.to_json() })
    Done => Json::object({ "event": Json::string("done") })
  }
}
