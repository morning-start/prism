# String ABI Specification

How strings pass between host and WASM in prism.wasm.

> **2026-10-25 修订（TASK-2c）**：本规范曾把长度头单位记为"字节"，
> 经 `scripts/wasm_smoke.mjs` 全链路验证，实际单位是 **UTF-16 code units**。
> 且两个 wasm 后端的字符串通道不同——按后端区分阅读。

## 后端差异（关键！）

| 后端 | String 参数传入 | String 返回值 | 说明 |
|---|---|---|---|
| **wasm-gc**（推荐宿主） | 直接传 JS string | 直接收 JS string | `use-js-builtin-string` 开启，MoonBit String ABI = JS string。宿主须以 `WebAssembly.instantiate(bytes, {}, { builtins: ['js-string'], importedStringConstants: '_' })` 实例化 |
| **wasm**（纯线性内存） | scratch 协议（下述） | 线性内存指针（下述） | MoonBit String 是 GC 对象，i32 指针 + 长度头交换 |

## 纯 wasm 后端：scratch 协议（String 参数）

```
┌──────────────────┬──────────────────────┐
│ Length (u32 LE)  │ UTF-16LE Data        │
│ code-unit 数     │ (length × 2 字节)    │
└──────────────────┴──────────────────────┘
  offset - 4         offset
```

- **Length**: u32 little-endian，单位是 **UTF-16 code units**（不是字节）
- **offset 必须 ≥ 8**：`wasm_init_scratch` 返回的指针指向 MoonBit 8 字节
  对象头（rc + meta）之后的载荷，`offset - 4` 不能落入对象头
- 多参数用不同 offset（stride 8192 推荐）

```javascript
const bufPtr = exports.wasm_init_scratch(65536);
function putArg(offset, str) {
  const dv = new DataView(memory.buffer); // memory 可能增长，每次现取
  dv.setUint32(bufPtr + offset - 4, str.length, true); // code units
  for (let i = 0; i < str.length; i++)
    dv.setUint16(bufPtr + offset + i * 2, str.charCodeAt(i), true);
}
putArg(8, 'openai'); putArg(8192, reqJson); putArg(16384, 'messages');
const outPtr = exports.wasm_convert_req(bufPtr + 8, bufPtr + 8192, bufPtr + 16384);
```

## 纯 wasm 后端：读取返回值（String 出）

返回值是线性内存指针，`ptr - 4` 处 u32 LE 存 **UTF-16 code-unit 数**：

```javascript
function readString(ptr) {
  const dv = new DataView(memory.buffer);
  const len = dv.getUint32(ptr - 4, true); // code units
  let r = '';
  for (let i = 0; i < len; i++) r += String.fromCharCode(dv.getUint16(ptr + i * 2, true));
  return r;
}
```

⚠️ memory 可能因 wasm 内部分配而增长：任何 `memory.buffer` 引用都要在
每次交互时重新获取（旧 buffer 会 detach）。

## wasm-gc 后端

```javascript
const { instance } = await WebAssembly.instantiate(bytes, {}, {
  builtins: ['js-string'],
  importedStringConstants: '_',
});
// String 参数直接传 JS string，返回值直接是 JS string：
const env = JSON.parse(instance.exports.wasm_convert_req('openai', reqJson, 'messages'));
```

注意：`wasm_init_scratch` / `wasm_log_init` / `wasm_log_pos` /
`wasm_read_scratch_arg` 在 wasm-gc/js 后端是**降级实现**（返回 0 或错误
信封）——宿主托管内存下线性内存指针技巧不存在。String 直传即可，无需
scratch。

## 信封契约（两后端一致）

所有转换导出返回 JSON 信封字符串：
`{"value": "<目标协议 JSON>", "diagnostics": [{"field", "status", "detail"}]}`
错误形态：`{"error": "message", "diagnostics": []}`。诊断绝不静默丢弃。
