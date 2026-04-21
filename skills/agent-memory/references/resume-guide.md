# Resume Flow

Execute this flow when the user asks to resume a previous session, or when passive discovery
identifies a relevant paused session.

## Trigger Variants

| Trigger | Example | Behavior |
|---------|---------|----------|
| **Explicit with target** | "resume kernel 分析" | Skip to Step 2 with search hint |
| **Explicit without target** | "继续上次的任务" | Start from Step 1 (show recent) |
| **Passive discovery** | Agent detects match via hint file | Suggest resume, await user confirmation |

## Step 1: Scan INDEX

1. Read `.agent-memory/MEMORY-INDEX.md`
2. Filter `## sessions` to entries with `paused` status (skip `completed` and `superseded`)
3. If user provided a keyword, fuzzy-match against filenames and summaries

Present results to user:

```
Found <N> paused session(s):
📄 <filename> — <summary>
📄 <filename> — <summary>

Which one to resume?
```

### Confirmation rules

- **Explicit resume** (user said `/agent-memory resume`): if only 1 match, proceed directly without confirmation
- **Passive discovery** (agent detected match via hint): **always** ask for confirmation, even if only 1 match — the agent should not auto-resume on behalf of the user

## Step 2: Load Session Context

1. Read the target session file from `.agent-memory/sessions/<filename>`
2. Parse each section and internalize:
   - `## summary` → understand overall task and progress
   - `## findings` → key discoveries to carry forward
   - `## next` → immediate action plan
   - `## decisions` → past choices (do not re-debate unless user asks)
   - `## open` → questions to address
3. Note the `files` field — these are likely still relevant

## Step 3: Acknowledge and Continue

Report the resume to the user:

```
已恢复上下文:
- 任务: <task from frontmatter>
- 进度: <summary of what's done>
- 下一步: <next action>

<proceed with the next action or ask for direction>
```

Then **immediately begin working** on the `## next` action, unless the user redirects.

## Step 4: Session Lifecycle

After resuming, the original session file remains unchanged until the next dump.
When the user dumps again:

- Generate a **new session file** with `parent: <original-filename>` in frontmatter
- The dump flow (Step 5) will automatically update the parent's INDEX status:
  - Same task continuing → parent becomes `superseded` (newer checkpoint exists)
  - Task fully done → parent becomes `completed`
- Only the latest checkpoint in a task chain stays `paused`; older ones are `superseded`

## Cross-Agent Resume

The session file format is plain markdown — any agent with filesystem access can resume:

- **Cursor** → reads file via Read tool
- **Claude Code** → reads file via cat / Read
- **Codex** → reads file via cat / file read

No special client or MCP tools required. The session template is intentionally
model-agnostic: no tool-specific IDs, no platform-specific metadata.

## Edge Cases

- **Session file not found**: report to user, suggest checking `.agent-memory/sessions/` manually
- **Multiple matching sessions**: present all matches, let user choose
- **Stale session (>30 days)**: resume normally but mention the age — context may be outdated
- **Parent chain**: if the session has a `parent` field, offer to also load the parent for fuller context
