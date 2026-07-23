test "construct MidMessage" {
  let msg = MidMessage::{ role: MidRole::User, content: [MidContent::Text("hello")] }
  assert_eq(msg.role, MidRole::User)
  assert_eq(msg.content[0], MidContent::Text("hello"))
}

test "construct MidRequest" {
  let req = MidRequest::{
    model: "gpt-4o",
    messages: [{ role: MidRole::User, content: [MidContent::Text("hi")] }],
    tools: None,
    temperature: Some(0.7),
    max_tokens: None,
    stream: false,
  }
  assert_eq(req.model, "gpt-4o")
  assert_eq(req.temperature, Some(0.7))
}

test "construct MidResponse" {
  let resp = MidResponse::{
    id: "resp-1",
    model: "gpt-4o",
    choices: [{
      message: { role: MidRole::Assistant, content: [MidContent::Text("hello there")] },
      finish_reason: "stop",
    }],
    usage: { prompt_tokens: 10, completion_tokens: 5, total_tokens: 15 },
  }
  assert_eq(resp.id, "resp-1")
  assert_eq(resp.usage.prompt_tokens, 10)
}

test "construct MidToolCall" {
  let tc = MidToolCall::{ id: "call-1", name: "get_weather", arguments: "{\"city\": \"Beijing\"}" }
  assert_eq(tc.name, "get_weather")
}

test "construct MidDelta" {
  let delta = MidDelta::{ role: Some(MidRole::Assistant), content: Some("Hello"), tool_calls: None }
  assert_eq(delta.content, Some("Hello"))
}

test "construct MidStreamChunk" {
  let chunk = MidStreamChunk::{
    id: "chunk-1",
    model: "gpt-4o",
    choices: [{
      delta: { role: Some(MidRole::Assistant), content: Some("Hello"), tool_calls: None },
      finish_reason: None,
    }],
    usage: None,
  }
  assert_eq(chunk.id, "chunk-1")
}

test "MidContent equality" {
  let a = MidContent::Text("ok")
  let b = MidContent::Text("ok")
  let c = MidContent::Text("no")
  assert_eq(a, b)
  assert_true(a != c)
}

test "construct empty messages array" {
  let msgs: Array[MidMessage] = []
  assert_eq(msgs.length(), 0)
}

test "construct with tool calls in message" {
  let msg = MidMessage::{
    role: MidRole::Assistant,
    content: [
      MidContent::Text("I'll check the weather"),
      MidContent::ToolUse("call-1", "get_weather", "{\"city\":\"Beijing\"}"),
    ],
  }
  assert_eq(msg.content.length(), 2)
}

test "MidUsage round trip" {
  let u = MidUsage::{ prompt_tokens: 100, completion_tokens: 50, total_tokens: 150 }
  assert_eq(u.prompt_tokens + u.completion_tokens, u.total_tokens)
}

test "MidOption defaults" {
  let req = MidRequest::{
    model: "gpt-4o-mini",
    messages: [{ role: MidRole::User, content: [MidContent::Text("test")] }],
    tools: None,
    temperature: None,
    max_tokens: None,
    stream: true,
  }
  assert_true(req.stream)
  assert_eq(req.temperature, None)
}
