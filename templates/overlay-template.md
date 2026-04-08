# Project Overlay

<!-- 
=== 使用说明 / Usage ===

1. 将此文件复制到项目根目录，重命名为 .agent-local.md
   Copy this file to your project root as .agent-local.md

2. 必填项只有 Project Overview 和 Project Structure 两个 section
   其他 section 都有合理的默认值，不改也能正常使用

3. 根据项目需要修改其他 section 的默认值，或直接删除不适用的部分

4. 此文件应提交到项目的 git 仓库（它包含项目约定，团队和 AI 都需要看到）
   This file SHOULD be committed to the project git repo

5. 个人私有偏好（本地路径、API key、个人习惯等）不要放在这里
   Claude Code 用户可以用 CLAUDE.local.md（自动加入 .gitignore）存放私有偏好

6. workspace 级和子 repo 级的 overlay 使用同一个模板
   只需根据粒度不同填写不同内容即可

7. HTML 注释（如本段）在 agent-sync 编译时会被自动去除，不会出现在最终的
   CLAUDE.md / AGENTS.md / .mdc 中，所以不占用 agent token
-->

## Project Overview

<!-- 
填写说明：
  - Project: 一句话描述项目是什么
  - Boundary: 一句话声明核心约束/优先级取舍
    例如高性能库应写 "Performance and memory efficiency take priority over code elegance"
    例如后台管理系统应写 "Maintainability and extensibility take priority over performance"
    如果没有特别的优先级取舍，保持默认 "General-purpose" 即可
  - Tech Stack / Build System / Target Platform: 列出主要技术栈
    这帮助 AI 判断应该使用哪些语言特性和工具
  - Packs: 声明本项目需要哪些语言包（会被拼接到 CLAUDE.md / AGENTS.md 中）
    可用的包名对应 packs/ 目录下的文件名（不含 .md 后缀）
    Cursor 的 .mdc 不受此设置影响（Cursor 通过 globs 自动按需加载）
    CC 原生模式下也通过 paths: 按需加载，不受此设置影响
    默认值：cpp, cuda, python, markdown, shell, git
  - CC Mode: 控制 Claude Code 原生输出的生成模式
    off    — 不生成 .claude/ 下的文件（仅 Cursor + legacy CLAUDE.md）
    dual   — 同时生成 .claude/ 原生文件和 legacy CLAUDE.md（默认）
    native — 仅生成 .claude/ 原生文件，跳过 legacy CLAUDE.md/AGENTS.md
  - Codex Mode: 控制 OpenAI Codex 原生输出的生成模式
    off    — 不生成任何 Codex 输出（不生成 AGENTS.md 也不生成 .codex/）
    legacy — 仅生成 .agent-rules/AGENTS.md（需要 shell wrapper 创建根目录 symlink）
    native — 生成 .codex/config.toml + .agents/skills/ + .agent-rules/AGENTS.md（默认）
             Codex 通过 config.toml 的 project_doc_fallback_filenames 自动发现 AGENTS.md
             无需 wrapper；同时支持层级 AGENTS.md（child_agents_md feature）

  @schema: section=Project Overview, required=true
  @schema: field=Project, format=bold_kv, required=true
  @schema: field=Boundary, format=bold_kv, required=true, default="General-purpose (no special priority trade-offs)"
  @schema: field=Tech Stack, format=bold_kv, required=true
  @schema: field=Build System, format=bold_kv, required=true, default="pip / setuptools"
  @schema: field=Target Platform, format=bold_kv, required=true, default="Linux"
  @schema: field=Packs, format=csv, required=true, values_from=packs/*.md, parsed_by=sed, default="cpp, cuda, python, markdown, shell, git"
  @schema: field=CC Mode, format=bold_kv, required=false, default="dual", values="off,dual,native"
  @schema: field=Codex Mode, format=bold_kv, required=false, default="native", values="off,legacy,native"
-->
**Project**: [TODO: project name] — [TODO: one-line description]
**Boundary**: General-purpose (no special priority trade-offs)

**Tech Stack**: Python 3.10+
**Build System**: pip / setuptools
**Target Platform**: Linux
**Packs**: cpp, cuda, python, markdown, shell, git
**CC Mode**: dual
**Codex Mode**: native

## Project Structure

<!-- 
填写说明：
  - 这是对 AI agent 效果影响最大的 section，务必认真填写
  - 没有这个信息，AI 会把文件建错位置、import 路径写错、测试放错目录
  - 至少包含：
    1. 目录树（depth 2-3 即可，不需要逐文件展开，列出关键目录和入口文件）
    2. 每个目录的用途注释
    3. 源码和测试文件的对应关系（见下面 Source-Test Mapping）
  - 保持和实际项目结构同步，结构变了这里也要更新
  - 下面的默认示例是一个最简 Python 项目结构

  @schema: section=Project Structure, required=true
  @schema: content=directory_tree, format=fenced_code_block, lang_tag=none
-->

```
project-root/
├── src/                    # Source code
├── tests/                  # Tests
├── README.md
└── pyproject.toml
```

### Source-Test Mapping

<!-- 
填写说明：
  - 告诉 AI 新建测试文件应该放在哪里、命名规则是什么
  - 格式：源文件路径 → 对应测试文件路径
  - AI 在生成新功能的测试时会严格参考这个映射

  @schema: subsection=Source-Test Mapping, required=conditional, allow_na=true
  @schema: format=bullet_list, pattern="`src` → `test`" or "N/A"
-->
- `src/*.py` → `tests/test_*.py`

## Build & Test Commands

<!-- 
填写说明：
  - AI 会直接执行这里的命令来构建和测试
  - 确保命令是可复制粘贴直接运行的（不需要额外的环境变量或前置操作）
  - 如果有前置条件（如需要先激活 conda 环境），在这里写明
  - 使用跨平台命令（cmake --build 而非 make）

  @schema: section=Build & Test Commands, required=false
  @schema: content=commands, format=fenced_code_block, lang_tag=bash
-->

```bash
pip install -e . -v
pytest tests/ -v
```

## Core Architectural Invariants

<!-- 
填写说明：
  - 这里列出不可违反的架构约束，违反 = bug
  - 典型场景：
    - GPU 内存管理策略（如"所有 GPU 内存必须通过 RAII wrapper 分配"）
    - 异常传播边界（如"异常不得跨越 CUDA kernel 边界"）
    - API 设计约束（如"所有公开 Python API 必须有 type annotation"）
    - 线程/并发模型（如"所有 kernel 必须接受 stream 参数"）
  - 这些约束会被 AI 视为 MUST 级别规则
  - 不确定的约束不要写在这里，放到 Boundaries 或注释中
  - 以下是通用默认约束，适用于大多数项目

  @schema: section=Core Architectural Invariants, required=false
  @schema: content=constraints, format=bullet_list
-->
- All public APIs must have type annotations
- All new features must have corresponding tests

## Performance Targets

<!-- 
填写说明：
  - 这些指标影响 AI 在生成代码时的设计决策（如 block size、shared memory 用量）
    以及代码审查/benchmark 生成时的验收标准
  - 没有明确数字的可以写定性描述（如 "must not regress existing benchmark"）
  - 如果项目没有性能要求，保持默认即可

  有具体指标的项目，以下是常见的 GPU 性能指标分类：

  设计期可指导（AI 写代码时会据此做决策）：
    - Kernel occupancy: > X%
      → AI 会倾向选择更小的 shared memory/register 用量
      → AI 会使用 cudaOccupancyMaxPotentialBlockSize
    - Memory coalescing: contiguous thread access pattern required
      → AI 会优先保证内存访问连续性
    - Python binding overhead: < Xµs per call
      → AI 会避免在 binding 层做不必要的数据拷贝

  验收期可测量（AI 会生成对应的 benchmark 代码来验证）：
    - Memory BW utilization: > X% of theoretical peak (HBM BW)
      → 针对 memory-bound kernel（如 elementwise、reduction）
    - CUDA Core FLOPs utilization: > X% of CUDA core theoretical peak
      → 针对不使用 Tensor Core 的 compute-bound kernel
    - Tensor Core FLOPs utilization: > X% of Tensor Core theoretical peak
      → 针对使用 wmma/mma.sync 的 GEMM/convolution kernel
      → 注意：Tensor Core 峰值远高于 CUDA Core，百分比基准完全不同

  不要混用 CUDA Core 和 Tensor Core 的 FLOPs 基准。
  如果项目同时有两类 kernel，分别列出各自的目标。

  @schema: section=Performance Targets, required=false
  @schema: content=targets, format=free_text
-->
No specific performance targets. Do not introduce obvious O(n^2) where O(n) is feasible.

## Boundaries (DO NOT touch)

<!-- 
填写说明：
  - 列出未经明确批准不得修改的文件、模块或 API
  - 对已发布的公开 API 尤其重要 — 防止 AI 随意改动导致下游兼容性问题
  - 格式建议：文件路径 + 原因
  - 如果项目处于早期开发阶段没有稳定 API，保持默认即可
  - 示例：
    - `cpp/include/package_name/core.h` — public API, backward compatibility required
    - `src/config/defaults.py` — shared configuration, changes affect all downstream modules

  @schema: section=Boundaries (DO NOT touch), required=false
  @schema: content=boundaries, format=bullet_list_or_none
-->
None (early development, all files modifiable).

## Project-Specific Patterns

<!-- 
填写说明：
  - 本项目特有的宏、模式、约定。在其他项目中不适用。
  - 典型场景：
    - 项目自定义的错误检查宏（如 CUDA_CHECK）
    - 特定的初始化/配置模式
    - 编译架构目标列表
  - 这些信息如果放到通用规则里会误导 AI 在其他项目中使用
  - 如果没有项目特有约定，保持默认即可

  @schema: section=Project-Specific Patterns, required=false
  @schema: content=patterns, format=free_text_or_none
-->

None.

<!-- 
=== 可选扩展（适用于 C++/CUDA 混合项目，按需取消注释并修改） ===

如果你的项目涉及 C++/CUDA，以下是推荐补充的内容。
将相关部分取消注释后移到上面对应的 section 中。

--- Project Overview 追加 ---
**Tech Stack**: Python 3.10+, C++17, CUDA 12.x, PyTorch/JAX
**Build System**: CMake 3.24+, setuptools
**Target Platform**: Linux (primary), Windows (secondary)
**Boundary**: Performance and memory efficiency take priority over code elegance

--- Project Structure 示例（替换默认的简单结构） ---
project-root/
├── python/
│   ├── src/package_name/       # Python source
│   │   ├── __init__.py
│   │   ├── core.py             # Main Python API
│   │   └── utils.py            # Utilities
│   └── tests/                  # Python tests (mirrors src/ structure)
│       └── test_core.py
├── cpp/
│   ├── src/                    # C++ implementation
│   │   ├── core.cpp
│   │   └── bindings.cpp        # PyBind11 bindings
│   ├── include/package_name/   # C++ public headers
│   │   └── core.h
│   └── tests/                  # Google Test
│       └── test_core.cpp
├── cuda/
│   ├── kernels/                # CUDA .cu files
│   │   ├── matmul.cu
│   │   └── reduce.cu
│   └── include/                # CUDA .cuh headers
│       └── cuda_utils.cuh
├── benchmarks/                 # Performance benchmarks
├── docs/
│   └── examples/               # Full reference implementations
├── CMakeLists.txt
└── pyproject.toml

Source-Test Mapping:
- python/src/package_name/core.py → python/tests/test_core.py
- cpp/src/core.cpp → cpp/tests/test_core.cpp

--- Build & Test Commands 追加 ---
cmake -B build -DCMAKE_BUILD_TYPE=Release
cmake --build build -j
cmake --build build --target test

--- Core Architectural Invariants 追加 ---
- All GPU memory allocation goes through CudaMemory RAII wrapper
- Exceptions must not cross CUDA kernel boundaries
- All CUDA API calls must use CUDA_CHECK macro

--- Performance Targets 替换 ---
Design-time (guides code generation):
- Kernel occupancy: > 50%
- Memory access pattern: coalesced (contiguous threads → contiguous addresses)
- Python binding overhead: < 10µs per call

Acceptance-time (verified by benchmark):
- Memory BW utilization: > 70% of HBM theoretical peak (for memory-bound kernels)
- CUDA Core FLOPs: > 60% of CUDA core peak (for non-Tensor-Core compute-bound kernels)
- Tensor Core FLOPs: > 40% of Tensor Core peak (for GEMM/convolution using wmma/mma.sync)

--- Project-Specific Patterns 追加 ---

### CUDA Architecture List
此列表必须和 CMakeLists.txt 中的 CMAKE_CUDA_ARCHITECTURES 完全一致:
set(CMAKE_CUDA_ARCHITECTURES 80 86 89 90 100 120)

### Key Macros
- CUDA_CHECK(call) — defined in cuda/include/cuda_utils.cuh, MUST be used for all CUDA API calls

-->
