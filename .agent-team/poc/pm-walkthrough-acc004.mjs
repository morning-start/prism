// PM 业务走查（排期④）：TASK-4b decode 形状守卫，按 ACC-004 / TC-7 / TC-8 签认
// 视角：业务/用户视角 —— 通过公开 TS wrapper 调用，验证业务可观察行为：
//   TC-7: 顶层数组/标量请求 → 明确 Err（CONVERSION_ERROR），绝不产出空请求
//   TC-8: 关键字段错型请求 → Invalid 诊断透出，绝不静默成空请求
//   对照: 合法请求仍正常转换（回归零影响）
// 运行：node .agent-team/poc/pm-walkthrough-acc004.mjs [--release]
import { readFileSync } from 'node:fs'
import { fileURLToPath } from 'node:url'
import { dirname, join } from 'node:path'
import { createRequire } from 'node:module'

const root = join(dirname(fileURLToPath(import.meta.url)), '..', '..')
const mode = process.argv[2] === '--release' ? 'release' : 'debug'
const wasmPath = join(root, '_build', 'wasm-gc', mode, 'build', 'cmd', 'main', 'main.wasm')

const require = createRequire(import.meta.url)
const { loadPrism, PrismError } = require(
  join(root, 'wrappers', 'ts', 'dist', 'index.js'),
)

const client = await loadPrism(readFileSync(wasmPath))
console.log(`artifact: ${mode} | irSchema: ${client.irSchema}`)

let pass = 0
let fail = 0
function check(name, cond, detail = '') {
  if (cond) {
    pass++
    console.log(`  ✓ ${name}${detail ? ` — ${detail}` : ''}`)
  } else {
    fail++
    console.log(`  ✗ ${name}${detail ? ` — ${detail}` : ''}`)
  }
}

// ---------- 对照组：合法请求照常转换（回归零影响） ----------
console.log('\n[对照] 合法 openai 请求 → messages')
const good = client.convertRequest(
  'openai',
  JSON.stringify({
    model: 'gpt-4o-mini',
    max_tokens: 256,
    messages: [{ role: 'user', content: 'pm walkthrough' }],
  }),
  'messages',
)
check('合法请求仍 Exact 转换', /"model"/.test(good.value) && good.value.includes('"user"'), `diagnostics=${good.diagnostics.length}`)

// ---------- TC-7：4 端 × 顶层数组 / 顶层标量 ----------
console.log('\n[TC-7] 顶层形状畸形的请求文档 → 必须明确 Err，无 IR 产出')
const targets = ['openai', 'responses', 'messages', 'gemini']
const badTopShapes = [
  ['顶层数组', JSON.stringify([1, 2, 3])],
  ['顶层标量', JSON.stringify(42)],
  ['顶层字符串', JSON.stringify('not-an-object')],
]
for (const to of targets) {
  for (const [label, doc] of badTopShapes) {
    let threw = null
    let value = null
    try {
      value = client.convertRequest(to, doc, 'openai')
    } catch (err) {
      threw = err
    }
    const ok = threw instanceof PrismError
      && threw.code === 'CONVERSION_ERROR'
      && value === null
    check(
      `${to} ← ${label}`,
      ok,
      ok ? `PrismError CONVERSION_ERROR` : `!! 静默产出 ${JSON.stringify(value).slice(0, 60)}`,
    )
  }
}

// ---------- TC-8：关键字段错型 → Invalid 诊断透出 ----------
console.log('\n[TC-8] 关键字段错型（messages/contents/input）→ Invalid 诊断，绝不静默')
// openai 端：messages 错型
const r1 = client.convertRequest('openai', JSON.stringify({ model: 'm', messages: 42 }), 'messages')
check('openai messages:42 → Invalid 诊断透出', r1.diagnostics.some((d) => d.status === 'invalid'), JSON.stringify(r1.diagnostics.map((d) => d.status)))
// gemini 端：contents 错型
const r2 = client.convertRequest('gemini', JSON.stringify({ contents: 'oops' }), 'openai')
check('gemini contents:"oops" → Invalid 诊断透出', r2.diagnostics.some((d) => d.status === 'invalid'), JSON.stringify(r2.diagnostics.map((d) => d.status)))
// responses 端：input 错型
const r3 = client.convertRequest('responses', JSON.stringify({ model: 'm', input: { nope: 1 } }), 'openai')
check('responses input 错型 → Invalid 诊断透出', r3.diagnostics.some((d) => d.status === 'invalid'), JSON.stringify(r3.diagnostics.map((d) => d.status)))
// messages 端：messages 错型
const r4 = client.convertRequest('messages', JSON.stringify({ model: 'm', messages: 42 }), 'openai')
check('messages messages:42 → Invalid 诊断透出', r4.diagnostics.some((d) => d.status === 'invalid'), JSON.stringify(r4.diagnostics.map((d) => d.status)))

// ---------- 走查结论 ----------
console.log(`\nPM 走查结论: ${fail === 0 ? 'PASS' : 'FAIL'} — ${pass} pass / ${fail} fail`)
process.exit(fail === 0 ? 0 : 1)
