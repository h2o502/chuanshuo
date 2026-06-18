#!/bin/bash
# check-impact.sh — 检查指定文件的影响范围，输出影响报告
#
# 用法：bash check-impact.sh <目标文件> [选项]
# 选项：
#   --index <file>   指定索引文件（默认 .impact-index.json）
#   --json           输出 JSON 格式（供 AI 可靠解析）
#   --no-skip        禁用白名单跳过，强制完整检查
#   --help, -h       显示帮助

set -euo pipefail

# 依赖检查
if ! command -v python3 >/dev/null 2>&1; then
  echo "错误：未找到 python3，本脚本依赖 python3 解析索引。" >&2
  exit 2
fi

# ===== 参数解析 =====
TARGET_FILE=""
INDEX_FILE=".impact-index.json"
OUTPUT_JSON=0
NO_SKIP=0

print_help() {
  cat <<'HELP'
check-impact.sh — 检查指定文件的影响范围

用法：bash check-impact.sh <目标文件> [选项]

选项：
  --index <file>   指定索引文件（默认 .impact-index.json）
  --json           输出 JSON 格式（供 AI 可靠解析）
  --no-skip        禁用白名单跳过，强制完整检查
  --help, -h       显示本帮助

白名单（默认跳过完整检查，仅报告风险等级）：
  *.md / README* / LICENSE / .gitignore / .impact-index.json / skills/_meta.json

退出码：
  0  正常
  1  参数错误 / 文件不存在
  2  依赖缺失
HELP
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_help; exit 0 ;;
    --json) OUTPUT_JSON=1; shift ;;
    --no-skip) NO_SKIP=1; shift ;;
    --index) INDEX_FILE="${2:-}"; shift 2 ;;
    --index=*) INDEX_FILE="${1#--index=}"; shift ;;
    --*) echo "未知选项：$1" >&2; exit 1 ;;
    *)
      if [ -z "$TARGET_FILE" ]; then
        TARGET_FILE="$1"
      else
        echo "错误：多余参数 $1" >&2; exit 1
      fi
      shift ;;
  esac
done

if [ -z "$TARGET_FILE" ]; then
  echo "用法：bash check-impact.sh <目标文件> [选项]"
  echo "运行 --help 查看完整帮助"
  exit 1
fi

if [ ! -f "$TARGET_FILE" ]; then
  echo "错误：文件 $TARGET_FILE 不存在" >&2
  exit 1
fi

# ===== 白名单判断（减少仪式负担） =====
# 这些文件显然不需要影响检查：文档、传火自身文件、忽略文件
is_whitelisted() {
  local file="$1"
  local base
  base=$(basename "$file")
  case "$base" in
    README*|LICENSE|.gitignore|.impact-index.json|_meta.json) return 0 ;;
  esac
  case "$file" in
    *.md) return 0 ;;
    */skills/_meta.json) return 0 ;;
  esac
  return 1
}

SKIPPED=0
if [ "$NO_SKIP" = "0" ] && is_whitelisted "$TARGET_FILE"; then
  SKIPPED=1
fi

# ===== 读取高风险清单 =====
HIGH_RISK_PATTERNS=""
if [ -f "PROJECT_MEMORY.md" ]; then
  HIGH_RISK_PATTERNS=$(awk '/^## 高风险文件/{f=1; next} /^## /{f=0} f && /^- /' PROJECT_MEMORY.md 2>/dev/null | sed 's/^- //' | sed 's/ .*//' || true)
fi

# glob → 正则转换（用 Python 处理，避免 sed 的 \x01 和 brace 兼容问题）
is_high_risk() {
  local file="$1"
  if [ -z "$HIGH_RISK_PATTERNS" ]; then
    echo "low"; return
  fi
  local result
  result=$(python3 - "$file" "$HIGH_RISK_PATTERNS" << 'PYEOF'
import re, sys

file = sys.argv[1]
patterns = sys.argv[2].split('\n')

def glob_to_regex(pattern):
    """把 glob pattern 转成正则：** → .*, * → [^/]*, {a,b} → (a|b)"""
    # 先处理 brace expansion {a,b} → \x01ts\x02json\x03（占位符保护）
    # \x01 = (, \x02 = |, \x03 = )
    def brace_repl(m):
        return '\x01' + m.group(1).replace(',', '\x02') + '\x03'
    pattern = re.sub(r'\{([^}]*)\}', brace_repl, pattern)
    # ** → \x04（占位符），转义元字符，再还原
    pattern = pattern.replace('**', '\x04')
    pattern = re.escape(pattern)
    pattern = pattern.replace('\x04', '.*')
    pattern = pattern.replace(r'\*', '[^/]*')
    # 还原 brace expansion 占位符
    pattern = pattern.replace('\x01', '(').replace('\x02', '|').replace('\x03', ')')
    return pattern

for pattern in patterns:
    pattern = pattern.strip()
    if not pattern:
        continue
    try:
        regex = glob_to_regex(pattern)
        if re.match('^' + regex + '$', file):
            print('high')
            sys.exit(0)
    except re.error:
        continue
print('low')
PYEOF
  )
  echo "$result"
}

RISK_LEVEL=$(is_high_risk "$TARGET_FILE")

# ===== 索引过期检测 =====
# 比对索引 mtime 与 src/ 下代码文件 mtime，找出索引生成后被修改的文件
INDEX_STALE=0
STALE_FILES=""
if [ -f "$INDEX_FILE" ]; then
  INDEX_MTIME=$(stat -c %Y "$INDEX_FILE" 2>/dev/null || stat -f %m "$INDEX_FILE" 2>/dev/null || echo 0)
  if [ "$INDEX_MTIME" != "0" ] && [ -d "src" ]; then
    STALE_FILES=$(find src -type f \
      \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
         -o -name '*.go' -o -name '*.py' -o -name '*.java' -o -name '*.rs' \
         -o -name '*.vue' -o -name '*.svelte' \) \
      -newer "$INDEX_FILE" 2>/dev/null || true)
    if [ -n "$STALE_FILES" ]; then
      INDEX_STALE=1
    fi
  fi
fi

# ===== 跳过模式：仅输出风险等级 =====
if [ "$SKIPPED" = "1" ]; then
  if [ "$OUTPUT_JSON" = "1" ]; then
    python3 -c "
import json, sys
print(json.dumps({
  'target_file': sys.argv[1],
  'risk_level': sys.argv[2],
  'skipped': True,
  'reason': '文件在白名单中，跳过完整影响检查',
  'index_stale': False,
  'status': '✅ 已跳过（白名单）'
}, ensure_ascii=False, indent=2))
" "$TARGET_FILE" "$RISK_LEVEL"
  else
    echo "=== 影响检查报告 ==="
    echo "目标文件：$TARGET_FILE"
    echo "风险等级：$RISK_LEVEL"
    echo "状态：✅ 已跳过（白名单文件，无需完整检查）"
  fi
  exit 0
fi

# ===== 完整检查 =====
HAS_INDEX=0
if [ -f "$INDEX_FILE" ]; then
  HAS_INDEX=1
fi

# 提取文件内联标注
FILE_ANNOTATIONS=$(grep -n '#@' "$TARGET_FILE" 2>/dev/null || true)

# 调用 Python 生成报告（同时支持文本和 JSON 输出）
python3 - "$TARGET_FILE" "$INDEX_FILE" "$RISK_LEVEL" "$HAS_INDEX" \
         "$INDEX_STALE" "$STALE_FILES" "$OUTPUT_JSON" "$FILE_ANNOTATIONS" << 'PYEOF'
import json
import sys

target_file = sys.argv[1]
index_file = sys.argv[2]
risk_level = sys.argv[3]
has_index = sys.argv[4] == '1'
index_stale = sys.argv[5] == '1'
stale_files = sys.argv[6].split('\n') if sys.argv[6] else []
output_json = sys.argv[7] == '1'
file_annotations_raw = sys.argv[8]

# 解析内联标注
annotations = []
if file_annotations_raw:
    for line in file_annotations_raw.split('\n'):
        if line.strip():
            annotations.append(line)

# 从索引查反向依赖、踩坑、影响
impacted_by = []
pitfalls = []
impacts = []

if has_index:
    try:
        with open(index_file, 'r', encoding='utf-8') as f:
            index = json.load(f)
    except (json.JSONDecodeError, IOError):
        index = {'files': {}}

    files = index.get('files', {})

    # 查找谁依赖目标文件
    for filepath, data in files.items():
        for dep in data.get('depends_on', []):
            dep_file = dep['target'].split('#')[0]
            if (dep_file == target_file or dep_file.endswith(target_file)
                    or target_file.endswith(dep_file)):
                impacted_by.append({
                    'source': filepath,
                    'symbol': dep['target'].split('#')[1] if '#' in dep['target'] else '',
                    'description': dep.get('description', ''),
                    'line': dep['line']
                })

    # 查找目标文件自身的踩坑和影响
    target_data = files.get(target_file, {})
    if not target_data:
        for filepath, data in files.items():
            if filepath == target_file or filepath.endswith(target_file) or target_file.endswith(filepath):
                target_data = data
                break

    pitfalls = target_data.get('pitfalls', [])
    impacts = target_data.get('impacts', [])

# 按来源文件分组统计反向依赖
impacted_by_grouped = {}
for item in impacted_by:
    src = item['source']
    impacted_by_grouped.setdefault(src, []).append(item)

# 状态判断
if risk_level == 'high':
    status = '⚠️ 高风险，等待用户确认'
else:
    status = '✅ 低风险，可继续'

suggestion = '改完后验证相关功能是否正常'

# ===== JSON 输出 =====
if output_json:
    result = {
        'target_file': target_file,
        'risk_level': risk_level,
        'skipped': False,
        'risk_reason': '在高风险清单中' if risk_level == 'high' else '不在高风险清单中',
        'annotations': annotations,
        'impacted_by': [
            {'source': src, 'count': len(items), 'symbols': [
                {'symbol': i['symbol'], 'description': i['description']} for i in items
            ]}
            for src, items in impacted_by_grouped.items()
        ],
        'pitfalls': [{'description': p['description'], 'line': p['line']} for p in pitfalls],
        'impacts': [{'structured': i['structured'], 'description': i.get('description', '')} for i in impacts],
        'index_stale': index_stale,
        'stale_files': [f for f in stale_files if f],
        'suggestion': suggestion,
        'status': status
    }
    print(json.dumps(result, ensure_ascii=False, indent=2))
    sys.exit(0)

# ===== 文本输出 =====
print('=== 影响检查报告 ===')
print(f'目标文件：{target_file}')
print(f'风险等级：{risk_level}')
if risk_level == 'high':
    print('（在高风险清单中）')
else:
    print('（不在高风险清单中）')
print()

# 索引过期警告
if index_stale:
    stale_count = len([f for f in stale_files if f])
    print(f'⚠️ 索引可能过期：{stale_count} 个文件在索引生成后被修改')
    print('  建议重跑：bash <skill-path>/scripts/extract-annotations.sh')
    print()

# 内联标注
print('直接依赖（本文件标注）：')
if not annotations:
    print('  （无标注）')
else:
    for line in annotations:
        print(f'  {line}')
print()

# 反向依赖
if has_index:
    print('反向依赖（谁依赖本文件）：')
    if not impacted_by_grouped:
        print('  （无反向依赖）')
    else:
        for src, items in impacted_by_grouped.items():
            print(f'  {src} ({len(items)}处引用)')
            for item in items:
                if item['symbol']:
                    desc = f" | {item['description']}" if item['description'] else ''
                    print(f'    → {item["symbol"]}{desc}')
    print()

    # 踩坑警告
    if pitfalls:
        print('踩坑警告：')
        for p in pitfalls:
            print(f'  ⚠️ {p["description"]} (line {p["line"]})')
        print()

    # 影响范围
    if impacts:
        print('影响范围：')
        for imp in impacts:
            desc = f" | {imp['description']}" if imp.get('description') else ''
            print(f'  {imp["structured"]}{desc}')
        print()

print(f'建议：{suggestion}')
print(f'状态：{status}')
PYEOF
