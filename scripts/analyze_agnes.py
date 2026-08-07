#!/usr/bin/env python3
# 分析 agnes 探测结果：tmp/agnes_resp.json（非流式）+ tmp/agnes_sse.txt（流式）
# 结论：是否返回 reasoning / reasoning_content / thinking 字段（V1/V3 前提）
import json, sys, re

def analyze_nonstream(path):
    print(f"=== 非流式 {path} ===")
    try:
        raw = open(path, encoding='utf-8', errors='replace').read()
        d = json.loads(raw)
    except Exception as e:
        print(f"  [解析失败] {e}")
        return {}
    if 'error' in d:
        print(f"  [API 错误] {json.dumps(d['error'], ensure_ascii=False)[:200]}")
        return {}
    keys = set()
    try:
        msg = d['choices'][0]['message']
        keys = set(msg.keys())
        print(f"  message 字段: {sorted(keys)}")
        for k in ('reasoning', 'reasoning_content', 'thinking', 'content'):
            v = msg.get(k)
            if v:
                s = v if isinstance(v, str) else json.dumps(v, ensure_ascii=False)
                print(f"  {k}: {s[:150]}")
    except Exception as e:
        print(f"  [结构异常] {e}")
    return keys

def analyze_stream(path):
    print(f"=== 流式 {path} ===")
    try:
        raw = open(path, encoding='utf-8', errors='replace').read()
    except Exception as e:
        print(f"  [读取失败] {e}")
        return set()
    found = set()
    delta_keys = set()
    for m in re.finditer(r'"delta"\s*:\s*\{([^}]*)\}', raw):
        for k in ('reasoning', 'reasoning_content', 'thinking', 'content', 'role'):
            if f'"{k}"' in m.group(1):
                found.add(k)
    print(f"  流中 delta 出现的字段: {sorted(found) or '（无）'}")
    # 也看看整体顶层字段
    toplevel = set(re.findall(r'"([a-z_]+)"\s*:', raw))
    print(f"  顶层出现字段(部分): {sorted(toplevel & {'id','model','choices','usage','error'})}")
    return found

if __name__ == '__main__':
    r = analyze_nonstream('tmp/agnes_resp.json')
    s = analyze_stream('tmp/agnes_sse.txt')
    rk = r & {'reasoning', 'reasoning_content', 'thinking'}
    sk = s & {'reasoning', 'reasoning_content', 'thinking'}
    print("\n=== 结论 ===")
    print(f"  非流式含推理字段: {sorted(rk) if rk else '无'}")
    print(f"  流式含推理字段:   {sorted(sk) if sk else '无'}")
    if rk or sk:
        print("  → 可走 openai-vllm 子协议真实链路验证")
    else:
        print("  → agnes 不返回 reasoning；模型可能无思考模式，需换 agnes 推理模型或加 thinking 参数")
