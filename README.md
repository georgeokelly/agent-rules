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
agent-toolkit/                   ← This repo / 本仓库 (deployed to ~/.config/agent-toolkit/)
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
│   ├── cursor-frontmatter/      # YAML frontmatter for .mdc / Cursor 前置元数据
│   │   ├── communication.yaml   # alwaysApply: true
│   │   ├── workflow.yaml        # alwaysApply: true
│   │   ├── quality-gates.yaml   # alwaysApply: true
│   │   ├── python.yaml          # globs: "**/*.py"
│   │   ├── cpp.yaml             # globs: "**/*.{cpp,h,hpp,cc}"
│   │   ├── cuda.yaml            # globs: "**/*.{cu,cuh,h,hpp}"
│   │   ├── rust.yaml            # globs: "**/*.rs"
│   │   ├── pybind11.yaml        # description-based (AI decides relevance)
│   │   ├── shell.yaml           # globs: "**/*.{sh,bash,zsh}"
│   │   ├── swift.yaml           # globs: "**/*.swift"
│   │   ├── markdown.yaml        # globs: "**/*.md"
│   │   └── git.yaml             # description-based (commit + README sync context)
│   └── cc-frontmatter/          # YAML frontmatter for CC .claude/rules/ / CC 前置元数据
│       ├── python.yaml          # globs: "**/*.py"
│       ├── cpp.yaml             # globs: "**/*.cpp,**/*.h,**/*.hpp,**/*.cc"
│       ├── cuda.yaml            # globs: "**/*.cu,**/*.cuh,**/*.h,**/*.hpp"
│       ├── rust.yaml            # globs: "**/*.rs,**/Cargo.toml"
│       ├── shell.yaml           # globs: "**/*.sh,**/*.bash,**/*.zsh"
│       ├── swift.yaml           # globs: "**/*.swift"
│       └── markdown.yaml        # globs: "**/*.md"
│
├── temp/                        ← Ephemeral verification artifacts / 临时验证产物
│   └── README.md
│
├── issue_history/               ← Issue lifecycle records / Issue 全生命周期记录
│   ├── HISTORY.md               # Canonical issue records / Issue 历史主记录
│   └── README.md
│
├── skills/                      ← Agent skills / Agent 技能（部署到 .cursor/skills/ + .claude/skills/ + .agents/skills/）
│   ├── agent-memory/            # Cross-session context dump/resume / 跨 session 上下文保存与恢复
│   ├── pre-commit/              # Draft git commit command (cross-tool) / 草拟 git commit 命令（跨工具）
│   ├── project-overlay/         # Guided .agent-local.md creation / 引导式项目配置生成
│   └── simple-review/           # Lightweight third-party review (cross-tool) / 轻量第三方评审（跨工具）
│
├── extras/                      ← Domain-specific submodule bundles / 领域扩展 submodule 挂载点
│   └── agent-extension/         # git submodule — optional skills / 可选技能扩展
│
├── scripts/
│   ├── agent-sync.sh            # Sync rules to project / 同步规则到项目
│   ├── agent-check.sh           # Validate generated files / 验证生成文件
│   ├── agent-test.sh            # E2E tests for sync/check pipeline / 端到端测试
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
git clone https://github.com/georgeokelly/agent-toolkit.git ~/.config/agent-toolkit

# 2. Make source files read-only (prevent accidental edits)
#    将源文件设为只读（防止意外修改）
chmod -R a-w ~/.config/agent-toolkit/{core,packs,templates}

# 3. Add shell aliases
#    添加 shell 别名
echo 'alias agent-sync="~/.config/agent-toolkit/scripts/agent-sync.sh"' >> ~/.zshrc
echo 'alias agent-check="~/.config/agent-toolkit/scripts/agent-check.sh"' >> ~/.zshrc
source ~/.zshrc
```

To update rules on this machine / 在本机更新规则:

```bash
chmod -R u+w ~/.config/agent-toolkit/{core,packs,templates}  # temporarily unlock
cd ~/.config/agent-toolkit && git pull
chmod -R a-w ~/.config/agent-toolkit/{core,packs,templates}   # re-lock
```

### Environment Variables / 环境变量

Scripts resolve the central repo path via `AGENT_TOOLKIT_HOME`. If unset, they fall back to `~/.config/agent-toolkit`.

脚本通过 `AGENT_TOOLKIT_HOME` 解析中央仓库路径。未设置时回退到 `~/.config/agent-toolkit`。

| Variable / 变量 | Default / 默认值 | Purpose / 用途 |
|---|---|---|
| `AGENT_TOOLKIT_HOME` | `~/.config/agent-toolkit` | Path to the central rules repo used by `agent-sync` and `agent-check` / 中央规则仓库路径,被 `agent-sync` 和 `agent-check` 读取 |

Override example / 自定义路径示例:

```bash
# If you cloned the repo to a non-default location
# 若克隆到非默认路径
export AGENT_TOOLKIT_HOME="$HOME/code/agent-toolkit"
```

**Migration from `AGENT_RULES_HOME` / 从旧变量迁移**: this repo was renamed from `agent-rules` to `agent-toolkit`; the environment variable changed accordingly. If your shell rc still exports `AGENT_RULES_HOME`, replace it with `AGENT_TOOLKIT_HOME` — the old name is no longer read.

本仓库由 `agent-rules` 重命名为 `agent-toolkit`,环境变量随之更改。若 shell rc 仍 export `AGENT_RULES_HOME`,请替换为 `AGENT_TOOLKIT_HOME`——旧变量名不再被识别。

### Per-Project Setup / 项目设置

```bash
# 1. Go to your project
#    进入项目目录
cd /path/to/workspace/my-project

# 2. Create project-specific rules (choose one method)
#    创建项目特定规则（二选一）

# Method A: Manual — copy template and edit by hand
# 方式 A：手动 — 复制模板后手工编辑
cp ~/.config/agent-toolkit/templates/overlay-template.md .agent-local.md
# Edit .agent-local.md — fill in project structure, build commands, etc.
# 编辑 .agent-local.md — 填写项目结构、构建命令等

# Method B: AI-guided — let the agent interview you and generate the file
# 方式 B：AI 引导 — 让 Agent 通过对话收集信息并自动生成
# In Cursor chat, say: "帮我创建项目配置" or "run project-overlay skill"
# Agent will read the project-overlay skill, ask you about your project,
# and generate .agent-local.md automatically.
# 在 Cursor 对话中说"帮我创建项目配置"或"run project-overlay skill"，
# Agent 会通过对话了解你的项目，然后自动生成 .agent-local.md。
# Prerequisite: run `agent-sync .` first so the skill is deployed (prefixed as 'gla-pre-commit' by default — see Skill Prefix)
# 前提：先运行一次 `agent-sync .` 完成部署（默认前缀后为 `gla-pre-commit`，见 Skill Prefix 段）

# 3. Sync rules (generates .cursor/rules/*.mdc, .claude/rules/*.md, .agent-rules/AGENTS.md)
#    同步规则（生成各工具的配置文件）
agent-sync .

# 4. Validate
#    验证
agent-check .

# 5. Add generated files to .gitignore
#    将生成文件加入 .gitignore
cat >> .gitignore <<'EOF'

# AI agent rules (generated by agent-sync)
.agent-rules/
.cursor/rules/
.cursor/skills/
.cursor/worktrees.json
.cursor/.worktrees-agent-sync
.claude/
.codex/
.agents/skills/
.agent-sync-hash
.agent-sync-manifest
.agent-sync-skills-manifest
EOF

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
agent-sync codex .        # Only regenerate AGENTS.md (legacy) / 仅重新生成 AGENTS.md
agent-sync codex-native . # Only regenerate Codex native files (.codex/) / 仅重新生成 Codex 原生文件
agent-sync cc .           # Only regenerate all CC native files (.claude/) / 仅重新生成 CC 所有原生文件
agent-sync cc-rules .     # Only regenerate .claude/rules/*.md / 仅重新生成 CC rules
agent-sync cc-skills .    # Only sync skills to .claude/skills/ / 仅同步 skills 到 .claude/skills/
agent-sync skills .       # Only sync skills to .cursor/skills/ / 仅同步 skills 到 .cursor/skills/
agent-sync clean .        # Remove all generated files / 清理所有生成文件
```

> **Note / 注意**: The legacy `agent-sync claude` subcommand was removed in
> HIST-004 (see §9). `CLAUDE.md` is no longer generated — Claude Code v2.0.64+
> reads `.claude/rules/*.md` natively. Running `agent-sync claude` now exits
> with a migration hint. / `agent-sync claude` 子命令已在 HIST-004 中移除
> (见 §9)。`CLAUDE.md` 不再生成——Claude Code v2.0.64+ 原生读取
> `.claude/rules/*.md`。运行 `agent-sync claude` 会输出迁移提示并退出。

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

### OpenAI Codex (Native Support / 原生支持)

`agent-sync` now generates **native Codex files** under `.codex/`, similar to Claude Code's `.claude/` support:

`agent-sync` 现在生成 **Codex 原生文件**到 `.codex/` 目录下，与 Claude Code 的 `.claude/` 支持对称：

| Output / 输出 | Path / 路径 | Description / 描述 |
|---|---|---|
| Project config | `.codex/config.toml` | Sets `project_doc_fallback_filenames` so Codex discovers `.agent-rules/AGENTS.md` without a root symlink / 配置 fallback 路径让 Codex 自动发现指令文件 |
| Skills | `.agents/skills/<name>/SKILL.md` | Repo-scoped skills (Codex standard discovery path) / 仓库级 skills（Codex 标准发现路径） |
| Instructions | `.agent-rules/AGENTS.md` | Assembled rules (shared with legacy mode) / 组装后的规则文件（与 legacy 模式共用） |

**Codex Mode**: Controlled by `**Codex Mode**:` in `.agent-local.md`. Three modes: / 通过 `.agent-local.md` 中的 `**Codex Mode**:` 控制，三种模式：

- `off` — No Codex output at all / 不生成任何 Codex 输出
- `legacy` — `.agent-rules/AGENTS.md` only (wrapper required) / 仅生成 AGENTS.md（需 wrapper）
- `native` (default) — `.codex/config.toml` + `.agents/skills/` + `.agent-rules/AGENTS.md` (no wrapper) / 原生模式（无需 wrapper）

**How native mode works / 原生模式原理：**

The generated `.codex/config.toml` sets `project_doc_fallback_filenames = [".agent-rules/AGENTS.md"]`. When Codex scans the project root for instructions, it tries `AGENTS.override.md` → `AGENTS.md` → fallback filenames in order. Since we place rules in `.agent-rules/AGENTS.md` (to avoid Cursor duplicate injection), the fallback mechanism lets Codex find them automatically — **no wrapper or root-level symlink needed**.

生成的 `.codex/config.toml` 设置了 `project_doc_fallback_filenames`。Codex 扫描项目根目录时按 `AGENTS.override.md` → `AGENTS.md` → fallback filenames 的顺序查找。由于我们将规则放在 `.agent-rules/AGENTS.md`（避免 Cursor 重复注入），fallback 机制让 Codex 自动发现——**无需 wrapper 或根目录 symlink**。

The config also enables `[features] child_agents_md = true`, which instructs Codex to respect hierarchical `AGENTS.md` scoping — deeper files override higher-level instructions for their subtree. This works with `agent-sync`'s sub-repo overlay generation.

配置同时启用了 `child_agents_md` feature，使 Codex 尊重层级 `AGENTS.md` 作用域——子目录文件覆盖上层指令。这与 `agent-sync` 的 sub-repo overlay 生成完美配合。

**Critical: 32KiB Limit / 关键：32KiB 限制**

Codex has a `project_doc_max_bytes` default of **32,768 bytes**. Content beyond this limit is **silently truncated** — you get no error or warning. `agent-check` validates file size. If your rules exceed this, consider splitting packs into subdirectory `AGENTS.md` files.

Codex 的 `project_doc_max_bytes` 默认为 **32,768 字节**。超出此限制的内容会被**静默截断**。`agent-check` 会检查文件大小。如果规则超出限制，可以考虑将 packs 拆分到子目录的 `AGENTS.md` 文件。

### Claude Code (Native Support / 原生支持)

`agent-sync` now generates **native CC files** under `.claude/`:

`agent-sync` 现在生成 **CC 原生文件**到 `.claude/` 目录下：

| Output / 输出 | Path / 路径 | Description / 描述 |
|---|---|---|
| Per-file rules | `.claude/rules/*.md` | Mirrors `.cursor/rules/*.mdc` with CC-native `globs:` frontmatter / 对应 Cursor 的 `.mdc`，使用 CC 原生 `globs:` 前置元数据（`paths:` multi-path YAML list 有上游 bug #33581） |
| Skills | `.claude/skills/<name>/SKILL.md` | Same format as Cursor skills / 与 Cursor skills 格式一致 |

**CC Mode**: Controlled by `**CC Mode**:` in `.agent-local.md`. Two modes: / 通过 `.agent-local.md` 中的 `**CC Mode**:` 控制，两种模式：

- `off` — No `.claude/` output / 不生成 `.claude/` 文件
- `native` (default) — `.claude/rules/` + `.claude/skills/` only / 仅 CC 原生文件

> **HIST-004 — CLAUDE.md decommissioned / CLAUDE.md 已退役**:
> The legacy `dual` mode and `.agent-rules/CLAUDE.md` were removed. Claude
> Code v2.0.64+ reads `.claude/rules/*.md` natively, making the monolithic
> CLAUDE.md redundant. `dual` is accepted as a deprecated alias that folds
> to `native` with a warning, so existing `.agent-local.md` files don't
> hard-fail. Run `agent-sync` once after upgrading — `cleanup_remnants()`
> sweeps any stale `.agent-rules/CLAUDE.md` automatically. See §9 for the
> migration runbook. / 旧 `dual` 模式和 `.agent-rules/CLAUDE.md` 已移除。
> Claude Code v2.0.64+ 原生读取 `.claude/rules/*.md`，CLAUDE.md 单体文件已
> 冗余。`dual` 作为过渡别名 fallback 到 `native` 并打警告，老 overlay 不会
> 硬失败。升级后运行一次 `agent-sync`——`cleanup_remnants()` 自动清扫残留的
> `.agent-rules/CLAUDE.md`。详见 §9 迁移说明。

**How CC loads rules natively / CC 原生规则加载方式：**

- `.claude/rules/*.md`: per-file rules, loaded based on `globs:` frontmatter or always-on (no frontmatter) / 分文件规则，按 `globs:` 条件加载或始终加载
- `.claude/skills/<name>/SKILL.md`: skills, discovered natively / 技能，原生发现
- Subdirectory `CLAUDE.md`: loaded when CC works in that directory (user-authored only; `agent-sync` no longer generates sub-repo `CLAUDE.md` as of HIST-004) / 子目录 `CLAUDE.md` 按需加载（仅用户手写；HIST-004 起 `agent-sync` 不再生成子 repo `CLAUDE.md`）
- `~/.claude/CLAUDE.md`: personal global rules / 个人全局规则
- `CLAUDE.local.md`: auto-gitignored, for private project preferences / 私有项目偏好

**Tip / 提示**: With CC Mode `native` (default), the shell wrapper is **no longer required** for Claude Code. Rules are discovered natively via `.claude/rules/`. / 默认 CC Mode `native` 下，Claude Code **不再需要** shell wrapper。规则通过 `.claude/rules/` 原生发现。

### Skill Prefix / Skill 命名空间 (HIST-005)

Every deployed skill is prefixed so agent-toolkit-managed skills don't collide with unrelated skill sources (user-authored skills, agentskills.io catalog, other rule packs). Default prefix: `gla-`. Applied to **both** the target directory and `SKILL.md` frontmatter `name:`, so the prefixed identifier is what agents invoke.

每个被部署的 skill 都会加前缀，避免 agent-toolkit 的 skill 和其他来源的 skill 撞名。默认前缀 `gla-`，同时作用于**目录名**和 `SKILL.md` frontmatter 里的 `name:`——agent 调用时用的就是这个带前缀的名字。

**Default behavior / 默认行为：**

```text
skills/pre-commit/SKILL.md     (name: pre-commit)
        ↓ agent-sync
.cursor/skills/gla-pre-commit/SKILL.md     (name: gla-pre-commit)
.claude/skills/gla-pre-commit/SKILL.md     (name: gla-pre-commit)
.agents/skills/gla-pre-commit/SKILL.md     (name: gla-pre-commit)
```

Invoke from chat / 在对话中调用：`/gla-pre-commit`, `/gla-simple-review`, …

**Overlay override / overlay 自定义：** add `**Skill Prefix**:` to `.agent-local.md`:

```markdown
**Skill Prefix**: myproj        # auto-dashed → 'myproj-' / 自动补划线
**Skill Prefix**: myproj-       # used verbatim / 原样使用
**Skill Prefix**: none          # opt-out: deploy bare names / 关闭前缀，部署原名
```

Accepted opt-out tokens: `none`, `off`, `-`. Omitting the key keeps the `gla-` default. / `none` / `off` / `-` 都表示关闭；缺省则使用 `gla-`。

**Scope / 作用范围：** core `skills/` **and** every `extras/<bundle>/skills/`. The prefix is idempotent — re-syncing never produces `gla-gla-…`; stale directories from the previous prefix are pruned via the manifest. / 作用于核心 `skills/` 和所有 `extras/<bundle>/skills/`。幂等：反复 sync 不会产生 `gla-gla-…`；切换前缀时旧目录通过 manifest 自动清理。

### Shell Wrapper (Legacy / 兼容层)

The shell wrapper is now **optional for both Claude Code and Codex**:

shell wrapper 现在对 **Claude Code 和 Codex 都是可选的**：

- **Claude Code**: Not needed when CC Mode is `native` (default) / CC Mode 为 native（默认）时不需要
- **Codex**: Not needed when Codex Mode is `native` (default) / Codex Mode 为 native（默认）时不需要
- **Legacy only**: Wrapper is only required when Codex Mode is `legacy` (CLAUDE.md path was decommissioned in HIST-004, see §9) / 仅在 Codex Mode 为 legacy 时需要（CLAUDE.md 路径已在 HIST-004 中退役，详见 §9）

```bash
# Legacy wrapper — optional for Codex with Codex Mode native
# 兼容层 wrapper — Codex Mode 为 native 时不需要

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
# claude-run removed in HIST-004 — Claude Code discovers .claude/rules/ natively.
# / HIST-004 移除 claude-run — Claude Code 原生读取 .claude/rules/。
```

**Exit criteria / 退出条件**: The wrapper can be removed entirely when / 当以下条件满足时可完全移除 wrapper：

- ✅ **Codex**: Native mode (`Codex Mode: native`) uses `.codex/config.toml` fallback — wrapper no longer needed / 原生模式通过 config.toml fallback 发现指令——已不需要 wrapper
- ✅ **Claude Code**: Native CC Mode uses `.claude/rules/` discovery — wrapper no longer needed (HIST-004) / 原生 CC Mode 通过 `.claude/rules/` 发现——已不需要 wrapper（HIST-004）
- Cursor supports disabling auto-injection of `AGENTS.md`/`CLAUDE.md` via settings or `.cursorignore` (still outstanding) / Cursor 支持禁用自动注入（尚未解决）

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
| File existence | `.agent-rules/AGENTS.md` (when Codex ≠ off); `.agent-rules/CLAUDE.md` **must be absent** (HIST-004) / `.agent-rules/AGENTS.md`（Codex ≠ off 时）；`.agent-rules/CLAUDE.md` 必须**不存在**（HIST-004） |
| Root remnants | No `CLAUDE.md`/`AGENTS.md` at project root / 根目录无残留文件 |
| Core semantics | Core `.mdc` files have `alwaysApply: true` / Core 文件必须始终加载 |
| Skills deployment | `.cursor/skills/` matches manifest from rules repo / skills 已部署且与 manifest 一致 |
| Worktrees deployment | `.cursor/worktrees.json` exists and is valid JSON; if agent-sync managed, matches template / worktrees.json 已部署且 JSON 有效 |
| Settings validity | `.vscode/settings.json` is valid JSON (if present) / 配置文件 JSON 有效性 |
| CC rules deployment | `.claude/rules/` matches manifest (when CC Mode ≠ off) / CC rules 已部署且与 manifest 一致 |
| CC skills deployment | `.claude/skills/` matches manifest (when CC Mode ≠ off) / CC skills 已部署且与 manifest 一致 |
| CC/Cursor consistency | `.claude/rules/` and `.cursor/rules/` have matching counts (when CC Mode ≠ off) / CC 与 Cursor rules 数量一致 |
| Codex config | `.codex/config.toml` is valid TOML with fallback filenames (when Codex Mode = native) / Codex 配置有效 |
| Codex skills | `.agents/skills/` matches manifest (when Codex Mode = native) / Codex skills 已部署 |
| Cross-tool consistency | Codex/CC/Cursor skill sets match (when Codex Mode = native) / 三工具 skills 集合一致 |

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

---

## 9. Maintenance / 维护指南

### When to re-run `agent-sync` / 何时重新同步

| Trigger / 触发条件 | Action / 操作 |
|---|---|
| Modified any file in `~/.config/agent-toolkit/` / 修改了规则仓库中的任何文件 | `agent-sync .` in each project / 在每个项目中运行 |
| Modified `.agent-local.md` (root or sub-repo) / 修改了项目 overlay | `agent-sync .` (auto-detected / 自动检测) |
| First time setting up a project / 首次设置项目 | `agent-sync .` |
| Deleted a sub-repo `.agent-local.md` / 删除了子目录 overlay | `agent-sync .` (auto-cleans ghost rules / 自动清理残留规则) |
| Generated files accidentally deleted / 生成文件被意外删除 | `agent-sync .` |
| Need to regenerate only one tool / 只需重新生成某个工具的文件 | `agent-sync codex .` or `agent-sync cc-rules .` |
| Want to remove all generated files / 需要清除所有生成文件 | `agent-sync clean .` |
| Nothing changed / 没有变化 | Script auto-detects and skips / 脚本自动检测并跳过 |

### How to update rules / 如何更新规则

1. Edit the source file in `~/.config/agent-toolkit/` (e.g., `packs/python.md`) / 编辑规则仓库中的源文件
2. (If git) Commit the change / 提交变更
3. Run `agent-sync .` in each active project / 在每个活跃项目中运行同步
4. Run `agent-check .` to validate / 运行检查脚本验证
5. (Optional) Run a regression test task to verify behavior / （可选）运行回归测试任务验证行为

### Migrating from pre-decommission layout / 从旧版布局迁移

If you upgrade from a version that still shipped `commands/` and `core/30-review-criteria.md`, note the following:

如果你从仍然包含 `commands/` 目录和 `core/30-review-criteria.md` 的旧版本升级到当前版本，请注意：

- **Auto-handled on the next `agent-sync` run** (zero action required) / **下一次 `agent-sync` 自动处理**（无需手动操作）
  - `.cursor/rules/30-review-criteria.mdc` — removed by `generate_cursor()` as a one-shot orphan cleanup (the source rule is gone).
  - `.claude/commands/` — **manifest-driven, precise**: only files listed in the stamped `.agent-sync-commands-manifest` are removed, along with the manifest itself; if you added your own `.md` files into the same directory after the original agent-sync deployment, they stay. The directory is rmdir'd only when empty (i.e. no user additions).
  - `.cursor/.reviewer-models-agent-sync` — the orphan stamp written by pre-refactor `agent-sync` is removed by `agent-sync clean`. The companion `.cursor/reviewer-models.conf` (if any) is treated as user-managed and left alone.
  - **First run after upgrade will always re-sync**: the staleness-hash key was compacted from 3 segments to 2 in this refactor, so an upgraded project will trigger one full regeneration even if the conceptual rule set did not change. After that, staleness-skip resumes as normal.

- **NOT touched by `agent-sync`** (safe to retain or manually clean) / **`agent-sync` 不会自动清理**（可自行保留或手动清理）
  - `.cursor/commands/`, `.cursor/agents/`, `.cursor/reviewer-models.conf` — Cursor treats `.cursor/commands/` as a user-authored slash-command directory and `.cursor/agents/` is where transitional multi-model reviewer prompts live; `agent-sync` will **not** delete anything under these paths to avoid trampling on user-maintained content. Remove them manually once `extras/agent-extension` ships the replacement.
  - Root-level `CLAUDE.md` / `AGENTS.md` written by older versions are still cleaned by `cleanup_remnants()` as before.

- **History / 历史上下文**: see `issue_history/HISTORY.md` → `HIST-003: Commands/Review 子系统退役` for the full rationale (why `pre-commit` became a skill, why multi-model `/review` moved to `extras/agent-extension`).

### Migrating from CC Mode `dual` / CLAUDE.md (HIST-004) / 从 CC Mode `dual` / CLAUDE.md 迁移

If you are upgrading from a version that still produced `.agent-rules/CLAUDE.md` or your `.agent-local.md` still has `**CC Mode**: dual`, note: / 如果你从仍然生成 `.agent-rules/CLAUDE.md` 的旧版本升级，或 `.agent-local.md` 里仍写着 `**CC Mode**: dual`：

- **Auto-handled on the next `agent-sync` run** (zero action required) / **下一次 `agent-sync` 自动处理**（无需手动操作）
  - `.agent-rules/CLAUDE.md` (root + every sub-repo) — `cleanup_remnants()` and `sync_sub_repos()` `rm -f` any stale CLAUDE.md unconditionally on every sync. Verified by regression test `T17`. / `.agent-rules/CLAUDE.md`（根目录 + 每个 sub-repo）—— 每次 sync 都会强制 `rm -f`，由 `T17` 覆盖。
  - `**CC Mode**: dual` in `.agent-local.md` — `resolve_cc_mode()` treats it as a deprecated alias and folds silently to `native` with one `DEPRECATED:` warning printed to stderr. Update the overlay at your leisure; no rush. Covered by `T16`. / `.agent-local.md` 里的 `**CC Mode**: dual` 被作为过渡别名 fallback 到 `native`，仅打一条 `DEPRECATED:` 警告。由 `T16` 覆盖。

- **Hard-fails** (behavior change, not silent) / **硬失败**（行为变更，不是静默）
  - `agent-sync claude <dir>` — subcommand removed. Exits 2 with a HIST-004 migration hint instead of cd-ing into a directory literally named `claude`. Use `agent-sync cc-rules <dir>` for the equivalent targeted regeneration. Covered by `T18`. / `agent-sync claude <dir>` 子命令已移除，退出码 2 并打印 HIST-004 迁移提示。等效用法改为 `agent-sync cc-rules <dir>`。由 `T18` 覆盖。
  - `agent-check` — now asserts `.agent-rules/CLAUDE.md` **absent**. A stray CLAUDE.md (e.g. from an old manual edit) is surfaced as FAIL; running `agent-sync` once resolves it. / `agent-check` 现在断言 `.agent-rules/CLAUDE.md` **不存在**；遗留 CLAUDE.md 会导致 FAIL，运行一次 `agent-sync` 即可解决。

- **Scope** / **影响面**:
  - `.claude/rules/*.md` (native, per-file with frontmatter), `.claude/skills/`, `.cursor/rules/*.mdc`, `.agent-rules/AGENTS.md` (Codex only) — **unchanged**. / 不受影响。
  - The shell wrapper `claude-run` is no longer published in README — Claude Code v2.0.64+ reads `.claude/rules/` natively. If you still have `claude-run` defined in your shell rc, feel free to delete it. / README 不再提供 `claude-run` —— v2.0.64+ 原生读取 `.claude/rules/`；shell rc 里的 `claude-run` 可自行删除。

- **History / 历史上下文**: see `issue_history/HISTORY.md` → `HIST-004: CLAUDE.md 退役`. / 详见 `issue_history/HISTORY.md` → `HIST-004: CLAUDE.md 退役`。

- **迁移落地三步** / **Three-step migration**:
  1. Pull the latest `agent-toolkit`, then run `agent-sync .` in each active project. Orphaned auto-generated files are removed; warnings list anything it chose to leave alone.
  2. Run `agent-check .` to confirm the post-migration state is clean.
  3. (Optional) If you previously relied on the removed slash commands and have not yet wired up `extras/agent-extension`, use `skills/simple-review` as a single-model fallback and `skills/pre-commit` for commit drafting — both are cross-tool and load automatically.

### Migrating to prefixed skills (HIST-005) / 迁移到带前缀的 skill

If you are upgrading from a version that deployed bare-named skills (`pre-commit`, `simple-review`, …), note that the next `agent-sync` will rename every deployed skill to `gla-<name>` (default prefix). / 如果你从部署裸名 skill 的旧版本升级，下一次 `agent-sync` 会把所有已部署 skill 重命名为 `gla-<name>`（默认前缀）。

- **Auto-handled on the next `agent-sync` run** (zero action required) / **下一次 `agent-sync` 自动处理**（无需手动操作）
  - Old `.cursor/skills/<name>/`, `.claude/skills/<name>/`, `.agents/skills/<name>/` are removed via manifest-driven stale cleanup in `deploy_artifacts`; new `gla-<name>/` is deployed in their place with frontmatter `name:` rewritten. Verified by regression tests `T19a`/`T19b`/`T19e`. / 旧目录通过 `deploy_artifacts` 的 manifest 清理机制自动删除，新目录重新部署并重写 frontmatter。由 `T19a`/`T19b`/`T19e` 覆盖。
  - Slash-command invocations must use the new identifier (`/gla-pre-commit` instead of `/pre-commit`). Update any shell aliases or docs that still reference bare names. / 调用 skill 时要用新名字 (`/gla-pre-commit`)，旧别名/文档需同步更新。

- **Opt-out** / **关闭前缀**:
  - Add `**Skill Prefix**: none` to `.agent-local.md` and re-sync. Old `gla-*` dirs are swept automatically; bare names are redeployed. Covered by `T19d`. / `.agent-local.md` 加一行 `**Skill Prefix**: none` 后重新 sync。旧 `gla-*` 目录自动清理，裸名重新部署。由 `T19d` 覆盖。

- **Custom prefix** / **自定义前缀**:
  - Add `**Skill Prefix**: myproj` (auto-dashed to `myproj-`) or `myproj-` (used as-is). Every skill — core **and** `extras/` — is remapped uniformly (single convention assumption). Covered by `T19c`. / `**Skill Prefix**: myproj` (自动补划线) 或 `myproj-` (原样使用)。核心和 `extras/` 所有 skill 统一按同一规则重命名。由 `T19c` 覆盖。

- **Idempotency guarantee** / **幂等保证**: re-running `agent-sync` never produces `gla-gla-…`; the rewriter skips names that already start with the active prefix. / 反复 sync 不会产生 `gla-gla-…`；已带前缀的名字会被跳过。

- **Scope** / **影响面**:
  - Only `SKILL.md` frontmatter `name:` is rewritten (first match, YAML header). `description:`, `when_to_use:`, body text are unchanged. / 仅改 `SKILL.md` frontmatter 里第一条 `name:` 字段；`description:` / `when_to_use:` / 正文不变。
  - User-authored skills outside `skills/` and `extras/<bundle>/skills/` (e.g. a hand-curated `.cursor/skills/mine/`) are **not** touched — `agent-sync` only manages deployment targets it wrote itself. / 不受 agent-sync 管理的 skill 目录不会被改。

- **History / 历史上下文**: see `issue_history/HISTORY.md` → `HIST-005: Skill 命名空间前缀`. / 详见 `HIST-005`。

### Managing extras/ submodules / 管理扩展 submodule

`extras/` contains optional, domain-specific skill bundles mounted as git submodules.
`agent-sync` automatically initializes and deploys them — no extra steps needed after initial setup.
If submodule initialization fails (e.g., network issues, missing SSH keys), a warning is printed and extras are skipped.

`extras/` 下存放按需挂载的领域专用扩展，以 git submodule 形式管理。`agent-sync` 会自动初始化并部署。若子模块初始化失败（如网络问题、SSH 密钥缺失），会输出警告并跳过 extras。

**Priority / 优先级**: Core skills (`skills/`) always take priority over extras. If an extras bundle contains a skill with the same name as a core one, the extras version is skipped and a warning is printed. To use both, create a renamed symlink in the extras bundle.

**优先级**：核心 skills（`skills/`）始终优先于 extras。若 extras 中存在与核心同名的 skill，extras 版本会被跳过并输出提示。如需同时使用，在 extras bundle 中创建重命名的软链接。

```bash
# Add a new bundle / 添加新扩展包
git submodule add git@github.com:georgeokelly/agent-extension.git extras/agent-extension
git commit -m "Add agent-extension as domain-specific skill bundle"

# Upgrade a bundle to latest / 升级某个扩展包
git -C extras/agent-extension pull origin main
git add extras/agent-extension
git commit -m "Update agent-extension submodule to latest"

# Remove a bundle / 移除某个扩展包
git submodule deinit extras/agent-extension
git rm extras/agent-extension
git commit -m "Remove agent-extension submodule"
```

On a new machine, clone with submodules / 新机器克隆时带上 submodule：

```bash
git clone --recurse-submodules https://github.com/georgeokelly/agent-toolkit.git ~/.config/agent-toolkit
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

No. `agent-sync` automatically strips all `<!-- ... -->` comments during compilation. You can keep detailed Chinese annotations in `.agent-local.md` for your own reference — they will not appear in the generated `.claude/rules/*.md`, `AGENTS.md`, or `.mdc` files.

不会。`agent-sync` 在编译时会自动去除所有 `<!-- ... -->` 注释。你可以在 `.agent-local.md` 中保留详细的中文引导注释供自己参考 — 它们不会出现在生成的文件中。

**Q: How to use with a multi-repo workspace? / 多 repo 的 workspace 怎么用？**

Place `.agent-local.md` at the workspace root (shared rules) and in each sub-repo (repo-specific rules). `agent-sync` recursively finds all `.agent-local.md` files and generates a sub-repo `AGENTS.md` (for Codex) and a per-sub-repo `.claude/rules/<path>-overlay.md` (for Claude Code native) with overlay-only content (no duplicate core/packs). For Cursor, it also generates a globs-scoped `.mdc` in `.cursor/rules/` (e.g. `extras-agent-extension-overlay.mdc` with `globs: extras/agent-extension/**`), so Cursor loads the overlay only when editing files under that sub-repo — avoiding token cost for unrelated contexts. Cursor only reads workspace-root `.cursor/rules/`. If you delete a sub-repo overlay, `agent-sync` automatically cleans up the generated files (including the sub-repo .mdc). HIST-004: sub-repo `CLAUDE.md` is no longer generated — the `.claude/rules/` overlay path supersedes it.

在 workspace 根目录放 `.agent-local.md`（共享规则），每个子 repo 也放一个（repo 特有规则）。`agent-sync` 会递归查找所有 `.agent-local.md`，在子目录生成只包含 overlay 内容的 `AGENTS.md`（Codex）和根目录 `.claude/rules/<path>-overlay.md`（Claude Code 原生）（不重复 core/packs）。对 Cursor 还会在 `.cursor/rules/` 生成 globs 作用域的 `.mdc`（如 `extras-agent-extension-overlay.mdc`，`globs: extras/agent-extension/**`），仅在编辑该子 repo 内文件时加载，避免无关上下文的 token 消耗。Cursor 只读 workspace 根目录的 `.cursor/rules/`。如果删除了某个子 repo 的 overlay，`agent-sync` 会自动清理其生成文件（含子 repo 的 .mdc）。HIST-004：子 repo `CLAUDE.md` 不再生成——由 `.claude/rules/` overlay 取代。

---

## 11. Roadmap

Detailed design docs and review history are tracked in `issue_history/`.

详细设计文档和 review 记录在 `issue_history/` 目录中。

| Priority / 优先级 | Item / 事项 | Reference / 参考 |
|--------|------|-----------|
| P3 | Phase C pilot — test C++/CUDA extension branch / Phase C 试点 — 测试 C++/CUDA 扩展分支 | `fea-002` Roadmap |
| Future | Cross-session conversation persistence for overlay generation / 对话持久化与跨会话恢复 | `fea-002` Roadmap |
