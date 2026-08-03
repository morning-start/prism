"""Phase 4 Task 1: 应用 moon check 报告的 unnecessary_annotation 修复。

从 warn3.log 解析每个 Warning: [0073] 块的位置 (file, line, col) 与注解类型，
在该精确位置删除多余前缀（`Type::` 或 `@lux.`）。编译器确认这些前缀多余，
删除后语义不变；删除后由 moon test 全量回归验证。
"""
import re
import sys

warn = open('warn3.log', encoding='utf-8', errors='replace').read()
lines = warn.splitlines()

pat_path = re.compile(r'\[ (E:.*?prism\\([a-z_\\]+\.mbt)):(\d+):(\d+) \]')
pat_annot_type = re.compile(r'This `([A-Za-z_]+)::` annotation is unnecessary')
pat_annot_at = re.compile(r'This `@lux\.` annotation is unnecessary')
pat_annot_at_type = re.compile(r'This `(@lux\.[A-Za-z_]+)::` annotation is unnecessary')

# 收集 (file, line, col, prefix)
fixes = []  # (file, line, col, prefix_len, prefix_text)
i = 0
while i < len(lines):
    if 'Warning: [0073]' in lines[i]:
        path_m = None
        prefix = None
        for k in range(1, 8):
            if i + k >= len(lines):
                break
            if path_m is None:
                path_m = pat_path.search(lines[i + k])
            if prefix is None:
                m3 = pat_annot_at_type.search(lines[i + k])
                m1 = pat_annot_type.search(lines[i + k])
                m2 = pat_annot_at.search(lines[i + k])
                if m3:
                    prefix = m3.group(1) + '::'
                elif m1:
                    prefix = m1.group(1) + '::'
                elif m2:
                    prefix = '@lux.'
            if path_m and prefix:
                break
        if path_m and prefix:
            f = path_m.group(2).replace('\\', '/')
            ln = int(path_m.group(3))
            col = int(path_m.group(4))
            fixes.append((f, ln, col, prefix))
    i += 1

print(f"解析到 {len(fixes)} 处修复")

# 按文件分组，行内按 col 降序（避免同行动态偏移）
by_file = {}
for f, ln, col, prefix in fixes:
    by_file.setdefault(f, []).append((ln, col, prefix))

applied = 0
for f, items in sorted(by_file.items()):
    try:
        src_lines = open(f, encoding='utf-8', errors='replace').read().split('\n')
    except OSError as e:
        print(f"SKIP {f}: {e}")
        continue
    # 同文件按行分组，行内 col 降序
    per_line = {}
    for ln, col, prefix in items:
        per_line.setdefault(ln, []).append((col, prefix))
    changed = False
    for ln, col_prefixes in per_line.items():
        idx = ln - 1
        if idx < 0 or idx >= len(src_lines):
            print(f"WARN {f}:{ln} out of range")
            continue
        line = src_lines[idx]
        for col, prefix in sorted(col_prefixes, reverse=True):
            start = col - 1
            if start < 0 or start + len(prefix) > len(line):
                print(f"WARN {f}:{ln} col {col} prefix {prefix!r} out of bounds in {line!r}")
                continue
            if line[start:start + len(prefix)] != prefix:
                print(f"WARN {f}:{ln} col {col} expected {prefix!r} got {line[start:start+len(prefix)]!r} in {line!r}")
                continue
            line = line[:start] + line[start + len(prefix):]
        if line != src_lines[idx]:
            src_lines[idx] = line
            changed = True
    if changed:
        open(f, 'w', encoding='utf-8', newline='').write('\n'.join(src_lines))
        applied += len(items)
        print(f"APPLIED {len(items)} fixes -> {f}")

print(f"共应用 {applied} / {len(fixes)} 处修复")
