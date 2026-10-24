///|
/// 非 js 后端的占位实现。
///
/// 本包是 js-target 专用驱动（见 driver_js.mbt）。其它 target 只需要一个
/// 可编译的 main 让 `moon check` 通过。引用 @wasm.abi_version 使包导入在
/// 所有 target 下都被使用（import 块不区分 target）。
fn main {
  let _ = @wasm.wasm_abi_version()
  println(
    "prism driver: js target only (build with: moon build --target js src/cmd/repl)",
  )
}
