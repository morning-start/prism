///| MidRole — speaker role in a conversation

pub enum MidRole {
  System
  User
  Assistant
  Tool
} derive(Eq, Debug)

///| MidContent — content part within a message

pub enum MidContent {
  Text(String)
  ToolUse(String, String, String) // id, name, arguments_json
  ToolResult(String, String) // tool_call_id, content
} derive(Eq, Debug)

///| MidMessage — a single turn in the conversation

pub struct MidMessage {
  role: MidRole
  content: Array[MidContent]
} derive(Eq, Debug)

///| MidTool — tool/function definition exposed to the LLM

pub struct MidTool {
  name: String
  description: String
  parameters: String // JSON Schema as raw string
} derive(Eq, Debug)

///| MidRequest — a complete LLM request

pub struct MidRequest {
  model: String
  messages: Array[MidMessage]
  tools: Option[Array[MidTool]]
  temperature: Option[Double]
  max_tokens: Option[Int]
  stream: Bool
} derive(Eq, Debug)

///| MidUsage — token consumption report

pub struct MidUsage {
  prompt_tokens: Int
  completion_tokens: Int
  total_tokens: Int
} derive(Eq, Debug)

///| MidChoice — one candidate response

pub struct MidChoice {
  message: MidMessage
  finish_reason: String
} derive(Eq, Debug)

///| MidResponse — a non-streaming LLM response

pub struct MidResponse {
  id: String
  model: String
  choices: Array[MidChoice]
  usage: MidUsage
} derive(Eq, Debug)

///| MidToolCall — a function-call requested by the model

pub struct MidToolCall {
  id: String
  name: String
  arguments: String // JSON as raw string
} derive(Eq, Debug)

///| MidDelta — the delta payload in a streaming chunk

pub struct MidDelta {
  role: Option[MidRole]
  content: Option[String]
  tool_calls: Option[Array[MidToolCall]]
} derive(Eq, Debug)

///| MidStreamChoice — one choice in a stream chunk

pub struct MidStreamChoice {
  delta: MidDelta
  finish_reason: Option[String]
} derive(Eq, Debug)

///| MidStreamChunk — a single streaming chunk

pub struct MidStreamChunk {
  id: String
  model: String
  choices: Array[MidStreamChoice]
  usage: Option[MidUsage]
} derive(Eq, Debug)
