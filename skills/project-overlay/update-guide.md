# Project Overlay 更新对话脚本

本文件指导 Agent 对已有的 `.agent-local.md` 进行局部更新。

**前置条件**: Agent 必须先读取当前 `.agent-local.md` 和 `overlay-template.md`（含 `@schema`）。

---

## 触发方式

### 显式触发

用户主动要求更新 overlay（如"帮我更新 .agent-local.md"）。

### 被动发现

Agent 在日常任务中检测到以下偏差信号时, 主动提议更新: 

- 项目中出现 `.agent-local.md` 未记录的新语言/框架文件
- 目录结构与 Project Structure 描述明显不符
- 实际使用的构建/测试命令与配置不一致

**提议措辞要贴合开发意图**, 不要生硬地报告"发现偏差": 

> 我注意到项目新增了 React 组件目录 `src/components/`, 需要更新目录结构和 Packs 吗？

---

## 更新流程

### Step 1: 主动检测过时信号

读取当前 `.agent-local.md`, 对比项目实际状态: 

- **Tech Stack 版本**: 是否有新语言/框架引入
- **目录结构**: 是否与实际文件系统匹配
- **Packs 列表**: 是否与实际使用的语言对应
- **Build & Test Commands**: 是否与实际构建方式一致

### Step 2: 向用户报告 + 询问变更点

将检测结果和用户的变更需求合并, 确认本次需要修改哪些 Section / Sub-section。

### Step 3: 聚焦讨论

仅讨论涉及变更的部分。**不要**重新遍历所有 Section。

---

## 操作粒度

最小操作单元为 `###` 级别（而非仅 `##`）。

例如: 
- 可以仅更新目录树（`## Project Structure` 下的 fenced code block）, 而不触碰 `### Source-Test Mapping`
- 可以仅更新某个 `## Core Architectural Invariants` 的条目, 不影响其他条目

### 自定义内容保护

如果用户在 `.agent-local.md` 中手动添加了超出模板 schema 的自定义内容（额外的 `##`/`###` Section）, Agent 识别后**原样保留**, 不删除也不移动。

---

## 写入流程

### Step 4: 备份

将当前 `.agent-local.md` 备份为 `.agent-local.md.bak`。

### Step 5: 生成临时文件

将修改后的完整内容写入 `.agent-local.md.tmp`。

对变更的内容应用证据标注: 
- 用户明确给出 → 无标注
- Agent 推断且用户已确认 → `<!-- [推断] 推断依据 -->`
- Agent 推断但用户未确认 → `<!-- [待确认] 推断依据 -->`

### Step 6: 格式校验门控

对 `.agent-local.md.tmp` 执行与 init-guide 相同的全部校验（参见 [init-guide.md](init-guide.md) Step 5）。

校验失败时：
- 仅允许自动修复**机械性问题**（最多 2 次）：修复未闭合的 HTML 注释、调整 fenced code block 语言标签、移除残留 `[TODO: ...]` 占位符
- **不得**通过自动修复重写用户内容或变更语义
- 2 次机械修复后仍失败 → 向用户报告具体校验项和失败原因，中止流程

### Step 7: 原子替换

校验通过后, 将 `.agent-local.md.tmp` 重命名为 `.agent-local.md`。

---

## Diff 展示

替换完成后, 为每个改动的 Section 独立展示 diff: 

````markdown
**## Project Overview** 🔄 已修改

```diff
- **Tech Stack**: Python 3.10+
+ **Tech Stack**: Python 3.10+, TypeScript 5.x
- **Packs**: python, markdown, shell, git
+ **Packs**: python, markdown, shell, git, swift
```

**## Build & Test Commands** — 未变
**## Core Architectural Invariants** — 未变
````

未变的 Section 用单行 "— 未变" 标记, 不展开。

---

## Section 级回滚

在 diff 展示后, 用户可以逐 Section 选择接受或还原: 

- 用户说"恢复 Performance Targets 到上一版" → 从 `.agent-local.md.bak` 中提取该 Section 替换回去
- 用户确认所有 Section → 更新完成

提示用户可以这样操作: 

> 如果对某个 Section 的修改不满意, 可以说"恢复 [Section 名] 到上一版", 我会从备份中还原。

---

## 输出摘要

### 变更摘要

列出本次修改的 Section 和修改类型（新增/修改/删除条目）。

### 未确认项清单

同 init-guide Step 7b。未确认项全部解决前不提示执行 `agent-sync`。

### Overlay 路径深度校验

同 init-guide Step 7c。

### 跨工具消费说明

```
📋 更新完成。请执行 `agent-sync .` 重新生成规则文件。
```

### 指标记录

如果项目中存在 `temp/` 目录, 追加一行到 `temp/overlay-metrics.log`: 

```
[ISO-8601-timestamp] mode=update sections_changed=<修改Section数> manual_edits_after=<上次更新后手工改动行数> bak_restored=<是否使用了回滚>
```

---

## 关键约束

- 所有格式约束与 init-guide 相同（Packs 格式、Section 标题一致性、HTML 注释闭合等）
- 更新时不要重写未涉及的 Section, 最小化变更范围
- `.bak` 文件在用户确认全部 Section 后可保留（供后续手动回滚参考）
