#!/bin/bash
# init-project.sh — 初始化或卸载项目的传火结构
#
# 用法：bash init-project.sh <项目根目录> [选项]
# 选项：
#   --uninstall  卸载传火结构（删除 PROJECT_MEMORY.md / memory.md / skills/ / .impact-index.json）
#   --help, -h   显示帮助

set -euo pipefail

# ===== 参数解析 =====
PROJECT_ROOT=""
UNINSTALL=0

print_help() {
  cat <<'HELP'
init-project.sh — 初始化或卸载传火项目结构

用法：bash init-project.sh <项目根目录> [选项]

选项：
  --uninstall  卸载传火结构，删除以下文件/目录：
               PROJECT_MEMORY.md / memory.md / skills/ / .impact-index.json
               并从 .gitignore 移除相关条目
  --help, -h   显示本帮助

初始化时创建（幂等，已存在则跳过）：
  PROJECT_MEMORY.md  从模板创建
  memory.md          从模板创建
  skills/_meta.json  空索引
  .gitignore         追加 .impact-index.json

退出码：
  0  正常
  1  参数错误 / 目录不存在
HELP
}

while [ $# -gt 0 ]; do
  case "$1" in
    --help|-h) print_help; exit 0 ;;
    --uninstall) UNINSTALL=1; shift ;;
    --*) echo "未知选项：$1" >&2; exit 1 ;;
    *)
      if [ -z "$PROJECT_ROOT" ]; then
        PROJECT_ROOT="$1"
      else
        echo "错误：多余参数 $1" >&2; exit 1
      fi
      shift ;;
  esac
done

PROJECT_ROOT="${PROJECT_ROOT:-.}"

if [ ! -d "$PROJECT_ROOT" ]; then
  echo "错误：项目目录 $PROJECT_ROOT 不存在" >&2
  exit 1
fi

cd "$PROJECT_ROOT"
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
TEMPLATES_DIR="$SCRIPT_DIR/templates"

# ===== 卸载模式 =====
if [ "$UNINSTALL" = "1" ]; then
  echo "卸载传火结构..."
  echo "项目根目录：$(pwd)"
  echo ""

  REMOVED=0
  for f in PROJECT_MEMORY.md memory.md .impact-index.json; do
    if [ -f "$f" ]; then
      rm -f "$f"
      echo "✅ 已删除 $f"
      REMOVED=1
    fi
  done
  if [ -d "skills" ]; then
    rm -rf skills
    echo "✅ 已删除 skills/"
    REMOVED=1
  fi

  # 从 .gitignore 移除传火相关条目
  if [ -f ".gitignore" ] && grep -q '.impact-index.json' .gitignore; then
    # 删除含 .impact-index.json 的行和紧邻的"# 传火"注释行
    grep -v -E '(^# 传火：自动生成的依赖索引|^\.impact-index\.json$|^$)' .gitignore \
      | awk 'NF{p=1} p' > .gitignore.tmp || true
    # 如果删完空了就留一个空行
    if [ ! -s .gitignore.tmp ]; then
      rm -f .gitignore.tmp
    else
      mv .gitignore.tmp .gitignore
    fi
    echo "✅ 已从 .gitignore 移除传火条目"
    REMOVED=1
  fi

  if [ "$REMOVED" = "0" ]; then
    echo "ℹ️ 未找到传火相关文件，无需卸载"
  else
    echo ""
    echo "=== 卸载完成 ==="
    echo "注意：代码中的 #@ 标注未被删除（需手动清理）"
  fi
  exit 0
fi

# ===== 初始化模式 =====
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
    # 确保文件末尾有换行，避免追加时粘连到上一行
    if [ -s ".gitignore" ] && [ "$(tail -c1 .gitignore)" != "" ]; then
      printf '\n' >> .gitignore
    fi
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
echo "  6. 用 update-memory.sh 追加带时间戳的状态/决策/问题"
