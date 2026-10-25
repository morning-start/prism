// TASK-2/2b POC：Node 加载 MoonBit wasm-gc 产物 + 字符串 ABI 转换验证
// 状态：PASS（2026-10-25）。TASK-2b 方案 A 落地后本脚本即验收脚本：
//   1. src/cmd/main/moon.pkg 补 "wasm-gc" exports 块 + use-js-builtin-string
//   2. src/wasm/memory.mbt 拆分：wasm-gc 用 memory_wasmgc.mbt 降级实现
//   3. 宿主须以 builtins:['js-string'], importedStringConstants:'_' 实例化
// 运行：node .agent-team/poc/task2-node-load.mjs [--release]
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
console.log('export kinds:', JSON.stringify(WebAssembly.Module.exports(mod).filter(x => exps.includes(x.name)).slice(0, 3)))
// js-string-builtins 宿主侧注入（moon.pkg: use-js-builtin-string=true, constants="_"）
const { instance } = await WebAssembly.instantiate(bytes, {}, {
  builtins: ['js-string'],
  importedStringConstants: '_',
})
const e = instance.exports
const abiOut = e[want]()
console.log('abi      :', abiOut)
if (!abiOut.includes('"abi":"1"')) {
  console.log('VERDICT  : FAIL — abi version unexpected')
  process.exit(1)
}
const openaiReq = JSON.stringify({ model: 'gpt-4o-mini', messages: [{ role: 'user', content: 'hello prism poc' }] })
const out = e['wasm_convert_req']('openai', openaiReq, 'messages')
// 信封契约：{value: "<目标协议 JSON 字符串>", diagnostics: [...]}
// messages 目标要求 max_tokens：Prism 按契约补默认 4096 并打 Degraded 诊断
// （预期行为，诊断必须透出——正好一并验证「诊断不吞」）
const env = JSON.parse(out)
const inner = JSON.parse(env.value)
const ok = inner.messages?.[0]?.role === 'user'
  && inner.messages?.[0]?.content?.[0]?.type === 'text'
  && inner.messages?.[0]?.content?.[0]?.text === 'hello prism poc'
  && inner.max_tokens === 4096
  && env.diagnostics.length >= 1
  && env.diagnostics[0].status === 'degraded'
console.log('convert  : inner =', JSON.stringify(inner).slice(0, 160))
console.log('diagnostics:', JSON.stringify(env.diagnostics))
if (!ok) {
  console.log('VERDICT  : FAIL — conversion output unexpected')
  process.exit(1)
}
console.log('VERDICT  : PASS — wasm-gc loads in Node (js-string-builtins), string ABI round-trips, openai→messages conversion works')
