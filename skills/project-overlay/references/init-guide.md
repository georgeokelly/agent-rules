# Project Overlay 初始化对话脚本

本文件指导 Agent 通过两阶段对话为项目创建 `.agent-local.md`。

**前置条件**：Agent 必须先读取 `overlay-template.md`（含 `@schema` 约束）。

---

## Phase 1：核心信息收集

### 开场

用一句话说明目的，然后用开放式问题启动对话：

> 我来帮你创建项目配置（`.agent-local.md`），这样 AI Agent 就能更好地理解你的项目。请简单介绍一下你的项目：它是什么、主要用什么技术栈、项目结构大概是怎样的？

### 上下文 Resume 检测

如果当前对话上下文已包含项目信息（例如用户刚完成一轮开发讨论），直接利用已知信息，跳过已明确的问题。

### 智能追问策略

根据用户回答中的关键词决定追问方向，**不要逐字段遍历**：

- 用户提到 "FastAPI" → 推断 Build System = pip/uvicorn，转而确认目录结构
- 用户提到 "React + TypeScript" → 推断 Packs 需包含前端相关包，追问构建工具
- 用户提到 "CUDA kernel" → 触发 C++/CUDA 扩展分支（Phase 2 自动展开）

### 推断与确认

对可推断字段，给出推断值并请用户确认：

> 根据你的描述，我推断 Build System 是 pip + setuptools，Target Platform 是 Linux，对吗？

### 最小信息集检查点

当以下字段都有值（用户明确给出或 Agent 推断后确认）时 Phase 1 完成：

| 字段 | 要求 |
|------|------|
| `**Project**:` | 项目名 + 一句话描述 |
| `**Tech Stack**:` | 主要技术栈 |
| `**Packs**:` | 可从 Tech Stack 自动推断，但须确认 |
| 目录树 | 到关键目录级别（depth 2-3 即可，不要逐文件展开） |
| Source-Test Mapping | 无测试项目允许声明 "N/A" |

**注意**：对于非代码项目（纯文档、数据仓库等），Source-Test Mapping 允许回答 "N/A"。

---

## Phase 2：可选 Section 补充

### 场景化触发

**不要逐条遍历所有可选 Section**。根据 Phase 1 已知信息判断哪些相关：

- 纯 Python CLI 工具 → 跳过 Performance Targets
- 含 C++/CUDA → 自动展开模板底部扩展块（架构列表、Key Macros 等）
- 含公开 API → 追问 Boundaries

### 每个 Section 一轮

对需要追问的 Section，用一句话解释用途 + 默认值，询问是否自定义：

> Build & Test Commands 默认是 `pip install -e . -v && pytest tests/ -v`。你的项目有不同的构建/测试命令吗？

用户说"用默认的"→ 直接采用默认值，不再追问。

### C++/CUDA 扩展分支

如果 Phase 1 确认了 C++/CUDA 技术栈，Phase 2 自动展开以下内容：
- Tech Stack 追加 C++ 版本、CUDA 版本
- Build System 追加 CMake
- Performance Targets 切换为 GPU 性能指标模板
- Project-Specific Patterns 追问 CUDA 架构列表和 Key Macros

---

## 生成流程

Phase 1 + Phase 2 完成后，执行以下步骤：

### Step 1：读取模板和 Schema

读取 `overlay-template.md`，解析每个 Section 的 `@schema` 注释获取：
- 字段列表、格式要求、默认值
- 必填/选填标记

### Step 2：组装内容

将对话收集的信息映射到模板 Section。规则：
- 用户明确给出的值 → 直接写入，无标注
- Agent 推断且用户已确认 → 写入，附加 `<!-- [推断] 推断依据 -->`
- Agent 推断但用户未确认 → 写入，附加 `<!-- [待确认] 推断依据 -->`
- 使用模板默认值的字段 → 直接使用默认值，无标注
- 所有写入文件的内容（字段值、自由文本、目录树注释等）**MUST** 使用英文，与 `overlay-template.md` 保持一致。对话中用户使用中文描述的内容，Agent 须翻译为英文后写入。HTML 注释（如 `<!-- [推断] -->` 标注）不受此限制，可使用中文。

### Step 3：插入阅读指南

在生成的 `.agent-local.md` **顶部**插入：

```markdown
<!--
=== 阅读指南 ===
本文件由 project-overlay Skill 通过对话生成。
- <!-- [推断] --> 标记表示 Agent 推断且已确认的内容
- <!-- [待确认] --> 标记表示需要你 review 的内容
- 所有 HTML 注释在 agent-sync 编译时会被自动去除
-->
```

### Step 4：写入临时文件

将内容写入 `.agent-local.md.tmp`，**不要直接写入 `.agent-local.md`**。

如果已存在 `.agent-local.md`，先备份为 `.agent-local.md.bak`。

### Step 5：格式校验门控

对 `.agent-local.md.tmp` 执行以下 **全部** 校验。任一失败则阻断，不得提示用户执行 `agent-sync`：

1. **Packs 合法性**：`**Packs**:` 行的每个值都存在于 `packs/` 目录（当前可用：cpp, cuda, python, markdown, shell, git, swift, pybind11）
2. **Section 标题一致性**：所有 `##` 标题与 `overlay-template.md` 的 Section 标题完全一致（大小写敏感）
3. **目录树格式**：目录树使用无语言标签的 fenced code block（`` ``` `` 而非 `` ```bash ``）
4. **构建命令格式**：Build & Test Commands 使用 `` ```bash `` fenced code block
5. **无残留占位符**：不包含 `[TODO: ...]` 占位符
6. **HTML 注释闭合**：所有 `<!--` 都有对应的 `-->`
7. **路径深度**：overlay 文件路径相对于项目根目录深度 ≤ 3

校验失败时：
- 仅允许自动修复**机械性问题**（最多 2 次）：修复未闭合的 HTML 注释、调整 fenced code block 语言标签、移除残留 `[TODO: ...]` 占位符
- **不得**通过自动修复重写用户内容或变更语义
- 2 次机械修复后仍失败 → 向用户报告具体校验项和失败原因，中止流程

### Step 6：原子替换

校验通过后：
1. 将 `.agent-local.md.tmp` 重命名为 `.agent-local.md`
2. 确认文件写入成功

### Step 7：输出摘要

生成完成后，输出以下内容：

#### 7a. Section 级摘要

列出每个 Section 的状态（已填写 / 使用默认值 / 未使用）。

#### 7b. 未确认项清单

如果存在 `<!-- [待确认] -->` 标注，单独输出：

```
⚠️ 以下内容为 Agent 推断，需要你确认后再执行 agent-sync：
  1. [Section 名] 推断内容（推断依据）
  2. ...
请逐条确认或修改，全部确认后再执行 agent-sync。
```

**未确认项全部解决前，不要提示用户执行 `agent-sync`。**

#### 7c. Overlay 路径深度校验

输出：
- 本次生成的 overlay 绝对路径
- 该路径相对于项目根目录的深度
- 若深度 > 3，明确警告：此文件超出 agent-sync 的扫描范围（`-maxdepth 3`），sync 不会处理

#### 7d. 跨工具消费说明

```
📋 生成完成。此文件将通过 agent-sync 编译为以下工具的规则：
  - Cursor: .cursor/rules/project-overlay.mdc（alwaysApply: true）
  - Claude Code: .claude/rules/*.md（HIST-004 原生 per-file）
  - Codex: 项目根 AGENTS.override.md（HIST-007 Codex 专属入口）
  - OpenCode: opencode.json + .opencode/skills/（HIST-006）
请执行 `agent-sync .` 生成上述文件。
```

#### 7e. 指标记录

如果项目中存在 `temp/` 目录，追加一行到 `temp/overlay-metrics.log`：

```
[ISO-8601-timestamp] mode=init rounds=<对话轮次> defaults_used=<默认值数>/<总Section数> unconfirmed=<待确认数> duration_sec=<估算耗时>
```

---

## 关键约束

- **Packs 格式**：逗号分隔，无引号，`agent-sync.sh` 使用 `sed` 解析 `**Packs**:` 行
- **Section 标题**：必须与 `overlay-template.md` 完全一致，`agent-sync` 不解析标题但下游工具可能依赖
- **HTML 注释**：`agent-sync` 的 `strip_html_comments` 会移除所有 `<!-- ... -->`，证据标注不会出现在最终规则中
- **自定义内容保护**：如果用户在 `.agent-local.md` 中手动添加了超出模板 schema 的内容（如额外 `##`/`###`），识别后原样保留
- **输出语言分离**：与用户的对话交互跟随用户语言（如中文），但写入 `.agent-local.md.tmp` 的所有内容 **MUST** 使用英文（HTML 注释除外）。`agent-sync` 会直接将文件内容编译为下游规则，中文内容会导致规则中英混杂。
