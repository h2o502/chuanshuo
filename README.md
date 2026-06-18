# chuanshuo（传火）

> 让 AI 编码会话像接力传火一样连续：改前检查影响、踩坑自动标注、状态无缝衔接。

解决的不是 AI 的能力问题，而是 AI 的工作方式问题——从"无状态的即时反应"变成"有状态的渐进式工程"。

---

## 它解决什么问题

AI 编码会话有三个通病：

1. **改了 A 破了 B**：AI 不知道 A 被谁依赖，改完才发现连锁反应
2. **会话失忆**：换一次会话，AI 把上次踩的坑、做的决策全忘了，重复犯错
3. **踩坑无沉淀**：同一个坑被不同会话反复踩，因为没有就近标注机制

传火用三件事解决：

- **标注住在代码旁**：用 `#@depends-on` / `#@pitfall` 等内联标注，让依赖信息就地存活
- **记忆按需加载**：分层记忆（框架/动态/技能库），启动只读元数据，按需加载正文
- **改前先报告影响**：改任何代码文件前先跑影响检查，高风险等用户确认，低风险 AI 自判

---

## 安装

### 依赖

- `bash` 4+
- `python3` 3.6+
- `grep`（支持 `-rn` / `--include` / `--exclude-dir`，GNU grep 即可）
- `git`（仅 `--since` 增量模式需要）

### 平台

- ✅ Linux / macOS
- ✅ Windows 下的 Git Bash / WSL
- ❌ 原生 cmd / PowerShell 暂不支持

### 安装方式

```bash
git clone https://github.com/h2o502/chuanshuo.git
```

推荐设置环境变量，方便通过 `chuanhuo` 统一入口调用：

```bash
export CHUANSHUO_HOME=/path/to/chuanshuo/chuanhuo
# 可选：加入 PATH，直接用 chuanhuo 命令
export PATH="$CHUANSHUO_HOME:$PATH"
```

---

## 5 分钟上手

### 1. 初始化传火结构

```bash
cd /path/to/your-project
chuanhuo init .
# 或：bash $CHUANSHUO_HOME/scripts/init-project.sh .
```

创建：

```
your-project/
├── PROJECT_MEMORY.md     # 项目框架记忆（手动填写）
├── memory.md             # 动态状态记忆（AI 更新）
├── skills/
│   └── _meta.json        # 踩坑技能索引
└── .gitignore            # 自动追加 .impact-index.json
```

### 2. 填写 PROJECT_MEMORY.md

至少填：架构、常用命令、高风险文件清单（glob pattern）、硬约束。控制在 200 行内。

### 3. 让 AI 读 SKILL.md

AI 按协议工作：会话启动读记忆 → 改文件前 check-impact → 踩坑后补标注 → 阶段任务完成后更新 memory。

### 4. 踩坑时补标注

```typescript
//#@depends-on: src/db/users.ts#findUser | 查找用户时依赖此函数
//#@pitfall: token 过期时间不能短于 1 小时，否则移动端频繁掉登录
function validateToken(token: string) { ... }
```

### 5. 生成依赖索引

```bash
chuanhuo extract src/
```

### 6. 改文件前检查影响

```bash
chuanhuo check src/auth/token.ts
```

---

## 命令参考

### 统一入口 `chuanhuo`

所有命令通过 `chuanhuo` 包装脚本调用，自动定位 skill 根目录。

| 命令 | 说明 |
|---|---|
| `chuanhuo init [dir]` | 初始化传火结构 |
| `chuanhuo uninstall [dir]` | 卸载传火结构 |
| `chuanhuo extract [dir] [opts]` | 扫描标注生成索引 |
| `chuanhuo check <file> [opts]` | 检查文件影响范围 |
| `chuanhuo memory <action> <text>` | 更新 memory.md |
| `chuanhuo lint [dir]` | 项目健康检查 |

### `init` / `uninstall`

```bash
chuanhuo init .              # 初始化（幂等）
chuanhuo uninstall .         # 卸载（删除传火文件，保留代码标注）
```

### `extract` — 标注扫描

```bash
chuanhuo extract src/                # 全量扫描
chuanhuo extract --since HEAD~1      # 增量：只扫 git diff 变更文件
chuanhuo extract --prune             # 清理指向不存在文件的标注
chuanhuo extract --check-meta        # 校验 _meta.json 与 skills/ 一致性
```

- 默认排除 `node_modules` / `.git` / `dist` / `build` / `target` / `vendor` / `.next` / `__pycache__`
- 支持后缀：`.ts .tsx .js .jsx .go .py .java .rs .vue .svelte`

### `check` — 影响检查

```bash
chuanhuo check src/auth/token.ts         # 文本报告
chuanhuo check src/auth/token.ts --json  # JSON 格式（供 AI 可靠解析）
chuanhuo check README.md                 # 白名单文件自动跳过
chuanhuo check README.md --no-skip       # 强制完整检查
```

- 风险等级来自 `PROJECT_MEMORY.md` 的高风险清单
- **白名单**（自动跳过）：`*.md` / `README*` / `LICENSE` / `.gitignore` / 传火自身文件
- **索引过期检测**：源文件比索引新时警告
- 高风险 → 等待用户确认；低风险 → AI 自判

### `memory` — 状态更新

```bash
chuanhuo memory status "正在做登录模块"              # 替换当前状态
chuanhuo memory decision "采用 JWT，原因：无状态"    # 追加决策（自动带日期，保留最近5条）
chuanhuo memory issue "登录接口偶发 500"             # 追加活跃问题
chuanhuo memory deadend "用 localStorage 存 token"  # 追加不要再试的方案
chuanhuo memory resolve "登录接口偶发 500"           # 移除已解决的活跃问题
```

### `lint` — 健康检查

```bash
chuanhuo lint
```

检查项：PROJECT_MEMORY.md 行数（<200）、memory.md 非空、_meta.json 一致性、索引是否过期、高风险清单是否配置。

---

## 标注语法

**推荐 3 种**（覆盖 90% 场景）：

| 标注 | 用途 | 示例 |
|---|---|---|
| `#@depends-on` | 声明依赖 | `//#@depends-on: src/db/users.ts#findUser \| 查找用户时依赖此函数` |
| `#@impact` | 声明影响范围 | `//#@impact: 所有需要鉴权的路由 \| token 验证逻辑改了会影响这里` |
| `#@pitfall` | 踩坑警告 | `//#@pitfall: token 过期时间不能短于 1 小时` |

兼容保留（确有需要时使用）：`#@flow` / `#@route` / `#@state`。

**原则**：只标反直觉的和踩过坑的。10 条精准标注 > 100 条"可能相关"。

---

## 项目文件结构

```
<project-root>/
├── PROJECT_MEMORY.md          # 项目框架记忆（必读，<200行）
├── memory.md                  # 动态状态记忆
├── skills/                    # 踩坑技能库
│   ├── _meta.json             # 技能元数据索引
│   └── <pitfall-name>.md      # 具体踩坑技能
└── .impact-index.json         # 自动生成的依赖索引（已加入 .gitignore）
```

---

## 测试

```bash
bash chuanhuo/tests/run.sh
```

57 个测试用例覆盖：初始化、标注扫描、影响检查、白名单、JSON 输出、glob 元字符转义、prune 清理、memory 更新、lint、卸载、--help、包装脚本。

---

## 引入节奏

| 阶段 | 动作 |
|---|---|
| 第 1 周 | `chuanhuo init` → 填 `PROJECT_MEMORY.md` + `memory.md` |
| 第 2 周 | 踩坑时补 `#@` 标注 → `chuanhuo extract` 建索引 |
| 第 3 周 | `PROJECT_MEMORY.md` 加"改动前必须 check-impact"硬约束 |
| 长期 | 踩一个坑标一条，标注库持续增长 |

---

## FAQ

### Q: AI 真的会每次改文件都跑 check 吗？

取决于 AI 是否遵守 SKILL.md 协议。强制力来自 `PROJECT_MEMORY.md` 里的"传火规则"——写成硬约束，AI 遵守概率显著提高。白名单机制已减少不必要的检查。

### Q: 冷启动时没有标注，check 还有用吗？

有用。即使索引为空，`check` 仍报告风险等级、提取内联标注、给出风险判断。索引是加分项。

### Q: 标注会过期吗？

会。`chuanhuo extract --prune` 可清理指向不存在文件的标注。`chuanhuo lint` 会检测索引是否过期。

### Q: 可以只用一部分功能吗？

可以。各模块解耦：只用记忆、只用索引、只用影响检查均可。

### Q: 和 .cursorrules / .trae/rules 有什么区别？

那些是"静态规则"，传火是"动态记忆 + 影响检查"。两者互补：静态规则告诉 AI "永远怎么做"，传火告诉 AI "当前状态、改了影响谁、踩过什么坑"。

---

## 一句话本质

> **标注住在代码旁，记忆按需加载，AI 先报告影响再动手——高风险等确认，低风险自己判。**

---

## License

MIT
