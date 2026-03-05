# Issue History / 历史记录

Records the full lifecycle of each issue: background, design, implementation, limitations, and follow-ups.

本文档记录每个 issue 的完整生命周期：背景、设计方案、实现方案、局限性及遗留事项。

- Entries are ordered newest-first / 条目按时间倒序排列（最新在上）
- See [README.md](README.md) for scope and field conventions / 参见 README.md 了解记录范围与字段约定

<!--
## Record Template / 记录模板

Copy the block below when creating a new entry.
新建条目时复制以下模板。

### HIST-NNN: <Title / 标题>

- **Status / 状态**: Open | In Progress | Closed
- **Date / 日期**: YYYY-MM-DD
- **Related commits / 关联提交**: (optional)

#### Background / 背景

(Why this issue exists — context, motivation, triggering event)

#### Design / 设计方案

(Approach chosen, alternatives considered, trade-offs)

#### Implementation / 实现方案

(What was actually done — files changed, key decisions during execution)

#### Limitations / 局限性

(Known constraints, edge cases not covered, performance caveats)

#### TODOs / 遗留项

(Follow-up work, deferred items, future improvements)

-->

---

## Summary / 总览

| ID | Title / 标题 | Status / 状态 | Date / 日期 |
|----|-------------|--------------|------------|
| HIST-002 | Project Overlay 优化方案 | In Progress | 2026-03-04 |
| HIST-001 | Agent Rules 隔离方案 | Closed | 2026-03-04 |
| HIST-000 | Visual Explanations 规则 | Closed | 2026-03-01 |

---

## Records / 记录

### HIST-002: Project Overlay 优化方案

- **Status / 状态**: In Progress
- **Date / 日期**: 2026-03-04
- **Related commits / 关联提交**: `e6c6157` Add project-overlay skill for AI-guided .agent-local.md generation, `9f1799e` Refactor agent-sync into subcommands and fix review findings

#### Background / 背景

当前 project overlay 流程要求用户手动复制 `overlay-template.md` 到 `.agent-local.md` 并逐 section 填写。模板 section 多、门槛高，导致 overlay 内容空泛、不贴合项目、缺乏维护动力，大部分项目实际依赖默认行为。

#### Design / 设计方案

将信息采集从「静态模板填写」改为「对话引导式收集」，封装为 Agent Skill `project-overlay`：

- **Init Flow**: 两阶段对话——Phase 1 收敛必填信息（Project Overview + Structure），Phase 2 发散探索可选配置；Agent 生成 `.agent-local.md`
- **Update Flow**: Agent 读取已有 overlay + 主动检测过时信号，聚焦变更 section 做局部刷新
- **模板内嵌 Schema**: 在 `overlay-template.md` 的 HTML 注释中追加 `@schema` 标注（Single Source of Truth），废弃独立 schema 文件
- **格式校验门控**: 生成后自动校验（Packs 合法性、标题一致性、占位符扫描等），失败则阻断
- **原子写入**: 临时文件 → 校验 → 原子替换 + `.bak` 备份
- **证据标注**: `[推断]` / `[待确认]` HTML 注释，sync 时自动剥离

经 4 个模型（Gemini、Kimi、GPT-Codex、Claude）多轮交叉 review 后迭代至 v3 方案（v1 初始构想 → v2 综合 review 细化 → 实现 → 实现 review 及修复引入 manifest、收敛同步等新设计 → v3）。

#### Implementation / 实现方案

| 文件 | 变更 |
|------|------|
| `skills/project-overlay/SKILL.md` | Skill 入口，路由 init/update 流程 |
| `skills/project-overlay/init-guide.md` | 初始化对话引导脚本 |
| `skills/project-overlay/update-guide.md` | 更新对话引导脚本 |
| `templates/overlay-template.md` | 嵌入 `@schema` 注释 |
| `scripts/agent-sync.sh` | 新增 skills 同步（收敛式 + manifest）、overlay 缺失提示 |
| `README.md` | 补充 Skill 触发引导 |

实现后经 Gemini / Kimi / GPT-Codex 两轮 review，修复了 `.gitignore` 冲突澄清、manifest 精确清理、收敛式同步、staleness gate 纳入 skills 等问题。

#### Limitations / 局限性

- 格式校验的自动修复仅限机械性问题（HTML 注释闭合、code block 标签），不涉及语义改写
- Skills 同步使用 `cp -R` glob 展开，不会复制隐藏文件（dotfiles），且对空目录可能触发 glob 异常
- 若 `.agent-sync-skills-manifest` 被手动删除，`clean` 无法识别历史托管目录，会导致残留

#### TODOs / 遗留项

- [x] Phase A 试点——在 1 个新项目上测试 Init Flow，采集 `overlay-metrics.log`
- [x] Phase B 试点——在 1 个已有项目上测试 Update Flow
- [ ] Phase C 试点——在 1 个 C++/CUDA 项目上测试扩展分支
- [ ] 将 skills 复制改为 `cp -R "$skill_dir/." "$target_dir/"` 以覆盖隐藏文件
- [ ] 为 manifest 丢失场景增加 fallback 清理策略
- [ ] 对话持久化与跨会话恢复

---

### HIST-001: Agent Rules 隔离方案

- **Status / 状态**: Closed
- **Date / 日期**: 2026-03-04
- **Related commits / 关联提交**: `32f2aa4` Move CLAUDE.md/AGENTS.md to .agent-rules/ to prevent Cursor duplicate injection, `f65f1fc` Auto-maintain .cursorignore to prevent Cursor duplicate rule loading

#### Background / 背景

Cursor 启动时自动嗅探并注入根目录 `AGENTS.md` 和 `CLAUDE.md`（不受 `.cursorignore` 控制），与 `.cursor/rules/` 内容完全重复，导致同一套规则被注入 2-3 次，浪费大量 Token 并挤压可用上下文窗口。

#### Design / 设计方案

根目录默认不放 `AGENTS.md` / `CLAUDE.md`，改为输出到 `.agent-rules/` 隐藏目录。Codex 和 Claude Code 通过 shell wrapper 临时软链接到根目录，用完自动清理：

| 输出 | 旧路径 | 新路径 |
|------|--------|--------|
| Cursor rules | `.cursor/rules/*.mdc` | 不变 |
| Codex rules | `./AGENTS.md` | `.agent-rules/AGENTS.md` |
| Claude Code rules | `./CLAUDE.md` | `.agent-rules/CLAUDE.md` |

Shell wrapper `_agent_with_rules()` 向上查找 `.agent-rules/`（不依赖 git）→ 软链接 → 执行 agent → trap 自动清理。采用软链接而非 `--append-system-prompt-file` 以保留 Claude Code 的多层 `CLAUDE.md` 发现机制。

退出条件：Codex 支持 `--agents` flag / Claude Code 支持自定义路径 / Cursor 支持禁用自动注入。

#### Implementation / 实现方案

已完成：

1. `agent-sync` 输出路径变更至 `.agent-rules/`
2. 根目录残留 `AGENTS.md` / `CLAUDE.md` 已清理
3. Shell wrapper（`_agent_with_rules` / `codex-run` / `claude-run`）已写入 `~/.bashrc`

#### Limitations / 局限性

- Codex/Claude Code 不再开箱即用，依赖 wrapper（临时方案）
- 不依赖 git 的目录查找可能在极端嵌套结构下效率低

#### TODOs / 遗留项

None.

---

### HIST-000: Visual Explanations 规则

- **Status / 状态**: Closed
- **Date / 日期**: 2026-03-01
- **Related commits / 关联提交**: (not recorded)

#### Background / 背景

对于算法、原理类 query，Agent 仅输出纯文字说明，缺乏可视化手段，信息传递效率低。用户提出希望 Agent 在适合时优先提供 ASCII 图或流程图辅助说明。

#### Design / 设计方案

采纳，按 SHOULD 级别实现。在 `.cursor/rules/00-communication.mdc` 的 `Output Format → General` 之后新增 `### Visual Explanations` 子节，包含 5 条规则：

- `SHOULD` 在解释算法、数据结构、架构模式、状态转换、并发模型、组件生命周期时提供 ASCII 或 Mermaid 图
- `SHOULD` 流程图/时序图/状态机优先用 Mermaid（Cursor 原生渲染），须使用 ` ```mermaid ` 代码块
- `SHOULD` 简单数据结构快照（树、数组、栈、内存布局）优先用 ASCII art
- `MUST NOT` 为追求形式而牺牲准确性——有歧义的图不如正确的文字
- `MAY` 说明简单时跳过图表（如单一公式、简单 API 用法）

经 Gemini、Kimi、GPT-Codex 三方 review 后，融合了以下建议：扩充场景（concurrency/lifecycle）、强调 ` ```mermaid ` 语法标记、补充 Acceptance Criteria、将触发条件具体化。

#### Implementation / 实现方案

| 文件 | 变更 |
|------|------|
| `.cursor/rules/00-communication.mdc` | 在 Output Format 下新增 `### Visual Explanations` 子节（5 条规则） |

#### Limitations / 局限性

- 触发条件为 SHOULD 弹性，不同模型/回合仍可能出现"该画不画"或"过度画图"的解释差异
- 未覆盖"Mermaid 渲染失败时自动回退 ASCII"的显式规则

#### TODOs / 遗留项

None.
