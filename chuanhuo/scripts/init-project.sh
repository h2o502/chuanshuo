#!/bin/bash
# init-project.sh — 初始化项目的传火结构
#
# 用法：bash init-project.sh <项目根目录>
# 创建：PROJECT_MEMORY.md、memory.md、skills/ 目录、.gitignore 条目

set -euo pipefail

PROJECT_ROOT="${1:-.}"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "错误：项目目录 $PROJECT_ROOT 不存在"
  exit 1
fi

cd "$PROJECT_ROOT"

echo "初始化传火项目结构..."
echo "项目根目录：$(pwd)"
echo ""

# 1. 创建 PROJECT_MEMORY.md（如果不存在）
if [ ! -f "PROJECT_MEMORY.md" ]; then
  if [ -f "$TEMPLATES_DIR/PROJECT_MEMORY-template.md" ]; then
    cp "$TEMPLATES_DIR/PROJECT_MEMORY-template.md" PROJECT_MEMORY.md
    echo "✅ 已创建 PROJECT_MEMORY.md（从模板）"
  else
    echo "⚠️ 模板文件不存在，创建空 PROJECT_MEMORY.md"
    touch PROJECT_MEMORY.md
  fi
else
  echo "ℹ️ PROJECT_MEMORY.md 已存在，跳过"
fi

# 2. 创建 memory.md（如果不存在）
if [ ! -f "memory.md" ]; then
  if [ -f "$TEMPLATES_DIR/memory-template.md" ]; then
    cp "$TEMPLATES_DIR/memory-template.md" memory.md
    echo "✅ 已创建 memory.md（从模板）"
  else
    echo "⚠️ 模板文件不存在，创建空 memory.md"
    touch memory.md
  fi
else
  echo "ℹ️ memory.md 已存在，跳过"
fi

# 3. 创建 skills/ 目录和 _meta.json
mkdir -p skills
if [ ! -f "skills/_meta.json" ]; then
  echo '{"skills":[]}' > skills/_meta.json
  echo "✅ 已创建 skills/_meta.json"
else
  echo "ℹ️ skills/_meta.json 已存在，跳过"
fi

# 4. 添加 .impact-index.json 到 .gitignore
if [ -f ".gitignore" ]; then
  if grep -q '.impact-index.json' .gitignore; then
    echo "ℹ️ .impact-index.json 已在 .gitignore 中"
  else
    echo "" >> .gitignore
    echo "# 传火：自动生成的依赖索引" >> .gitignore
    echo ".impact-index.json" >> .gitignore
    echo "✅ 已将 .impact-index.json 添加到 .gitignore"
  fi
else
  echo "# 传火：自动生成的依赖索引" > .gitignore
  echo ".impact-index.json" >> .gitignore
  echo "✅ 已创建 .gitignore 并添加 .impact-index.json"
fi

echo ""
echo "=== 初始化完成 ==="
echo ""
echo "下一步："
echo "  1. 编辑 PROJECT_MEMORY.md，填写项目架构、命令、高风险文件清单"
echo "  2. 编辑 memory.md，填写当前项目状态"
echo "  3. 开始编码，遇到踩坑时用 #@ 标注补在代码旁"
echo "  4. 运行 extract-annotations.sh 生成依赖索引"
echo "  5. 以后改动文件前，运行 check-impact.sh 检查影响"
