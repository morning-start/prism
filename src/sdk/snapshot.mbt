///|
/// ═══ 功能组：snapshot（会话快照存储，T8 stage B）═══
/// ConversationStore（宿主注入 KV）+ 快照还原 + convert_request_with_store。
///
/// 背景（IR 治理：docs/lux-ir-design.md ConversationSnapshot 节 +
/// docs/rules/lucent-ir-evolution.md）：
/// Responses 的 previous_response_id 是有状态续接——客户端第二轮只带新
/// input + 上一轮 response id，历史在服务端。中间件把它转到无状态端点
/// （chat/messages/gemini）时，必须本地保存 response_id → 会话快照，
/// 编码前还原历史，否则第二轮必败（最小矩阵 #10 的拒绝语义）。
///
/// 与 wasm 无状态导出兼容：存储由宿主持有（闭包/外部 KV），SDK 只持有
/// get/put 函数对。

///|
/// ConversationStore — 宿主注入的会话快照存储
///
/// get：按 response_id 取快照（无则 None）
/// put：存快照（同 id 覆盖）
pub struct ConversationStore {
  get : (String) -> @lux.ConversationSnapshot?
  put : (@lux.ConversationSnapshot) -> Unit
}

///|
pub fn ConversationStore::new(
  get : (String) -> @lux.ConversationSnapshot?,
  put : (@lux.ConversationSnapshot) -> Unit,
) -> ConversationStore {
  { get, put, }
}

///|
/// 取请求的 previous_response_id（标准字段优先，extras 旧载荷回退）
pub fn previous_response_id_of(req : @lux.LucentRequest) -> String? {
  match req.options.previous_response_id {
    Some(id) => Some(id)
    None =>
      match req.options.extras {
        Some(m) =>
          match m.get("previous_response_id") {
            Some(String(id)) => Some(id)
            _ => None
          }
        None => None
      }
  }
}

///|
/// 快照还原：快照历史 + 新请求项合并为完整对话
///
/// 规则：
/// - conversation：快照请求的会话项全部在前，新请求项追加在后
/// - instructions / tools / tool_choice：新请求优先，缺失时继承快照
/// - options / capabilities / reasoning / metadata / extra：取新请求
/// - previous_response_id **保留**：responses → responses 时后端仍持
///   有状态（正确续接）；无状态目标端由编码器既有逻辑剔除并打诊断
pub fn restore_request_from_snapshot(
  req : @lux.LucentRequest,
  snapshot : @lux.ConversationSnapshot,
) -> @lux.LucentRequest {
  let merged : Array[@lux.LucentConversationItem] = []
  for item in snapshot.request.conversation {
    merged.push(item)
  }
  for item in req.conversation {
    merged.push(item)
  }
  let instructions = match req.instructions {
    Some(i) => Some(i)
    None => snapshot.request.instructions
  }
  let tools = match req.tools {
    Some(t) => Some(t)
    None => snapshot.request.tools
  }
  let tool_choice = match req.tool_choice {
    Some(tc) => Some(tc)
    None => snapshot.request.tool_choice
  }
  @lux.LucentRequest::new(
    req.model,
    instructions,
    merged,
    tools,
    tool_choice,
    req.options,
    req.capabilities,
    req.reasoning,
    req.metadata,
    req.extra,
  )
}

///|
/// 从「已解码请求 + 已解码响应」构造并存储快照（中间件转发成功后调用）
pub fn store_snapshot_from_response(
  store : ConversationStore,
  req : @lux.LucentRequest,
  response : @lux.LucentResponse,
) -> Unit {
  (store.put)(
    @lux.ConversationSnapshot::new(response.id, req, Some(response.get_text())),
  )
}

///|
/// 需要时还原：
/// - 无 previous_response_id → 原样返回
/// - 有快照 → 还原（Responses 的 input 只是新项，快照历史 + 新项合并）
/// - 无快照但请求自带内容 → 原样返回（目标端编码器剔除 id 并打诊断）
/// - 无快照且无内容 → 显式拒绝（无可恢复历史，不允许伪造续接——矩阵 #10）
fn maybe_restore_request(
  req : @lux.LucentRequest,
  store : ConversationStore,
) -> Result[@lux.LucentRequest, String] {
  match previous_response_id_of(req) {
    None => Ok(req)
    Some(prev_id) =>
      match (store.get)(prev_id) {
        Some(snap) => Ok(restore_request_from_snapshot(req, snap))
        None =>
          if req.conversation.length() > 0 {
            Ok(req)
          } else {
            Err(
              "no local snapshot for previous_response_id '" +
              prev_id +
              "': stateless continuation cannot be converted without history",
            )
          }
      }
  }
}

///|
/// convert_request_with_store — 请求转换 + 会话快照还原（T8）
///
/// 管线：source decode →（previous_response_id 且无历史 → 快照还原）
/// → target encode。诊断按 decode/encode 两段合并。
/// 无快照时显式 Err（与直接 convert_request 的拒绝语义一致）。
pub fn convert_request_with_store(
  source : String,
  json_str : String,
  target : String,
  store : ConversationStore,
) -> Result[@lux.ConversionResult[String], String] {
  match resolve_pair(source, target) {
    Ok((src, dst)) =>
      match (src.request_decode)(json_str) {
        Ok(dcr) =>
          match maybe_restore_request(dcr.value(), store) {
            Ok(restored) =>
              match (dst.request_encode)(restored) {
                Ok(ecr) => Ok(ecr.with_diagnostics(dcr.diagnostics()))
                Err(e) => Err(e)
              }
            Err(e) => Err(e)
          }
        Err(e) => Err(e)
      }
    Err(e) => Err(e)
  }
}
