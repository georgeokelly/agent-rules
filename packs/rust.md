# Rust Guidelines

**Edition**: Rust 2021 (edition = "2021"). Rust 2024 features are NOT permitted unless explicitly whitelisted.
**Formatter**: rustfmt (`cargo fmt`). MUST pass with zero diff.
**Linter**: Clippy (`cargo clippy -- -D warnings`). MUST pass with zero warnings.
**Dependency management**: Cargo.toml with workspace support for multi-crate projects; `Cargo.lock` committed for binaries, ignored for libraries.
**Naming convention base**: [Rust API Guidelines](https://rust-lang.github.io/api-guidelines/) (RFC 430).

---

## Project Layout (MUST)

Follow the [Cargo conventions](https://doc.rust-lang.org/cargo/guide/project-layout.html):

```
├── Cargo.toml
├── Cargo.lock          # commit for binaries; .gitignore for libraries
├── src/
│   ├── lib.rs          # library crate root (omit if pure binary)
│   ├── main.rs         # binary crate root (omit if pure library)
│   └── bin/            # additional binaries
├── tests/              # integration tests
├── benches/            # benchmarks
└── examples/           # example programs
```

> Not all entries above are required — include only what your crate needs.

- **MUST** use `snake_case` for module file names
- **SHOULD** split modules into separate files when exceeding ~300 lines

## Naming Conventions (MUST)

Per RFC 430 and the Rust API Guidelines:

```rust
// Types, Traits, Enum variants: UpperCamelCase
struct TensorBuffer { ... }
trait Serialize { ... }
enum ParseError { InvalidInput, Overflow }

// Functions, Methods, Variables, Modules: snake_case
fn compute_checksum(data: &[u8]) -> u32 { ... }
let batch_size = 32;
mod memory_pool;

// Constants, Statics: SCREAMING_SNAKE_CASE
const MAX_BATCH_SIZE: usize = 1024;
static GLOBAL_CONFIG: LazyLock<Config> = LazyLock::new(Config::default);  // std::sync::LazyLock (Rust 1.80+)

// Type parameters: concise UpperCamelCase, usually single letter
fn process<T: Send + Sync>(item: T) -> T { ... }

// Lifetimes: short lowercase
fn parse<'a>(input: &'a str) -> &'a str { ... }

// Macros: snake_case!
macro_rules! ensure { ... }
```

### Acronyms in CamelCase

Treat acronyms as single words: `Uuid` not `UUID`, `HttpClient` not `HTTPClient`, `Stdin` not `StdIn`.

### Getter / Setter Naming (MUST)

Getters do **not** use the `get_` prefix per Rust convention:

```rust
impl Config {
    // Getter — returns shared reference
    pub fn timeout(&self) -> Duration { self.timeout }
    // Mutable getter
    pub fn timeout_mut(&mut self) -> &mut Duration { &mut self.timeout }
    // Setter — use set_ prefix
    pub fn set_timeout(&mut self, val: Duration) { self.timeout = val; }
}
```

### Conversion & Iterator Method Naming (MUST)

Follow the Rust API Guidelines (C-CONV, C-ITER):

| Prefix | Cost | Ownership | Example |
|---------|-----------|-------------------------|-------------------------------|
| `as_` | Free | borrowed → borrowed | `as_bytes()`, `as_slice()` |
| `to_` | Expensive | borrowed → owned | `to_string()`, `to_vec()` |
| `into_` | Variable | owned → owned | `into_inner()`, `into_bytes()` |

Iterator methods: `iter()`, `iter_mut()`, `into_iter()`.

## Ownership & Borrowing (MUST)

- **MUST** prefer borrowing (`&T` / `&mut T`) over owned values in function parameters unless ownership transfer is required
- **MUST** use `Clone` explicitly when duplication is needed — never rely on implicit copies for non-`Copy` types
- **MUST NOT** hold non-`Send` borrows across `.await` points in futures that will be spawned on a multi-threaded runtime (`&T` is `Send` iff `T: Sync`)
- **SHOULD** prefer `&str` over `&String`, `&[T]` over `&Vec<T>` in function signatures
- **SHOULD** accept `impl Into<String>` or `AsRef<str>` for functions that need owned `String` for flexibility

```rust
// SHOULD: accept slices, not concrete containers
fn process(data: &[f32]) -> f32 { ... }

// SHOULD: accept Into<String> when ownership is needed
fn set_name(&mut self, name: impl Into<String>) {
    self.name = name.into();
}
```

## Lifetime Annotations (SHOULD)

- **SHOULD** rely on lifetime elision when the compiler can infer lifetimes
- **MUST** add explicit annotations when the compiler requires them or when elision would be ambiguous to the reader
- **SHOULD** use descriptive lifetime names for complex signatures: `'src`, `'buf`, `'ctx` instead of `'a`, `'b`, `'c`

## Error Handling (MUST)

### Libraries: `thiserror` for structured errors

```rust
use thiserror::Error;

#[derive(Error, Debug)]
pub enum ConfigError {
    #[error("failed to read config: {0}")]
    Io(#[from] std::io::Error),
    #[error("invalid value for field `{field}`: {reason}")]
    Validation { field: String, reason: String },
    #[error("missing required field: {0}")]
    MissingField(String),
}
```

- **MUST** derive `Error` and `Debug` on all error types
- **MUST** use `#[from]` for automatic `From` conversions where appropriate
- **MUST** carry structured data in error variants — do not hide information in message strings
- **MAY** follow verb-object-error word order for error type names (e.g., `ParseConfigError`); prefer consistency with the surrounding crate and ecosystem — std itself uses both orders (e.g., `AddrParseError`)

### Applications: `anyhow` for ergonomic error propagation

```rust
use anyhow::{Context, Result};

fn load_config(path: &Path) -> Result<Config> {
    let contents = std::fs::read_to_string(path)
        .with_context(|| format!("failed to read {}", path.display()))?;
    let config: Config = toml::from_str(&contents)
        .context("failed to parse config")?;
    Ok(config)
}
```

- **MUST** use `.context()` / `.with_context()` to add meaningful context to errors
- **MUST NOT** use `anyhow` in library crates — use `thiserror` instead
- **MUST NOT** use `.unwrap()` or `.expect()` in production paths — reserve for tests and provably infallible cases
- **SHOULD** use `bail!()` for early returns with an error message

### General

- **MUST NOT** use `panic!()` for recoverable errors — use `Result`
- **SHOULD** use `Option<T>` for values that may be absent, `Result<T, E>` for operations that may fail
- **MAY** use `.expect("reason")` when the invariant is documented and provably maintained

## `unsafe` Code (MUST)

- **MUST** minimize `unsafe` blocks to the smallest possible scope
- **MUST** document the safety invariant with a `// SAFETY:` comment immediately above each `unsafe` block
- **MUST** wrap `unsafe` operations in a safe public API that upholds the invariant
- **MUST NOT** introduce `unsafe` without a clear justification (performance, FFI, or hardware access)
- **SHOULD** use `#[deny(unsafe_op_in_unsafe_fn)]` to require explicit `unsafe` blocks inside `unsafe fn`

```rust
/// Returns the element at `index` without bounds checking.
///
/// # Safety
/// `index` must be less than `self.len()`.
pub unsafe fn get_unchecked(&self, index: usize) -> &T {
    // SAFETY: caller guarantees index < self.len()
    unsafe { &*self.ptr.add(index) }
}
```

## Type System (SHOULD)

- **SHOULD** use newtypes to enforce semantic meaning: `struct UserId(u64)` over bare `u64`
- **SHOULD** implement `Display` for user-facing output and `Debug` for developer diagnostics
- **SHOULD** derive standard traits (`Debug`, `Clone`, `PartialEq`, `Eq`, `Hash`) when semantically appropriate
- **SHOULD** use `#[non_exhaustive]` on public enums and structs to allow future expansion without breaking changes
- **MAY** use `#[must_use]` on functions whose return value should not be ignored

## Concurrency (MUST)

- **MUST** prefer message passing (`mpsc`, `crossbeam`, `tokio::sync`) over shared state when practical
- **MUST** use `Arc<Mutex<T>>` or `Arc<RwLock<T>>` for shared mutable state — never raw pointer sharing
- **MUST NOT** hold `std::sync::MutexGuard` across `.await` points — use `tokio::sync::Mutex` for async code, but still minimize the critical section to avoid contention and potential deadlocks
- **SHOULD** use `Rayon` for data-parallel CPU workloads
- **SHOULD** prefer `RwLock` over `Mutex` when reads vastly outnumber writes

## Documentation (MUST for public APIs)

Use `///` doc comments with Markdown. Every public item **MUST** have:

```rust
/// Computes the checksum of a byte slice using CRC-32.
///
/// # Arguments
///
/// * `data` - The input byte slice to checksum.
///
/// # Returns
///
/// The CRC-32 checksum as a `u32`.
///
/// # Errors
///
/// Returns [`ChecksumError::EmptyInput`] if `data` is empty.
///
/// # Examples
///
/// ```
/// use mycrate::compute_checksum;
///
/// let checksum = compute_checksum(b"hello world")?;
/// assert_eq!(checksum, 0x0D4A_1185);
/// # Ok::<(), mycrate::ChecksumError>(())
/// ```
pub fn compute_checksum(data: &[u8]) -> Result<u32, ChecksumError> { ... }
```

- **MUST** include `# Errors` section for fallible functions
- **MUST** include `# Panics` section if the function can panic
- **MUST** include `# Safety` section for `unsafe` functions
- **SHOULD** include `# Examples` with runnable doc-tests for complex functions
- **SHOULD** use `[`backtick links`]` to cross-reference types and functions

## Testing (MUST for new features)

### Unit Tests

```rust
#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn checksum_known_value() {
        let result = compute_checksum(b"hello").unwrap();
        assert_eq!(result, 0x3610_A686);
    }

    #[test]
    fn checksum_empty_input_fails() {
        let err = compute_checksum(b"").unwrap_err();
        assert!(matches!(err, ChecksumError::EmptyInput));
    }
}
```

### Integration Tests

Place in `tests/` directory. Each file compiles as a separate crate using only the public API:

```rust
// tests/integration.rs
use mycrate::Config;

#[test]
fn config_round_trip() {
    let config = Config::default();
    let serialized = toml::to_string(&config).unwrap();
    let deserialized: Config = toml::from_str(&serialized).unwrap();
    assert_eq!(config, deserialized);
}
```

- **MUST** use `#[cfg(test)]` on unit test modules
- **MUST** test both success and error paths
- **SHOULD** use `assert_eq!` / `assert_ne!` over plain `assert!` for better diagnostics
- **SHOULD** use `matches!` macro for pattern-matching assertions on enums
- **SHOULD** use `proptest` or `quickcheck` for property-based testing of invariants
- **SHOULD** use `#[should_panic(expected = "...")]` sparingly — prefer `Result`-returning tests

## Performance (SHOULD)

- **SHOULD** use `cargo bench` with `criterion` for micro-benchmarks
- **SHOULD** prefer `&[T]` zero-copy slices over collecting into `Vec<T>` when possible
- **SHOULD** use `with_capacity()` for `Vec`, `String`, `HashMap` when the size is known or estimated
- **SHOULD** prefer iterators over explicit index loops — the optimizer handles them well
- **MAY** use `#[inline]` on small, hot functions in library crates; avoid in application code

## Quick Reference Commands

```bash
# Format
cargo fmt
cargo fmt -- --check          # CI: verify without modifying

# Lint
cargo clippy -- -D warnings
cargo clippy --all-targets --all-features -- -D warnings

# Check (fast compile check, no codegen)
cargo check
cargo check --all-targets

# Build
cargo build --release

# Test
cargo test
cargo test --all-features
cargo test -- --nocapture     # show println! output

# Doc-tests only
cargo test --doc

# Generate & open docs
cargo doc --open --no-deps

# Audit dependencies for security vulnerabilities
cargo audit
```

## Common Pitfalls (MUST NOT)

- **MUST NOT** use `.unwrap()` in library code or production paths — handle errors explicitly
- **MUST NOT** use `String` where `&str` suffices in function parameters
- **MUST NOT** implement `Drop` and `Copy` on the same type — they are mutually exclusive
- **MUST NOT** ignore Clippy warnings — either fix or `#[allow(...)]` with a justification comment
- **MUST NOT** use `std::mem::transmute` without an explicit `// SAFETY:` justification and a safer alternative analysis
- **SHOULD NOT** use `clone()` to satisfy the borrow checker — restructure the code instead
- **SHOULD NOT** block async runtime threads with synchronous I/O — use `spawn_blocking`
