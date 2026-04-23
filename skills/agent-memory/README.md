# Agent Memory

让 AI agent 能保存工作上下文并在后续 session 中恢复，支持跨 session、跨 agent（Cursor / Claude Code / Codex）。

## 安装

```bash
# 通过 agent-sync 部署到目标项目（推荐）
agent-sync skills <project-dir>

# 或手动复制到个人 skills 目录（所有项目可用）
cp -r agent-memory ~/.cursor/skills/
```

部署后 Cursor 自动发现 `SKILL.md` 并在匹配场景加载。

## 命令

> **注**：通过 `agent-sync` 部署时默认前缀 `gla-`（HIST-005），实际调用变成 `/gla-agent-memory <子命令>`（例如 `/gla-agent-memory dump`）。前缀可在项目 `.agent-local.md` 的 `**Skill Prefix**: ...` 自定义或关闭（`none` = 关闭），详见 agent-toolkit 根 README 的 "Skill Prefix" 小节。

在 Cursor 中通过 `/agent-memory <子命令>` 调用：

| 命令 | 作用 |
|------|------|
| `/agent-memory dump` | 保存当前 session 上下文到文件 |
| `/agent-memory resume` | 从之前的 session 恢复上下文 |
| `/agent-memory resume kernel` | 恢复包含 "kernel" 关键词的 session |
| `/agent-memory knowledge` | 沉淀长期有用的知识笔记 |

### /agent-memory dump

将当前对话中的任务目标、关键发现、决策、下一步行动提取为 session 文件。

```
你: [完成了一系列分析工作]
你: /agent-memory dump
Agent: ✓ Session saved: .agent-memory/sessions/2026-03-17T08-30Z_kernel-6-perf.md
       ✓ INDEX updated
       Status: paused
       Summary: kernel_6 瓶颈分析完成, 待 padding 优化
```

支持自动触发：当 context window 接近上限触发 summarization 时，agent 会先执行 dump 保存上下文。

### /agent-memory resume

在新 session 中加载之前保存的上下文继续工作。

```
你: /agent-memory resume kernel
Agent: 找到 1 个匹配的 paused session:
       📄 kernel-6-perf (2026-03-17) — 瓶颈分析完成, 待 padding 优化
       
       已恢复上下文，继续实施 padding 优化...
```

支持被动发现：如果之前有 paused session 且与当前任务相关，agent 会主动提示。

### /agent-memory knowledge

独立于 dump，将当前或历史 session 中有长期价值的发现沉淀为给人阅读的知识笔记。

```
你: /agent-memory knowledge
Agent: ✓ Knowledge note saved: .agent-memory/knowledge/kernel-6-perf-insights.md
```

Knowledge note 是唯一给人阅读的产出物，格式为正常 markdown，默认 git tracked。

## 项目中生成的文件

```
<project>/
├── .agent-memory/
│   ├── sessions/              # Agent 用的 session 快照 (.gitignore)
│   ├── knowledge/             # 给人读的知识笔记 (git tracked)
│   └── MEMORY-INDEX.md        # Agent 用的索引 (.gitignore)
└── .cursor/rules/
    └── agent-memory-hint.mdc  # 被动发现提示 (自动维护)
```

推荐 `.gitignore`：

```gitignore
.agent-memory/sessions/
.agent-memory/MEMORY-INDEX.md
```

## 跨 Agent 使用

Session 文件是纯 markdown，任何有文件系统访问权限的 agent 都能直接读取恢复：

| Agent | 用法 |
|-------|------|
| Cursor | `/resume` |
| Claude Code | 读取 `.agent-memory/MEMORY-INDEX.md`，然后读取对应 session 文件 |
| Codex | 同上 |

无需 MCP、无需数据库、无需额外进程。

## Skill 文件结构

```
agent-memory/
├── README.md                  # 本文件
├── SKILL.md                   # Agent 指令入口
├── DESIGN.md                  # 设计文档 + 调研
└── references/
    ├── dump-guide.md          # /dump 流程
    ├── resume-guide.md        # /resume 流程
    ├── knowledge-guide.md     # /knowledge 流程
    ├── session-template.md    # Session 文件模板 (LLM-compact)
    ├── index-template.md      # INDEX 文件模板 (LLM-compact)
    └── knowledge-template.md  # 知识笔记模板 (human-readable)
```
