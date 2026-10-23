///|
/// 元数据扩展载体的出站门控 —— 四个 provider 的 stream / response 编码器共用。
///
/// ## 为什么放在 `meta`
///
/// 判定需要 `@internal.split_provider_payload`（归属表），诊断需要
/// `@lux.ConversionDiagnostic`（类型），因此必须放在**同时依赖 internal 与
/// lux** 的包里。`lux` 反向依赖 `internal` 会破坏分层（lux 是纯 IR 核心，
/// 不能知道 wire 协议）；四个 provider 各复制一份又会漂移。`meta` 是
/// provider 共享叶子包，天然是落点。
///
/// ## 门控规则（与请求侧 `options.extras` 完全对称）
///
/// - 键 ∈ native_response(T) 或未知键 → 写出；
/// - 可证明属于其它协议 → 剔除 + Unsupported 诊断；
/// - 与 `reserved`（本编码器自己会写的键）撞名 → 跳过 + Degraded 诊断；
/// - 编码旋钮（`reasoning_field` 等）→ 跳过，不写出也不诊断。

///|
/// 把元数据载体（`provider_payload` / `ConversationStart.extra`）分拣成
/// 「可直接拼进 JSON 的 `,"k":v` 片段串」，并补齐诊断。
///
/// 返回空串表示无需写出。`prefix` 决定诊断字段名（`provider_payload` / `extra`）。
pub fn meta_extra_fragments(
  extra : Json?,
  protocol : String,
  reserved : Array[String],
  prefix : String,
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  let (kept, foreign) = @internal.split_provider_payload(extra, protocol)
  @lux.push_extras_foreign_at(prefix, foreign, diagnostics)
  let collided : Array[String] = []
  match kept {
    Some(m) =>
      for k, _ in m {
        if reserved.contains(k) {
          collided.push(k)
        }
      }
    None => ()
  }
  let clean = @internal.extras_without_keys(kept, collided)
  @lux.push_extras_collisions_at(prefix, collided, diagnostics)
  // `clean` 非空 ⟹ 至少一个键 ⟹ `parts` 必非空，故无需 length 兜底分支
  //（留着只会成为不可测的死代码，拉低覆盖率）。
  match clean {
    Some(m) => {
      let parts : Array[String] = []
      for k, v in m {
        parts.push("\"" + k + "\":" + v.stringify())
      }
      "," + parts.join(",")
    }
    None => ""
  }
}

///|
/// `provider_payload` 专用的薄包装（诊断前缀固定为 `provider_payload`）。
pub fn payload_fragments(
  payload : Json?,
  protocol : String,
  reserved : Array[String],
  diagnostics : Array[@lux.ConversionDiagnostic],
) -> String {
  meta_extra_fragments(
    payload, protocol, reserved, "provider_payload", diagnostics,
  )
}
