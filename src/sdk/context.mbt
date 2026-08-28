///|
/// Context — 对话上下文构建器
///
/// 面向 L1/L2 开发者，隐藏 IR 类型细节。
/// 内部将用户输入转换为 LucentConversationItem。

///|
/// SdkMessage — SDK 层的消息表示
pub struct SdkMessage {
  role : String
  content : String
  /// 工具结果专用：关联的 tool_use_id（None 表示普通消息）
  tool_use_id : String?
  /// 工具结果专用：是否执行出错（默认 false）
  is_error : Bool?
}

///|
pub fn SdkMessage::new(role : String, content : String) -> SdkMessage {
  { role, content, tool_use_id: None, is_error: None }
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
  }
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
  { name, description, parameters_json }
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
  { system_prompt: None, messages: [], tools: None }
}

///|
/// 设置系统指令
pub fn Context::add_system(self : Context, prompt : String) -> Context {
  { ..self, system_prompt: Some(prompt) }
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
  { ..self, tools: Some(tools) }
}

///|

///|
/// 内部辅助：追加消息并返回新 Context（消除 add_* 中的 copy+push 样板）
fn Context::push_msg(self : Context, msg : SdkMessage) -> Context {
  let new_msgs = self.messages.copy()
  new_msgs.push(msg)
  { ..self, messages: new_msgs }
}
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
      None => {
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
