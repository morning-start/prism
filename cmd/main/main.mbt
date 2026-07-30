///|
/// WASM 导出入口
///
/// 空 main 函数，通过调用 wasm 包中的任意函数
/// 强制 MoonBit 链接器将整个 Prism 库
/// （lux/ + provider/*/ + sdk/ + wasm/）编译为完整的 .wasm 二进制。
///
/// 实际的 11 个导出函数（wasm_to_lux_request 等）定义在 wasm/wasm.mbt 中，
/// 编译后作为 WASM exports 暴露给宿主。
fn main {
  let _ = @wasm.wasm_sdk_capability("openai")
}
