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

- **MUST** use fenced code blocks with language tags for all code snippets
- **SHOULD** provide a concise change summary when modifying multiple files (list files + one-line description each)
- **SHOULD** keep responses proportional to the question — do not over-explain simple tasks

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
