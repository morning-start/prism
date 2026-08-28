# JavaScript 集成示例

本示例展示如何在 JavaScript/Node.js 中直接使用 `prism.wasm` 进行协议转换。

## 完整 Gateway 实现

```javascript
class PrismGateway {
  constructor() {
    this.instance = null;
    this.memory = null;
  }

  /**
   * 初始化 WASM 实例
   * @param {string} wasmPath - wasm 文件路径
   */
  async init(wasmPath = 'prism.wasm') {
    const wasmBytes = await fetch(wasmPath).then(r => r.arrayBuffer());
    this.memory = new WebAssembly.Memory({ initial: 256, maximum: 65536 });
    const { instance } = await WebAssembly.instantiate(wasmBytes, {
      env: { memory: this.memory }
    });
    this.instance = instance;
    return this;
  }

  /**
   * 写入字符串到 WASM 内存
   * @param {string} str - 要写入的字符串
   * @returns {{ ptr: number, len: number }}
   */
  _writeString(str) {
    const bytes = new TextEncoder().encode(str);
    const len = bytes.length;
    const ptr = this.instance.exports.wasm_init_scratch(len + 4);
    new DataView(this.memory.buffer).setUint32(ptr - 4, len, true);
    new Uint8Array(this.memory.buffer, ptr, len).set(bytes);
    return { ptr, len };
  }

  /**
   * 从 WASM 内存读取字符串
   * @param {number} ptr - 字符串指针
   * @returns {string}
   */
  _readString(ptr) {
    const len = new DataView(this.memory.buffer).getUint32(ptr - 4, true);
    const bytes = new Uint8Array(this.memory.buffer, ptr, len);
    return new TextDecoder().decode(bytes);
  }

  /**
   * 转换请求
   * @param {string} clientProto - 客户端协议 (openai/anthropic/gemini)
   * @param {object} request - 请求体
   * @param {string} serverProto - 服务端协议
   * @returns {object} 转换后的请求
   */
  convertRequest(clientProto, request, serverProto) {
    const reqJson = JSON.stringify(request);
    const resultPtr = this.instance.exports.wasm_convert_req(
      clientProto, reqJson, serverProto
    );
    return JSON.parse(this._readString(resultPtr));
  }

  /**
   * 转换响应
   * @param {string} serverProto - 服务端协议
   * @param {object} response - 响应体
   * @param {string} clientProto - 客户端协议
   * @returns {object} 转换后的响应
   */
  convertResponse(serverProto, response, clientProto) {
    const respJson = JSON.stringify(response);
    const resultPtr = this.instance.exports.wasm_convert_resp(
      serverProto, respJson, clientProto
    );
    return JSON.parse(this._readString(resultPtr));
  }

  /**
   * 转换流式事件
   * @param {string} serverProto - 服务端协议
   * @param {object} event - SSE 事件
   * @param {string} clientProto - 客户端协议
   * @returns {object} 转换后的事件
   */
  convertStreamEvent(serverProto, event, clientProto) {
    const eventJson = JSON.stringify(event);
    const resultPtr = this.instance.exports.wasm_convert_stream_event(
      serverProto, eventJson, clientProto
    );
    return JSON.parse(this._readString(resultPtr));
  }

  /**
   * 转换完整流
   * @param {string} serverProto - 服务端协议
   * @param {object[]} events - SSE 事件数组
   * @param {string} clientProto - 客户端协议
   * @returns {object} 转换后的事件数组
   */
  convertStream(serverProto, events, clientProto) {
    const eventsJson = JSON.stringify(events);
    const resultPtr = this.instance.exports.wasm_convert_stream(
      serverProto, eventsJson, clientProto
    );
    return JSON.parse(this._readString(resultPtr));
  }

  /**
   * 带 trace 的请求转换
   * @param {string} clientProto - 客户端协议
   * @param {object} request - 请求体
   * @param {string} serverProto - 服务端协议
   * @returns {object} 包含 trace 的转换结果
   */
  convertRequestTrace(clientProto, request, serverProto) {
    const reqJson = JSON.stringify(request);
    const resultPtr = this.instance.exports.wasm_convert_req_trace(
      clientProto, reqJson, serverProto
    );
    return JSON.parse(this._readString(resultPtr));
  }

  /**
   * 列出支持的 Provider
   * @returns {string[]} Provider ID 列表
   */
  listProviders() {
    const resultPtr = this.instance.exports.wasm_list_providers();
    return JSON.parse(this._readString(resultPtr));
  }
}

export default PrismGateway;
```

## Express 网关服务器

```javascript
import express from 'express';
import PrismGateway from './prism-gateway.js';

const app = express();
app.use(express.json());

// 初始化 Gateway
const gateway = new PrismGateway();
await gateway.init('prism.wasm');

console.log('Supported providers:', gateway.listProviders());

/**
 * 通用协议转换端点
 * POST /convert
 * Body: { clientProto, serverProto, request }
 */
app.post('/convert', async (req, res) => {
  try {
    const { clientProto, serverProto, request } = req.body;
    const converted = gateway.convertRequest(clientProto, request, serverProto);
    res.json({ success: true, data: converted });
  } catch (error) {
    res.status(400).json({ success: false, error: error.message });
  }
});

/**
 * OpenAI -> Anthropic 代理
 * POST /v1/chat/completions
 */
app.post('/v1/chat/completions', async (req, res) => {
  try {
    // 转换请求: OpenAI -> Anthropic
    const anthropicReq = gateway.convertRequest('openai', req.body, 'anthropic');

    // 发送到 Anthropic API
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify(anthropicReq)
    });

    const anthropicResp = await response.json();

    // 转换响应: Anthropic -> OpenAI
    const openaiResp = gateway.convertResponse('anthropic', anthropicResp, 'openai');
    res.json(openaiResp);
  } catch (error) {
    res.status(500).json({ error: { message: error.message, type: 'server_error' } });
  }
});

/**
 * 流式代理端点
 * POST /v1/chat/completions/stream
 */
app.post('/v1/chat/completions/stream', async (req, res) => {
  try {
    // 转换请求
    const anthropicReq = gateway.convertRequest('openai', req.body, 'anthropic');

    // 设置 SSE
    res.writeHead(200, {
      'Content-Type': 'text/event-stream',
      'Cache-Control': 'no-cache',
      'Connection': 'keep-alive'
    });

    // 发送到 Anthropic (流式)
    const response = await fetch('https://api.anthropic.com/v1/messages', {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        'x-api-key': process.env.ANTHROPIC_API_KEY,
        'anthropic-version': '2023-06-01'
      },
      body: JSON.stringify({ ...anthropicReq, stream: true })
    });

    // 处理 SSE 流
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = '';

    while (true) {
      const { done, value } = await reader.read();
      if (done) break;

      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split('\n');
      buffer = lines.pop() || '';

      for (const line of lines) {
        if (line.startsWith('data: ')) {
          const data = line.slice(6);
          if (data === '[DONE]') {
            res.write('data: [DONE]\n\n');
            continue;
          }

          try {
            const event = JSON.parse(data);
            // 转换事件: Anthropic -> OpenAI
            const converted = gateway.convertStreamEvent('anthropic', event, 'openai');
            res.write(`data: ${JSON.stringify(converted)}\n\n`);
          } catch (e) {
            // 忽略解析错误
          }
        }
      }
    }

    res.end();
  } catch (error) {
    res.status(500).json({ error: { message: error.message, type: 'server_error' } });
  }
});

// 启动服务器
const PORT = process.env.PORT || 3000;
app.listen(PORT, () => {
  console.log(`Prism Gateway running on port ${PORT}`);
});
```

## 纯 WASM 调用示例

```javascript
// 不使用 Gateway 包装器，直接调用 WASM
async function directWasmCall() {
  // 加载 WASM
  const wasmBytes = await fetch('prism.wasm').then(r => r.arrayBuffer());
  const memory = new WebAssembly.Memory({ initial: 256, maximum: 65536 });
  const { instance } = await WebAssembly.instantiate(wasmBytes, {
    env: { memory }
  });

  // 辅助函数
  function writeString(str) {
    const bytes = new TextEncoder().encode(str);
    const len = bytes.length;
    const ptr = instance.exports.wasm_init_scratch(len + 4);
    new DataView(memory.buffer).setUint32(ptr - 4, len, true);
    new Uint8Array(memory.buffer, ptr, len).set(bytes);
    return ptr;
  }

  function readString(ptr) {
    const len = new DataView(memory.buffer).getUint32(ptr - 4, true);
    const bytes = new Uint8Array(memory.buffer, ptr, len);
    return new TextDecoder().decode(bytes);
  }

  // OpenAI 请求
  const openaiRequest = {
    model: 'gpt-4',
    messages: [
      { role: 'user', content: 'Hello!' }
    ],
    temperature: 0.7
  };

  // 转换: OpenAI -> Anthropic
  const reqJson = JSON.stringify(openaiRequest);
  const resultPtr = instance.exports.wasm_convert_req('openai', reqJson, 'anthropic');
  const anthropicRequest = JSON.parse(readString(resultPtr));

  console.log('Converted request:', anthropicRequest);

  // 假设收到 Anthropic 响应
  const anthropicResponse = {
    id: 'msg_123',
    type: 'message',
    role: 'assistant',
    content: [{ type: 'text', text: 'Hello! How can I help you?' }],
    model: 'claude-3-opus-20240229',
    stop_reason: 'end_turn'
  };

  // 转换: Anthropic -> OpenAI
  const respJson = JSON.stringify(anthropicResponse);
  const respPtr = instance.exports.wasm_convert_resp('anthropic', respJson, 'openai');
  const openaiResponse = JSON.parse(readString(respPtr));

  console.log('Converted response:', openaiResponse);
}

directWasmCall().catch(console.error);
```

## 使用说明

1. 确保 `prism.wasm` 文件在可访问的路径
2. Gateway 类封装了字符串 ABI 的复杂性
3. Express 示例展示了完整的代理服务器实现
4. 流式处理使用 SSE (Server-Sent Events) 协议
