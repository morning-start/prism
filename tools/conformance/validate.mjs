#!/usr/bin/env node
/**
 * Prism 一致性校验 —— 单一入口。
 *
 * 用法：
 *   node validate.mjs                 # 跑全部检查
 *   node validate.mjs --json          # 机器可读输出（给 CI 解析）
 *
 * 退出码：0 全部通过；1 有失败。
 *
 * 检查分四组：
 *   [1] 权威枚举：从官方 SDK 抽出的取值集合 vs 本仓库白名单（src/provider/meta/finish.mbt）
 *   [2] schema 自检：用官方 schema 校验"已知合法/已知非法"样本，证明校验器本身有效
 *   [3] 跨协议泄漏：源协议词汇不得出现在目标协议槽位
 *   [4] golden 回放：若存在 fixtures/golden/*.json，逐条回放校验
 */
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { authority, authorityCheck, crossProtocolCheck, official, formatIssues } from './lib.mjs';

const HERE = path.dirname(fileURLToPath(import.meta.url));
const REPO = path.resolve(HERE, '..', '..');
const JSON_OUT = process.argv.includes('--json');

const results = [];
function record(group, name, ok, detail) {
  results.push({ group, name, ok, detail });
  if (!JSON_OUT) {
    console.log(`  ${ok ? '✅' : '❌'} ${name}`);
    if (!ok && detail) console.log(detail.split('\n').map((l) => '     ' + l).join('\n'));
  }
}
function heading(t) {
  if (!JSON_OUT) console.log(`\n${t}`);
}

// ─────────────────────────────────────────────────────────────
// [1] 权威枚举 vs 本仓库白名单
// ─────────────────────────────────────────────────────────────
heading('[1] 权威枚举 vs 仓库白名单 (src/provider/meta/finish.mbt)');

const finishMbt = fs.readFileSync(
  path.join(REPO, 'src/provider/meta/finish.mbt'),
  'utf8',
);

/** 从 MoonBit 源码里抠出某个 let 数组字面量的字符串元素 */
function extractArray(src, constName) {
  const re = new RegExp(`let\\s+${constName}\\s*:\\s*Array\\[String\\]\\s*=\\s*\\[([\\s\\S]*?)\\]`, 'm');
  const m = src.match(re);
  if (!m) return null;
  return [...m[1].matchAll(/"([^"]*)"/g)].map((x) => x[1]);
}

const WHITELISTS = [
  { const: 'messages_stop_reasons', kind: 'messages.stop_reason', label: 'Anthropic stop_reason' },
  { const: 'openai_finish_reasons', kind: 'openai.finish_reason', label: 'OpenAI finish_reason' },
  { const: 'gemini_finish_reasons', kind: 'gemini.finishReason', label: 'Gemini finishReason' },
];

const auth = authority();
for (const { const: cname, kind, label } of WHITELISTS) {
  const mine = extractArray(finishMbt, cname);
  const gold = auth[kind];
  if (!mine) {
    record('authority', `${label}: 无法从 finish.mbt 解析 ${cname}`, false);
    continue;
  }
  if (!gold) {
    record('authority', `${label}: authority.json 缺少 ${kind}`, false);
    continue;
  }
  const missing = gold.filter((v) => !mine.includes(v)); // 官方有、我没有 → 会误判非法
  const extra = mine.filter((v) => !gold.includes(v));   // 我没有依据 → 编造值
  const ok = missing.length === 0 && extra.length === 0;
  let detail = '';
  if (!ok) {
    if (missing.length) detail += `\n缺失（官方有，仓库无 → 会把合法值误判为非法）: ${missing.join(', ')}`;
    if (extra.length) detail += `\n编造（仓库有，官方无 → 会放行非法值）: ${extra.join(', ')}`;
  }
  record('authority', `${label}: ${mine.length} vs 官方 ${gold.length}`, ok, detail);
}

// ─────────────────────────────────────────────────────────────
// [2] schema 自检：证明校验器本身能分辨合法/非法
// ─────────────────────────────────────────────────────────────
heading('[2] 校验器自检（已知合法必须通过，已知非法必须拒绝）');

const ANTH_USAGE = {
  input_tokens: 1, output_tokens: 5,
  cache_creation: null, cache_creation_input_tokens: null, cache_read_input_tokens: null,
  inference_geo: null, server_tool_use: null, service_tier: null,
  output_tokens_details: { thinking_tokens: 0 }, speed: null,
};
const anthMsg = (sr, ss) => ({
  id: 'msg_1', type: 'message', role: 'assistant', model: 'c', content: [],
  stop_reason: sr, stop_sequence: ss, usage: ANTH_USAGE,
  container: null, diagnostics: null, stop_details: null,
});

const SELF_TESTS = [
  {
    name: 'Anthropic Message: stop_sequence 合法',
    run: () => official('anthropic-message.json', anthMsg('stop_sequence', 'END')),
    expect: true,
  },
  {
    name: 'Anthropic Message: 拒绝 openai 的 "stop"',
    run: () => official('anthropic-message.json', anthMsg('stop', null)),
    expect: false,
  },
  {
    name: 'Anthropic Message: 拒绝 gemini 的 "SAFETY"',
    run: () => official('anthropic-message.json', anthMsg('SAFETY', null)),
    expect: false,
  },
  {
    name: 'OpenAI chunk: finish_reason=stop 合法',
    run: () => official('openai-chat-chunk.json', {
      id: 'c', object: 'chat.completion.chunk', created: 1, model: 'm',
      choices: [{ index: 0, delta: {}, finish_reason: 'stop' }],
    }),
    expect: true,
  },
  {
    name: 'OpenAI chunk: 拒绝 anthropic 的 "pause_turn"',
    run: () => official('openai-chat-chunk.json', {
      id: 'c', object: 'chat.completion.chunk', created: 1, model: 'm',
      choices: [{ index: 0, delta: {}, finish_reason: 'pause_turn' }],
    }),
    expect: false,
  },
  {
    name: 'Gemini Candidate: NO_IMAGE 合法（官方 19 值之一）',
    run: () => official('gemini-candidate.json', { content: { parts: [] }, finishReason: 'NO_IMAGE' }),
    expect: true,
  },
  {
    name: 'Gemini Candidate: 拒绝编造的 MALFORMED_RESPONSE',
    run: () => official('gemini-candidate.json', { content: { parts: [] }, finishReason: 'MALFORMED_RESPONSE' }),
    expect: false,
  },
];

for (const t of SELF_TESTS) {
  let res;
  try {
    res = t.run();
  } catch (e) {
    record('selftest', t.name, false, `\n抛异常: ${String(e.message).slice(0, 200)}`);
    continue;
  }
  const ok = res.ok === t.expect;
  record('selftest', t.name, ok, ok ? '' : `\n期望 ok=${t.expect}，实际 ok=${res.ok}\n${formatIssues(res.issues)}`);
}

// ─────────────────────────────────────────────────────────────
// [3] 跨协议词汇泄漏
// ─────────────────────────────────────────────────────────────
heading('[3] 跨协议词汇泄漏（源协议的值不得出现在目标槽位）');

const LEAK_CASES = [
  { name: 'Anthropic 目标不接受 openai 的词', kind: 'messages.stop_reason', vals: ['stop', 'length', 'tool_calls', 'content_filter', 'function_call'] },
  { name: 'Anthropic 目标不接受 gemini 的词', kind: 'messages.stop_reason', vals: ['STOP', 'MAX_TOKENS', 'SAFETY'] },
  { name: 'OpenAI 目标不接受 anthropic 的词', kind: 'openai.finish_reason', vals: ['end_turn', 'stop_sequence', 'tool_use', 'pause_turn'] },
  { name: 'OpenAI 目标不接受 gemini 的词', kind: 'openai.finish_reason', vals: ['STOP', 'MAX_TOKENS', 'SAFETY'] },
  { name: 'Gemini 目标不接受 anthropic 的词', kind: 'gemini.finishReason', vals: ['end_turn', 'stop_sequence', 'tool_use'] },
  { name: 'Gemini 目标不接受 openai 的词', kind: 'gemini.finishReason', vals: ['stop', 'length', 'tool_calls'] },
];

for (const c of LEAK_CASES) {
  const r = crossProtocolCheck(c.kind, c.vals);
  // 期望全部被拒 → r.ok 应为 false，且 issues 数量等于输入数
  const allRejected = !r.ok && r.issues.length === c.vals.length;
  record('cross-protocol', c.name, allRejected,
    allRejected ? '' : `\n有 ${c.vals.length - (r.issues?.length ?? 0)} 个泄漏值未被拒`);
}

// 反向：目标协议自己的值必须被接受
const ACCEPT_CASES = [
  { name: 'Anthropic 接受自己的全部取值', kind: 'messages.stop_reason' },
  { name: 'OpenAI 接受自己的全部取值', kind: 'openai.finish_reason' },
  { name: 'Gemini 接受自己的全部取值', kind: 'gemini.finishReason' },
];
for (const c of ACCEPT_CASES) {
  const r = crossProtocolCheck(c.kind, auth[c.kind]);
  record('cross-protocol', c.name, r.ok, r.ok ? '' : formatIssues(r.issues));
}

// ─────────────────────────────────────────────────────────────
// [4] golden 回放（若存在）
// ─────────────────────────────────────────────────────────────
heading('[4] golden 回放（fixtures/golden/*.json）');

const GOLDEN = path.join(REPO, 'fixtures/golden');
if (!fs.existsSync(GOLDEN)) {
  if (!JSON_OUT) console.log('  (跳过：fixtures/golden/ 不存在)');
} else {
  const files = fs.readdirSync(GOLDEN).filter((f) => f.endsWith('.json'));
  if (files.length === 0) {
    if (!JSON_OUT) console.log('  (跳过：目录为空)');
  }
  for (const f of files) {
    const doc = JSON.parse(fs.readFileSync(path.join(GOLDEN, f), 'utf8'));
    // 约定：每份 golden 是 { schema, payload, expect }
    const { schema, payload, expect = true, desc } = doc;
    const r = official(schema, payload);
    const ok = r.ok === expect;
    record('golden', `${f}${desc ? ' — ' + desc : ''}`, ok,
      ok ? '' : `\n期望 ${expect}，实际 ${r.ok}\n${formatIssues(r.issues)}`);
  }
}

// ─────────────────────────────────────────────────────────────
// 汇总
// ─────────────────────────────────────────────────────────────
const failed = results.filter((r) => !r.ok);
const byGroup = {};
for (const r of results) {
  byGroup[r.group] ??= { pass: 0, fail: 0 };
  r.ok ? byGroup[r.group].pass++ : byGroup[r.group].fail++;
}

if (JSON_OUT) {
  console.log(JSON.stringify({ ok: failed.length === 0, results, summary: byGroup }, null, 2));
} else {
  console.log('\n' + '─'.repeat(60));
  for (const [g, s] of Object.entries(byGroup)) {
    console.log(`  ${g.padEnd(16)} ${s.pass} passed, ${s.fail} failed`);
  }
  console.log(`\n总计 ${results.length} 项检查，${failed.length} 项失败`);
}

if (failed.length > 0) {
  if (!JSON_OUT) {
    console.error('\n失败项：');
    for (const f of failed) console.error(`  [${f.group}] ${f.name}`);
  }
  process.exit(1);
}
process.exit(0);
