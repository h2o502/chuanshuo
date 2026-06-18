#!/bin/bash
# check-impact.sh — 检查指定文件的影响范围，输出影响报告
#
# 用法：bash check-impact.sh <目标文件> [索引文件]
# 默认索引文件：.impact-index.json

set -euo pipefail

TARGET_FILE="${1:-}"
INDEX_FILE="${2:-.impact-index.json}"

if [ -z "$TARGET_FILE" ]; then
  echo "用法：bash check-impact.sh <目标文件> [索引文件]"
  exit 1
fi

if [ ! -f "$TARGET_FILE" ]; then
  echo "错误：文件 $TARGET_FILE 不存在"
  exit 1
fi

if [ ! -f "$INDEX_FILE" ]; then
  echo "警告：索引文件 $INDEX_FILE 不存在，将只检查文件内联标注"
  HAS_INDEX=0
else
  HAS_INDEX=1
fi

# 读取高风险清单（从 PROJECT_MEMORY.md）
HIGH_RISK_PATTERNS=""
if [ -f "PROJECT_MEMORY.md" ]; then
  # 提取高风险清单部分（跳过标题行，到下一个 ## 标题结束）
  HIGH_RISK_PATTERNS=$(awk '/^## 高风险文件/{f=1; next} /^## /{f=0} f && /^- /' PROJECT_MEMORY.md 2>/dev/null | sed 's/^- //' | sed 's/ .*//' || true)
fi

# 检查是否高风险（用 here-string 避免子 shell 陷阱）
is_high_risk() {
  local file="$1"
  if [ -z "$HIGH_RISK_PATTERNS" ]; then
    echo "low"
    return
  fi
  local pattern regex
  while IFS= read -r pattern; do
    [ -z "$pattern" ] && continue
    # 将 glob pattern 转为正则：** → .*，* → [^/]*，. → \.
    regex=$(echo "$pattern" | sed 's/\*\*/§§§/g; s/\*/[^\/]*/g; s/§§§/.*/g; s/\./\\./g')
    if echo "$file" | grep -qE "$regex" 2>/dev/null; then
      echo "high"
      return
    fi
  done <<< "$HIGH_RISK_PATTERNS"
  echo "low"
}

RISK_LEVEL=$(is_high_risk "$TARGET_FILE")

echo "=== 影响检查报告 ==="
echo "目标文件：$TARGET_FILE"
echo "风险等级：$RISK_LEVEL"

if [ "$RISK_LEVEL" = "high" ]; then
  echo "（在高风险清单中）"
else
  echo "（不在高风险清单中）"
fi

echo ""

# 1. 提取文件内的 #@ 标注
echo "直接依赖（本文件标注）："
FILE_ANNOTATIONS=$(grep -n '#@' "$TARGET_FILE" 2>/dev/null || true)

if [ -z "$FILE_ANNOTATIONS" ]; then
  echo "  （无标注）"
else
  echo "$FILE_ANNOTATIONS" | while IFS= read -r line; do
    echo "  $line" | sed 's/^/  /'
  done
fi

echo ""

# 2. 从索引查反向依赖
if [ "$HAS_INDEX" = "1" ]; then
  echo "反向依赖（谁依赖本文件）："
  python3 - "$INDEX_FILE" "$TARGET_FILE" << 'PYEOF'
import json
import sys

index_file = sys.argv[1]
target_file = sys.argv[2]

with open(index_file, 'r', encoding='utf-8') as f:
    index = json.load(f)

# 查找谁依赖目标文件
impacted_by = []
for filepath, data in index.get('files', {}).items():
    for dep in data.get('depends_on', []):
        dep_file = dep['target'].split('#')[0]
        # 模糊匹配（处理相对路径差异）
        if dep_file == target_file or dep_file.endswith(target_file) or target_file.endswith(dep_file):
            impacted_by.append({
                'source': filepath,
                'symbol': dep['target'].split('#')[1] if '#' in dep['target'] else '',
                'description': dep.get('description', ''),
                'line': dep['line']
            })

if not impacted_by:
    print("  （无反向依赖）")
else:
    # 按来源文件分组统计
    source_counts = {}
    for item in impacted_by:
        src = item['source']
        if src not in source_counts:
            source_counts[src] = 0
        source_counts[src] += 1

    for src, count in source_counts.items():
        print(f"  {src} ({count}处引用)")
        for item in impacted_by:
            if item['source'] == src and item['symbol']:
                desc = f" | {item['description']}" if item['description'] else ""
                print(f"    → {item['symbol']}{desc}")

# 查找目标文件自身的标注
target_data = index.get('files', {}).get(target_file, {})
if not target_data:
    # 尝试模糊匹配
    for filepath, data in index.get('files', {}).items():
        if filepath == target_file or filepath.endswith(target_file) or target_file.endswith(filepath):
            target_data = data
            break

pitfalls = target_data.get('pitfalls', [])
if pitfalls:
    print()
    print("踩坑警告：")
    for p in pitfalls:
        print(f"  ⚠️ {p['description']} (line {p['line']})")

impacts = target_data.get('impacts', [])
if impacts:
    print()
    print("影响范围：")
    for imp in impacts:
        desc = f" | {imp['description']}" if imp['description'] else ""
        print(f"  {imp['structured']}{desc}")
PYEOF
fi

echo ""
echo "建议：改完后验证相关功能是否正常"
if [ "$RISK_LEVEL" = "high" ]; then
  echo "状态：⚠️ 高风险，等待用户确认"
else
  echo "状态：✅ 低风险，可继续"
fi
