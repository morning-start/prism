///|
/// js-target driver：把 Prism 转换层暴露给 Node（零编组）。
///
/// 构建产物 `moon build --target js src/cmd/repl` 会执行 `main`，把函数挂到
/// `globalThis.__prism` 上；Node 侧 import 该产物后即可直接调用。
/// ABI 与 wasm 层完全一致（String 进 / String 出 / JSON 信封），
/// 因此一套 Node 校验可以同时跑 js 产物直接驱动真实转换管线。

///|
/// 请求：source 协议 JSON → target 协议 JSON
pub fn convert_req(
  source : String,
  json_str : String,
  target : String,
) -> String {
  @wasm.wasm_convert_request(source, json_str, target)
}

///|
/// 响应：source 协议 JSON → target 协议 JSON
pub fn convert_resp(
  source : String,
  json_str : String,
  target : String,
) -> String {
  @wasm.wasm_convert_response(source, json_str, target)
}

///|
/// 流式：source 协议 SSE → target 协议 SSE
pub fn convert_stream(
  source : String,
  sse_str : String,
  target : String,
) -> String {
  @wasm.wasm_convert_stream(source, sse_str, target)
}

///|
/// provider JSON → LucentResp JSON
pub fn to_lux_resp(provider : String, json_str : String) -> String {
  @wasm.wasm_to_lux_response(provider, json_str)
}

///|
/// LucentResp JSON → provider JSON
pub fn lux_resp_to_provider(provider : String, json_str : String) -> String {
  @wasm.wasm_lux_response_to_provider(provider, json_str)
}

///|
/// provider JSON → LucentReq JSON
pub fn to_lux_req(provider : String, json_str : String) -> String {
  @wasm.wasm_to_lux_request(provider, json_str)
}

///|
/// LucentReq JSON → provider JSON
pub fn lux_req_to_provider(provider : String, json_str : String) -> String {
  @wasm.wasm_lux_request_to_provider(provider, json_str)
}

///|
/// 全部 provider 主名称
pub fn list_providers() -> String {
  @wasm.wasm_list_providers()
}

///|
/// ABI 版本
pub fn abi_version() -> String {
  @wasm.wasm_abi_version()
}

///|
/// 注册三参函数到 globalThis.__prism
extern "js" fn js_register3(
  name : String,
  f : (String, String, String) -> String,
) =
  #|((name, f) => { globalThis.__prism[name] = f; })

///|
/// 注册双参函数
extern "js" fn js_register2(name : String, f : (String, String) -> String) =
  #|((name, f) => { globalThis.__prism[name] = f; })

///|
/// 注册零参函数
extern "js" fn js_register0(name : String, f : () -> String) =
  #|((name, f) => { globalThis.__prism[name] = f; })

///|
fn main {
  ignore(js_register3("convert_req", convert_req))
  ignore(js_register3("convert_resp", convert_resp))
  ignore(js_register3("convert_stream", convert_stream))
  ignore(js_register2("to_lux_resp", to_lux_resp))
  ignore(js_register2("lux_resp_to_provider", lux_resp_to_provider))
  ignore(js_register2("to_lux_req", to_lux_req))
  ignore(js_register2("lux_req_to_provider", lux_req_to_provider))
  ignore(js_register0("list_providers", list_providers))
  ignore(js_register0("abi_version", abi_version))
  println("PRISM_DRIVER_READY")
}
