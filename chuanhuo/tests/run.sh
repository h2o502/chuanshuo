# tests/run.sh — 传火脚本回归测试
#
# 用法：bash tests/run.sh
# 在临时目录搭建 fixture 项目，运行全部测试用例并断言。

set -euo pipefail

# 定位 skill 根目录
SCRIPT_DIR="$(cd "$(dirname "$0")/.." && pwd)"
SCRIPTS="$SCRIPT_DIR/scripts"

PASS=0
FAIL=0
FAILED_TESTS=()

assert_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    PASS=$((PASS + 1))
    echo "  ✅ $desc"
  else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$desc")
    echo "  ❌ $desc"
    echo "     期望包含: $needle"
  fi
}

assert_not_contains() {
  local desc="$1" haystack="$2" needle="$3"
  if echo "$haystack" | grep -qF "$needle"; then
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$desc")
    echo "  ❌ $desc"
    echo "     不应包含: $needle"
  else
    PASS=$((PASS + 1))
    echo "  ✅ $desc"
  fi
}

assert_file_exists() {
  local desc="$1" path="$2"
  if [ -f "$path" ]; then
    PASS=$((PASS + 1))
    echo "  ✅ $desc"
  else
    FAIL=$((FAIL + 1))
    FAILED_TESTS+=("$desc")
    echo "  ❌ $desc（文件不存在: $path）"
  fi
}

# ===== 搭建测试项目 =====
TEST_PROJECT=$(mktemp -d)
trap 'rm -rf "$TEST_PROJECT"' EXIT
cd "$TEST_PROJECT"

mkdir -p src/auth src/db src/utils
cat > src/auth/token.ts <<'EOF'
//#@depends-on: src/db/users.ts#findUser | 查找用户时依赖此函数
//#@impact: 所有需要鉴权的路由 | token 验证逻辑改了会影响这里
//#@pitfall: token 过期时间不能短于 1 小时，否则移动端频繁掉登录
export function validateToken(token: string) {
  return token.length > 0;
}
EOF

cat > src/db/users.ts <<'EOF'
export function findUser(id: string) {
  return { id, name: 'test' };
}
EOF

cat > src/utils/helper.ts <<'EOF'
//#@flow: if (debug) → logVerbose | 调试模式输出详细日志
export function log(msg: string) {
  console.log(msg);
}
EOF

echo "========================================"
echo "传火脚本回归测试"
echo "========================================"
echo ""

# ===== 测试 1: init-project.sh =====
echo "--- 测试组 1: init-project.sh ---"
OUT=$(bash "$SCRIPTS/init-project.sh" . 2>&1)
assert_contains "init 创建 PROJECT_MEMORY.md" "$OUT" "PROJECT_MEMORY.md"
assert_contains "init 创建 memory.md" "$OUT" "memory.md"
assert_contains "init 创建 skills/_meta.json" "$OUT" "_meta.json"
assert_file_exists "PROJECT_MEMORY.md 存在" "PROJECT_MEMORY.md"
assert_file_exists "memory.md 存在" "memory.md"
assert_file_exists "skills/_meta.json 存在" "skills/_meta.json"

# 幂等性
OUT2=$(bash "$SCRIPTS/init-project.sh" . 2>&1)
assert_contains "init 幂等：已存在跳过" "$OUT2" "已存在"

# .gitignore
assert_contains ".gitignore 含 .impact-index.json" "$(cat .gitignore)" ".impact-index.json"
echo ""

# ===== 测试 2: extract-annotations.sh 全量 =====
echo "--- 测试组 2: extract-annotations.sh 全量 ---"
OUT=$(bash "$SCRIPTS/extract-annotations.sh" src/ 2>&1)
assert_contains "extract 全量模式" "$OUT" "全量模式"
assert_contains "extract 文件数 2" "$OUT" "文件数：2"
assert_contains "extract 标注总数 4" "$OUT" "标注总数：4"
assert_contains "extract 反向依赖 1" "$OUT" "反向依赖关系：1"
assert_file_exists ".impact-index.json 存在" ".impact-index.json"

# 验证索引内容
INDEX=$(cat .impact-index.json)
assert_contains "索引含 token.ts" "$INDEX" "src/auth/token.ts"
assert_contains "索引含 depends-on findUser" "$INDEX" "findUser"
assert_contains "索引含 pitfall" "$INDEX" "token 过期时间"
assert_contains "索引含 flow" "$INDEX" "logVerbose"
echo ""

# ===== 测试 3: check-impact.sh 高风险 =====
echo "--- 测试组 3: check-impact.sh 高风险文件 ---"
cat > PROJECT_MEMORY.md <<'EOF'
# 项目框架记忆

## 高风险文件（改动前必须用户确认）
- src/auth/**          # 鉴权链路
- **/config.{ts,json}  # 配置文件
EOF

OUT=$(bash "$SCRIPTS/check-impact.sh" src/auth/token.ts 2>&1)
assert_contains "check 高风险等级" "$OUT" "high"
assert_contains "check 高风险状态" "$OUT" "高风险，等待用户确认"
assert_contains "check 含内联标注" "$OUT" "depends-on"
assert_contains "check 含踩坑警告" "$OUT" "token 过期时间"
assert_contains "check 含影响范围" "$OUT" "所有需要鉴权的路由"
echo ""

# ===== 测试 4: check-impact.sh 低风险 + 反向依赖 =====
echo "--- 测试组 4: check-impact.sh 低风险文件 + 反向依赖 ---"
OUT=$(bash "$SCRIPTS/check-impact.sh" src/db/users.ts 2>&1)
assert_contains "check 低风险等级" "$OUT" "low"
assert_contains "check 低风险状态" "$OUT" "低风险，可继续"
assert_contains "check 含反向依赖" "$OUT" "src/auth/token.ts"
assert_contains "check 反向依赖符号" "$OUT" "findUser"
echo ""

# ===== 测试 5: check-impact.sh 白名单跳过 =====
echo "--- 测试组 5: check-impact.sh 白名单跳过 ---"
echo "test" > README.md
OUT=$(bash "$SCRIPTS/check-impact.sh" README.md 2>&1)
assert_contains "check 白名单跳过" "$OUT" "已跳过"

# --no-skip 强制检查
OUT=$(bash "$SCRIPTS/check-impact.sh" README.md --no-skip 2>&1)
assert_not_contains "check --no-skip 不跳过" "$OUT" "已跳过"
echo ""

# ===== 测试 6: check-impact.sh --json =====
echo "--- 测试组 6: check-impact.sh --json ---"
OUT=$(bash "$SCRIPTS/check-impact.sh" src/auth/token.ts --json 2>&1)
assert_contains "json 含 risk_level" "$OUT" "risk_level"
assert_contains "json 含 high" "$OUT" '"high"'
assert_contains "json 含 impacted_by" "$OUT" "impacted_by"
assert_contains "json 含 pitfalls" "$OUT" "pitfalls"
echo ""

# ===== 测试 7: check-impact.sh 花括号 glob 不报错 =====
echo "--- 测试组 7: check-impact.sh 花括号 glob 元字符转义 ---"
echo 'export const x = 1;' > src/config.ts
OUT=$(bash "$SCRIPTS/check-impact.sh" src/config.ts 2>&1)
assert_contains "check config.ts 高风险" "$OUT" "high"
echo ""

# ===== 测试 8: extract-annotations.sh --prune =====
echo "--- 测试组 8: extract-annotations.sh --prune ---"
# 删除被依赖的文件，prune 应清理对应标注
rm src/db/users.ts
OUT=$(bash "$SCRIPTS/extract-annotations.sh" src/ --prune 2>&1)
assert_contains "prune 清理提示" "$OUT" "Prune"
assert_contains "prune 清理 findUser" "$OUT" "findUser"
# 索引里不应再有 findUser
INDEX=$(cat .impact-index.json)
assert_not_contains "prune 后索引无 findUser" "$INDEX" "findUser"
echo ""

# ===== 测试 9: update-memory.sh =====
echo "--- 测试组 9: update-memory.sh ---"
OUT=$(bash "$SCRIPTS/update-memory.sh" decision "采用 JWT 替代 session" 2>&1)
assert_contains "memory decision 成功" "$OUT" "已追加决策"
MEM=$(cat memory.md)
assert_contains "memory 含决策内容" "$MEM" "采用 JWT"
assert_contains "memory 含日期" "$MEM" "[20"

OUT=$(bash "$SCRIPTS/update-memory.sh" issue "登录接口偶发 500" 2>&1)
assert_contains "memory issue 成功" "$OUT" "已追加活跃问题"
MEM=$(cat memory.md)
assert_contains "memory 含问题" "$MEM" "登录接口偶发"

OUT=$(bash "$SCRIPTS/update-memory.sh" resolve "登录接口" 2>&1)
assert_contains "memory resolve 成功" "$OUT" "已移除"
MEM=$(cat memory.md)
assert_not_contains "memory resolve 后无该问题" "$MEM" "登录接口偶发 500"

# 决策保留最近 5 条
for i in 1 2 3 4 5 6; do
  bash "$SCRIPTS/update-memory.sh" decision "决策 $i" >/dev/null 2>&1
done
MEM=$(cat memory.md)
DECISION_COUNT=$(echo "$MEM" | grep -c '\[20' || true)
if [ "$DECISION_COUNT" -le 5 ]; then
  PASS=$((PASS + 1))
  echo "  ✅ memory 决策保留最近 5 条（实际 $DECISION_COUNT 条）"
else
  FAIL=$((FAIL + 1))
  FAILED_TESTS+=("memory 决策保留最近 5 条")
  echo "  ❌ memory 决策保留最近 5 条（实际 $DECISION_COUNT 条）"
fi
echo ""

# ===== 测试 10: lint.sh =====
echo "--- 测试组 10: lint.sh ---"
OUT=$(bash "$SCRIPTS/lint.sh" . 2>&1 || true)
assert_contains "lint 检查 PROJECT_MEMORY" "$OUT" "PROJECT_MEMORY.md"
assert_contains "lint 检查 memory" "$OUT" "memory.md"
echo ""

# ===== 测试 11: init-project.sh --uninstall =====
echo "--- 测试组 11: init-project.sh --uninstall ---"
OUT=$(bash "$SCRIPTS/init-project.sh" . --uninstall 2>&1)
assert_contains "uninstall 删除 PROJECT_MEMORY" "$OUT" "PROJECT_MEMORY.md"
assert_contains "uninstall 删除 memory" "$OUT" "memory.md"
assert_contains "uninstall 删除 skills" "$OUT" "skills"
if [ ! -f "PROJECT_MEMORY.md" ] && [ ! -f "memory.md" ] && [ ! -d "skills" ]; then
  PASS=$((PASS + 1))
  echo "  ✅ uninstall 后文件确实被删除"
else
  FAIL=$((FAIL + 1))
  FAILED_TESTS+=("uninstall 后文件被删除")
  echo "  ❌ uninstall 后文件未被删除"
fi
echo ""

# ===== 测试 12: --help =====
echo "--- 测试组 12: --help ---"
OUT=$(bash "$SCRIPTS/check-impact.sh" --help 2>&1)
assert_contains "check --help" "$OUT" "用法"
OUT=$(bash "$SCRIPTS/extract-annotations.sh" --help 2>&1)
assert_contains "extract --help" "$OUT" "用法"
OUT=$(bash "$SCRIPTS/init-project.sh" --help 2>&1)
assert_contains "init --help" "$OUT" "用法"
OUT=$(bash "$SCRIPTS/update-memory.sh" --help 2>&1)
assert_contains "update-memory --help" "$OUT" "用法"
echo ""

# ===== 测试 13: chuanhuo 包装脚本 =====
echo "--- 测试组 13: chuanhuo 包装脚本 ---"
export CHUANSHUO_HOME="$SCRIPT_DIR"
OUT=$(bash "$SCRIPT_DIR/chuanhuo" --help 2>&1)
assert_contains "chuanhuo --help" "$OUT" "init"
assert_contains "chuanhuo --help 含 check" "$OUT" "check"
assert_contains "chuanhuo --help 含 memory" "$OUT" "memory"
echo ""

# ===== 汇总 =====
echo "========================================"
echo "测试结果"
echo "========================================"
echo "通过: $PASS"
echo "失败: $FAIL"
if [ "$FAIL" -gt 0 ]; then
  echo ""
  echo "失败用例:"
  for t in "${FAILED_TESTS[@]}"; do
    echo "  - $t"
  done
  exit 1
fi
echo "全部通过 ✅"
