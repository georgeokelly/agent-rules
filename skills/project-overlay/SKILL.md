---
name: project-overlay
description: Create or update project-specific AI configuration (.agent-local.md) through guided conversation. Use when the user wants to create overlay, init project, setup agent rules, 创建项目配置, 初始化规则, update overlay, 更新项目配置, or when .agent-local.md is missing or outdated.
---

# Project Overlay

通过引导式对话创建或更新项目的 `.agent-local.md` 配置文件，取代手动逐字段填写。

## 流程路由

根据当前状态选择执行路径：

**创建新 overlay？**（项目中不存在 `.agent-local.md`）→ 执行 Init Flow
**更新已有 overlay？**（`.agent-local.md` 已存在）→ 执行 Update Flow

### Init Flow

1. 读取 [init-guide.md](init-guide.md)
2. 读取项目中的 `overlay-template.md`（位于 `$AGENT_RULES_HOME/templates/overlay-template.md`，其中包含 `@schema` 约束注释）
3. 按 init-guide 的两阶段对话流程与用户交互
4. 生成 `.agent-local.md`（含格式校验门控 + 原子写入）

### Update Flow

1. 读取 [update-guide.md](update-guide.md)
2. 读取 `overlay-template.md`（含 `@schema`）和当前 `.agent-local.md`
3. 按 update-guide 的流程执行局部刷新

## 被动发现

在日常执行任务时，如果检测到以下信号，主动提议运行 Update Flow：

- 项目中出现 `.agent-local.md` 未记录的新语言/框架文件（如出现 `.tsx` 但 Packs 无前端包）
- 目录结构与 Project Structure 描述明显不符
- 构建命令与实际使用不匹配

提议应贴合开发意图，例如：
> 我注意到项目新增了 React 组件，需要更新 Packs 和目录结构吗？

## 关键文件

| 文件 | 位置 | 用途 |
|------|------|------|
| `overlay-template.md` | `$AGENT_RULES_HOME/templates/` | 模板 + @schema 约束（Single Source of Truth） |
| `.agent-local.md` | 项目根目录 | 项目配置文件（用户提交到 git） |
| `init-guide.md` | 本 skill 目录 | 初始化对话脚本 |
| `update-guide.md` | 本 skill 目录 | 更新对话脚本 |

## 跨工具消费

`.agent-local.md` 通过 `agent-sync` 编译为多个工具的规则：

- **Cursor**: `.cursor/rules/project-overlay.mdc`（alwaysApply: true）
- **Claude Code**: `.agent-rules/CLAUDE.md`（拼接到末尾）
- **Codex**: `.agent-rules/AGENTS.md`（与 CLAUDE.md 相同）
