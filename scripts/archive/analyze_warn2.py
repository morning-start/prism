import re, collections

warn = open('warn2.log', encoding='utf-8', errors='replace').read()
lines = warn.splitlines()
pat_path = re.compile(r'\[ (E:.*?prism\\([a-z_\\]+\.mbt)):(\d+):(\d+) \]')
pat_annot = re.compile(r'This `([A-Za-z_@]+)::` annotation is unnecessary')
results = []
i = 0
while i < len(lines):
    if 'Warning: [0073]' in lines[i]:
        path_m = None
        annot = None
        for k in range(1, 8):
            if i + k >= len(lines):
                break
            if path_m is None:
                path_m = pat_path.search(lines[i + k])
            if annot is None:
                am = pat_annot.search(lines[i + k])
                if am:
                    annot = am.group(1)
            if path_m and annot:
                break
        if path_m and annot:
            f = path_m.group(2).replace('\\', '/')
            results.append((f, path_m.group(3), path_m.group(4), annot))
    i += 1
print("剩余警告数:", len(results))
for f, ln, col, a in results:
    print(f"{f}:{ln}:{col}  {a}::")
