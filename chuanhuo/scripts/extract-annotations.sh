#!/bin/bash
# extract-annotations.sh — 扫描代码中的 #@ 标注，生成/更新 .impact-index.json 索引
#
# 用法：bash extract-annotations.sh [扫描目录] [选项]
# 选项：
#   --output <file>    指定输出文件（默认 .impact-index.json）
#   --since <git-ref>  增量模式：只扫描 git diff <ref> 的变更文件
#   --prune            清理指向不存在文件的标注条目
#   --check-meta       校验 skills/_meta.json 与 skills/ 目录一致性
#   --help, -h         显示帮助

set -euo pipefail

# 依赖检查
if ! command -v python3 >/dev/null 2>&1; then
  echo "错误：未找到 python3，本脚本依赖 python3 生成索引。" >&2
  exit 2
fi

# ===== 参数解析 =====
SCAN_DIR="src"
OUTPUT_FILE=".impact-index.json"
SINCE_REF=""
PRUNE=0
CHECK_META=0

print_help() {
  cat <<'HELP'
extract-annotations.sh — 扫描 #@ 标注，生成依赖索引

用法：bash extract-annotations.sh [扫描目录] [选项]

选项：
  --output <file>    指定输出文件（默认 .impact-index.json）
  --since <git-ref>  增量模式：只扫描 git diff <ref> 的变更文件
  --prune            清理指向不存在文件的标注条目
  --check-meta       校验 skills/_meta.json 与 skills/ 目录一致性
  --help, -h         显示本帮助

默认排除目录：node_modules .git dist build target vendor .next __pycache__
支持后缀：.ts .tsx .js .jsx .go .py .java .rs .vue .svelte

退出码：
  0  正常
  1  参数错误 / 目录不存在
  2  依赖缺失
HELP
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_help; exit 0 ;;
    --output) OUTPUT_FILE="${2:-}"; shift 2 ;;
    --output=*) OUTPUT_FILE="${1#--output=}"; shift ;;
    --since) SINCE_REF="${2:-}"; shift 2 ;;
    --since=*) SINCE_REF="${1#--since=}"; shift ;;
    --prune) PRUNE=1; shift ;;
    --check-meta) CHECK_META=1; shift ;;
    --*) echo "未知选项：$1" >&2; exit 1 ;;
    *)
      SCAN_DIR="$1"
      shift ;;
  esac
done

# 仅 --check-meta 模式不需要扫描目录
if [ "$CHECK_META" = "1" ] && [ "$SINCE_REF" = "" ] && [ "$PRUNE" = "0" ]; then
  python3 - "$OUTPUT_FILE" << 'PYEOF'
import json, os, sys

output_file = sys.argv[1]
meta_file = 'skills/_meta.json'

# 加载索引（用于 prune 检查）
index = {'files': {}}
if os.path.exists(output_file):
    try:
        with open(output_file, 'r', encoding='utf-8') as f:
            index = json.load(f)
    except (json.JSONDecodeError, IOError):
        pass

# _meta.json 与 skills/ 目录一致性校验
errors = []
if os.path.exists(meta_file):
    try:
        with open(meta_file, 'r', encoding='utf-8') as f:
            meta = json.load(f)
    except (json.JSONDecodeError, IOError):
        meta = {'skills': []}
    meta_files = {s.get('file', '') for s in meta.get('skills', [])}
    # 检查 _meta.json 里的 file 是否都存在
    for s in meta.get('skills', []):
        f = s.get('file', '')
        if f and not os.path.exists(os.path.join('skills', f)):
            errors.append(f"  _meta.json 引用了不存在的文件：skills/{f}")
    # 检查 skills/ 下的 .md 文件是否都在 _meta.json 里
    if os.path.isdir('skills'):
        for f in os.listdir('skills'):
            if f.endswith('.md') and f != '_meta.json' and f not in meta_files:
                errors.append(f"  skills/{f} 未在 _meta.json 中登记")
else:
    if os.path.isdir('skills'):
        errors.append("  skills/ 目录存在但 _meta.json 不存在")

if errors:
    print("⚠️ _meta.json 一致性问题：")
    for e in errors:
        print(e)
    sys.exit(1)
else:
    print("✅ _meta.json 与 skills/ 目录一致")
    sys.exit(0)
PYEOF
  exit $?
fi

if [ ! -d "$SCAN_DIR" ] && [ "$SINCE_REF" = "" ]; then
  echo "错误：目录 $SCAN_DIR 不存在" >&2
  exit 1
fi

echo "扫描 #@ 标注..."

# ===== 扫描标注 =====
TMP_FILE=$(mktemp)
trap 'rm -f "$TMP_FILE"' EXIT

EXCLUDE_DIRS=(--exclude-dir='node_modules' --exclude-dir='.git' --exclude-dir='dist'
  --exclude-dir='build' --exclude-dir='target' --exclude-dir='vendor'
  --exclude-dir='.next' --exclude-dir='__pycache__')

INCLUDES=(--include='*.ts' --include='*.tsx' --include='*.js' --include='*.jsx'
  --include='*.go' --include='*.py' --include='*.java' --include='*.rs'
  --include='*.vue' --include='*.svelte')

if [ -n "$SINCE_REF" ]; then
  # 增量模式：只扫描 git diff 变更文件
  if ! command -v git >/dev/null 2>&1; then
    echo "错误：--since 需要 git，但未找到 git" >&2
    exit 2
  fi
  if ! git rev-parse --git-dir >/dev/null 2>&1; then
    echo "错误：当前不在 git 仓库中，无法使用 --since" >&2
    exit 1
  fi
  echo "增量模式：扫描 git diff $SINCE_REF 的变更文件"
  # 获取变更文件列表，只保留存在的代码文件
  git diff --name-only "$SINCE_REF" 2>/dev/null | while IFS= read -r f; do
    [ -f "$f" ] || continue
    # 只扫描支持的代码后缀
    case "$f" in
      *.ts|*.tsx|*.js|*.jsx|*.go|*.py|*.java|*.rs|*.vue|*.svelte)
        grep -n '#@' "$f" 2>/dev/null | sed "s|^|$f:|" >> "$TMP_FILE" || true ;;
    esac
  done
else
  # 全量模式
  if [ -d "$SCAN_DIR" ]; then
    echo "全量模式：扫描 $SCAN_DIR"
    grep -rn '#@' "$SCAN_DIR" "${INCLUDES[@]}" "${EXCLUDE_DIRS[@]}" \
      2>/dev/null > "$TMP_FILE" || true
  fi
fi

# ===== 调用 Python 解析、merge、prune、meta 校验 =====
python3 - "$TMP_FILE" "$OUTPUT_FILE" "$PRUNE" "$CHECK_META" "$SINCE_REF" << 'PYEOF'
import json
import os
import re
import sys
from collections import defaultdict

tmp_file = sys.argv[1]
output_file = sys.argv[2]
prune = sys.argv[3] == '1'
check_meta = sys.argv[4] == '1'
incremental = sys.argv[5] != ''

# 标注正则
patterns = {
    'depends_on': re.compile(r'#@depends-on:\s*(\S+?)(?:\s*\|\s*(.*))?$'),
    'impact': re.compile(r'#@impact:\s*(.+?)(?:\s*\|\s*(.*))?$'),
    'flow': re.compile(r'#@flow:\s*(.+?)(?:\s*\|\s*(.*))?$'),
    'route': re.compile(r'#@route:\s*(.+?)(?:\s*\|\s*(.*))?$'),
    'state': re.compile(r'#@state:\s*(.+?)(?:\s*\|\s*(.*))?$'),
    'pitfall': re.compile(r'#@pitfall:\s*(.+)$'),
}

# grep -rn 输出格式：文件路径:行号:内容
# 用正则非贪婪匹配路径，\d+ 匹配行号（唯一可靠锚点）
LINE_RE = re.compile(r'^(.+?):(\d+):(.*)$')

def new_file_data():
    return {
        'depends_on': [], 'impacts': [], 'flows': [],
        'routes': [], 'states': [], 'pitfalls': [], 'lines': []
    }

# 加载现有索引（增量模式或 prune 模式需要）
existing = {'files': {}}
if os.path.exists(output_file):
    try:
        with open(output_file, 'r', encoding='utf-8') as f:
            existing = json.load(f)
    except (json.JSONDecodeError, IOError):
        pass

# 解析本次扫描结果
new_data = defaultdict(new_file_data)
scanned_files = set()

with open(tmp_file, 'r', encoding='utf-8') as f:
    for line in f:
        line = line.rstrip('\n')
        if not line or '#@' not in line:
            continue
        m = LINE_RE.match(line)
        if not m:
            continue
        filepath, lineno, content = m.group(1), m.group(2), m.group(3).strip()
        if not content:
            continue
        scanned_files.add(filepath)
        file_info = new_data[filepath]
        file_info['lines'].append(int(lineno))
        for ann_type, pattern in patterns.items():
            match = pattern.search(content)
            if match:
                if ann_type == 'depends_on':
                    target = match.group(1).strip()
                    desc = match.group(2).strip() if match.group(2) else ''
                    file_info['depends_on'].append({
                        'target': target, 'description': desc, 'line': int(lineno)
                    })
                elif ann_type == 'pitfall':
                    file_info['pitfalls'].append({
                        'description': match.group(1).strip(), 'line': int(lineno)
                    })
                else:
                    structured = match.group(1).strip()
                    desc = match.group(2).strip() if match.group(2) else ''
                    key = {'impact': 'impacts', 'flow': 'flows',
                           'route': 'routes', 'state': 'states'}[ann_type]
                    file_info[key].append({
                        'structured': structured, 'description': desc, 'line': int(lineno)
                    })
                break

# ===== Merge 逻辑 =====
# 增量模式：保留未扫描文件的旧数据，用新数据覆盖扫描过的文件
# 全量模式：用新数据完全替换
merged_files = {}
if incremental:
    # 保留未变更文件的旧数据
    for filepath, data in existing.get('files', {}).items():
        if filepath not in scanned_files:
            merged_files[filepath] = data
# 加入本次扫描的数据
for filepath, data in new_data.items():
    data['lines'] = sorted(set(data['lines']))
    merged_files[filepath] = data

# ===== Prune 逻辑：清理指向不存在文件的标注 =====
prune_warnings = []
if prune:
    for filepath, data in list(merged_files.items()):
        # 如果标注所在的源文件已不存在，整个删掉
        if not os.path.exists(filepath):
            prune_warnings.append(f"  删除：{filepath}（文件已不存在）")
            del merged_files[filepath]
            continue
        # 清理 depends_on 中指向不存在文件的条目
        kept_deps = []
        for dep in data.get('depends_on', []):
            dep_file = dep['target'].split('#')[0]
            if not os.path.exists(dep_file):
                prune_warnings.append(
                    f"  {filepath}:{dep['line']} → {dep['target']}（目标文件不存在，已移除）")
            else:
                kept_deps.append(dep)
        data['depends_on'] = kept_deps

# ===== 构建反向依赖索引 =====
impacted_by = defaultdict(list)
for filepath, data in merged_files.items():
    for dep in data.get('depends_on', []):
        target_file = dep['target'].split('#')[0]
        impacted_by[target_file].append({
            'source': filepath,
            'symbol': dep['target'].split('#')[1] if '#' in dep['target'] else '',
            'description': dep.get('description', ''),
            'line': dep['line']
        })

# 合并到输出
output = {'files': {}}
for filepath, data in merged_files.items():
    data['impacted_by'] = impacted_by.get(filepath, [])
    output['files'][filepath] = data

with open(output_file, 'w', encoding='utf-8') as f:
    json.dump(output, f, ensure_ascii=False, indent=2)

# ===== 统计输出 =====
total_annotations = sum(
    len(d.get('depends_on', [])) + len(d.get('impacts', [])) +
    len(d.get('flows', [])) + len(d.get('routes', [])) +
    len(d.get('states', [])) + len(d.get('pitfalls', []))
    for d in merged_files.values()
)
mode = '增量' if incremental else '全量'
print(f"已生成索引（{mode}模式）：{output_file}")
print(f"  文件数：{len(merged_files)}")
print(f"  标注总数：{total_annotations}")
print(f"  反向依赖关系：{sum(len(v) for v in impacted_by.values())}")

if prune_warnings:
    print()
    print("🧹 Prune 清理：")
    for w in prune_warnings:
        print(w)

# ===== _meta.json 一致性校验 =====
if check_meta:
    meta_file = 'skills/_meta.json'
    meta_errors = []
    if os.path.exists(meta_file):
        try:
            with open(meta_file, 'r', encoding='utf-8') as f:
                meta = json.load(f)
        except (json.JSONDecodeError, IOError):
            meta = {'skills': []}
        meta_files = {s.get('file', '') for s in meta.get('skills', [])}
        for s in meta.get('skills', []):
            f = s.get('file', '')
            if f and not os.path.exists(os.path.join('skills', f)):
                meta_errors.append(f"  _meta.json 引用了不存在的文件：skills/{f}")
        if os.path.isdir('skills'):
            for f in os.listdir('skills'):
                if f.endswith('.md') and f != '_meta.json' and f not in meta_files:
                    meta_errors.append(f"  skills/{f} 未在 _meta.json 中登记")
    elif os.path.isdir('skills'):
        meta_errors.append("  skills/ 目录存在但 _meta.json 不存在")

    if meta_errors:
        print()
        print("⚠️ _meta.json 一致性问题：")
        for e in meta_errors:
            print(e)
    else:
        print()
        print("✅ _meta.json 与 skills/ 目录一致")

print("完成。")
PYEOF
