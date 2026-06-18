#!/bin/bash
# extract-annotations.sh — 扫描代码中的 #@ 标注，生成 .impact-index.json 索引
#
# 用法：bash extract-annotations.sh [扫描目录] [输出文件]
# 默认：扫描 src/，输出到项目根目录的 .impact-index.json

set -euo pipefail

SCAN_DIR="${1:-src}"
OUTPUT_FILE="${2:-.impact-index.json}"

# 支持的标注类型
# #@depends-on: <file>#<symbol> | <描述>
# #@impact: <描述>
# #@flow: <condition> → <result> | <描述>
# #@route: <pattern> → <handler>
# #@state: <state> +<event> → <next>
# #@pitfall: <描述>

if [ ! -d "$SCAN_DIR" ]; then
  echo "错误：目录 $SCAN_DIR 不存在"
  exit 1
fi

echo "扫描 $SCAN_DIR 中的 #@ 标注..."

# 临时文件
TMP_FILE=$(mktemp)

# 扫描所有包含 #@ 的行
# 输出格式：文件路径:行号:标注内容
grep -rn '#@' "$SCAN_DIR" \
  --include='*.ts' \
  --include='*.tsx' \
  --include='*.js' \
  --include='*.jsx' \
  --include='*.go' \
  --include='*.py' \
  --include='*.java' \
  --include='*.rs' \
  --include='*.vue' \
  --include='*.svelte' \
  2>/dev/null > "$TMP_FILE" || true

if [ ! -s "$TMP_FILE" ]; then
  echo "未找到 #@ 标注"
  echo '{"files":{}}' > "$OUTPUT_FILE"
  rm -f "$TMP_FILE"
  exit 0
fi

# 用 Python 解析并生成 JSON
python3 - "$TMP_FILE" "$OUTPUT_FILE" << 'PYEOF'
import json
import re
import sys
from collections import defaultdict

tmp_file = sys.argv[1]
output_file = sys.argv[2]

# 标注正则
patterns = {
    'depends_on': re.compile(r'#@depends-on:\s*(\S+?)(?:\s*\|\s*(.*))?$'),
    'impact': re.compile(r'#@impact:\s*(.+?)(?:\s*\|\s*(.*))?$'),
    'flow': re.compile(r'#@flow:\s*(.+?)(?:\s*\|\s*(.*))?$'),
    'route': re.compile(r'#@route:\s*(.+?)(?:\s*\|\s*(.*))?$'),
    'state': re.compile(r'#@state:\s*(.+?)(?:\s*\|\s*(.*))?$'),
    'pitfall': re.compile(r'#@pitfall:\s*(.+)$'),
}

files_data = defaultdict(lambda: {
    'depends_on': [],
    'impacts': [],
    'flows': [],
    'routes': [],
    'states': [],
    'pitfalls': [],
    'lines': []
})

with open(tmp_file, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.rstrip('\n')
        if not line or '#@' not in line:
            continue

        # 解析 文件路径:行号:内容
        parts = line.split(':', 2)
        if len(parts) < 3:
            continue
        filepath = parts[0]
        lineno = parts[1]
        content = parts[2].strip()

        file_info = files_data[filepath]
        file_info['lines'].append(int(lineno))

        for ann_type, pattern in patterns.items():
            match = pattern.search(content)
            if match:
                if ann_type == 'depends_on':
                    target = match.group(1).strip()
                    desc = match.group(2).strip() if match.group(2) else ''
                    file_info['depends_on'].append({
                        'target': target,
                        'description': desc,
                        'line': int(lineno)
                    })
                elif ann_type == 'pitfall':
                    desc = match.group(1).strip()
                    file_info['pitfalls'].append({
                        'description': desc,
                        'line': int(lineno)
                    })
                else:
                    structured = match.group(1).strip()
                    desc = match.group(2).strip() if match.group(2) else ''
                    key = {
                        'impact': 'impacts',
                        'flow': 'flows',
                        'route': 'routes',
                        'state': 'states'
                    }[ann_type]
                    file_info[key].append({
                        'structured': structured,
                        'description': desc,
                        'line': int(lineno)
                    })
                break

# 构建反向依赖索引
# 如果 A depends_on B，则 B 被 A 依赖
impacted_by = defaultdict(list)
for filepath, data in files_data.items():
    for dep in data['depends_on']:
        target_file = dep['target'].split('#')[0]
        impacted_by[target_file].append({
            'source': filepath,
            'symbol': dep['target'].split('#')[1] if '#' in dep['target'] else '',
            'description': dep['description'],
            'line': dep['line']
        })

# 合并到输出
output = {'files': {}}
for filepath, data in files_data.items():
    data['impacted_by'] = impacted_by.get(filepath, [])
    data['lines'] = sorted(set(data['lines']))
    output['files'][filepath] = data

with open(output_file, 'w', encoding='utf-8') as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

# 统计
total_annotations = sum(
    len(data['depends_on']) + len(data['impacts']) + len(data['flows']) +
    len(data['routes']) + len(data['states']) + len(data['pitfalls'])
    for data in files_data.values()
)
print(f"已生成索引：{output_file}")
print(f"  文件数：{len(files_data)}")
print(f"  标注总数：{total_annotations}")
print(f"  反向依赖关系：{sum(len(v) for v in impacted_by.values())}")
PYEOF

rm -f "$TMP_FILE"
echo "完成。"
