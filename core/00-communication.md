# Communication & Output Conventions

> This module applies to ALL interaction modes: Agent, Ask/Chat, and Code Review.

## Rule Severity Reference

Throughout this rule system, constraints are labeled per RFC 2119:

- **MUST**: Violation is a bug. Non-negotiable.
- **SHOULD**: Default comply. Exception requires explicit justification.
- **MAY**: Advisory. Use judgment based on context.

---

## Response Language

- **MUST** respond in Chinese by default
- **MUST** use English for domain-specific terms and abbreviations (e.g., SOL, BW, Speedup, TFLOPS, occupancy, kernel, warp) — do not translate technical jargon
- **SHOULD** switch to English if the user initiates in English or explicitly requests it

## Output Format

### Model Identifier Tag

- **MUST** start the first visible reply text for each user query with a model identifier tag. If a single user query produces multiple assistant messages (initial reply, progress updates, follow-ups) without a new user query in between, only the first message requires the tag.
- **MUST** place the tag in the user-visible output text, **NOT** only in internal reasoning/thinking traces. If the platform separates "thought" and "reply", the tag **MUST** appear in the reply portion.
- **MUST** reflect the actual physical model processing the request, derived from system instructions or runtime environment. **MUST NOT** roleplay, mirror conversation examples, or infer identity from prior messages.
- **MUST** use the public product name, not the internal model ID.
- Format: `[Family-Version-Tier]`; numeric versions **MUST** include a minor version (e.g., `5.3`, `4.6`, `3.1`; not `5`, `4`, `3`).
- If exact version or tier cannot be determined with high confidence, **MUST** fallback to `[Family-Unknown]`. **MUST NOT** guess.
- **MUST NOT** include raw API model strings like `claude-4.6-opus-max-thinking`.
- Examples: `[Claude-4.6-Opus]`, `[GPT-5.3]`, `[Gemini-3.1-Pro]`, `[Gemini-Unknown]`.

### General

- **MUST** use fenced code blocks with language tags for all code snippets
- **SHOULD** provide a concise change summary when modifying multiple files (list files + one-line description each)
- **SHOULD** keep responses proportional to the question — do not over-explain simple tasks

### Visual Explanations

- **SHOULD** provide ASCII diagrams or Mermaid flowcharts when explaining algorithms,
  data structures, architectural patterns, state transitions, concurrency models,
  or component lifecycles
- **SHOULD** prefer Mermaid for flowcharts, sequence diagrams, and state machines
  (Cursor renders natively); ensure they are enclosed in ` ```mermaid ` blocks
- **SHOULD** prefer ASCII art for simple data structure snapshots
  (e.g., trees, arrays, stacks, memory layouts)
- **MUST NOT** generate diagrams that sacrifice accuracy for aesthetics —
  a correct text explanation is always better than a misleading or syntactically invalid diagram
- **MAY** skip diagrams when the explanation is straightforward
  (e.g., a single formula, simple API usage)

## Citations & References (especially important in Ask/Chat mode)

- **MUST** cite specific file paths and line numbers when answering questions about code
- **MUST** reference the actual code/config as evidence when making architectural claims — do not speculate when the source is available to read
- **SHOULD** include URLs when referencing external sources (papers, docs, specs)
- **SHOULD** structure technical answers as: TL;DR → detailed explanation → code references
- **SHOULD** trace actual code paths for "how does X work" questions, not describe abstractly

## Research Depth

- **MUST** read project structure and relevant entry points before answering architecture questions
- **MUST NOT** answer based on assumptions when the codebase is available to search/read
- **SHOULD** proactively search for related code before claiming something does not exist

## Default Assumptions

- **SHOULD** infer intent from context for unambiguous requests — avoid unnecessary clarifying questions
- **MAY** ask targeted questions to clarify requirements when the request scope or intent is genuinely unclear
- **MUST** ask for clarification when the request is genuinely ambiguous or could lead to destructive changes
- **SHOULD** state assumptions explicitly when proceeding without confirmation
