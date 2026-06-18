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
- **改前先报告影响**：改任何文件前先跑影响检查，高风险等用户确认，低风险 AI 自判

---

## 安装

### 依赖

- `bash` 4+
- `python3` 3.6+
- `grep`（支持 `-rn` / `--include` / `--exclude-dir`，GNU grep 即可）

### 平台

- ✅ Linux / macOS
- ✅ Windows 下的 Git Bash / WSL
- ❌ 原生 cmd / PowerShell 暂不支持

### 安装方式

把本仓库克隆到任意位置，作为 skill 目录使用：

```bash
git clone https://github.com/h2o502/chuanshuo.git
```

或直接拷贝 `chuanhuo/` 目录到你的 skill 集合路径下。

---

## 5 分钟上手

### 1. 在你的项目里初始化传火结构

```bash
cd /path/to/your-project
bash /path/to/chuanshuo/chuanhuo/scripts/init-project.sh .
```

这会创建：

```
your-project/
├── PROJECT_MEMORY.md     # 项目框架记忆（你需手动填写）
├── memory.md             # 动态状态记忆（AI 会话结束时更新）
├── skills/
│   └── _meta.json        # 踩坑技能索引
└── .gitignore            # 自动追加 .impact-index.json
```

### 2. 填写 PROJECT_MEMORY.md

至少填这几项：

- **架构**：几句话或结构图
- **常用命令**：build / test / dev
- **高风险文件清单**：用 glob pattern，例如 `src/auth/**`、`**/config.{ts,json}`
- **硬约束**：不可违反的规则

控制在 200 行内。

### 3. 让 AI 读 SKILL.md

把 `chuanhuo/SKILL.md` 作为 skill 提供给 AI。AI 会按协议工作：

- 会话启动 → 读三层记忆
- 改文件前 → 跑 `check-impact.sh`
- 踩坑后 → 在代码旁补 `#@` 标注
- 会话结束 → 更新 `memory.md`

### 4. 踩坑时手动补标注（可选但推荐）

```typescript
//#@depends-on: src/db/users.ts#findUser | 查找用户时依赖此函数
//#@pitfall: token 过期时间不能短于 1 小时，否则移动端频繁掉登录
function validateToken(token: string) { ... }
```

### 5. 生成依赖索引

```bash
bash /path/to/chuanshuo/chuanhuo/scripts/extract-annotations.sh src/
```

生成 `.impact-index.json`，供 `check-impact.sh` 查询反向依赖。

### 6. 改文件前检查影响

```bash
bash /path/to/chuanshuo/chuanhuo/scripts/check-impact.sh src/auth/token.ts
```

输出影响报告，高风险文件会提示"等待用户确认"。

---

## 命令参考

### `init-project.sh <项目根目录>`

初始化传火结构。幂等，已存在的文件会跳过。

### `extract-annotations.sh [扫描目录] [输出文件]`

扫描代码中的 `#@` 标注，生成 `.impact-index.json`。

- 扫描目录默认 `src/`
- 输出文件默认 `.impact-index.json`
- 默认排除 `node_modules` / `.git` / `dist` / `build` / `target` / `vendor` / `.next` / `__pycache__`
- 支持的代码后缀：`.ts .tsx .js .jsx .go .py .java .rs .vue .svelte`

### `check-impact.sh <目标文件> [索引文件]`

检查指定文件的影响范围。

- 索引文件默认 `.impact-index.json`
- 风险等级来自 `PROJECT_MEMORY.md` 的高风险清单
- 高风险 → 输出报告并提示等待用户确认
- 低风险 → 输出报告，AI 自行判断

---

## 标注语法

混合语法：竖线前是结构化字段（脚本解析），竖线后是自然语言（AI 理解上下文）。

| 标注 | 用途 | 示例 |
|---|---|---|
| `#@depends-on` | 声明依赖 | `//#@depends-on: src/db/users.ts#findUser \| 查找用户时依赖此函数` |
| `#@impact` | 声明影响范围 | `//#@impact: 所有需要鉴权的路由 \| token 验证逻辑改了会影响这里` |
| `#@flow` | 条件→结果 | `//#@flow: if (token.expired) → refreshToken \| 过期时自动刷新` |
| `#@route` | 路由映射 | `//#@route: /api/login → handleLogin` |
| `#@state` | 状态机 | `//#@state: idle +click → active` |
| `#@pitfall` | 踩坑警告 | `//#@pitfall: token 过期时间不能短于 1 小时` |

**标注原则**：只标反直觉的和踩过坑的，不标显而易见的。10 条精准标注 > 100 条"可能相关"。

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

## 引入节奏

| 阶段 | 动作 |
|---|---|
| 第 1 周 | `init-project.sh` 初始化 → 只写 `PROJECT_MEMORY.md` + `memory.md` |
| 第 2 周 | 发生踩坑时手动补 `#@` 标注 → `extract-annotations.sh` 建索引 |
| 第 3 周 | `PROJECT_MEMORY.md` 里加"改动前必须 check-impact"的强制规则 |
| 长期 | 踩一个坑标一条，标注库持续增长，技能库交给 AI 迭代 |

---

## FAQ

### Q: AI 真的会每次改文件都跑 check-impact.sh 吗？

取决于 AI 是否遵守 SKILL.md 的协议。传火提供的是机制和工具，强制力来自 `PROJECT_MEMORY.md` 里的"传火规则"——把它写成硬约束，AI 遵守的概率会显著提高。

### Q: 冷启动时没有标注，check-impact.sh 还有用吗？

有用。即使索引为空，`check-impact.sh` 仍会：
- 报告目标文件是否在高风险清单中
- 提取文件内的内联 `#@` 标注
- 给出风险等级判断

索引是加分项，不是前置条件。

### Q: 标注会过期吗？怎么清理？

会。代码改了但标注没同步就会过期。目前需要手动维护，改代码时同步改标注。未来会加过期检测脚本。

### Q: 可以只用一部分功能吗？

可以。比如：
- 只用 `init-project.sh` + `memory.md` 做会话记忆
- 只用 `#@` 标注 + `extract-annotations.sh` 做依赖索引
- 只用 `check-impact.sh` 做改动前检查

各模块解耦，按需取用。

### Q: 和 .cursorrules / .trae/rules 有什么区别？

那些是"静态规则"，传火是"动态记忆 + 影响检查"。两者互补：
- 静态规则告诉 AI "永远怎么做"
- 传火告诉 AI "这个项目当前状态是什么、这个文件改了会影响谁、上次踩过什么坑"

---

## 一句话本质

> **标注住在代码旁，记忆按需加载，AI 先报告影响再动手——高风险等确认，低风险自己判。**

---

## License

MIT
