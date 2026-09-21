///|
/// 会话快照存储与还原测试（T8 stage B）
///
/// 覆盖 ConversationStore / restore_request_from_snapshot /
/// convert_request_with_store / store_snapshot_from_response：
///   - 还原合并快照历史 + 新请求项（新字段优先，缺失继承快照）
///   - 中间件两轮模拟：turn1 解码→存储 → turn2 带 previous_response_id
///     还原 → 编码到无状态端点
///   - 无快照显式拒绝（矩阵 #10 语义保持）
///   - 有历史时原样透传（不咨询存储）

///|
/// 内存 Store（测试用）：Map + 闭包
fn mem_store() -> (
  @sdk.ConversationStore,
  Map[String, @lux.ConversationSnapshot],
) {
  let snapshots : Map[String, @lux.ConversationSnapshot] = Map([])
  let store = @sdk.ConversationStore::new(
    fn(id : String) -> @lux.ConversationSnapshot? { snapshots.get(id) },
    fn(snap : @lux.ConversationSnapshot) -> Unit {
      snapshots[snap.response_id] = snap
    },
  )
  (store, snapshots)
}

///|
/// turn-1 请求（Responses 形态，含一轮对话）
fn turn1_request() -> @lux.LucentRequest {
  @lux.LucentRequest::new(
    "gpt-5.3",
    Some([@lux.LucentContent::text("You are a weather bot")]),
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::text("weather in SH?"),
        ]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
}

///|
test "restore_request_from_snapshot - merges history and new items" {
  let snapshot = @lux.ConversationSnapshot::new(
    "resp_1",
    turn1_request(),
    Some("sunny"),
  )
  // 第二轮请求：只有新 input，无历史
  let turn2 = @lux.LucentRequest::new(
    "gpt-5.3",
    None,
    [
      @lux.LucentConversationItem::message(
        @lux.LucentMessage::new(User, [
          @lux.LucentContent::text("and tomorrow?"),
        ]),
      ),
    ],
    None,
    None,
    @lux.LucentOptions::default().with_previous_response_id(Some("resp_1")),
    None,
    None,
    None,
    None,
  )
  let restored = @sdk.restore_request_from_snapshot(turn2, snapshot)
  // 历史 1 条 + 新 1 条
  assert_eq(restored.conversation.length(), 2)
  // instructions 新请求缺失 → 继承快照
  match restored.instructions {
    Some(instr) => assert_eq(instr.length(), 1)
    None => fail("expected inherited instructions")
  }
  // previous_response_id 保留（responses→responses 续接仍正确）
  assert_eq(restored.options.previous_response_id, Some("resp_1"))
}

///|
test "restore_request_from_snapshot - new fields win over snapshot" {
  let snapshot = @lux.ConversationSnapshot::new("resp_1", turn1_request(), None)
  let turn2 = @lux.LucentRequest::new(
    "gpt-5.3",
    Some([@lux.LucentContent::text("new system")]),
    [],
    None,
    None,
    @lux.LucentOptions::default(),
    None,
    None,
    None,
    None,
  )
  let restored = @sdk.restore_request_from_snapshot(turn2, snapshot)
  match restored.instructions {
    Some(instr) => {
      assert_eq(instr.length(), 1)
      match instr[0] {
        Text(s, _) => assert_eq(s, "new system")
        _ => fail("expected text")
      }
    }
    None => fail("expected instructions")
  }
}

///|
/// 中间件两轮模拟：turn1 解码 → 存储快照 → turn2 还原 → 编码到 messages
test "convert_request_with_store - middleware two-turn simulation" {
  let (store, _) = mem_store()
  // --- turn 1：客户端首轮请求（无 previous_response_id）---
  let turn1_json = "{\"model\":\"gpt-5.3\",\"instructions\":\"You are a weather bot\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"weather in SH?\"}]}]}"
  match @sdk.convert_request("responses", turn1_json, "messages") {
    Ok(_) =>
      // 解码首轮请求并存储快照（以响应 id 为键）
      match @responses.responses_to_lux_request(turn1_json) {
        Ok(cr) => {
          let resp = @lux.LucentResponse::new(
            "resp_1",
            "gpt-5.3",
            None,
            [
              @lux.LucentChoice::new(
                0,
                @lux.LucentMessage::new(Assistant, [
                  @lux.LucentContent::text("sunny"),
                ]),
                Stop,
                None,
              ),
            ],
            None,
            None,
          )
          @sdk.store_snapshot_from_response(store, cr.value(), resp)
        }
        Err(e) => fail("turn1 decode failed: \{e}")
      }
    Err(e) => fail("turn1 convert failed: \{e}")
  }
  // --- turn 2：客户端只带 previous_response_id + 新 input ---
  let turn2_json = "{\"model\":\"gpt-5.3\",\"previous_response_id\":\"resp_1\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"and tomorrow?\"}]}]}"
  match
    @sdk.convert_request_with_store("responses", turn2_json, "messages", store) {
    Ok(cr) => {
      let json = cr.value()
      // 还原后的完整对话：首轮问题 + 第二轮问题都在
      assert_true(json.contains("weather in SH?"))
      assert_true(json.contains("and tomorrow?"))
      // 系统指令从快照继承
      assert_true(json.contains("You are a weather bot"))
      // previous_response_id 不得落入 Anthropic 请求体
      assert_false(json.contains("previous_response_id"))
    }
    Err(e) => fail("turn2 convert failed: \{e}")
  }
}

///|
/// 无快照且请求无内容：显式拒绝（不允许伪造续接——矩阵 #10）
test "convert_request_with_store - missing snapshot rejects" {
  let (store, _) = mem_store()
  // 纯续接请求：只有 previous_response_id，input 为空（无任何可发送内容）
  let turn2_json = "{\"model\":\"gpt-5.3\",\"previous_response_id\":\"resp_missing\",\"input\":[]}"
  match
    @sdk.convert_request_with_store("responses", turn2_json, "messages", store) {
    Ok(_) => fail("expected rejection without snapshot")
    Err(e) => assert_true(e.contains("previous_response_id"))
  }
}

///|
/// 无快照但请求自带内容：原样透传（目标端剔除 id 并打 Unsupported 诊断）
test "convert_request_with_store - with content passes through" {
  let (store, _) = mem_store()
  // 带完整历史的请求（首轮已在 conversation 中）
  let json = "{\"model\":\"gpt-5.3\",\"previous_response_id\":\"resp_x\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"first\"}]},{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"second\"}]}]}"
  match @sdk.convert_request_with_store("responses", json, "messages", store) {
    Ok(cr) => {
      // 与直接 convert_request 行为一致：历史保留、id 剔除、Unsupported 诊断
      assert_false(cr.value().contains("previous_response_id"))
      let mut has_unsupported = false
      for d in cr.diagnostics() {
        if d.field == "options.previous_response_id" && d.status == Unsupported {
          has_unsupported = true
        }
      }
      assert_true(has_unsupported)
    }
    Err(e) => fail("convert failed: \{e}")
  }
}

///|
/// 无 previous_response_id：行为与 convert_request 一致
test "convert_request_with_store - no prev id equals plain convert" {
  let (store, _) = mem_store()
  let json = "{\"model\":\"gpt-5.3\",\"input\":[{\"type\":\"message\",\"role\":\"user\",\"content\":[{\"type\":\"input_text\",\"text\":\"hi\"}]}]}"
  match @sdk.convert_request("responses", json, "messages") {
    Ok(base) =>
      match
        @sdk.convert_request_with_store("responses", json, "messages", store) {
        Ok(with_store) => assert_eq(with_store.value(), base.value())
        Err(e) => fail("with_store failed: \{e}")
      }
    Err(e) => fail("base failed: \{e}")
  }
}

///|
/// 旧 extras 载荷的回退识别（T8 前持久化的请求）
test "previous_response_id_of - extras legacy fallback" {
  let opts = @lux.LucentOptions::default().with_extras(
    Some({ "previous_response_id": Json::string("resp_legacy") }),
  )
  let req = @lux.LucentRequest::new(
    "gpt-5.3",
    None,
    [],
    None,
    None,
    opts,
    None,
    None,
    None,
    None,
  )
  assert_eq(@sdk.previous_response_id_of(req), Some("resp_legacy"))
}
