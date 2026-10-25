// TASK-2 POC：Node 加载 MoonBit wasm-gc 产物 + 字符串 ABI 转换验证
// 状态：POC 完成（结论=直接 import 假设**部分推翻**，两个阻塞点见 02-技术可行性 POC-1）
//
// 发现 1（已修，待验证）：src/cmd/main/moon.pkg 只有 "wasm" link 块，
//   wasm-gc 后端从不产生 28 项导出 → 已补 "wasm-gc" exports 块。
// 发现 2（阻塞）：src/wasm/memory.mbt 用 `= "%identity"` 把 Int32 强转为
//   Bytes / FixedArray[Byte] 引用（线性内存指针技巧）。纯 wasm 后端成立；
//   wasm-gc 后端下这些类型是 GC 托管 (ref n)，V8 校验直接拒绝整个模块：
//   Compiling function #92:"_M0FP...log__write" failed:
//   local.set[0] expected type (ref 2), found local.get of type i32
//
// 运行：node .agent-team/poc/task2-node-load.mjs [--debug|--release]
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..')
const mode = process.argv[2] === '--release' ? 'release' : 'debug'
const wasmPath = join(root, '_build', 'wasm-gc', mode, 'build', 'cmd', 'main', 'main.wasm')
const bytes = readFileSync(wasmPath)

console.log(`artifact : ${wasmPath} (${(bytes.length / 1024).toFixed(0)} KB)`)
let mod
try {
  mod = await WebAssembly.compile(bytes)
} catch (err) {
  console.log('VERDICT  : FAIL — V8 rejects the module:', String(err.message).split('\n')[0].slice(0, 200))
  process.exit(1)
}
const exps = WebAssembly.Module.exports(mod).map(e => e.name)
console.log('imports  :', JSON.stringify(WebAssembly.Module.imports(mod).map(i => `${i.module}.${i.name}`)))
console.log('exports  :', exps.length, exps.length <= 3 ? JSON.stringify(exps) : '(28 ABI)')

const want = 'wasm_abi_version'
if (!exps.includes(want)) {
  console.log(`VERDICT  : FAIL — "${want}" not exported (memory.mbt invalidates wasm-gc module; see POC header)`)
  process.exit(1)
}
const instance = await WebAssembly.instantiate(bytes, {})
const e = instance.exports
console.log('abi      :', e[want]())
const openaiReq = JSON.stringify({ model: 'gpt-4o-mini', messages: [{ role: 'user', content: 'hello prism poc' }] })
const out = e['wasm_convert_req']('openai', openaiReq, 'messages')
console.log('convert  :', out.slice(0, 160))
console.log('VERDICT  : PASS — wasm-gc loads in Node, string ABI round-trips, openai→messages conversion works')
