# Project Overlay



## Project Overview



**Project**: [TODO: project name] — [TODO: one-line description]
**Boundary**: General-purpose (no special priority trade-offs)

**Tech Stack**: Python 3.10+
**Build System**: pip / setuptools
**Target Platform**: Linux
**Packs**: cpp, cuda, python, markdown, shell, git
**CC Mode**: native
**Codex Mode**: native
**OpenCode Mode**: native

## Project Structure



```
project-root/
├── src/                    # Source code
├── tests/                  # Tests
├── README.md
└── pyproject.toml
```

### Source-Test Mapping



- `src/*.py` → `tests/test_*.py`

## Build & Test Commands



```bash
pip install -e . -v
pytest tests/ -v
```

## Core Architectural Invariants



- All public APIs must have type annotations
- All new features must have corresponding tests

## Performance Targets



No specific performance targets. Do not introduce obvious O(n^2) where O(n) is feasible.

## Boundaries (DO NOT touch)



None (early development, all files modifiable).

## Project-Specific Patterns



None.

