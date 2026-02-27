# Markdown Writing Guidelines

## References & Links

### External Sources (MUST)

Always include URL links when referencing external sources.

```markdown
# Good: Descriptive text with URL
See the [CUDA Best Practices Guide](https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/)
for memory coalescing techniques.

# Bad: Missing URL
See the CUDA Best Practices Guide for memory coalescing techniques.

# Bad: Raw URL without context
https://docs.nvidia.com/cuda/cuda-c-best-practices-guide/
```

### Link Text (SHOULD)

- Use descriptive link text that indicates the destination
- Avoid generic text like "click here" or "this link"

### Academic & Technical Citations (SHOULD)

```markdown
# Paper citation with link
This implementation is based on FlashAttention [Dao et al., 2022](https://arxiv.org/abs/2205.14135).

# Multiple references
For background on attention mechanisms, see:
- [Attention Is All You Need (Vaswani et al., 2017)](https://arxiv.org/abs/1706.03762)
- [FlashAttention-2 (Dao, 2023)](https://arxiv.org/abs/2307.08691)
```

## Admonitions

Use admonitions to highlight important information:

| Level   | Format                  | Use When                                            |
|---------|-------------------------|-----------------------------------------------------|
| NOTE    | `> **NOTE**: ...`       | Providing additional context or clarification        |
| TIP     | `> **TIP**: ...`        | Suggesting best practices or optimizations           |
| WARNING | `> **WARNING**: ...`    | Highlighting potential pitfalls or unexpected behavior|
| DANGER  | `> **DANGER**: ...`     | Indicating critical risks or irreversible operations |

Example:

```markdown
> **WARNING**: This operation modifies the tensor in-place. Clone the tensor first
> if you need to preserve the original data.
```

## Line Breaks in Enumerated Items

### Consecutive Key-Value Lines (MUST)

When multiple "label: content" lines appear consecutively (e.g. `**field**: value`),
every line **must** have an explicit line break. This applies to:

1. Lines inside blockquotes (prefixed with `>`)
2. Lines in normal paragraphs (no `>`)

#### What Counts as "Consecutive Enumerated Lines"

- `**xxx**: yyy`
- `**xxx**：yyy`
- Any sequence of short "label: content" lines appearing back-to-back

#### Line Break Requirements

- Preferred: append `<br>` at the end of each line (most stable, consistent across renderers)
- Acceptable: two trailing spaces (not recommended — easily lost by editors/formatters)
- Acceptable: rewrite as a proper Markdown list (`- `), which renders correctly without `<br>`

#### Prohibited Patterns

- **MUST NOT** rely on plain newlines (soft line breaks) to create visual line breaks
- **MUST NOT** mix styles within a single group (some lines with `<br>`, some without)

```markdown
# Good: every line has <br>
**Paper**: ...<br>
**Code**: ...<br>
**Authors**: ...<br>
**Affiliation**: ...<br>
**Date**: ...

# Good: proper list (no <br> needed)
- **Paper**: ...
- **Code**: ...
- **Authors**: ...

# Bad: plain newlines only — renders as a single paragraph
**Paper**: ...
**Code**: ...
**Authors**: ...

# Bad: inconsistent — some lines break, some don't
**Paper**: ...<br>
**Code**: ...
**Authors**: ...<br>
```
