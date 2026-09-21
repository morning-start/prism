///|
/// ═══ 功能组：context（Agent 状态）═══
/// Context/SdkMessage/SdkTool 构建与 context_to_lux_request。

///|
/// Context — 对话上下文构建器
///
/// 面向 L1/L2 开发者，隐藏 IR 类型细节。
/// 内部将用户输入转换为 LucentConversationItem。

///|
/// SdkToolCall — SDK 层的 assistant 工具调用回合
///
/// Agent 循环第二轮必需：模型发出 tool_call 后，transcript 中必须先有
/// 对应的 assistant tool_use 回合，provider（Anthropic/OpenAI 均硬校验）
/// 才接受紧随其后的 tool_result。
pub struct SdkToolCall {
  id : String
  name : String
  arguments_json : String
}

///|
pub fn SdkToolCall::new(
  id : String,
  name : String,
  arguments_json : String,
) -> SdkToolCall {
  { id, name, arguments_json, }
}

///|
/// SdkMessage — SDK 层的消息表示
pub struct SdkMessage {
  role : String
  content : String
  /// 工具结果专用：关联的 tool_use_id（None 表示普通消息）
  tool_use_id : String?
  /// 工具结果专用：是否执行出错（默认 false）
  is_error : Bool?
  /// assistant 工具调用专用：空数组表示普通消息（见 SdkMessage::tool_call）
  tool_calls : Array[SdkToolCall]
}

///|
pub fn SdkMessage::new(role : String, content : String) -> SdkMessage {
  { role, content, tool_use_id: None, is_error: None, tool_calls: [], }
}

///|
/// 构造工具结果消息（Agent 循环注入工具执行结果用）
pub fn SdkMessage::tool_result(
  tool_use_id : String,
  content : String,
  is_error : Bool,
) -> SdkMessage {
  {
    role: "tool",
    content,
    tool_use_id: Some(tool_use_id),
    is_error: Some(is_error),
    tool_calls: [],
  }
}

///|
/// 构造 assistant 工具调用消息（Agent 循环第一轮回填用，单个调用）
///
/// role 固定为 "assistant"；content 可携带同回合的文本（混合输出）。
pub fn SdkMessage::tool_call(
  id : String,
  name : String,
  arguments_json : String,
  content : String,
) -> SdkMessage {
  SdkMessage::assistant_turn(content, [
    SdkToolCall::new(id, name, arguments_json),
  ])
}

///|
/// 构造 assistant 回合消息（文本 + 任意数量工具调用合并为一条消息）
///
/// 回合级语义：一个 assistant 回合的文本与全部 tool_use 必须在同一条
/// 消息里，provider（Anthropic/OpenAI）才接受紧随其后的 tool_result。
pub fn SdkMessage::assistant_turn(
  content : String,
  tool_calls : Array[SdkToolCall],
) -> SdkMessage {
  { role: "assistant", content, tool_use_id: None, is_error: None, tool_calls, }
}

///|
/// SdkTool — SDK 层的工具定义
pub struct SdkTool {
  name : String
  description : String
  parameters_json : String
}

///|
pub fn SdkTool::new(
  name : String,
  description : String,
  parameters_json : String,
) -> SdkTool {
  { name, description, parameters_json, }
}

///|
/// Context — 对话上下文
pub struct Context {
  system_prompt : String?
  messages : Array[SdkMessage]
  tools : Array[SdkTool]?
}

///|
pub fn Context::new() -> Context {
  { system_prompt: None, messages: [], tools: None, }
}

///|
/// 设置系统指令
pub fn Context::add_system(self : Context, prompt : String) -> Context {
  { ..self, system_prompt: Some(prompt), }
}

///|
/// 添加用户消息
pub fn Context::add_user(self : Context, text : String) -> Context {
  self.push_msg(SdkMessage::new("user", text))
}

///|
/// 添加助手消息
pub fn Context::add_assistant(self : Context, text : String) -> Context {
  self.push_msg(SdkMessage::new("assistant", text))
}

///|
/// 添加工具
pub fn Context::add_tools(self : Context, tools : Array[SdkTool]) -> Context {
  { ..self, tools: Some(tools), }
}

///|

///|
/// 内部辅助：追加消息并返回新 Context（消除 add_* 中的 copy+push 样板）
fn Context::push_msg(self : Context, msg : SdkMessage) -> Context {
  let new_msgs = self.messages.copy()
  new_msgs.push(msg)
  { ..self, messages: new_msgs, }
}

///|
/// 注入工具执行结果（Agent 循环：执行工具后继续对话）
pub fn Context::add_tool_result(
  self : Context,
  tool_use_id : String,
  content : String,
  is_error : Bool,
) -> Context {
  self.push_msg(SdkMessage::tool_result(tool_use_id, content, is_error))
}

///|
/// 回填 assistant 工具调用回合（Agent 循环：模型要求调用工具后、
/// 注入 tool_result 之前，必须先补这一回合，否则第二轮请求会被
/// provider 拒绝——tool_result 必须紧跟含 tool_use 的 assistant 消息）
pub fn Context::add_tool_call(
  self : Context,
  id : String,
  name : String,
  arguments_json : String,
  content : String,
) -> Context {
  self.push_msg(SdkMessage::tool_call(id, name, arguments_json, content))
}

///|
/// 回填整个 assistant 回合（文本 + 任意数量工具调用合并为一条消息）
///
/// Agent 循环回填闭环用：`Prism::events_to_context` 内部调用。
pub fn Context::add_assistant_turn(
  self : Context,
  text : String,
  tool_calls : Array[SdkToolCall],
) -> Context {
  self.push_msg(SdkMessage::assistant_turn(text, tool_calls))
}

///|
/// 将 Context 转为 LucentRequest（SDK 内部使用）
pub fn context_to_lux_request(
  ctx : Context,
  model : String,
  opts : PrismOptions,
) -> @lux.LucentRequest {
  let items : Array[@lux.LucentConversationItem] = []
  for msg in ctx.messages {
    match msg.tool_use_id {
      Some(id) => {
        // 工具结果消息 → Item::ToolResult（Agent 循环注入）
        let is_err = match msg.is_error {
          Some(b) => b
          None => false
        }
        items.push(
          @lux.LucentConversationItem::tool_result(
            @lux.LucentToolResult::new(
              id,
              [@lux.LucentContent::text(msg.content)],
              is_err,
            ),
          ),
        )
      }
      None =>
        // assistant 工具调用回合 → Message{Assistant, [Text?, ToolUse...]}
        // 与 provider 入站解码形态一致（openai append_tool_calls）
        if msg.tool_calls.length() > 0 {
          let content : Array[@lux.LucentContent] = []
          if msg.content != "" {
            content.push(@lux.LucentContent::text(msg.content))
          }
          for tc in msg.tool_calls {
            content.push(
              @lux.LucentContent::tool_use(
                tc.id,
                tc.name,
                tc.arguments_json,
                None,
              ),
            )
          }
          let lmsg = @lux.LucentMessage::new(Assistant, content)
          items.push(@lux.LucentConversationItem::message(lmsg))
        } else {
          let role = match msg.role {
            "system" => @lux.System
            "user" => User
            "assistant" => Assistant
            "tool" => Tool
            _ => User
          }
          let content = [@lux.LucentContent::text(msg.content)]
          let lmsg = @lux.LucentMessage::new(role, content)
          items.push(@lux.LucentConversationItem::message(lmsg))
        }
    }
  }
  let tools_arr = match ctx.tools {
    Some(tools) => {
      let arr : Array[@lux.LucentTool] = []
      for t in tools {
        arr.push(
          @lux.LucentTool::simple(t.name, t.description, t.parameters_json),
        )
      }
      Some(arr)
    }
    None => None
  }
  let lux_opts = @lux.LucentOptions::new(
    opts.temperature,
    None,
    None,
    opts.max_tokens,
    None,
    false,
    None,
    None,
    opts.store,
    opts.extras,
  )
  @lux.LucentRequest::new(
    model,
    match ctx.system_prompt {
      Some(s) => Some([@lux.LucentContent::text(s)])
      None => None
    },
    items,
    tools_arr,
    None,
    lux_opts,
    None,
    None,
    None,
    None,
  )
}
