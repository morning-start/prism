// TASK-2c：WASM 产物加载冒烟检查（CI 护栏，RISK-007）
//
// 为什么需要：moon test 的 wasm-gc runner 不校验主模块导出段，moonc 对
// exports 清单里不存在的函数静默忽略——"1442 tests 全绿但产物无法加载"
// 的假阴性已实际发生两次（POC-1 / P2-1，见 .agent-team/docs/06 RISK-007）。
// 本脚本是 ABI 契约的第一道消费者侧防线，任何漂移在此红灯。
//
// 检查内容（口径经 QA P2-2 确认：宽松计数，不精确匹配避免 _start 干扰）：
//   1. 两个后端产物（wasm / wasm-gc）都能通过引擎校验并实例化
//   2. 每个后端 ≥25 项导出且 29 项关键锚点导出全在位
//   3. wasm_abi_version 返回 abi="1"
//   4. 每后端 1 次真实转换（openai→messages）语义断言 + 诊断透出断言
//   5. wasm-gc：js-string-builtins 宿主契约生效（不带 options 必须失败）
//   6. wasm-gc：scratch/log 降级语义（wasm_init_scratch=0、
//      wasm_read_scratch_arg 错误信封而非崩溃）
//   7. wasm-gc：流会话 4 导出 + wasm_stream_finished 自查实跑
//
// 纯 wasm 后端的 String ABI（skills/prism-wasm 曾记载错误，已修正）：
//   - String 参数走 scratch 协议：wasm_init_scratch 分配缓冲区（返回载荷
//     指针），宿主在 offset-4 写 u32 LE **UTF-16 code-unit 数**，offset 写
//     UTF-16LE 载荷；offset 需 ≥8（避开 MoonBit 8 字节对象头）
//   - String 返回值 = 线性内存指针，ptr-4 处 u32 LE code-unit 数
//
// 用法：node scripts/wasm_smoke.mjs [--release]（默认 debug）
// 前置：moon build --target wasm / moon build --target wasm-gc
import { readFileSync, existsSync } from 'node:fs'
import { dirname, join } from 'node:path'
import { fileURLToPath } from 'node:url'

const root = join(dirname(fileURLToPath(import.meta.url)), '..')
const mode = process.argv.includes('--release') ? 'release' : 'debug'
const buildDir = t => join(root, '_build', t, mode, 'build', 'cmd', 'main', 'main.wasm')

// 29 项 ABI 锚点（以 src/cmd/main/moon.pkg exports 为唯一真值）
const CORE_EXPORTS = [
  'wasm_to_lux_req', 'wasm_lux_req_to_provider', 'wasm_to_lux_resp', 'wasm_lux_resp_to_provider',
  'wasm_sse_to_events', 'wasm_events_to_sse',
  'wasm_sdk_encode_req', 'wasm_sdk_decode_resp', 'wasm_sdk_encode_stream', 'wasm_sdk_decode_sse', 'wasm_sdk_capability',
  'wasm_convert_req', 'wasm_convert_resp', 'wasm_convert_stream', 'wasm_convert_stream_event',
  'wasm_stream_new', 'wasm_stream_feed', 'wasm_stream_finish', 'wasm_stream_finished', 'wasm_stream_free',
  'wasm_list_providers', 'wasm_abi_version',
  'wasm_init_scratch', 'wasm_read_scratch_arg', 'wasm_log_init', 'wasm_log_pos',
  'wasm_convert_req_trace', 'wasm_convert_resp_trace', 'wasm_convert_stream_trace',
]

let failures = 0
const fail = msg => { console.error(`  ✗ ${msg}`); failures++ }
const ok = msg => console.log(`  ✓ ${msg}`)

const OPENAI_REQ = JSON.stringify({
  model: 'gpt-4o-mini',
  messages: [{ role: 'user', content: 'hello wasm smoke' }],
})
const assertConvertEnvelope = (envJson, label) => {
  const env = JSON.parse(envJson)
  const inner = JSON.parse(env.value)
  if (inner.messages?.[0]?.role !== 'user') fail(`${label}: 转换语义错误（role）`)
  else if (inner.messages?.[0]?.content?.[0]?.text !== 'hello wasm smoke') fail(`${label}: 转换语义错误（content）`)
  else if (inner.max_tokens !== 4096) fail(`${label}: max_tokens 默认值缺失`)
  else if (!(env.diagnostics.length >= 1 && env.diagnostics[0].status === 'degraded')) fail(`${label}: Degraded 诊断未透出`)
  else ok(`${label}: openai→messages 转换语义 + 诊断透出`)
}

// --- 纯 wasm 后端：scratch 协议编解码（见文件头 ABI 说明） ---
function scratchConvert(e, label) {
  const bufPtr = e.wasm_init_scratch(65536)
  const dv = () => new DataView(e.memory.buffer) // memory 可增长，每次现取
  const putArg = (offset, str) => {
    const d = dv()
    d.setUint32(bufPtr + offset - 4, str.length, true)
    for (let i = 0; i < str.length; i++) d.setUint16(bufPtr + offset + i * 2, str.charCodeAt(i), true)
  }
  const readStr = p => {
    const d = dv()
    const len = d.getUint32(p - 4, true)
    let r = ''
    for (let i = 0; i < len; i++) r += String.fromCharCode(d.getUint16(p + i * 2, true))
    return r
  }
  putArg(8, 'openai'); putArg(8192, OPENAI_REQ); putArg(16384, 'messages')
  const outPtr = e.wasm_convert_req(bufPtr + 8, bufPtr + 8192, bufPtr + 16384)
  assertConvertEnvelope(readStr(outPtr), label)
}

async function checkBackend(target, load) {
  const path = buildDir(target)
  if (!existsSync(path)) { fail(`${target}: 产物不存在 ${path}（先 moon build --target ${target}）`); return }
  const bytes = readFileSync(path)
  console.log(`[${target}] ${(bytes.length / 1024).toFixed(0)} KB`)
  let mod
  try { mod = await WebAssembly.compile(bytes) } catch (err) { fail(`${target}: 引擎校验拒绝 — ${String(err.message).split('\n')[0].slice(0, 160)}`); return }
  const names = WebAssembly.Module.exports(mod).map(x => x.name)
  const missing = CORE_EXPORTS.filter(n => !names.includes(n))
  if (names.length - 1 < 25) fail(`${target}: 导出数 ${names.length - 1} < 25`)
  else ok(`${target}: 导出数 ${names.length - 1} ≥ 25`)
  if (missing.length) fail(`${target}: 缺关键导出 ${missing.join(', ')}`)
  else ok(`${target}: ${CORE_EXPORTS.length} 项关键导出全在位`)
  const { instance } = await load(bytes)
  const e = instance.exports
  if (target === 'wasm-gc') {
    const abi = String(e['wasm_abi_version']())
    if (!abi.includes('"abi":"1"')) fail(`${target}: abi 版本异常 ${abi}`)
    else ok(`${target}: wasm_abi_version → abi=1`)
    assertConvertEnvelope(e['wasm_convert_req']('openai', OPENAI_REQ, 'messages'), target)
    // 降级语义探针（TASK-2b 方案 A 契约）
    if (e['wasm_init_scratch'](8192) !== 0) fail('wasm-gc: wasm_init_scratch 未降级为 0')
    else ok('wasm-gc: scratch/log 降级语义（init_scratch=0）')
    const scratchErr = JSON.parse(e['wasm_read_scratch_arg'](1234, 32))
    if (!scratchErr.error) fail('wasm-gc: wasm_read_scratch_arg 未返回错误信封')
    else ok('wasm-gc: read_scratch_arg 错误信封而非崩溃')
    // 流会话 + finished 自查（P2-1 回归锚点）
    const h = JSON.parse(e['wasm_stream_new']('openai', 'messages')).value
    if (JSON.parse(e['wasm_stream_finished'](h)).value !== false) fail('wasm-gc: finished 初值非 false')
    const fin = JSON.parse(e['wasm_stream_finish'](h))
    if (!Array.isArray(fin.value) || fin.value.length === 0) fail('wasm-gc: finish 未冲刷尾部帧')
    if (JSON.parse(e['wasm_stream_finished'](h)).value !== true) fail('wasm-gc: finished 终值非 true')
    if (!JSON.parse(e['wasm_stream_free'](h)).value) fail('wasm-gc: free 未返回 true')
    else ok('wasm-gc: 流会话 new/finish/finished/free 实跑（含 finished 自查）')
  } else {
    // 纯 wasm：abi_version 返回的是指针（String 未经 js-string-builtins），
    // 经 scratch 协议读出验证
    const scratchProbe = e0 => {
      const bufPtr = e0.wasm_init_scratch(4096)
      const d = new DataView(e0.memory.buffer)
      const readStr = p => {
        const len = d.getUint32(p - 4, true)
        let r = ''
        for (let i = 0; i < len; i++) r += String.fromCharCode(d.getUint16(p + i * 2, true))
        return r
      }
      return readStr(e0.wasm_abi_version())
    }
    const abi = scratchProbe(e)
    if (!abi.includes('"abi":"1"')) fail(`${target}: abi 版本异常 ${abi}`)
    else ok(`${target}: wasm_abi_version → abi=1（scratch 协议读取）`)
    scratchConvert(e, target)
  }
}

// wasm 后端：需要宿主提供 memory
const loadWasm = async bytes => {
  const mod = await WebAssembly.compile(bytes)
  const memImport = WebAssembly.Module.imports(mod).find(i => i.kind === 'memory')
  const imports = {}
  if (memImport) imports[memImport.module] = { [memImport.name]: new WebAssembly.Memory({ initial: 256, maximum: 65536 }) }
  return WebAssembly.instantiate(bytes, imports)
}
// wasm-gc 后端：js-string-builtins 宿主契约
const loadWasmGc = async bytes => WebAssembly.instantiate(bytes, {}, { builtins: ['js-string'], importedStringConstants: '_' })

await checkBackend('wasm-gc', loadWasmGc)
await checkBackend('wasm', loadWasm)

// js-string-builtins 契约负向验证：不带 options 必须失败（否则契约形同虚设）
{
  const bytes = readFileSync(buildDir('wasm-gc'))
  let rejected = false
  try { await WebAssembly.instantiate(bytes, {}) } catch { rejected = true }
  if (!rejected) fail('wasm-gc: 不带 builtins options 实例化居然成功 — 宿主契约失效')
  else ok('wasm-gc: 宿主契约负向验证（缺 builtins 即失败）')
}

console.log(failures === 0 ? '\nSMOKE PASS — wasm ABI 契约完整' : `\nSMOKE FAIL — ${failures} 项失败`)
process.exit(failures === 0 ? 0 : 1)
