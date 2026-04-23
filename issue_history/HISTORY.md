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
| HIST-005 | Skill 命名空间前缀（`gla-` default） | Closed | 2026-04-21 |
| HIST-004 | CLAUDE.md 退役（CC 原生 `.claude/rules/` 接管） | Closed | 2026-04-21 |
| HIST-003 | Commands/Review 子系统退役 | Closed | 2026-04-21 |
| HIST-002 | Project Overlay 优化方案 | In Progress | 2026-03-04 |
| HIST-001 | Agent Rules 隔离方案 | Closed | 2026-03-04 |
| HIST-000 | Visual Explanations 规则 | Closed | 2026-03-01 |

---

## Records / 记录

### HIST-005: Skill 命名空间前缀（`gla-` default）

- **Status / 状态**: Closed
- **Date / 日期**: 2026-04-21
- **Scope / 范围**: `scripts/lib/resolve.sh`, `scripts/lib/common.sh`, `scripts/agent-sync.sh`, `scripts/agent-test.sh`, `README.md`, `issue_history/HISTORY.md`

#### 背景 / Background

`skills/` 下已经有 `pre-commit` / `simple-review`，未来会越来越多；同时 `extras/agent-extension` 也提供自有 skill。Cursor / Claude Code / Codex 在 workspace 内解析 skill 时，**按名字查找**（`/pre-commit`, `/simple-review` …），没有 namespace。当用户同时订阅多个 skill 来源（agent-toolkit、agentskills.io catalog、手写 skill、其他 rule pack）时，**撞名**会导致不可预测的解析：CC 甚至直接报错 "Duplicate skill name"。

我们需要在部署环节加一层 namespace，让 agent-toolkit 生产的 skill 和其他来源在名字级别清晰可分，又不强迫用户改源目录结构。

#### 设计 / Design

**方案 B（最终采纳）**：部署时统一加前缀 `gla-`，通过 overlay 可定制。

- **影响两处**：目标目录名（`.cursor/skills/gla-pre-commit/`）和 `SKILL.md` frontmatter 的 `name: gla-pre-commit`。agent 调用 skill 靠 `name:` 字段；只改目录不改 frontmatter 对 invocation 无效。
- **可配置**：`.agent-local.md` 里加 `**Skill Prefix**: <value>`：
  - 空 / 缺失 → default `gla-`
  - `none` / `off` / `-` → 完全关闭前缀（bare name 部署）
  - `myproj` → auto-dash → `myproj-`
  - `myproj-` → 原样使用
- **一视同仁**：核心 `skills/` 和所有 `extras/<bundle>/skills/` 用同一前缀；假设所有 skill 源走同一命名规范（这是当前 agent-toolkit deploy pipeline 的假设）。
- **幂等**：`_apply_skill_prefix` 对 frontmatter `name:` 检查 `startsWith($prefix)`，重复 sync 不会产生 `gla-gla-…`；目录层面 `deploy_artifacts` 每次 `rm -rf $item_target` 再重建，天然幂等。
- **staleness 同步**：`check_staleness` 把 manifest 比对也改成 prefix-qualified（`${SKILL_PREFIX}$(basename "$expected_skill")`），否则切换 prefix 后会永久 re-sync。
- **切换清理**：`deploy_artifacts` 尾端的 manifest-driven stale cleanup 自动删除旧前缀下的目录（T19e 覆盖）。

#### 实现 / Implementation

| 文件 | 改动 |
|------|------|
| `scripts/lib/resolve.sh` | 新增 `SKILL_PREFIX="gla-"` 默认值 + `resolve_skill_prefix()`（overlay 读取、auto-dash、`none`/`off`/`-` opt-out、export）；`check_staleness` 里 skills manifest 比对改成 `${_sp}$(basename ...)` 带前缀 |
| `scripts/lib/common.sh` | 新增私有 `_apply_skill_prefix()`（perl `-i` in-place 重写首个 `^name:` 行，macOS/Linux 统一；python3 兜底）；`deploy_artifacts` 核心循环 + extras 循环都把 `item_target` 从 `item_name` 改为 `${prefix}${item_name}`，部署后调用 `_apply_skill_prefix "$item_target"`，manifest 记录 prefixed name |
| `scripts/agent-sync.sh` | `sync` / `skills` / `codex-native` / `cc` / `cc-skills` 五个分支在 skill 部署前加 `resolve_skill_prefix`（`cc-rules` 不涉及 skills，不需要） |
| `scripts/agent-test.sh` | T1 / T11 原 bare-name 断言改为 `gla-*`，并追加三条"bare 不应存在"反向断言；新增 T19 五个子场景（T19a 默认 + frontmatter，T19b 幂等，T19c 自定义前缀 + auto-dash，T19d `none` opt-out，T19e 切换前缀清理旧目录） |
| `README.md` | §4 (Claude Code 段后) 新增 "Skill Prefix / Skill 命名空间 (HIST-005)" 小节，解释 overlay 语法、调用方式、default；§3 示例注释更新为 `gla-pre-commit`；§9 新增 "Migrating to prefixed skills (HIST-005)" 小节 |
| `issue_history/HISTORY.md` | 本条 |

#### Regression Guards

- `T19a: Default 'gla-' prefix applied to core + frontmatter` — `agent-sync` 默认：目录 `.cursor/skills/gla-pre-commit/` + `.claude/skills/gla-pre-commit/` + `.agents/skills/gla-pre-commit/` 均存在；`SKILL.md` 里 `^name: gla-pre-commit`；manifest 里 `gla-pre-commit`。
- `T19b: Idempotent re-sync (no double-prefix)` — 连续 `agent-sync` + `agent-sync cc-skills` 后：不存在 `gla-gla-pre-commit/` 目录；`SKILL.md` 不出现 `^name: gla-gla-`。
- `T19c: Overlay custom prefix with auto-dash` — overlay `**Skill Prefix**: myproj`（无尾划线）→ 目录 `myproj-pre-commit/` + frontmatter `name: myproj-pre-commit`；default `gla-*` 不产生。
- `T19d: 'none' opt-out deploys bare names` — overlay `**Skill Prefix**: none` → 目录 `pre-commit/` + frontmatter `name: pre-commit`（bare）；`gla-*` 目录不存在。
- `T19e: Prefix switch cleans previous generation` — 先 default sync，再切到 `**Skill Prefix**: myproj-` 重 sync：`myproj-pre-commit/` 在位，原 `gla-pre-commit/` 已被 manifest 清理删除。

#### 限制 / Limitations

- **首次升级会触发一次 re-sync**：旧版本 manifest 记录裸名，新版本期望前缀名 → `skills_ok=false` → 全量 re-deploy。这是预期行为（和 HIST-003/004 类似）。运行一次 `agent-sync` 即可收敛。
- **YAML 格式假设**：`_apply_skill_prefix` 只重写**第一个** `^name:` 行（perl regex `$done` flag）。这假设 frontmatter 在文件顶端且 `name:` 在第一次出现时一定是 frontmatter 里的值——这符合 agent-toolkit 当前所有 `SKILL.md` 的写法。如果以后有 skill 在 frontmatter 外也写了一条 `name:` 在更靠前的位置（例如文件第一行就是注释里引用了 `name:`），重写会错位；但这需要手动构造异常 skill，现有任何 skill 都不触发。
- **opt-out 不保留前缀历史**：从 `gla-` 切到 `none` 时，deploy_artifacts 的 stale cleanup 会删除所有 `gla-*` 目录。如果用户在这些目录下手动加了文件（不该这么做，agent-sync 是单向部署），会一并丢失。和 HIST-003/004 的 cleanup 策略一致。
- **自定义 prefix 不校验合法性**：我们不限制字符集。如果用户写了 `**Skill Prefix**: /bad`（会产生 `/bad-pre-commit/` 这样的路径），`mkdir -p` 会失败或产生子目录。建议保持 `[a-z0-9-]+` 字符集——未来可以加校验，目前靠用户自律。
- **与 Cursor 原生 skill 扫描路径的兼容**：Cursor 按目录名扫 `.cursor/skills/*/SKILL.md`，无其它约束，目录叫什么都可以。Codex 的 `.agents/skills/` 同理。CC 的 `.claude/skills/` 类似。前缀不会破坏任何原生发现路径。

#### Cross-refs / 关联

- HIST-003：退役 commands/ 子系统，把 `pre-commit`/`simple-review` 变成跨工具 skill；本次命名空间化直接继承那些 skill 的部署链路。
- HIST-004：CLAUDE.md 退役，进一步收敛"agent-toolkit 只写 `.claude/rules/` + `.claude/skills/`"的单一约定；加前缀让"所有 agent-toolkit 生成的 skill"在仓库里一眼可识别。
- `deploy_artifacts` 现在是所有 skill 部署的单一入口——任何新增的 skill 源（未来可能的 `extras/<new-bundle>/skills/`）都会自动走前缀逻辑，无需额外改动。

---

### HIST-004: CLAUDE.md 退役（CC 原生 `.claude/rules/` 接管）

- **Status / 状态**: Closed
- **Date / 日期**: 2026-04-21
- **Related commits / 关联提交**: (pending — this commit)

#### Background / 背景

- Claude Code v2.0.64+ 原生读取 `.claude/rules/*.md`（带 `globs:` frontmatter 的 per-file rules）与 `.claude/skills/`，CC Mode `dual` 下同时产出的 `.agent-rules/CLAUDE.md` 单体文件早已不再被加载——这个路径的唯一遗留用途是"shell wrapper + symlink"兜底，而该兜底本身也在 v2.0.64+ 被 `.claude/` 原生发现取代。用户明确使用最新 CC。
- `generate_codex` 依赖 `generate_claude` 作为中间产物的设计把两个工具的代码路径耦合在一起：Codex 的 `AGENTS.md` 其实是先 `generate_claude` → `cp CLAUDE.md AGENTS.md` → `sed` 替换头部注释，导致 `.agent-rules/CLAUDE.md` 被不管 CC 模式、不管是否需要都被顺带写出。简化这条耦合能同时降低维护面和意外产物。
- `CC Mode=dual` 这一档本质上只是"native + 多造一份 legacy CLAUDE.md 当兜底"，兜底既失效，这一档就没有理由存在；只保留 `{off, native}` 与 Codex Mode `{off, legacy, native}` 的三档对称。

#### Design / 设计方案

- **Clean Break (方案 A)**：整段移除 `.agent-rules/CLAUDE.md` 的生成、sub-repo 侧 `CLAUDE.md` 的生成、`agent-sync claude` 子命令与 CC Mode `dual`。
- **D1X — `CC Mode: dual` 保留为过渡别名**：`resolve_cc_mode()` 读到 `dual` 时 fallback 到 `native` 并打印一条 `DEPRECATED:` 警告；`agent-check.sh` 同样 silent-fold 为 `native`（不重复 warn）。避免老 `.agent-local.md` 在升级后直接硬失败。
- **D2X — `agent-sync claude` 子命令打专项 error**：显式 `case claude)` 分支，exit 2 并打印 HIST-004 迁移提示 + `cc-rules` 等效替代建议；同时新增 `case *)` 兜底把未知子命令/路径与 `-*` 未知 flag 区分出来，避免 `cd claude` 这种沉默降级。
- **Codex 解耦**：在 `gen-codex.sh` 新增私有辅助 `_build_agents_body`，把"header + core + 激活 packs + overlay"的 concat 逻辑迁移到 Codex 自己这边，`generate_codex` 不再调用 `generate_claude`。

#### Implementation / 实现方案

| 文件 | 变更 |
|------|------|
| `scripts/lib/resolve.sh` | `CC_MODE` 默认 `dual → native`；`resolve_cc_mode` `case` 折掉 `dual` 为 `native` 并打 `DEPRECATED:`；`check_staleness` 删 `claude_exists` 状态跟踪与 `claude_required` 分支，仅保留 `agents_required`，staleness 不再关心 CLAUDE.md 是否存在 |
| `scripts/lib/gen-claude.sh` | 删除 `generate_claude` 整段函数；顶部文档改为"Claude Code native generation (.claude/rules/, skills/)" + HIST-004 说明 |
| `scripts/lib/gen-codex.sh` | 新增私有 `_build_agents_body`（承接原 `generate_claude` 的 concat 管线）；`generate_codex` 改为直接 `_build_agents_body` + 32KiB 尺寸校验，不再 `cp CLAUDE.md` + `sed` |
| `scripts/lib/sync.sh` | `cleanup_remnants()` 追加 `rm -f .agent-rules/CLAUDE.md`；`sync_sub_repos()` 把 sub-repo 侧输出改为直写 `AGENTS.md`（Codex 模式开时）+ 无条件 `rm -f $sub_dir/CLAUDE.md`（清存量）；日志报出 overlay 字节数而非 CLAUDE.md 字节数 |
| `scripts/agent-sync.sh` | USAGE/SUBCOMMANDS/EXAMPLES 删除 `claude` 描述，新增 NOTE 指向 HIST-004；`case` 语句拆出 `claude)` 专项 error、`'')` 空分支、`-*)` 未知 flag error、`*)` 未知子命令/路径兜底；删除 `claude` 子命令分支；`sync` 分支把原 "CC=native+Codex=off 时跳过" 简化为"仅 Codex≠off 时 `generate_codex`" |
| `scripts/agent-check.sh` | `CC_MODE` 默认 `dual → native` + `dual` silent-fold；CLAUDE.md 断言反转：存在即 FAIL（HIST-004 升级残留），不存在即 PASS；AGENTS.md 断言保留并只依赖 `CODEX_MODE` |
| `scripts/agent-test.sh` | `write_overlay` default `cc_mode` `dual → native`；T1/T4/T5/T6/T7/T8/T8b/T9 的 `test -f CLAUDE.md` 全部反转为 `test ! -f`，T8 额外新增 "No sub-repo CLAUDE.md" 与 "Sub-repo AGENTS.md" 断言；T5/T6 用 `dual` 跑一次以顺带覆盖 alias 路径；新增 T16 / T17 / T18 三条 HIST-004 regression guard |
| `README.md` | §3 目录树注释 `CLAUDE.md → .claude/rules/*.md`；subcommand 表删 `claude` 行并追加 HIST-004 NOTE；§4 "Claude Code (Native Support)" 段重写（`dual` 删除、加 HIST-004 blockquote + fallback 说明）；Shell Wrapper 段删 `claude-run`、Exit criteria 更新；Validation Checklist `File existence` 行反转 CLAUDE.md 语义；Size Budget 删 "Assembled CLAUDE.md"；§9 新增 "Migrating from CC Mode dual / CLAUDE.md (HIST-004)" 小节；Q&A `.agent-local.md` HTML 注释回答把 `CLAUDE.md` 改为 `.claude/rules/*.md`；sub-repo overlay 段更新为"sub-repo `AGENTS.md` + 根 `.claude/rules/<path>-overlay.md`" |

#### Regression guards / 回归保障

- `T16: CC Mode 'dual' deprecated alias` — `write_overlay P16 dual native`，断言：(1) stderr 含 `DEPRECATED: CC Mode 'dual'`，(2) `.agent-rules/CLAUDE.md` 不生成，(3) `AGENTS.md` 仍生成，(4) `.claude/rules/` 仍生成，(5) `agent-check` pass。
- `T17: Legacy CLAUDE.md upgrade cleanup` — 先 `agent-sync` 成功，随后手工 plant `.agent-rules/CLAUDE.md` + `libs/core/CLAUDE.md`（模拟 pre-HIST-004 部署），删 hash 强制 re-sync，断言：(1) 根 CLAUDE.md 被清，(2) sub-repo CLAUDE.md 被清，(3) AGENTS.md + sub-repo AGENTS.md 仍在。
- `T18: 'agent-sync claude' rejected` — `"$AGENT_SYNC" claude "$P18"` 退出码非零，stderr 含 `removed in HIST-004`，且 P18 下未生成 `.agent-rules/CLAUDE.md`（即未 silent-cd 进 `claude/`）。

#### Limitations / 局限性

- **`dual` 过渡别名仅是 *soft* deprecation**：目前 `resolve_cc_mode()` 在每次 sync 时都会打一条 `DEPRECATED:`；没有硬截止日期，也没有"N 次警告后强制 FAIL"的 escalation。长期看可以在下一次 CC Mode 语义变动时清掉 `dual)` 分支，但本次不动。
- **User-authored sub-repo `CLAUDE.md` 的误伤边界**：`sync_sub_repos` 的 `rm -f "$sub_dir/CLAUDE.md"` 对所有带 `.agent-local.md` 的 sub-repo 无条件执行。若用户在 sub-repo 根手写了 `CLAUDE.md`（把它当 Anthropic 规范的 per-repo rules 用），这次 sync 会把它一并删掉。考虑到 (a) 工具此前一直声称"sub-repo `CLAUDE.md` 由 agent-sync 生成"、(b) 本 commit 明确声明 HIST-004 移除这条写入路径，把这个路径视作 agent-sync 独占是合理假设——但若后续有用户反馈，可加一个"只删带 auto-generated 头部的 CLAUDE.md"的精细化条件。
- **AGENTS.md 内容路径变更需要重算 hash**：`_build_agents_body` 写的 header 改为"Auto-generated by agent-sync for Codex. Do not edit manually."（与旧 `sed` 替换后的结果一致），但调用时序从 `generate_claude → cp → sed` 改为直接写入，首次升级会触发一次 re-sync（与 HIST-003 hash 段变更类似）。
- **`agent-sync claude` 路径兜底的 `case *)` 副作用**：新加的 `*)` 分支依赖 `[ -e "$1" ]` 判断是否是合法 project-dir；若用户传入的 arg 既不是已知子命令也不是已存在路径，会在 `cd` 前就 exit 2，不再降级为 `cd typo` 的原生错误。这比以前友好，但会拒绝"先 agent-sync 再 mkdir 目标目录"这种极端顺序的用法——此时请先创建目录。

#### TODOs / 遗留项

- [ ] 若持续观察到用户仍写 `CC Mode: dual`，考虑在 N 个版本后把 `resolve_cc_mode()` 的 `dual)` 分支从 soft warn 升级为 hard error 并给出最终迁移窗口。
- [ ] `extras/agent-extension/` 本次未涉及；下游 hooks / plugins 若还在读 `.agent-rules/CLAUDE.md`，需要统一改为读 `.claude/rules/` 或直接依赖 CC 自身的加载机制。
- [ ] `async-agent-rules.sh` 及其他围绕 "后台 sync" 的脚本本次只做 syntax 级兼容性检查，未做端到端验证——若后续发现 async 路径仍在 touch CLAUDE.md，应当追加 regression test。

---

### HIST-003: Commands/Review 子系统退役

- **Status / 状态**: Closed
- **Date / 日期**: 2026-04-21
- **Related commits / 关联提交**: (pending — this commit)

#### Background / 背景

- `commands/` 子系统只在 Cursor 中以 `/xxx` slash command 形式被识别，Claude Code 和 Codex 都没有对等机制，导致同一份内容要么被复制，要么降级为无效部署。维护 `deploy_artifacts` + 两份 manifest (`COMMANDS_MANIFEST` / `CC_COMMANDS_MANIFEST`) 却只服务单一 IDE，性价比低。
- 原 `30-review-criteria.mdc` + `.cursor/commands/review.md` 的多模型 review 流程涉及 reviewer 配置、模型矩阵、`/review` dispatcher 等复杂组合，超出 `agent-toolkit` core 应承载的通用规则范畴，应下沉到可选 extension。
- `pre-commit` 命令本质是"为当前 repo 起草 commit message"的跨工具操作，和 IDE 层的 slash-command 没有绑定关系，更适合 cross-tool skill。

#### Design / 设计方案

- **删除整个 `commands/` 目录**以及围绕它的基础设施：`deploy_artifacts` 的 `files` 模式、`COMMANDS_MANIFEST` / `CC_COMMANDS_MANIFEST`、`gen-cursor.sh` 和 `gen-claude.sh` 中部署命令的代码路径。
- **`pre-commit.md` → `skills/pre-commit/SKILL.md`**：作为跨工具 skill（Cursor / Claude Code / Codex 都能加载），携带 YAML frontmatter + `when_to_use` 触发器。
- **`review` 子系统分拆**：
  - 新增 `skills/simple-review/SKILL.md` 作为轻量单模型 review 的 cross-tool 回退入口；
  - 多模型编排（reviewer 矩阵、dispatcher、criteria）迁往 `extras/agent-extension/`，保持 core repo 精简；
  - 过渡期间保留用户在 parent workspace `.cursor/agents/reviewer-*.md` 下自行维护的 reviewer 配置——**agent-sync 不对这些路径做任何自动清理**。
- **User-managed artifact 保护原则**：`.cursor/commands/` / `.cursor/agents/` / `.cursor/reviewer-models.conf` 在 Cursor 中可以由用户自行创建，`agent-toolkit` 不再写入、也不清理。这和 `agent-sync` 自管辖的 `.claude/commands/` / `.cursor/rules/30-review-criteria.mdc` 等本次清理目标严格区分。

#### Implementation / 实现方案

| 文件 | 变更 |
|------|------|
| `commands/` 目录 | 删除（`pre-commit.md` / `review.md` / `README.md` 等） |
| `core/30-review-criteria.md` | 删除 |
| `skills/pre-commit/SKILL.md` | 新增，跨工具 commit-draft skill |
| `skills/simple-review/SKILL.md` | 新增，跨工具单模型 review fallback |
| `scripts/lib/common.sh` | `deploy_artifacts` 简化为仅 `dirs` 模式，删除 `files` 分支 |
| `scripts/lib/gen-cursor.sh` | 移除 commands 部署；新增 `.cursor/rules/30-review-criteria.mdc` 一次性 orphan 清理 |
| `scripts/lib/gen-claude.sh` | 移除 commands 部署 |
| `scripts/lib/sync.sh` | `cleanup_legacy_cc_commands` manifest-driven 精确清理（列表逐文件删除 + 空则 rmdir，保留 user-authored 文件） |
| `scripts/lib/clean.sh` | `do_clean` stamp-gated 清理 legacy `.claude/commands/` + `.cursor/.reviewer-models-agent-sync` 孤儿 stamp |
| `scripts/agent-sync.sh` | USAGE/EXAMPLES 去掉 commands；新增 `cc-rules` / `cc-skills` 显式子命令；`cc` / `cc-rules` / `cc-skills` 三支全部调用 `cleanup_legacy_cc_commands` |
| `scripts/agent-check.sh` | 删除 commands 部署检查，renumber；CC/Cursor 比较从 `-eq` 改为 `-le` + 详细注释；`CC_SKILLS_MF` 下游 Codex 块改为本地别名避免 `set -u` unbound；warning 文案拆分 `CC=0 & Cursor>0`（部署失败）与 both=0（空库）两支 |
| `scripts/agent-test.sh` | T1 新增 per-skill + P0 regression 断言，正则收紧为 `\(\[0-9\]+\)`；T11 覆盖 `cc-rules` / `cc-skills` 独立部署；T12a-d 覆盖 stamp-gated 清理三种场景 + mixed-ownership；T13 orphan `30-review-criteria.mdc` 清理；T14 `cc` / `cc-rules` / `cc-skills` 均 fire cleanup；T15 `.cursor/.reviewer-models-agent-sync` stamp 在 `clean` 时移除 |
| `skills/project-overlay/SKILL.md` | 新增 `when_to_use` 字段，version 1.1 → 1.2，与其余 skill frontmatter 口径一致 |
| `skills/agent-memory/SKILL.md` | 新增 `when_to_use` 字段，version 1.1 → 1.2 |
| `README.md` | 目录树、gitignore 示例、USAGE、Validation checklist 全面更新；§9 新增 "Migrating from pre-decommission layout" + 首次升级 hash re-sync 说明 |
| `.agent-local.md` | 同步项目内部目录树描述 |

#### Limitations / 局限性

- **User-managed path 保护**（交叉引用 `README.md` §9）：`agent-sync` **不会自动迁移** parent workspace 下的 `.cursor/commands/`、`.cursor/agents/reviewer-*.md`、`.cursor/reviewer-models.conf`——这是刻意设计，Cursor 将这些路径视为用户自管的 slash-command / reviewer 配置域，在 extension 落地前用户可继续手动维护过渡期 reviewer 矩阵。
- **`extras/agent-extension/` `/review` planned-state**：目前尚未实装，`skills/simple-review/SKILL.md` 对它的引用以"如果/当 `/review` 落地"语气表述，不假定其已存在。
- **`.claude/commands/` stamp-gated 清理的精度边界**：只会命中**曾经由 pre-refactor agent-sync 写入**的文件（以 `.agent-sync-commands-manifest` 列表为证据，逐行删除）；若用户事后在同一目录添加了自己的 `.md`，mixed-ownership 场景下这些用户文件会被保留、仅删除 agent-sync 列过的那些 + manifest 本身；若用户从未经历 pre-refactor 部署（manifest 不存在），整个目录视为 user-authored，零操作。详见 `scripts/lib/sync.sh::cleanup_legacy_cc_commands` 头注。
- **首次升级的一次性 re-sync**：staleness hash 片段从 3 段扩展到 2 段；从上一版本升级到当前版本的项目，第一次 `agent-sync` 会强制重新生成一次输出（即使源文件内容等价）。这是预期行为，见 `README.md` §9。

#### TODOs / 遗留项

- [ ] `extras/agent-extension/` 实装 `/review` 多模型编排
- [ ] 视需要在 `extras/agent-extension/skills/` 下同步增补 reviewer 配置模板
- [ ] 向下游用户广播迁移说明（`README.md` §9 "Migrating from pre-decommission layout" 已加）

---

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
