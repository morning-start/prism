import re, collections, os

warn = open('warn.log', encoding='utf-8', errors='replace').read()
lines = warn.splitlines()

pat_path = re.compile(r'\[ (E:.*?prism\\([a-z_\\]+\.mbt)):(\d+):(\d+) \]')
pat_annot = re.compile(r'This `([A-Za-z_]+)::` annotation is unnecessary')
pat_annot_lux = re.compile(r'This `@lux\.` annotation is unnecessary')

# 收集警告位置: (file, line, prefix_kind)  prefix_kind: 'Type::' 或 '@lux.'
results = []
i = 0
while i < len(lines):
    if 'Warning: [0073]' in lines[i]:
        path_m = None
        kind = None
        for k in range(1, 8):
            if i + k >= len(lines):
                break
            if path_m is None:
                path_m = pat_path.search(lines[i + k])
            if kind is None:
                m1 = pat_annot.search(lines[i + k])
                m2 = pat_annot_lux.search(lines[i + k])
                if m1:
                    kind = ('type', m1.group(1))
                elif m2:
                    kind = ('at', '')
            if path_m and kind:
                break
        if path_m and kind:
            f = path_m.group(2).replace('\\', '/')
            ln = int(path_m.group(3))
            results.append((f, ln, kind))
    i += 1

# 对每个文件，统计被警告的前缀种类
by_file = collections.defaultdict(set)
for f, ln, kind in results:
    by_file[f].add(kind)

# 对每个文件检查该前缀的所有出现是否都被警告
print("=== 每个文件的警告前缀与总出现数对比 ===")
for f in sorted(by_file):
    kinds = by_file[f]
    src = open(f, encoding='utf-8', errors='replace').read()
    for kind in kinds:
        if kind[0] == 'type':
            prefix = kind[1] + '::'
            total = len(re.findall(re.escape(prefix), src))
            warned = sum(1 for _, ln, k in results if k == kind and _ == f)
            print(f"{f}: {prefix}  warned={warned}  total={total}  {'SAFE' if warned == total else 'PARTIAL'}")
        else:
            # @lux. 前缀（跨包引用，可能带具体类型名，如 @lux.User 或 @lux.LucentRole::User）
            total_at = len(re.findall(r'@lux\.', src))
            warned = sum(1 for _, ln, k in results if k[0] == 'at' and _ == f)
            print(f"{f}: @lux.  warned={warned}  total={total_at}  {'SAFE' if warned == total_at else 'PARTIAL'}")
