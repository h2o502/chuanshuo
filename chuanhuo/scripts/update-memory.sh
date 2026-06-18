#!/bin/bash
# update-memory.sh — 向 memory.md 追加带时间戳的状态/决策/问题
#
# 用法：bash update-memory.sh <action> <content...>
# action:
#   status    替换"当前状态"部分
#   decision  追加一条决策（带日期，自动保留最近 5 条）
#   issue     追加一条活跃问题
#   deadend   追加一条"不要再试的方案"
#   resolve   从"活跃问题"中移除匹配的条目
#   --help    显示帮助

set -euo pipefail

if ! command -v python3 >/dev/null 2>&1; then
  echo "错误：未找到 python3。" >&2
  exit 2
fi

MEMORY_FILE="${MEMORY_FILE:-memory.md}"

print_help() {
  cat <<'HELP'
update-memory.sh — 更新 memory.md

用法：bash update-memory.sh <action> <content...>

action:
  status <text>     替换"当前状态"部分（多行用引号）
  decision <text>   追加一条决策，自动带日期，保留最近 5 条
  issue <text>      追加一条活跃问题
  deadend <text>    追加一条"不要再试的方案"
  resolve <text>    从"活跃问题"中移除包含 <text> 的条目
  --help, -h        显示本帮助

环境变量：
  MEMORY_FILE  指定 memory.md 路径（默认 ./memory.md）

示例：
  bash update-memory.sh decision "采用 JWT 替代 session，原因：无状态更易扩展"
  bash update-memory.sh issue "登录接口偶发 500，相关文件 src/auth/login.ts"
  bash update-memory.sh resolve "登录接口偶发 500"

退出码：
  0  正常
  1  参数错误 / memory.md 不存在
  2  依赖缺失
HELP
}

if [ $# -lt 1 ]; then
  print_help
  exit 1
fi

ACTION="$1"
shift

case "$ACTION" in
  --help|-h) print_help; exit 0 ;;
  status|decision|issue|deadend|resolve) ;;
  *) echo "错误：未知 action '$ACTION'，运行 --help 查看帮助" >&2; exit 1 ;;
esac

if [ $# -lt 1 ]; then
  echo "错误：$ACTION 需要 content 参数" >&2
  exit 1
fi

CONTENT="$*"

if [ ! -f "$MEMORY_FILE" ]; then
  echo "错误：$MEMORY_FILE 不存在，请先运行 init-project.sh" >&2
  exit 1
fi

python3 - "$MEMORY_FILE" "$ACTION" "$CONTENT" << 'PYEOF'
import re
import sys
from datetime import date

memory_file = sys.argv[1]
action = sys.argv[2]
content = sys.argv[3]

with open(memory_file, 'r', encoding='utf-8') as f:
    text = f.read()

today = date.today().isoformat()

# 按 ## 标题分节
SECTIONS = ['当前状态', '近期决策', '活跃问题', '不要再试的方案']

def split_sections(text):
    """把 memory.md 按二级标题拆成 dict"""
    sections = {}
    current = None
    lines = text.split('\n')
    buf = []
    for line in lines:
        m = re.match(r'^## (.+)$', line)
        if m:
            if current is not None:
                sections[current] = buf
            current = m.group(1).strip()
            buf = []
        else:
            buf.append(line)
    if current is not None:
        sections[current] = buf
    return sections

def rebuild(sections):
    """把 dict 重新拼成 memory.md"""
    out = ['# 项目状态', '']
    for name in SECTIONS:
        title = name
        if name == '近期决策':
            title = '近期决策（最近 5 条）'
        out.append(f'## {title}')
        out.append('')
        lines = sections.get(name, [])
        # 过滤纯空行尾部的多余空行
        while lines and lines[-1].strip() == '':
            lines.pop()
        out.extend(lines)
        out.append('')
    return '\n'.join(out).rstrip('\n') + '\n'

sections = split_sections(text)

if action == 'status':
    # 替换当前状态部分
    new_lines = [f'- {line}' if not line.startswith('-') else line
                 for line in content.split('\\n')]
    sections['当前状态'] = new_lines
    print(f"✅ 已更新当前状态")

elif action == 'decision':
    # 追加决策，保留最近 5 条
    lines = sections.get('近期决策', [])
    # 过滤掉模板占位行
    lines = [l for l in lines if l.strip() and not l.strip().startswith('[日期]')]
    lines.insert(0, f'- [{today}] {content}')
    sections['近期决策'] = lines[:5]
    print(f"✅ 已追加决策（{today}），保留最近 5 条")

elif action == 'issue':
    lines = sections.get('活跃问题', [])
    lines = [l for l in lines if l.strip() and not l.strip().startswith('<')]
    lines.append(f'- {content}')
    sections['活跃问题'] = lines
    print(f"✅ 已追加活跃问题")

elif action == 'deadend':
    lines = sections.get('不要再试的方案', [])
    lines = [l for l in lines if l.strip() and not l.strip().startswith('<')]
    lines.append(f'- {content}（已验证不可行）')
    sections['不要再试的方案'] = lines
    print('✅ 已追加"不要再试的方案"')

elif action == 'resolve':
    lines = sections.get('活跃问题', [])
    kept = [l for l in lines if content not in l]
    removed = len(lines) - len(kept)
    sections['活跃问题'] = kept
    if removed > 0:
        print(f"✅ 已移除 {removed} 条匹配的活跃问题")
    else:
        print(f"ℹ️ 未找到包含 '{content}' 的活跃问题")

with open(memory_file, 'w', encoding='utf-8') as f:
    f.write(rebuild(sections))
PYEOF
