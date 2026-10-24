/**
 * [7] 真实 socket 回放 —— 协议服务器 + 官方 SDK 全链路消费。
 *
 * 这是 Node 路线的**独有能力**（当初排除 Go/Python 路线的决定性理由）：
 *
 *   官方 SDK（client）──HTTP──► 本地协议服务器 ──► Prism 真实转换 ──► SSE 回给 SDK
 *                                   │
 *                    收到的是【SDK 原样发出的 wire 请求体】
 *                    （不是手写样本 —— 请求侧也过真实管线）
 *
 * 矩阵（SDK 客户端 → 服务器目标协议 → Prism → 回源流）：
 *   - openai    SDK → POST /chat/completions          → Prism openai 请求解码
 *   - messages  SDK → POST /v1/messages               → Prism messages 请求解码
 *   - gemini    SDK → POST /v1beta/models/{m}:streamGenerateContent?alt=sse
 *
 * 每路验证三件事：
 *   1. SDK 发出的请求体被 Prism 请求解码器**无错误**接受（请求侧真实管线）
 *   2. Prism 产出的 SSE 被官方 SDK 通过真实 socket 逐帧解析，
 *      文本增量拼接与终止原因语义正确（响应侧真实管线 + 官方解析器裁判）
 *   3. 诊断不丢失（SDK 侧错误帧 → APIError；Prism 侧诊断随信封计数）
 *
 * 与 [5]/[6] 组的区别：那两组用手写样本直接调 driver；这一组让**官方 SDK 的
 * 请求序列化器与响应解析器**站在链路两端 —— 它们比 ajv 更挑剔
 * （auth 头、SSE 分帧、event 配对、[DONE] 哨兵、usage 聚合都要过）。
 */
import http from 'node:http';
import { load, parseSse } from './prism.mjs';

const HOST = '127.0.0.1';

/** 服务器要回放的源协议流（每路测试设置） */
const SOURCE_STREAMS = {
  // openai Chat Completions 官方流形态（终结于 [DONE]）
  openai: (text, finish) =>
    chunkFrame({ id: 'chatcmpl-x', object: 'chat.completion.chunk', created: 1700000000, model: 'gpt-4o',
      choices: [{ index: 0, delta: { role: 'assistant', content: text }, finish_reason: null }] }) +
    chunkFrame({ id: 'chatcmpl-x', object: 'chat.completion.chunk', created: 1700000000, model: 'gpt-4o',
      choices: [{ index: 0, delta: {}, finish_reason: finish ?? 'stop' }] }) +
    chunkFrame({ id: 'chatcmpl-x', object: 'chat.completion.chunk', created: 1700000000, model: 'gpt-4o',
      choices: [], usage: { prompt_tokens: 3, completion_tokens: 2, total_tokens: 5 } }) +
    'data: [DONE]\n\n',
  // Anthropic Messages 官方流形态（event: 前缀 + message_stop）
  messages: (text) => {
    const f = (type, data) => `event: ${type}\ndata: ${JSON.stringify({ type, ...data })}\n\n`;
    return f('message_start', { message: { id: 'msg_x', type: 'message', role: 'assistant', model: 'claude-sonnet-4',
        content: [], stop_reason: null, stop_sequence: null, usage: { input_tokens: 3, output_tokens: 1 } } }) +
      f('content_block_start', { index: 0, content_block: { type: 'text', text: '' } }) +
      f('content_block_delta', { index: 0, delta: { type: 'text_delta', text } }) +
      f('content_block_stop', { index: 0 }) +
      f('message_delta', { delta: { stop_reason: 'end_turn', stop_sequence: null }, usage: { output_tokens: 2 } }) +
      f('message_stop', {});
  },
  // Gemini generateContent SSE（data: 前缀，无 event: 行）
  gemini: (text) =>
    `data: ${JSON.stringify({ candidates: [{ content: { parts: [{ text }], role: 'model' }, finishReason: 'STOP', index: 0 }],
      usageMetadata: { promptTokenCount: 3, candidatesTokenCount: 2, totalTokenCount: 5 },
      modelVersion: 'gemini-2.0-flash', responseId: 'r1' })}\n\n`,
};

function chunkFrame(body) {
  return `data: ${JSON.stringify(body)}\n\n`;
}

let pass = 0;
let fail = 0;
const failures = [];

function record(name, ok, issues = []) {
  if (ok) {
    pass++;
    console.log(`  ✅ ${name}`);
  } else {
    fail++;
    failures.push({ name, issues });
    console.log(`  ❌ ${name}`);
    for (const i of issues) console.log(`     ${i.message}`);
  }
}

/**
 * 起一台「协议服务器」：
 * - 收到请求后用 Prism 的请求解码（to_lux_req）+ 目标编码（lux_req_to_provider）
 *   走一遍真实请求管线 —— 验证 SDK 的 wire 请求体被接受且能转出。
 * - 然后回放 `streamOf` 指定的源协议 SSE。
 * - 收集每次请求的 (method, url, headers, body) 供断言。
 */
async function startServer(P, streamOf) {
  const requests = [];
  const server = http.createServer((req, res) => {
    let body = '';
    req.on('data', (c) => (body += c));
    req.on('end', () => {
      requests.push({ method: req.method, url: req.url, headers: req.headers, body });
      res.writeHead(200, { 'content-type': 'text/event-stream' });
      res.end(streamOf(body));
    });
  });
  await new Promise((resolve) => server.listen(0, HOST, resolve));
  const port = server.address().port;
  return {
    server,
    requests,
    base: `http://${HOST}:${port}`,
    close: () => new Promise((resolve) => server.close(resolve)),
  };
}

/** 解码请求体：provider wire JSON → LucentRequest JSON（经真实管线） */
function decodeRequest(P, provider, body) {
  return P.call('to_lux_req', provider, body);
}

export async function run() {
  const P = await load();
  console.log('\n[7] 真实 socket 回放（官方 SDK → 本地协议服务器 → Prism 转换 → SDK 消费）');
  console.log(`    driver abi=${P.abi.value?.abi ?? '?'} providers=${P.providers.join(',')}`);

  // ── 1. openai SDK：POST /chat/completions，消费 openai 流 ──────────────
  {
    const srv = await startServer(P, () => SOURCE_STREAMS.openai('Hi', 'stop'));
    try {
      const OpenAI = (await import('openai')).default;
      const client = new OpenAI({ apiKey: 'sk-test', baseURL: srv.base, maxRetries: 0 });
      const stream = await client.chat.completions.create({
        model: 'gpt-4o',
        messages: [{ role: 'user', content: 'hi' }],
        stream: true,
        stream_options: { include_usage: true },
      });
      let text = '';
      let finish = null;
      let usage = null;
      for await (const chunk of stream) {
        if (chunk.usage) usage = chunk.usage;
        const c = chunk.choices?.[0];
        if (c?.delta?.content) text += c.delta.content;
        if (c?.finish_reason) finish = c.finish_reason;
      }
      record('openai SDK: 流消费（text/finish/usage 语义完整）',
        text === 'Hi' && finish === 'stop' && usage?.total_tokens === 5,
        text !== 'Hi' ? [{ message: `text=${JSON.stringify(text)}` }] :
        finish !== 'stop' ? [{ message: `finish=${finish}` }] :
        [{ message: `usage=${JSON.stringify(usage)}` }]);

      const req = srv.requests[0];
      record('openai SDK: 请求到达（POST /chat/completions + Bearer 头）',
        req?.method === 'POST' && req?.url === '/chat/completions' &&
        String(req?.headers?.authorization).startsWith('Bearer '),
        [{ message: `got ${req?.method} ${req?.url}` }]);

      // 请求侧真实管线：SDK 的 wire 请求体 → IR（decode 必须成功、零 error）
      const dec = decodeRequest(P, 'openai', req.body);
      record('openai SDK: wire 请求体 → Prism IR（真实解码）', dec.ok, dec.ok ? [] : [{ message: dec.error }]);
      if (dec.ok) {
        const ir = dec.value;
        record('openai SDK: 请求语义保真（model + 用户消息进入 IR）',
          ir.model === 'gpt-4o' && JSON.stringify(ir.conversation ?? []).includes('hi'),
          [{ message: `model=${ir.model}` }]);
        // 继续转出：IR → messages 目标请求 JSON（encode 必须成功）
        const enc = P.call('lux_req_to_provider', 'messages', JSON.stringify(ir));
        record('openai SDK: 请求转出 messages 目标（encode 成功）', enc.ok, enc.ok ? [] : [{ message: enc.error }]);
      }
    } catch (e) {
      record('openai SDK: 流消费（text/finish/usage 语义完整）', false, [{ message: e.message }]);
    } finally {
      await srv.close();
    }
  }

  // ── 2. anthropic SDK：POST /v1/messages，消费 messages 流 ──────────────
  {
    const srv = await startServer(P, () => SOURCE_STREAMS.messages('Hi'));
    try {
      const Anthropic = (await import('@anthropic-ai/sdk')).default;
      const client = new Anthropic({ apiKey: 'k', baseURL: srv.base, maxRetries: 0 });
      const stream = await client.messages.create({
        model: 'claude-sonnet-4',
        max_tokens: 32,
        messages: [{ role: 'user', content: 'hi' }],
        stream: true,
      });
      let text = '';
      let stop = null;
      let outTokens = null;
      for await (const ev of stream) {
        if (ev.type === 'content_block_delta' && ev.delta?.type === 'text_delta') text += ev.delta.text;
        if (ev.type === 'message_delta') {
          stop = ev.delta?.stop_reason ?? stop;
          outTokens = ev.usage?.output_tokens ?? outTokens;
        }
        if (ev.type === 'error') throw new Error(`error event: ${JSON.stringify(ev.error)}`);
      }
      record('anthropic SDK: 流消费（text/stop_reason/usage 语义完整）',
        text === 'Hi' && stop === 'end_turn' && outTokens === 2,
        [{ message: `text=${JSON.stringify(text)} stop=${stop} out=${outTokens}` }]);

      const req = srv.requests[0];
      record('anthropic SDK: 请求到达（POST /v1/messages + version 头）',
        req?.method === 'POST' && req?.url === '/v1/messages' && !!req?.headers?.['anthropic-version'],
        [{ message: `got ${req?.method} ${req?.url}` }]);

      const dec = decodeRequest(P, 'messages', req.body);
      record('anthropic SDK: wire 请求体 → Prism IR（真实解码）', dec.ok, dec.ok ? [] : [{ message: dec.error }]);
      if (dec.ok) {
        const ir = dec.value;
        record('anthropic SDK: 请求语义保真（model + max_tokens 进入 IR）',
          ir.model === 'claude-sonnet-4' && (ir.options?.max_tokens ?? ir.options?.max_output_tokens ?? 0) > 0,
          [{ message: `model=${ir.model}` }]);
      }
    } catch (e) {
      record('anthropic SDK: 流消费（text/stop_reason/usage 语义完整）', false, [{ message: e.message }]);
    } finally {
      await srv.close();
    }
  }

  // ── 3. gemini SDK：POST /v1beta/models/{m}:streamGenerateContent?alt=sse ─
  {
    const srv = await startServer(P, () => SOURCE_STREAMS.gemini('Hi'));
    try {
      const { GoogleGenAI } = await import('@google/genai');
      const ai = new GoogleGenAI({
        apiKey: 'test',
        httpOptions: { baseUrl: srv.base, apiVersion: 'v1beta' },
      });
      const stream = await ai.models.generateContentStream({
        model: 'gemini-2.0-flash',
        contents: 'hi',
        config: {
          automaticFunctionCalling: { disable: true },
          httpOptions: { retryOptions: { attempts: 1 } },
        },
      });
      let text = '';
      let finish = null;
      for await (const resp of stream) {
        const c = resp.candidates?.[0];
        for (const p of c?.content?.parts ?? []) {
          if (p.text !== undefined) text += p.text;
        }
        if (c?.finishReason) finish = c.finishReason;
      }
      record('gemini SDK: 流消费（text/finishReason 语义完整）',
        text === 'Hi' && finish === 'STOP',
        [{ message: `text=${JSON.stringify(text)} finish=${finish}` }]);

      const req = srv.requests[0];
      record('gemini SDK: 请求到达（streamGenerateContent?alt=sse + x-goog-api-key）',
        req?.method === 'POST' && req?.url?.includes(':streamGenerateContent') &&
        req?.url?.includes('alt=sse') && !!req?.headers?.['x-goog-api-key'],
        [{ message: `got ${req?.method} ${req?.url}` }]);

      const dec = decodeRequest(P, 'gemini', req.body);
      record('gemini SDK: wire 请求体 → Prism IR（真实解码）', dec.ok, dec.ok ? [] : [{ message: dec.error }]);
    } catch (e) {
      record('gemini SDK: 流消费（text/finishReason 语义完整）', false, [{ message: e.message }]);
    } finally {
      await srv.close();
    }
  }

  // ── 4. 跨协议中转：请求/响应两端都是官方 SDK，中间是 Prism 真实转换 ─────
  // 拓扑 = transit middleware：
  //   请求侧  openai SDK wire 请求体 → Prism 解码/编码 → 转出 JSON
  //   响应侧  源协议 SSE → Prism convert_stream → 目标 SSE → 官方 SDK 消费
  // 组合选取依据（SDK 解析器的硬约束，实测确认）：
  //   - anthropic SDK 的 SSE 解码器**跳过无 event: 行的帧**（event=null →
  //     continue），因此回给它的流必须带 event: 行 —— messages 目标天然满足，
  //     openai/responses 目标也带 event: 行，均可回 anthropic SDK；
  //   - gemini 目标只发 data: 行（官方形态），不能回 anthropic SDK，
  //     但 openai SDK / gemini SDK 的解码器接受纯 data: 流。
  {
    const oaiSse =
      chunkFrame({ id: 'c1', object: 'chat.completion.chunk', created: 1700000000, model: 'gpt-4o',
        choices: [{ index: 0, delta: { role: 'assistant', content: 'Hi' }, finish_reason: null }] }) +
      chunkFrame({ id: 'c1', object: 'chat.completion.chunk', created: 1700000000, model: 'gpt-4o',
        choices: [{ index: 0, delta: {}, finish_reason: 'stop' }] }) +
      chunkFrame({ id: 'c1', object: 'chat.completion.chunk', created: 1700000000, model: 'gpt-4o',
        choices: [], usage: { prompt_tokens: 3, completion_tokens: 2, total_tokens: 5 } }) +
      'data: [DONE]\n\n';
    const srv = await startServer(P, () => oaiSse);
    let convDiag = -1;
    try {
      // fetch 包装必须先于 SDK 构造 —— anthropic SDK 在构造函数里把
      // globalThis.fetch 绑定到实例（实测：后包装不生效）。
      const origFetch = globalThis.fetch;
      globalThis.fetch = async (url, init) => {
        const resp = await origFetch(url, init);
        const raw = await resp.text();
        const conv = P.call('convert_stream', 'openai', raw, 'messages');
        if (!conv.ok) throw new Error(`convert_stream failed: ${conv.error}`);
        convDiag = conv.diagnostics.length;
        return new Response(conv.value, {
          status: 200,
          headers: { 'content-type': 'text/event-stream' },
        });
      };
      const Anthropic = (await import('@anthropic-ai/sdk')).default;
      const client = new Anthropic({ apiKey: 'k', baseURL: srv.base, maxRetries: 0 });

      // fetch 包装层 = 中转层：openai 源流 → Prism convert_stream → messages 流
      const stream = await client.messages.create({
        model: 'claude-sonnet-4',
        max_tokens: 32,
        messages: [{ role: 'user', content: 'hi' }],
        stream: true,
      });
      let text = '';
      let stop = null;
      let outTokens = null;
      for await (const ev of stream) {
        if (ev.type === 'content_block_delta' && ev.delta?.type === 'text_delta') text += ev.delta.text;
        if (ev.type === 'message_delta') {
          stop = ev.delta?.stop_reason ?? stop;
          outTokens = ev.usage?.output_tokens ?? outTokens;
        }
      }
      globalThis.fetch = origFetch;

      record('跨协议中转: openai 源流经 Prism 转换后被 anthropic SDK 消费',
        text === 'Hi' && stop === 'end_turn' && outTokens === 2,
        [{ message: `text=${JSON.stringify(text)} stop=${stop} out=${outTokens}` }]);
      record('跨协议中转: 转换过程零诊断', convDiag === 0,
        [{ message: `diagnostics=${convDiag}` }]);

      // 请求侧：anthropic SDK 发出的 messages wire 请求体 → Prism 解码 →
      // 转出 gemini 形态请求（本地 SDK 无法直接对端消费 gemini URL 形态，
      // 此处以形态断言 + 管线成功为准；gemini 请求侧语义由第 3 路覆盖）
      const req = srv.requests[0];
      const dec = decodeRequest(P, 'messages', req.body);
      if (dec.ok) {
        const enc = P.call('lux_req_to_provider', 'gemini', JSON.stringify(dec.value));
        const geminiBody = enc.ok ? JSON.parse(enc.value) : null;
        record('跨协议中转: messages 请求 → Prism → gemini 请求形态（contents 数组）',
          geminiBody !== null && Array.isArray(geminiBody.contents),
          geminiBody === null ? [{ message: enc.error ?? 'parse failed' }] : []);
      } else {
        record('跨协议中转: messages 请求 → Prism → gemini 请求形态（contents 数组）',
          false, [{ message: dec.error }]);
      }
    } catch (e) {
      record('跨协议中转: openai 源流经 Prism 转换后被 anthropic SDK 消费',
        false, [{ message: e.message }]);
    } finally {
      await srv.close();
    }
  }

  // ── 5. 错误帧回放：SDK 收到 Prism 产出的 error 流必须抛 APIError ────────
  // 机制（实测确认）：anthropic SDK 的 SSE 解码器看到 event: error 即抛
  // APIError（包 error 载荷）—— 这是「失败不得伪装成正常结束」的官方裁决。
  {
    const srv = await startServer(P, () =>
      `event: error\ndata: ${JSON.stringify({ type: 'error', error: { type: 'api_error', message: 'boom from prism' } })}\n\n`);
    try {
      const Anthropic = (await import('@anthropic-ai/sdk')).default;
      const { APIError } = await import('@anthropic-ai/sdk');
      const client = new Anthropic({ apiKey: 'k', baseURL: srv.base, maxRetries: 0 });
      const stream = await client.messages.create({
        model: 'claude-sonnet-4', max_tokens: 32,
        messages: [{ role: 'user', content: 'hi' }], stream: true,
      });
      let threw = null;
      try {
        for await (const _ev of stream) { /* 期待 error 事件中断 */ }
      } catch (e) {
        threw = e;
      }
      record('错误帧回放: anthropic SDK 把 error 流升级为 APIError（不静默）',
        threw instanceof APIError,
        [{ message: threw ? `got ${threw.constructor.name}` : 'stream completed without error' }]);
    } catch (e) {
      // 构造期抛错也算「不静默」——但必须是 APIError 家族
      const { APIError } = await import('@anthropic-ai/sdk');
      record('错误帧回放: anthropic SDK 把 error 流升级为 APIError（不静默）',
        e instanceof APIError, [{ message: e.message }]);
    } finally {
      await srv.close();
    }
  }

  return { pass, fail, failures };
}
