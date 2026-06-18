---
name: "chuanhuo"
description: "约束 AI 在连续性编码任务中的工作方式：强制改动前影响检查、渐进式记忆加载、踩坑标注。会话启动时和修改任何文件前必须触发。"
---

# 传火 — 连续性任务守护

> **本质**：让依赖信息住在它描述的代码旁边，让记忆按需加载而非全量灌入，让 AI 先报告影响再动手。

## 何时触发

- **会话启动时**：自动执行协议1（加载记忆）
- **修改任何文件前**：自动执行协议2（影响检查）
- **发生修B破A或发现反直觉依赖时**：自动执行协议3（踩坑标注）
- **会话结束或重大决策后**：自动执行协议4（状态更新）

---

## 协议1：会话启动

每次新会话开始时，按顺序加载三层记忆：

1. **读 PROJECT_MEMORY.md**（项目框架记忆）— 架构、命令、硬约束、高风险文件清单
2. **读 memory.md**（动态状态）— 当前状态、近期决策、活跃问题
3. **扫描 skills/_meta.json**（踩坑技能索引）— 只读元数据，不读正文
4. **输出确认**：

```
=== 传火已启动 ===
当前状态：<从 memory.md 提取>
活跃问题：<从 memory.md 提取>
可用技能：<N> 个（按需加载）
高风险区域：<从 PROJECT_MEMORY.md 提取>
```

**关键原则**：启动时只读 _meta.json 的元数据（~100 tokens/技能），不读技能正文。只有当任务涉及某技能的触发条件时，才加载对应 .md 正文。

---

## 协议2：改动前检查

准备修改任何文件前，必须执行影响检查。

### 步骤

1. **判断风险等级**：检查目标文件是否在 PROJECT_MEMORY.md 的高风险清单中
2. **调用脚本**：`bash <skill-path>/scripts/check-impact.sh <目标文件>`
3. **阅读影响报告**
4. **分级处理**：
   - **高风险**（在清单中）→ 输出报告，**等待用户确认**后才动手
   - **低风险**（不在清单中）→ 输出报告，AI 自行判断是否需要确认
5. **动手修改**

### 影响检查输出格式

```
=== 影响检查报告 ===
目标文件：<file>
风险等级：<高/低>（<原因>）

直接依赖（本文件标注）：
  → <file>#<symbol> | <描述>
  影响：<影响范围描述>

反向依赖（谁依赖本文件）：
  <file> (<N>处调用)
  <file> (<N>处调用)

踩坑警告：
  <pitfall 描述>

建议：<验证建议>
状态：<⚠️ 高风险，等待用户确认 / ✅ 低风险，可继续>
```

### 高风险清单示例（在 PROJECT_MEMORY.md 中维护）

```markdown
## 高风险文件（改动前必须用户确认）
- src/auth/**          # 鉴权链路
- src/db/migrations/** # 数据库迁移
- src/middleware/**    # 中间件
- **/config.{ts,json}  # 配置文件
- **/*.sql             # SQL 脚本
```

---

## 协议3：踩坑标注

### 触发条件

- 发生"修B破A"
- 发现反直觉的依赖关系
- 踩了一个坑并修复后

### 步骤

1. **在相关代码旁补 #@ 标注**
2. **运行** `bash <skill-path>/scripts/extract-annotations.sh <目录>` 更新索引
3. **如果是通用坑** → 写入 `skills/<pitfall-name>.md` 并更新 `skills/_meta.json`

### 标注规范

混合语法：竖线前是结构化字段（脚本解析），竖线后是自然语言（AI 理解上下文）。

```
#@depends-on: <file>#<symbol> | <自然语言描述>
#@impact: <自然语言描述>
#@flow: <condition> → <result> | <自然语言描述>
#@route: <pattern> → <handler>
#@state: <state> +<event> → <next>
#@pitfall: <自然语言描述>
```

### 标注示例

```typescript
//#@depends-on: src/db/users.ts#findUser | 查找用户时依赖此函数
//#@impact: 所有需要鉴权的路由 | token 验证逻辑改了会影响这里
//#@flow: if (token.expired) → refreshToken | 过期时自动刷新，不重新登录
//#@pitfall: token 过期时间不能短于 1 小时，否则移动端频繁掉登录
function validateToken(token: string) { ... }
```

### 标注原则

- **只标反直觉的和踩过坑的**，不标显而易见的
- **标注住在它描述的代码旁边**，不存外部文件
- **10 条精准标注 > 100 条"可能相关"**
- 标注和代码一起演化，改代码时同步更新标注

---

## 协议4：状态更新

### 触发条件

- 会话结束前
- 做出重大决策后
- 完成一个阶段性任务后

### 步骤

1. **更新 memory.md**
2. **只记四类信息**：
   - 当前状态（正在做什么、进度）
   - 近期决策（最近 5 条，含原因）
   - 活跃问题（未解决的问题）
   - 不要再试的方案（已验证不可行）

### 禁止

- ❌ 记流水账（"我先试了 A，又试了 B"）
- ❌ 记代码细节（代码本身就是记录）
- ❌ 记临时信息（构建产物、临时文件路径等）

---

## 项目文件结构

```
<project-root>/
├── PROJECT_MEMORY.md                    # 项目框架记忆（必读，<200行）
├── memory.md                    # 动态状态记忆
├── skills/                      # 踩坑技能库
│   ├── _meta.json               # 技能元数据索引
│   └── <pitfall-name>.md        # 具体踩坑技能
└── .impact-index.json           # 自动生成的依赖索引（加入 .gitignore）
```

### PROJECT_MEMORY.md 应包含

- 项目架构概述（一图或几句话）
- 构建/测试/部署命令
- 硬约束（不可违反的规则）
- 高风险文件清单
- 环境信息（数据库、端口、依赖版本）

### memory.md 结构

```markdown
# 项目状态

## 当前状态
- 正在做：<任务>
- 进度：<模块> 已完成，<模块> 进行中

## 近期决策（最近 5 条）
- [日期] 决定 <方案>，原因：<为什么>

## 活跃问题
- <问题描述，含相关文件>

## 不要再试的方案
- <方案>：会导致 <问题>（已验证不可行）
```

### skills/_meta.json 结构

```json
{
  "skills": [
    {
      "id": "<唯一标识>",
      "name": "<技能名称>",
      "trigger": "<触发条件：修改XX文件时 / 遇到XX问题时>",
      "file": "<文件名>.md",
      "tokens": "<预估 token 数>"
    }
  ]
}
```

---

## 脚本说明

### init-project.sh

初始化项目结构，创建 PROJECT_MEMORY.md、memory.md、skills/ 目录。

```bash
bash <skill-path>/scripts/init-project.sh <项目根目录>
```

### extract-annotations.sh

扫描代码中的 #@ 标注，生成 .impact-index.json 索引。

```bash
bash <skill-path>/scripts/extract-annotations.sh [扫描目录，默认 src/]
```

### check-impact.sh

检查指定文件的影响范围，输出影响报告。

```bash
bash <skill-path>/scripts/check-impact.sh <目标文件>
```

---

## 引入节奏

```
第1周：init-project.sh 初始化 → 只写 PROJECT_MEMORY.md + memory.md
第2周：发生踩坑时手动补 #@ 标注 → extract-annotations.sh 建索引
第3周：PROJECT_MEMORY.md 里加"改动前必须 check-impact"的强制规则
长期：踩一个坑标一条，标注库持续增长，技能库交给 agent 迭代
```

---

## 一句话本质

> **标注住在代码旁，记忆按需加载，AI 先报告影响再动手 — 高风险等确认，低风险自己判。**

解决的不是 AI 的能力问题，而是 AI 的工作方式问题 — 从"无状态的即时反应"变成"有状态的渐进式工程"。
