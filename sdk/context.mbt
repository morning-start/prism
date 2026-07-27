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
}

///|
/// SdkTool — SDK 层的工具定义
pub struct SdkTool {
  name : String
  description : String
  parameters_json : String
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
  let new_msgs = self.messages
  new_msgs.push({ role: "user", content: text })
  { ..self, messages: new_msgs }
}

///|
/// 添加助手消息
pub fn Context::add_assistant(self : Context, text : String) -> Context {
  let new_msgs = self.messages
  new_msgs.push({ role: "assistant", content: text })
  { ..self, messages: new_msgs }
}

///|
/// 添加工具
pub fn Context::add_tools(self : Context, tools : Array[SdkTool]) -> Context {
  { ..self, tools: Some(tools) }
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
    let role = match msg.role {
      "system" => @lux.System
      "user" => @lux.User
      "assistant" => @lux.Assistant
      "tool" => @lux.Tool
      _ => @lux.User
    }
    let content = [@lux.LucentContent::text(msg.content)]
    let lmsg = @lux.LucentMessage::new(role, content)
    items.push(@lux.LucentConversationItem::message(lmsg))
  }
  let tools_arr = match ctx.tools {
    Some(tools) => {
      let arr : Array[@lux.LucentTool] = []
      for t in tools {
        arr.push(@lux.LucentTool::simple(t.name, t.description, t.parameters_json))
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
