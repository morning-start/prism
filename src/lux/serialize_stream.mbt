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
        "index": idx.to_json(),
        "item": item.to_json(),
      })
    BlockStart(idx, bt) =>
      Json::object({
        "event": Json::string("block_start"),
        "index": idx.to_json(),
        "block_type": bt.to_json(),
      })
    BlockDelta(idx, delta) =>
      Json::object({
        "event": Json::string("block_delta"),
        "index": idx.to_json(),
        "delta": delta.to_json(),
      })
    BlockEnd(idx) =>
      Json::object({
        "event": Json::string("block_end"),
        "index": idx.to_json(),
      })
    ItemEnd(idx) =>
      Json::object({ "event": Json::string("item_end"), "index": idx.to_json() })
    BlockDiscard(idx) =>
      Json::object({
        "event": Json::string("block_discard"),
        "index": idx.to_json(),
      })
    Annotations(idx, anns) =>
      Json::object({
        "event": Json::string("annotations"),
        "index": idx.to_json(),
        "annotations": Json::array(anns.map(fn(a) { a.to_json() })),
      })
    Finish(fr) =>
      Json::object({
        "event": Json::string("finish"),
        "finish_reason": fr.to_json(),
      })
    Usage(u) =>
      Json::object({ "event": Json::string("usage"), "usage": u.to_json() })
    Error(e) =>
      Json::object({ "event": Json::string("error"), "error": e.to_json() })
    Done => Json::object({ "event": Json::string("done") })
  }
}
