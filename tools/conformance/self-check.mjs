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
  // responses 官方 Response schema（[5] 组完整校验的护栏）
  ['responses official-null 形状仍通过', 'openai-responses-response.json',
    { id: 'resp_x', object: 'response', created_at: 0, status: 'completed', model: 'm',
      error: null, incomplete_details: null, metadata: {}, instructions: null,
      temperature: null, top_p: null, tool_choice: 'auto', tools: [],
      parallel_tool_calls: true,
      output: [{ type: 'message', id: 'msg_0', role: 'assistant', status: 'completed',
        content: [{ type: 'output_text', text: 'Hi', annotations: [] }] }],
      usage: { input_tokens: 3, output_tokens: 2, total_tokens: 5 } }, true],
  ['responses status 非法值仍被拒', 'openai-responses-response.json',
    { id: 'resp_x', object: 'response', created_at: 0, status: 'weird_status', model: 'm',
      error: null, incomplete_details: null, metadata: {}, instructions: null,
      temperature: null, top_p: null, tool_choice: 'auto', tools: [],
      parallel_tool_calls: true,
      output: [{ type: 'message', id: 'msg_0', role: 'assistant', status: 'completed',
        content: [{ type: 'output_text', text: 'Hi', annotations: [] }] }] }, false],
  ['responses error 槽位写对象会被 schema 校出结构', 'openai-responses-response.json',
    { id: 'resp_x', object: 'response', created_at: 0, status: 'completed', model: 'm',
      error: { code: 123 }, incomplete_details: null, metadata: {}, instructions: null,
      temperature: null, top_p: null, tool_choice: 'auto', tools: [],
      parallel_tool_calls: true,
      output: [{ type: 'message', id: 'msg_0', role: 'assistant', status: 'completed',
        content: [{ type: 'output_text', text: 'Hi', annotations: [] }] }] }, false],
  // gemini 信封级 schema（GenerateContentResponse，2026-10-24 新增）
  ['gemini 信封 official 形态仍通过', 'gemini-response.json',
    { responseId: 'r1', modelVersion: 'm',
      candidates: [{ index: 0, content: { role: 'model', parts: [{ text: 'Hi' }] },
        finishReason: 'STOP' }],
      usageMetadata: { promptTokenCount: 3, candidatesTokenCount: 2, totalTokenCount: 5 } },
    true],
  ['gemini 信封编造 finishReason 仍被拒', 'gemini-response.json',
    { responseId: 'r1', modelVersion: 'm',
      candidates: [{ index: 0, content: { role: 'model', parts: [{ text: 'Hi' }] },
        finishReason: 'MALFORMED_RESPONSE' }] }, false],
  ['gemini 信封缺 candidates 时 promptFeedback 兜底仍通过', 'gemini-response.json',
    { promptFeedback: { blockReason: 'PROHIBITED_CONTENT' },
      usageMetadata: { promptTokenCount: 3, totalTokenCount: 3 } }, true],
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
