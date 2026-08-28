# Python 集成示例

本示例展示如何在 Python 中直接使用 `prism.wasm` 进行协议转换。

## 完整 Gateway 实现

```python
import json
import struct
from typing import Any, Dict, List, Optional
from wasmtime import Store, Module, Instance, Memory

class PrismGateway:
    """Prism WASM 协议转换网关"""

    def __init__(self):
        self.store: Optional[Store] = None
        self.instance: Optional[Instance] = None
        self.memory: Optional[Memory] = None

    def init(self, wasm_path: str = 'prism.wasm') -> 'PrismGateway':
        """
        初始化 WASM 实例

        Args:
            wasm_path: wasm 文件路径

        Returns:
            self
        """
        from wasmtime import Store, Module, Instance

        self.store = Store()
        module = Module.from_file(self.store.engine, wasm_path)
        self.instance = Instance(self.store, module, [])
        self.memory = self.instance.exports(self.store)['memory']
        return self

    def _write_string(self, s: str) -> tuple[int, int]:
        """
        写入字符串到 WASM 内存

        Args:
            s: 要写入的字符串

        Returns:
            (ptr, len) 元组
        """
        data = s.encode('utf-8')
        length = len(data)

        # 分配内存（4 字节长度头 + 数据）
        ptr = self.instance.exports(self.store)['wasm_init_scratch'](self.store, length + 4)

        # 写入长度（小端序）
        self.memory.write(self.store, struct.pack('<I', length), ptr - 4)

        # 写入数据
        self.memory.write(self.store, data, ptr)

        return ptr, length

    def _read_string(self, ptr: int) -> str:
        """
        从 WASM 内存读取字符串

        Args:
            ptr: 字符串指针

        Returns:
            读取的字符串
        """
        # 读取长度
        length_bytes = self.memory.read(self.store, ptr - 4, ptr)
        length = struct.unpack('<I', length_bytes)[0]

        # 读取数据
        data = self.memory.read(self.store, ptr, ptr + length)
        return data.decode('utf-8')

    def convert_request(
        self,
        client_proto: str,
        request: Dict[str, Any],
        server_proto: str
    ) -> Dict[str, Any]:
        """
        转换请求

        Args:
            client_proto: 客户端协议 (openai/anthropic/gemini)
            request: 请求体
            server_proto: 服务端协议

        Returns:
            转换后的请求
        """
        req_json = json.dumps(request)
        result_ptr = self.instance.exports(self.store)['wasm_convert_req'](
            self.store, client_proto, req_json, server_proto
        )
        return json.loads(self._read_string(result_ptr))

    def convert_response(
        self,
        server_proto: str,
        response: Dict[str, Any],
        client_proto: str
    ) -> Dict[str, Any]:
        """
        转换响应

        Args:
            server_proto: 服务端协议
            response: 响应体
            client_proto: 客户端协议

        Returns:
            转换后的响应
        """
        resp_json = json.dumps(response)
        result_ptr = self.instance.exports(self.store)['wasm_convert_resp'](
            self.store, server_proto, resp_json, client_proto
        )
        return json.loads(self._read_string(result_ptr))

    def convert_stream_event(
        self,
        server_proto: str,
        event: Dict[str, Any],
        client_proto: str
    ) -> Dict[str, Any]:
        """
        转换流式事件

        Args:
            server_proto: 服务端协议
            event: SSE 事件
            client_proto: 客户端协议

        Returns:
            转换后的事件
        """
        event_json = json.dumps(event)
        result_ptr = self.instance.exports(self.store)['wasm_convert_stream_event'](
            self.store, server_proto, event_json, client_proto
        )
        return json.loads(self._read_string(result_ptr))

    def convert_stream(
        self,
        server_proto: str,
        events: List[Dict[str, Any]],
        client_proto: str
    ) -> List[Dict[str, Any]]:
        """
        转换完整流

        Args:
            server_proto: 服务端协议
            events: SSE 事件列表
            client_proto: 客户端协议

        Returns:
            转换后的事件列表
        """
        events_json = json.dumps(events)
        result_ptr = self.instance.exports(self.store)['wasm_convert_stream'](
            self.store, server_proto, events_json, client_proto
        )
        return json.loads(self._read_string(result_ptr))

    def convert_request_trace(
        self,
        client_proto: str,
        request: Dict[str, Any],
        server_proto: str
    ) -> Dict[str, Any]:
        """
        带 trace 的请求转换

        Args:
            client_proto: 客户端协议
            request: 请求体
            server_proto: 服务端协议

        Returns:
            包含 trace 的转换结果
        """
        req_json = json.dumps(request)
        result_ptr = self.instance.exports(self.store)['wasm_convert_req_trace'](
            self.store, client_proto, req_json, server_proto
        )
        return json.loads(self._read_string(result_ptr))

    def list_providers(self) -> List[str]:
        """
        列出支持的 Provider

        Returns:
            Provider ID 列表
        """
        result_ptr = self.instance.exports(self.store)['wasm_list_providers'](self.store)
        return json.loads(self._read_string(result_ptr))
```

## Flask 网关服务器

```python
from flask import Flask, request, jsonify, Response
import requests
import json
from prism_gateway import PrismGateway

app = Flask(__name__)

# 初始化 Gateway
gateway = PrismGateway()
gateway.init('prism.wasm')

print(f"Supported providers: {gateway.list_providers()}")


@app.route('/convert', methods=['POST'])
def convert():
    """通用协议转换端点"""
    try:
        data = request.json
        client_proto = data['clientProto']
        server_proto = data['serverProto']
        req_body = data['request']

        converted = gateway.convert_request(client_proto, req_body, server_proto)
        return jsonify({'success': True, 'data': converted})
    except Exception as e:
        return jsonify({'success': False, 'error': str(e)}), 400


@app.route('/v1/chat/completions', methods=['POST'])
def chat_completions():
    """OpenAI -> Anthropic 代理"""
    try:
        openai_req = request.json

        # 转换请求: OpenAI -> Anthropic
        anthropic_req = gateway.convert_request('openai', openai_req, 'anthropic')

        # 发送到 Anthropic API
        response = requests.post(
            'https://api.anthropic.com/v1/messages',
            headers={
                'Content-Type': 'application/json',
                'x-api-key': os.environ.get('ANTHROPIC_API_KEY'),
                'anthropic-version': '2023-06-01'
            },
            json=anthropic_req
        )

        anthropic_resp = response.json()

        # 转换响应: Anthropic -> OpenAI
        openai_resp = gateway.convert_response('anthropic', anthropic_resp, 'openai')
        return jsonify(openai_resp)
    except Exception as e:
        return jsonify({'error': {'message': str(e), 'type': 'server_error'}}), 500


@app.route('/v1/chat/completions/stream', methods=['POST'])
def chat_completions_stream():
    """流式代理端点"""
    try:
        openai_req = request.json

        # 转换请求
        anthropic_req = gateway.convert_request('openai', openai_req, 'anthropic')

        # 发送到 Anthropic (流式)
        response = requests.post(
            'https://api.anthropic.com/v1/messages',
            headers={
                'Content-Type': 'application/json',
                'x-api-key': os.environ.get('ANTHROPIC_API_KEY'),
                'anthropic-version': '2023-06-01'
            },
            json={**anthropic_req, 'stream': True},
            stream=True
        )

        def generate():
            for line in response.iter_lines():
                if line:
                    line = line.decode('utf-8')
                    if line.startswith('data: '):
                        data = line[6:]
                        if data == '[DONE]':
                            yield 'data: [DONE]\n\n'
                            continue

                        try:
                            event = json.loads(data)
                            # 转换事件: Anthropic -> OpenAI
                            converted = gateway.convert_stream_event(
                                'anthropic', event, 'openai'
                            )
                            yield f'data: {json.dumps(converted)}\n\n'
                        except json.JSONDecodeError:
                            pass

        return Response(
            generate(),
            mimetype='text/event-stream',
            headers={
                'Cache-Control': 'no-cache',
                'Connection': 'keep-alive'
            }
        )
    except Exception as e:
        return jsonify({'error': {'message': str(e), 'type': 'server_error'}}), 500


if __name__ == '__main__':
    import os
    port = int(os.environ.get('PORT', 3000))
    app.run(host='0.0.0.0', port=port, debug=True)
```

## 纯 WASM 调用示例

```python
import json
import struct
from wasmtime import Store, Module, Instance

def direct_wasm_call():
    """不使用 Gateway 包装器，直接调用 WASM"""

    # 加载 WASM
    store = Store()
    module = Module.from_file(store.engine, 'prism.wasm')
    instance = Instance(store, module, [])
    memory = instance.exports(store)['memory']

    # 辅助函数
    def write_string(s: str) -> int:
        data = s.encode('utf-8')
        length = len(data)
        ptr = instance.exports(store)['wasm_init_scratch'](store, length + 4)
        memory.write(store, struct.pack('<I', length), ptr - 4)
        memory.write(store, data, ptr)
        return ptr

    def read_string(ptr: int) -> str:
        length_bytes = memory.read(store, ptr - 4, ptr)
        length = struct.unpack('<I', length_bytes)[0]
        data = memory.read(store, ptr, ptr + length)
        return data.decode('utf-8')

    # OpenAI 请求
    openai_request = {
        'model': 'gpt-4',
        'messages': [
            {'role': 'user', 'content': 'Hello!'}
        ],
        'temperature': 0.7
    }

    # 转换: OpenAI -> Anthropic
    req_json = json.dumps(openai_request)
    result_ptr = instance.exports(store)['wasm_convert_req'](
        store, 'openai', req_json, 'anthropic'
    )
    anthropic_request = json.loads(read_string(result_ptr))

    print('Converted request:', json.dumps(anthropic_request, indent=2))

    # 假设收到 Anthropic 响应
    anthropic_response = {
        'id': 'msg_123',
        'type': 'message',
        'role': 'assistant',
        'content': [{'type': 'text', 'text': 'Hello! How can I help you?'}],
        'model': 'claude-3-opus-20240229',
        'stop_reason': 'end_turn'
    }

    # 转换: Anthropic -> OpenAI
    resp_json = json.dumps(anthropic_response)
    resp_ptr = instance.exports(store)['wasm_convert_resp'](
        store, 'anthropic', resp_json, 'openai'
    )
    openai_response = json.loads(read_string(resp_ptr))

    print('Converted response:', json.dumps(openai_response, indent=2))


if __name__ == '__main__':
    direct_wasm_call()
```

## 使用说明

1. 安装依赖: `pip install wasmtime requests flask`
2. 确保 `prism.wasm` 文件在可访问的路径
3. Gateway 类封装了字符串 ABI 的复杂性
4. Flask 示例展示了完整的代理服务器实现
5. 流式处理使用 SSE (Server-Sent Events) 协议

## 注意事项

- Python 的 wasmtime 库需要单独安装
- 内存读写使用 struct 模块处理字节序
- 流式响应使用 Flask 的 Response 生成器
- 生产环境建议使用 Gunicorn 或 uWSGI 部署
