#!/bin/bash
# lint.sh — 检查传火项目的健康度
#
# 用法：bash lint.sh [项目根目录]
# 检查项：
#   1. PROJECT_MEMORY.md 行数是否超过 200 行
#   2. skills/_meta.json 与 skills/ 目录一致性
#   3. memory.md 是否存在且非空
#   4. .impact-index.json 是否过期（有源文件比索引新）
#   5. 高风险清单格式是否正确

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "错误：未找到 python3。" >&2
  exit 2
fi

PROJECT_ROOT="${1:-.}"

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "错误：目录 $PROJECT_ROOT 不存在" >&2
  exit 1
fi

cd "$PROJECT_ROOT"

echo "=== 传火项目健康检查 ==="
echo ""

ERRORS=0
WARNINGS=0

# 1. PROJECT_MEMORY.md 行数
if [ -f "PROJECT_MEMORY.md" ]; then
  LINES=$(wc -l < PROJECT_MEMORY.md)
  if [ "$LINES" -gt 200 ]; then
    echo "❌ PROJECT_MEMORY.md 有 ${LINES} 行，超过 200 行上限"
    ERRORS=$((ERRORS + 1))
  else
    echo "✅ PROJECT_MEMORY.md ${LINES} 行（<200）"
  fi
else
  echo "❌ PROJECT_MEMORY.md 不存在"
  ERRORS=$((ERRORS + 1))
fi

# 2. memory.md 存在且非空
if [ -f "memory.md" ]; then
  if [ ! -s "memory.md" ]; then
    echo "⚠️ memory.md 为空，建议填写当前状态"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "✅ memory.md 存在且非空"
  fi
else
  echo "❌ memory.md 不存在"
  ERRORS=$((ERRORS + 1))
fi

# 3. skills/_meta.json 一致性
if [ -f "skills/_meta.json" ]; then
  META_OK=$(python3 -c "
import json, os, sys
try:
    with open('skills/_meta.json', 'r', encoding='utf-8') as f:
        meta = json.load(f)
except Exception as e:
    print('invalid'); sys.exit(0)
meta_files = {s.get('file','') for s in meta.get('skills', [])}
errors = []
for s in meta.get('skills', []):
    f = s.get('file', '')
    if f and not os.path.exists(os.path.join('skills', f)):
        errors.append(f)
if os.path.isdir('skills'):
    for f in os.listdir('skills'):
        if f.endswith('.md') and f != '_meta.json' and f not in meta_files:
            errors.append(f)
print('ok' if not errors else 'mismatch:' + ','.join(errors))
")
  case "$META_OK" in
    ok) echo "✅ skills/_meta.json 与 skills/ 目录一致" ;;
    invalid) echo "❌ skills/_meta.json 格式无效"; ERRORS=$((ERRORS + 1)) ;;
    mismatch:*)
      echo "⚠️ _meta.json 与 skills/ 目录不一致：${META_OK#mismatch:}"
      WARNINGS=$((WARNINGS + 1)) ;;
  esac
else
  if [ -d "skills" ]; then
    echo "⚠️ skills/ 目录存在但 _meta.json 不存在"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "ℹ️ skills/ 目录不存在（未初始化或未使用踩坑技能库）"
  fi
fi

# 4. 索引过期检测
if [ -f ".impact-index.json" ] && [ -d "src" ]; then
  STALE=$(find src -type f \
    \( -name '*.ts' -o -name '*.tsx' -o -name '*.js' -o -name '*.jsx' \
       -o -name '*.go' -o -name '*.py' -o -name '*.java' -o -name '*.rs' \
       -o -name '*.vue' -o -name '*.svelte' \) \
    -newer .impact-index.json 2>/dev/null | wc -l)
  if [ "$STALE" -gt 0 ]; then
    echo "⚠️ 索引可能过期：${STALE} 个源文件比 .impact-index.json 新"
    echo "   建议重跑：bash <skill-path>/scripts/extract-annotations.sh"
    WARNINGS=$((WARNINGS + 1))
  else
    echo "✅ 索引是最新的"
  fi
else
  if [ ! -f ".impact-index.json" ]; then
    echo "ℹ️ .impact-index.json 不存在（未运行 extract-annotations.sh）"
  fi
fi

# 5. 高风险清单格式检查
if [ -f "PROJECT_MEMORY.md" ]; then
  if grep -q '## 高风险文件' PROJECT_MEMORY.md; then
    echo "✅ 高风险清单已配置"
  else
    echo "⚠️ PROJECT_MEMORY.md 中未找到'## 高风险文件'章节"
    WARNINGS=$((WARNINGS + 1))
  fi
fi

echo ""
echo "=== 检查结果 ==="
echo "错误：$ERRORS"
echo "警告：$WARNINGS"
if [ "$ERRORS" -gt 0 ]; then
  exit 1
fi
exit 0
