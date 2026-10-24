// 反向验证：噪音/豁免机制是否让真 bug 漏网？
// 这是护栏：豁免列表必须只管"上游版本差"，不能顺手放过枚举与结构错误。
import { official, formatIssues } from './lib.mjs';

const cases = [
  ['非法 finish_reason 仍被拒', 'openai-chat-chunk.json',
    { id: 'c', object: 'chat.completion.chunk', created: 1, model: 'm',
      choices: [{ index: 0, delta: {}, finish_reason: 'pause_turn' }] }, false],
  ['缺少 choices 仍被拒', 'openai-chat-chunk.json',
    { id: 'c', object: 'chat.completion.chunk' }, false],
  ['object 标识错误仍被拒', 'openai-chat-chunk.json',
    { id: 'c', object: 'wrong.object', created: 1, model: 'm',
      choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] }, false],
  ['合法 chunk 仍通过', 'openai-chat-chunk.json',
    { id: 'c', object: 'chat.completion.chunk', created: 1, model: 'm',
      choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] }, true],
  ['gemini 编造值仍被拒', 'gemini-candidate.json',
    { content: { parts: [] }, finishReason: 'MALFORMED_RESPONSE' }, false],
  ['gemini 官方值仍通过', 'gemini-candidate.json',
    { content: { parts: [] }, finishReason: 'NO_IMAGE' }, true],
  ['anthropic 非法 stop_reason 仍被拒', 'anthropic-message.json',
    { id: 'm', type: 'message', role: 'assistant', model: 'c', content: [],
      stop_reason: 'stop', stop_sequence: null,
      usage: { input_tokens: 1, output_tokens: 1 },
      container: null, diagnostics: null, stop_details: null }, false],
];

let pass = 0;
for (const [name, schema, payload, expect] of cases) {
  const r = official(schema, payload);
  const ok = r.ok === expect;
  if (ok) pass++;
  console.log(`${ok ? '✅' : '❌'} ${name} (expect ${expect}, got ${r.ok})`);
  if (!ok) console.log(formatIssues(r.issues));
}
console.log(`\n${pass}/${cases.length} 符合预期`);
process.exit(pass === cases.length ? 0 : 1);
