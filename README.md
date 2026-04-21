# AI Agent Rule System / AI 代理规则系统

A modular, cross-tool rule system for AI coding agents (Cursor, OpenAI Codex, Claude Code).

一套模块化、跨工具的 AI 编程代理规则系统，适用于 Cursor、OpenAI Codex 和 Claude Code。

---

## 1. Overview / 概述

This rule system replaces a single monolithic AGENTS file with a **3-layer architecture**:

本系统将单一的巨型 AGENTS 文件重构为 **3 层架构**：

| Layer / 层级 | Content / 内容 | Loading / 加载方式 | Budget / 规模 |
|---|---|---|---|
| **Core** (core/) | Workflow, communication, quality gates / 工作流、沟通规范、质量门槛 | Always loaded / 始终加载 | ~250 lines |
| **Language Packs** (packs/) | Python, C++, CUDA, Rust, PyBind11, Shell, Swift, Markdown, Git | By file type / 按文件类型 | ~150 lines each |
| **Project Overlay** (.agent-local.md) | Project structure, build cmds, boundaries / 项目结构、构建命令、边界 | Per project / 按项目 | ~100-200 lines |

**Why this structure? / 为什么这样设计？**

- Avoid wasting tokens on irrelevant rules (e.g., CUDA rules when editing Python) / 避免加载无关规则浪费 token
- Prevent cross-language contamination (e.g., C++ naming conventions leaking into Python) / 防止跨语言规范污染
- Keep each file focused with high instruction density / 每个文件专注且指令密度高
- Stay within Codex's 32KiB limit / 确保不超过 Codex 的 32KiB 限制

---

## 2. Directory Structure / 目录结构

```
agent-rules/                     ← This repo / 本仓库 (deployed to ~/.config/agent-rules/)
├── core/                        ← Always loaded / 始终加载
│   ├── 00-communication.md      # Output format, language, citations / 输出格式、语言、引用规范
│   ├── 10-workflow.md           # 3-stage workflow + fast track / 三阶段工作流 + 快速通道
│   └── 20-quality-gates.md      # Review checklist, doc standards / 审查清单、文档标准
│
├── packs/                       ← Loaded by file type / 按文件类型加载
│   ├── python.md                # Python 3.10+ rules / Python 规范
│   ├── cpp.md                   # C++17 rules / C++ 规范
│   ├── cuda.md                  # CUDA kernel rules / CUDA 规范
│   ├── rust.md                  # Rust 2021 rules / Rust 规范
│   ├── pybind11.md              # PyBind11 bindings / PyBind11 绑定规范
│   ├── shell.md                 # Bash/Zsh scripting / Shell 脚本规范
│   ├── swift.md                 # Swift 5.9+ rules / Swift 规范
│   ├── markdown.md              # Markdown writing / Markdown 写作规范
│   └── git.md                   # Git commit conventions + README sync / Git 提交规范 + README 同步检查
│
├── templates/
│   ├── overlay-template.md      # Template for .agent-local.md / 项目特定规则模板（含中文引导注释）
│   ├── worktrees.json           # Worktree setup script for parallel agents / 并发 Agent worktree 初始化脚本
│   └── cursor-frontmatter/      # YAML frontmatter for .mdc / Cursor 前置元数据
│       ├── communication.yaml   # alwaysApply: true
│       ├── workflow.yaml        # alwaysApply: true
│       ├── quality-gates.yaml   # alwaysApply: true
│       ├── python.yaml          # globs: "**/*.py"
│       ├── cpp.yaml             # globs: "**/*.{cpp,h,hpp,cc}"
│       ├── cuda.yaml            # globs: "**/*.{cu,cuh,h,hpp}"
│       ├── pybind11.yaml        # description-based (AI decides relevance)
│       ├── shell.yaml           # globs: "**/*.{sh,bash,zsh}"
│       ├── swift.yaml           # globs: "**/*.swift"
│       ├── markdown.yaml        # globs: "**/*.md"
│       └── git.yaml             # description-based (commit + README sync context)
│
├── temp/                        ← Ephemeral verification artifacts / 临时验证产物
│   └── README.md
│
├── issue_history/               ← Issue lifecycle records / Issue 全生命周期记录
│   ├── HISTORY.md               # Canonical issue records / Issue 历史主记录
│   └── README.md
│
├── skills/                      ← Agent skills / Agent 技能（部署到 .cursor/skills/）
│   ├── project-overlay/         # Guided .agent-local.md creation / 引导式项目配置生成
│   └── agent-memory/            # Cross-session context dump/resume / 跨 session 上下文保存与恢复
│
├── commands/                    ← Cursor slash-commands / Cursor 斜杠命令
│   ├── pre-commit.md            # /pre-commit — draft git commit command / 草拟 git commit 命令
│   └── review.md                # /review — strict third-party code review / 严格第三方代码评审
│
├── extras/                      ← Domain-specific submodule bundles / 领域扩展 submodule 挂载点
│   └── agent-toolkit/           # git submodule — optional skills & commands / 可选技能与命令扩展
│
├── scripts/
│   ├── agent-sync.sh            # Sync rules to project / 同步规则到项目
│   ├── agent-check.sh           # Validate generated files / 验证生成文件
│   └── async-agent-rules.sh     # Pull latest rules with unlock/relock flow / 拉取最新规则（解锁-重锁流程）
│
├── LICENSE
└── README.md                    # This file / 本文件
```

---

## 3. Quick Start / 快速开始

### First-Time Setup / 首次设置

The rule system is deployed as a single git clone per machine. All source files are read-only — modifications should only be made via git commits in the repo, then pulled.

每台机器上只需要一个 git clone。所有源文件只读 — 修改规则应该在仓库中 commit，然后 pull 更新。

```bash
# 1. Clone the rules repo (one-time, per machine)
#    克隆规则仓库（每台机器一次）
git clone https://github.com/georgeokelly/agent-rules.git ~/.config/agent-rules

# 2. Make source files read-only (prevent accidental edits)
#    将源文件设为只读（防止意外修改）
chmod -R a-w ~/.config/agent-rules/{core,packs,templates}

# 3. Add shell aliases
#    添加 shell 别名
echo 'alias agent-sync="~/.config/agent-rules/scripts/agent-sync.sh"' >> ~/.zshrc
echo 'alias agent-check="~/.config/agent-rules/scripts/agent-check.sh"' >> ~/.zshrc
source ~/.zshrc
```

To update rules on this machine / 在本机更新规则:

```bash
chmod -R u+w ~/.config/agent-rules/{core,packs,templates}  # temporarily unlock
cd ~/.config/agent-rules && git pull
chmod -R a-w ~/.config/agent-rules/{core,packs,templates}   # re-lock
```

### Per-Project Setup / 项目设置

```bash
# 1. Go to your project
#    进入项目目录
cd /path/to/workspace/my-project

# 2. Create project-specific rules (choose one method)
#    创建项目特定规则（二选一）

# Method A: Manual — copy template and edit by hand
# 方式 A：手动 — 复制模板后手工编辑
cp ~/.config/agent-rules/templates/overlay-template.md .agent-local.md
# Edit .agent-local.md — fill in project structure, build commands, etc.
# 编辑 .agent-local.md — 填写项目结构、构建命令等

# Method B: AI-guided — let the agent interview you and generate the file
# 方式 B：AI 引导 — 让 Agent 通过对话收集信息并自动生成
# In Cursor chat, say: "帮我创建项目配置" or "run project-overlay skill"
# Agent will read the project-overlay skill, ask you about your project,
# and generate .agent-local.md automatically.
# 在 Cursor 对话中说"帮我创建项目配置"或"run project-overlay skill"，
# Agent 会通过对话了解你的项目，然后自动生成 .agent-local.md。
# Prerequisite: run `agent-sync .` first so the skill is deployed to .cursor/skills/
# 前提：先运行一次 `agent-sync .` 将 skill 部署到 .cursor/skills/

# 3. Sync rules (generates .cursor/rules/*.mdc, .agent-rules/CLAUDE.md, .agent-rules/AGENTS.md)
#    同步规则（生成各工具的配置文件）
agent-sync .

# 4. Validate
#    验证
agent-check .

# 5. Add generated files to .gitignore
#    将生成文件加入 .gitignore
echo -e '\n# AI agent rules (generated)\n.agent-rules/\n.cursor/rules/\n.agent-sync-hash\n.agent-sync-manifest' >> .gitignore

# 6. Commit .agent-local.md (project-specific rules belong in git)
#    提交 .agent-local.md（项目特定规则应进入 git）
git add .agent-local.md .gitignore
```

### Daily Usage / 日常使用

```bash
cd ~/workspace/my-project
agent-sync .    # Check + sync if needed (usually instant) / 检查 + 按需同步（通常瞬间完成）
cursor .        # Cursor reads .cursor/rules/*.mdc natively / Cursor 原生读取 .mdc
codex-run       # Codex via wrapper (see below) / 通过 wrapper 启动 Codex（见下文）
claude-run      # Claude Code via wrapper (see below) / 通过 wrapper 启动 Claude Code（见下文）
```

`agent-sync` supports subcommands for fine-grained control / `agent-sync` 支持子命令进行精细控制：

```bash
agent-sync .              # Full sync (default): Cursor + Claude + Codex / 全量同步（默认）
agent-sync codex .        # Only regenerate AGENTS.md / 仅重新生成 AGENTS.md
agent-sync claude .       # Only regenerate CLAUDE.md / 仅重新生成 CLAUDE.md
agent-sync skills .       # Only sync skills to .cursor/skills/ / 仅同步 skills
agent-sync commands .     # Only sync commands to .cursor/commands/ / 仅同步 commands
agent-sync clean .        # Remove all generated files / 清理所有生成文件
```

Or combine into one command / 或合并为一条命令:

```bash
# Add to ~/.zshrc:
cursor-go() { agent-sync "${1:-.}" && cursor "${1:-.}"; }
```

---

## 4. Tool-Specific Deployment / 各工具部署说明

### Cursor

`agent-sync` generates `.cursor/rules/*.mdc` files with YAML frontmatter. Cursor reads these automatically:

`agent-sync` 会生成带有 YAML 前置元数据的 `.cursor/rules/*.mdc` 文件。Cursor 自动读取：

- `alwaysApply: true` — loaded in ALL modes (Agent, Ask, Chat) / 在所有模式下加载
- `globs: "**/*.py"` — loaded only when editing matching files / 仅在编辑匹配文件时加载
- `description: "..."` — Cursor uses AI to decide relevance / Cursor 用 AI 判断相关性

**Known Pitfalls / 已知坑点:**

1. **Missing closing `---`**: If YAML frontmatter is not properly closed, the rule **silently fails** — no error, no warning. `agent-check` validates this. / 如果 YAML 前置元数据没有正确闭合 `---`，规则会**静默失效**。`agent-check` 会检查这一点。
2. **`.cursorrules` conflict**: If both `.cursorrules` and `.cursor/rules/*.mdc` exist, `.mdc` may silently override. Use only `.mdc`. / 如果同时存在 `.cursorrules` 和 `.mdc`，`.mdc` 可能静默覆盖。只使用 `.mdc`。
3. **Injection vs Activation**: `alwaysApply: true` guarantees injection into context, but does not guarantee the model will follow every instruction. This is a fundamental limitation of prompt-based rules. / `alwaysApply: true` 保证注入上下文，但不保证模型一定遵循每条指令。这是基于 prompt 的规则的根本局限。
4. **Duplicate context from CLAUDE.md/AGENTS.md**: Cursor auto-injects root-level `AGENTS.md`/`CLAUDE.md` into system prompt (as `always_applied_workspace_rules`), duplicating `.mdc` rules. This is **not preventable via `.cursorignore`**. `agent-sync` avoids this by outputting to `.agent-rules/` instead of the project root, and cleans up any root-level remnants. / Cursor 会自动将根目录的 `AGENTS.md`/`CLAUDE.md` 注入 system prompt，导致规则重复。这**无法通过 `.cursorignore` 阻止**。`agent-sync` 通过输出到 `.agent-rules/` 目录来规避，并会清理根目录下的残留文件。

### OpenAI Codex

`agent-sync` generates `.agent-rules/AGENTS.md` (not at project root, to avoid Cursor duplicate injection). Codex requires `AGENTS.md` at the project root, so a shell wrapper temporarily symlinks it during execution.

`agent-sync` 生成 `.agent-rules/AGENTS.md`（不在项目根目录，以避免 Cursor 重复注入）。Codex 要求 `AGENTS.md` 在项目根目录，因此需要通过 shell wrapper 在执行期间临时软链接。

**Critical: 32KiB Limit / 关键：32KiB 限制**

Codex has a `project_doc_max_bytes` default of **32,768 bytes**. Content beyond this limit is **silently truncated** — you get no error or warning. `agent-check` validates file size.

Codex 的 `project_doc_max_bytes` 默认为 **32,768 字节**。超出此限制的内容会被**静默截断** — 没有任何错误或警告。`agent-check` 会检查文件大小。

Codex also supports subdirectory `AGENTS.md` files for layered rules. If your project structure is large, consider splitting packs into subdirectories.

Codex 也支持子目录的 `AGENTS.md` 文件来分层加载规则。如果项目结构很大，可以考虑将 packs 拆分到子目录。

### Claude Code

`agent-sync` generates `.agent-rules/CLAUDE.md` (not at project root, to avoid Cursor duplicate injection). Claude Code requires `CLAUDE.md` at the project root, so a shell wrapper temporarily symlinks it during execution. This preserves Claude Code's native multi-level `CLAUDE.md` discovery (subdirectory lazy-loading).

`agent-sync` 生成 `.agent-rules/CLAUDE.md`（不在项目根目录，以避免 Cursor 重复注入）。Claude Code 要求 `CLAUDE.md` 在项目根目录，因此需要通过 shell wrapper 在执行期间临时软链接。这保留了 Claude Code 原生的多层 `CLAUDE.md` 发现机制（子目录懒加载）。

**How Claude Code loads rules / Claude Code 的规则加载方式：**

- Root `CLAUDE.md`: loaded automatically at startup (via symlink from wrapper) / 启动时自动加载（通过 wrapper 软链接）
- Subdirectory `CLAUDE.md`: loaded when Claude works in that directory / 在该目录工作时按需加载
- `~/.claude/CLAUDE.md`: personal global rules (apply to all projects) / 个人全局规则（适用于所有项目）
- `CLAUDE.local.md`: auto-gitignored, for private project preferences / 自动加入 .gitignore，用于私有项目偏好

**Tip / 提示**: Put your language preference (e.g., "Always respond in Chinese") in `~/.claude/CLAUDE.md` so it applies everywhere. / 把语言偏好（如"始终用中文回复"）放在 `~/.claude/CLAUDE.md` 中，这样所有项目都会生效。

### Shell Wrapper for Codex / Claude Code

Since `agent-sync` outputs to `.agent-rules/` instead of the project root, Codex and Claude Code need a wrapper that temporarily symlinks the rules file during execution. Add the following to `~/.zshrc` (or `~/.bashrc`):

由于 `agent-sync` 将规则输出到 `.agent-rules/` 而非项目根目录，Codex 和 Claude Code 需要一个 wrapper 在执行期间临时软链接规则文件。将以下内容添加到 `~/.zshrc`（或 `~/.bashrc`）：

```bash
# Temporary wrapper — remove when Codex/Claude Code support custom rule paths natively
# 临时 wrapper — 待 Codex/Claude Code 原生支持自定义路径后移除

_agent_with_rules() {
    local agent_cmd="$1"
    local rules_file="$2"
    shift 2

    # Walk up from $PWD to find .agent-rules/ (no git dependency)
    local dir="$PWD" project_root=""
    while [[ "${dir}" != "/" ]]; do
        if [[ -d "${dir}/.agent-rules" ]]; then
            project_root="${dir}"
            break
        fi
        dir="$(dirname "${dir}")"
    done

    if [[ -n "${project_root}" && -f "${project_root}/.agent-rules/${rules_file}" ]]; then
        ln -sf ".agent-rules/${rules_file}" "${project_root}/${rules_file}"
        trap "rm -f '${project_root}/${rules_file}'" EXIT INT TERM
    fi

    "${agent_cmd}" "$@"
}

codex-run() { _agent_with_rules codex AGENTS.md "$@"; }
claude-run() { _agent_with_rules claude CLAUDE.md "$@"; }
```

**Exit criteria / 退出条件**: Remove the wrapper when any of these are met / 当以下任一条件满足时可移除 wrapper：

- Codex supports `--agents` or equivalent custom path flag ([#10067](https://github.com/openai/codex/issues/10067))
- Claude Code supports config-level custom `CLAUDE.md` path without bypassing multi-level discovery
- Cursor supports disabling auto-injection of `AGENTS.md`/`CLAUDE.md` via settings or `.cursorignore`

---

## 5. Validation Checklist / 验证清单

Run `agent-check .` in your project directory. It checks:

在项目目录中运行 `agent-check .`，它会检查：

| Check / 检查项 | What it validates / 验证内容 |
|---|---|
| Codex size | `.agent-rules/AGENTS.md` < 32KiB (silent truncation risk) / 是否低于 32KiB |
| Cursor frontmatter | Every `.mdc` has opening and closing `---` / 每个 `.mdc` 的 YAML 是否闭合 |
| No dual-write | `.cursorrules` and `.mdc` don't coexist / 没有同时存在 `.cursorrules` 和 `.mdc` |
| Staleness | Generated files match rules repo version / 生成文件是否与规则仓库版本一致 |
| File existence | All expected files present in `.agent-rules/` / `.agent-rules/` 中预期文件是否存在 |
| Root remnants | No `CLAUDE.md`/`AGENTS.md` at project root / 根目录无残留文件 |
| Core semantics | Core `.mdc` files have `alwaysApply: true` / Core 文件必须始终加载 |
| Skills deployment | `.cursor/skills/` matches manifest from rules repo / skills 已部署且与 manifest 一致 |
| Commands deployment | `.cursor/commands/` matches manifest from rules repo / commands 已部署且与 manifest 一致 |
| Worktrees deployment | `.cursor/worktrees.json` exists and is valid JSON; if agent-sync managed, matches template / worktrees.json 已部署且 JSON 有效 |
| Settings validity | `.vscode/settings.json` is valid JSON (if present) / 配置文件 JSON 有效性 |

---

## 6. Evaluation Criteria / 评价标准

Use these 5 criteria to judge if the rule system is working effectively:

用以下 5 个标准来评判规则系统是否有效运作：

1. **Executability / 可执行性**: Agent can immediately determine "what to do next, where to edit, how to verify" / Agent 能立即判断"下一步做什么、去哪改、怎么验收"
2. **Consistency / 一致性**: Same task produces similar behavior across Cursor, Codex, and Claude Code / 同一任务在三个工具中产出一致的行为
3. **Instruction Density / 指令密度**: High ratio of actionable constraints per 1k tokens (not tutorials) / 每 1k token 中可执行约束的占比高（而不是教程）
4. **Maintainability / 可维护性**: Updating one rule auto-propagates to all tools; no "ghost rules" / 更新一条规则后自动传播到所有工具，不会出现"幽灵规则"
5. **Verifiability / 可验证性**: Can check if rules loaded, not truncated, not conflicting / 能验证规则是否加载、未被截断、没有冲突

---

## 7. Regression Testing / 回归测试

After modifying rules, test with these fixed tasks across all 3 tools:

修改规则后，用以下固定任务在 3 个工具上测试：

1. **Python**: "Add a `normalize_tensor` function to `core.py` with type hints and a pytest test" / 添加一个带类型标注的函数和测试
2. **C++**: "Add a new `Reshape` method to `ComputeEngine` with Google Test" / 为类添加新方法和 Google Test
3. **CUDA**: "Add a new elementwise kernel with CUDA_CHECK and stream support" / 添加一个带错误检查和 stream 的新 kernel
4. **PyBind11**: "Expose the new Reshape method to Python" / 将新方法暴露给 Python
5. **Shell**: "Write a deployment script with argument parsing, error handling, and cleanup trap" / 编写一个带参数解析、错误处理和 cleanup 的部署脚本
6. **Swift**: "Add a `NetworkClient` struct with async/await fetch, error handling, and a Swift Testing test" / 添加一个带 async/await、错误处理和 Swift Testing 测试的网络客户端
7. **Bug fix**: "The batch processing crashes on empty input — find and fix" / 修复一个空输入的崩溃
8. **Refactor**: "Extract the memory management code into a separate utility class" / 将内存管理代码提取为独立工具类
9. **Ask mode**: "How does the MatMul kernel handle non-square matrices?" (expect citations) / 问答模式：解释 kernel 如何处理非方阵（期望有引用）
10. **Small fix**: "Fix the typo in the docstring of train_model" (expect Fast Track) / 修复一个 typo（期望使用快速通道）

**Pass criteria / 通过标准**: All 3 tools produce structurally similar output, follow the correct workflow stage, and respect MUST-level rules.

所有 3 个工具产出结构相似的输出，遵循正确的工作流阶段，并遵守 MUST 级别规则。

---

## 8. Size Budget / 规模预算

| Component / 组件 | Target / 目标 | Hard Limit / 硬限制 |
|---|---|---|
| Global Core (all 3 files) | ~250 lines | — |
| Each Language Pack | ~100-150 lines | — |
| Project Overlay | ~100-200 lines | — |
| Assembled AGENTS.md | — | **32,768 bytes** (Codex) |
| Assembled CLAUDE.md | — | No hard limit (but shorter is better) |

---

## 9. Maintenance / 维护指南

### When to re-run `agent-sync` / 何时重新同步

| Trigger / 触发条件 | Action / 操作 |
|---|---|
| Modified any file in `~/.config/agent-rules/` / 修改了规则仓库中的任何文件 | `agent-sync .` in each project / 在每个项目中运行 |
| Modified `.agent-local.md` (root or sub-repo) / 修改了项目 overlay | `agent-sync .` (auto-detected / 自动检测) |
| First time setting up a project / 首次设置项目 | `agent-sync .` |
| Deleted a sub-repo `.agent-local.md` / 删除了子目录 overlay | `agent-sync .` (auto-cleans ghost rules / 自动清理残留规则) |
| Generated files accidentally deleted / 生成文件被意外删除 | `agent-sync .` |
| Need to regenerate only one tool / 只需重新生成某个工具的文件 | `agent-sync codex .` or `agent-sync claude .` |
| Want to remove all generated files / 需要清除所有生成文件 | `agent-sync clean .` |
| Nothing changed / 没有变化 | Script auto-detects and skips / 脚本自动检测并跳过 |

### How to update rules / 如何更新规则

1. Edit the source file in `~/.config/agent-rules/` (e.g., `packs/python.md`) / 编辑规则仓库中的源文件
2. (If git) Commit the change / 提交变更
3. Run `agent-sync .` in each active project / 在每个活跃项目中运行同步
4. Run `agent-check .` to validate / 运行检查脚本验证
5. (Optional) Run a regression test task to verify behavior / （可选）运行回归测试任务验证行为

### Managing extras/ submodules / 管理扩展 submodule

`extras/` contains optional, domain-specific skill/command bundles mounted as git submodules.
`agent-sync` automatically initializes and deploys them — no extra steps needed after initial setup.
If submodule initialization fails (e.g., network issues, missing SSH keys), a warning is printed and extras are skipped.

`extras/` 下存放按需挂载的领域专用扩展，以 git submodule 形式管理。`agent-sync` 会自动初始化并部署。若子模块初始化失败（如网络问题、SSH 密钥缺失），会输出警告并跳过 extras。

**Priority / 优先级**: Core skills and commands (`skills/`, `commands/`) always take priority over extras. If an extras bundle contains a skill or command with the same name as a core one, the extras version is skipped and a warning is printed. To use both, create a renamed symlink in the extras bundle.

**优先级**：核心 skills 和 commands（`skills/`、`commands/`）始终优先于 extras。若 extras 中存在与核心同名的 skill 或 command，extras 版本会被跳过并输出提示。如需同时使用，在 extras bundle 中创建重命名的软链接。

```bash
# Add a new bundle / 添加新扩展包
git submodule add git@github.com:georgeokelly/agent-toolkit.git extras/agent-toolkit
git commit -m "Add agent-toolkit as domain-specific skill/command bundle"

# Upgrade a bundle to latest / 升级某个扩展包
git -C extras/agent-toolkit pull origin main
git add extras/agent-toolkit
git commit -m "Update agent-toolkit submodule to latest"

# Remove a bundle / 移除某个扩展包
git submodule deinit extras/agent-toolkit
git rm extras/agent-toolkit
git commit -m "Remove agent-toolkit submodule"
```

On a new machine, clone with submodules / 新机器克隆时带上 submodule：

```bash
git clone --recurse-submodules https://github.com/georgeokelly/agent-rules.git ~/.config/agent-rules
# or, if already cloned / 或已克隆后初始化：
git submodule update --init --recursive
```

---

## 10. FAQ / 常见问题

**Q: Do rules apply in Cursor's Ask/Chat mode? / 规则在 Cursor 的 Ask/Chat 模式下生效吗？**

Yes. Rules with `alwaysApply: true` (like `00-communication.md`) apply in ALL modes. Rules with `globs` apply when the relevant file is in context.

是的。`alwaysApply: true` 的规则（如 `00-communication.md`）在所有模式下生效。`globs` 规则在相关文件在上下文中时生效。

**Q: My Cursor rules don't seem to work. / Cursor 规则似乎不生效。**

Run `agent-check .` first. Most common cause: unclosed `---` in frontmatter. Also check for `.cursorrules` file conflicts.

先运行 `agent-check .`。最常见原因：frontmatter 中 `---` 未闭合。也要检查是否有 `.cursorrules` 文件冲突。

**Q: Can I customize rules per tool? / 可以按工具自定义规则吗？**

The core rules and language packs are shared across tools. Tool-specific behavior differences are handled in `10-workflow.md` via the Tool Adaptation Matrix. If you need completely different rules per tool, modify `agent-sync.sh` to generate different content.

核心规则和语言包在所有工具间共享。工具特定的行为差异在 `10-workflow.md` 的"工具适配矩阵"中处理。如果需要完全不同的规则，修改 `agent-sync.sh` 生成不同内容。

**Q: Should `.agent-local.md` be committed to git? / `.agent-local.md` 应该提交到 git 吗？**

Yes. It contains project-specific rules that the whole team (and all AI tools) should follow. For personal preferences (local paths, API keys), Claude Code users can use `CLAUDE.local.md` (auto-gitignored).

是的。它包含整个团队（和所有 AI 工具）都应遵循的项目特定规则。个人偏好（本地路径、API 密钥）可以放在 Claude Code 的 `CLAUDE.local.md`（自动加入 .gitignore）中。

**Q: What if AGENTS.md exceeds 32KiB? / AGENTS.md 超过 32KiB 怎么办？**

Split language packs into subdirectory `AGENTS.md` files (e.g., `python/AGENTS.md`). Codex merges them hierarchically. Or reduce rule content — review for tutorial-style code that can be moved to `docs/examples/`.

将语言包拆分为子目录的 `AGENTS.md` 文件（如 `python/AGENTS.md`）。Codex 会层级合并。或者精简规则内容 — 检查是否有教程式代码可以移到 `docs/examples/`。

**Q: Do HTML comments in `.agent-local.md` waste agent tokens? / `.agent-local.md` 中的 HTML 注释会浪费 token 吗？**

No. `agent-sync` automatically strips all `<!-- ... -->` comments during compilation. You can keep detailed Chinese annotations in `.agent-local.md` for your own reference — they will not appear in the generated `CLAUDE.md`, `AGENTS.md`, or `.mdc` files.

不会。`agent-sync` 在编译时会自动去除所有 `<!-- ... -->` 注释。你可以在 `.agent-local.md` 中保留详细的中文引导注释供自己参考 — 它们不会出现在生成的文件中。

**Q: How to use with a multi-repo workspace? / 多 repo 的 workspace 怎么用？**

Place `.agent-local.md` at the workspace root (shared rules) and in each sub-repo (repo-specific rules). `agent-sync` recursively finds all `.agent-local.md` files and generates sub-repo CLAUDE.md + AGENTS.md with overlay-only content (no duplicate core/packs). For Cursor, it also generates a globs-scoped `.mdc` in `.cursor/rules/` (e.g. `extras-agent-toolkit-overlay.mdc` with `globs: extras/agent-toolkit/**`), so Cursor loads the overlay only when editing files under that sub-repo — avoiding token cost for unrelated contexts. Cursor only reads workspace-root `.cursor/rules/`. If you delete a sub-repo overlay, `agent-sync` automatically cleans up the generated files (including the sub-repo .mdc).

在 workspace 根目录放 `.agent-local.md`（共享规则），每个子 repo 也放一个（repo 特有规则）。`agent-sync` 会递归查找所有 `.agent-local.md`，在子目录生成只包含 overlay 内容的 CLAUDE.md + AGENTS.md（不重复 core/packs）。对 Cursor 还会在 `.cursor/rules/` 生成 globs 作用域的 `.mdc`（如 `extras-agent-toolkit-overlay.mdc`，`globs: extras/agent-toolkit/**`），仅在编辑该子 repo 内文件时加载，避免无关上下文的 token 消耗。Cursor 只读 workspace 根目录的 `.cursor/rules/`。如果删除了某个子 repo 的 overlay，`agent-sync` 会自动清理其生成文件（含子 repo 的 .mdc）。

---

## 9. Roadmap

Detailed design docs and review history are tracked in `issue_history/`.

详细设计文档和 review 记录在 `issue_history/` 目录中。

| Priority / 优先级 | Item / 事项 | Reference / 参考 |
|--------|------|-----------|
| P3 | Phase C pilot — test C++/CUDA extension branch / Phase C 试点 — 测试 C++/CUDA 扩展分支 | `fea-002` Roadmap |
| Future | Cross-session conversation persistence for overlay generation / 对话持久化与跨会话恢复 | `fea-002` Roadmap |
