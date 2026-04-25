---
# Spec (required)
name: agent-memory
description: >-
  Dump and resume agent working context across sessions via structured files.
  Use when the user asks to save context, dump memory, resume a previous session,
  保存上下文, 继续上次任务, or when a paused session is detected that matches
  the current task. Commands: /agent-memory dump, /agent-memory resume, /agent-memory knowledge.

# Spec (optional)
license: MIT
compatibility: Cross-tool (Cursor, Claude Code, Codex). Requires filesystem access.
metadata:
  author: georgel
  version: "1.2"

# Spec (experimental)
# allowed-tools: Bash(git add *) Bash(git commit *) Read  # support claude only
# disable-model-invocation: true                          # support cursor + claude

# Spec (claude-only)
when_to_use: >-
  Use when the user explicitly asks to save / dump / checkpoint the current
  working context, resume a previous session, or distill a knowledge note —
  OR when the context window is approaching its limit and a summarization
  is about to happen (auto-dump). Also use passively when a paused session
  hint in .cursor/rules/agent-memory-hint.mdc is clearly related to the
  user's current task. Do NOT use just to take notes during a live task.
# argument-hint: "[issue-number] [branch]"
# arguments: [issue, branch]
# user-invocable: true
# model: sonnet        # sonnet / opus / haiku / id / inherit
# effort: medium       # low / medium / high / xhigh / max
# context: fork        # When forking, run the body in an independent subagent context
# agent: general-purpose
# hooks:
#   PreToolUse: ./hooks/<pre.sh>
#   PostToolUse: ./hooks/<post.sh>
#   Stop: ./hooks/<stop.sh>
# paths:
#   - "src/**/*.ts"
# shell: bash          # bash / powershell
---

# Agent Memory

持久化 agent 工作上下文，支持跨 session、跨 agent 恢复。

## 双轨设计

| 类型 | 目录 | 消费者 | 格式 | Git |
|------|------|--------|------|-----|
| **Session dump** | `.agent-memory/sessions/` | LLM agent | LLM-compact (≤200 tokens) | ignored |
| **Memory index** | `.agent-memory/MEMORY-INDEX.md` | LLM agent | LLM-compact (one-line/entry) | ignored |
| **Knowledge note** | `.agent-memory/knowledge/` | 人类 | Human-readable markdown | tracked |

## 命令路由

Cursor 中通过 `/agent-memory <子命令>` 调用，也支持自然语言触发：

| 子命令 | 自然语言触发 | Flow |
|--------|------------|------|
| `dump` | "dump memory" / "保存上下文" / "存一下" | Dump Flow |
| `resume [keyword]` | "resume" / "继续上次" / "从哪里接着" | Resume Flow |
| `knowledge` | "沉淀一下" / "写个总结" | Knowledge Flow |

### Dump Flow

1. 读取 [dump-guide.md](references/dump-guide.md)
2. 读取 [session-template.md](references/session-template.md)
3. 按 dump-guide 的 7 步流程执行（context 分析 → 生成 session → 安全审查 → 写文件 → 更新 INDEX → 更新 hint）

**自动触发**：当 context window 接近上限、即将触发 summarization 时，agent **SHOULD** 先执行 dump flow 保存当前上下文，再进入 summarization。详见 dump-guide.md "Auto Dump" 一节。

### Resume Flow

1. 读取 [resume-guide.md](references/resume-guide.md)
2. 按 resume-guide 流程扫描 INDEX → 加载 session → 继续工作

### Knowledge Flow

1. 读取 [knowledge-guide.md](references/knowledge-guide.md)
2. 读取 [knowledge-template.md](references/knowledge-template.md)
3. 按 knowledge-guide 流程生成 human-readable 知识笔记

Knowledge flow 独立于 dump — 可以在任何时候执行，不需要先 dump。
适用于：当前对话有长期有用的发现，或用户想整理一个主题的认知。

## 被动发现

如果 `.cursor/rules/agent-memory-hint.mdc` 存在（由 dump flow 自动维护），
agent 会在系统 prompt 中看到 paused session 摘要。

当用户的当前任务与某个 paused session 明显相关时，主动建议：

> 我发现有一个之前的相关 session: <slug> (<date>)。要从上次的进度继续吗？

**MUST NOT** 在用户没有相关任务时主动提起。

## 安全基线

Agent 在 dump 时 **MUST NOT** 写入以下内容：

- API keys, tokens, passwords, credentials
- 完整的环境变量值（可记录变量名 `$VAR`，不记录值）
- PII（邮箱、工号等）
- 敏感的内部 IP / hostname

违反时用 `<REDACTED>` 替换。详见 dump-guide.md Step 3。

## 关键文件

| 文件 | 用途 |
|------|------|
| [dump-guide.md](references/dump-guide.md) | `/dump` 流程 |
| [resume-guide.md](references/resume-guide.md) | `/resume` 流程 |
| [knowledge-guide.md](references/knowledge-guide.md) | `/knowledge` 流程 |
| [session-template.md](references/session-template.md) | LLM-compact session 模板 |
| [index-template.md](references/index-template.md) | LLM-compact INDEX 模板 |
| [knowledge-template.md](references/knowledge-template.md) | Human-readable 知识笔记模板 |

## 语言约束

- **对话语言**：跟随用户
- **Session / INDEX 输出**：技术术语保持英文，描述性文字可用用户语言
- **Knowledge note 输出**：跟随项目主语言 / 用户偏好
