<div align="center">

# rules_verus

<sup>Bazel rules for Verus Rust verification</sup>

&nbsp;

![Bazel](https://img.shields.io/badge/Bazel-43A047?style=flat-square&logo=bazel&logoColor=white&labelColor=1a1b27)
![Formally Verified](https://img.shields.io/badge/Formally_Verified-00C853?style=flat-square&logoColor=white&labelColor=1a1b27)
![License: Apache-2.0](https://img.shields.io/badge/License-Apache--2.0-blue?style=flat-square&labelColor=1a1b27)

</div>

&nbsp;

Bazel rules for [Verus](https://github.com/verus-lang/verus) SMT-backed Rust verification. Downloads pre-built Verus release binaries from GitHub with hermetic toolchain support.

> [!NOTE]
> Part of the PulseEngine toolchain. Provides Verus verification infrastructure used across PulseEngine for Rust correctness proofs.

## Quick Start

### 1. Add to MODULE.bazel

```starlark
bazel_dep(name = "rules_verus", version = "0.1.0")

git_override(
    module_name = "rules_verus",
    remote = "https://github.com/pulseengine/rules_verus.git",
    commit = "<latest-commit>",
)

# Configure Verus toolchain
verus = use_extension("@rules_verus//verus:extensions.bzl", "verus")
verus.toolchain(version = "0.2026.02.15")
use_repo(verus, "verus_toolchains")
register_toolchains("@verus_toolchains//:all")
```

### 2. Create a Rust file to verify

```rust
// counter.rs
use vstd::prelude::*;

verus! {

pub struct Counter {
    pub value: u64,
}

impl Counter {
    pub spec fn valid(&self) -> bool {
        self.value < u64::MAX
    }

    pub fn increment(&mut self)
        requires old(self).valid(),
        ensures self.value == old(self).value + 1,
    {
        self.value = self.value + 1;
    }
}

} // verus!
```

### 3. Add BUILD.bazel

```starlark
load("@rules_verus//verus:defs.bzl", "verus_library", "verus_test")

verus_library(
    name = "counter_verified",
    srcs = ["counter.rs"],
)

verus_test(
    name = "counter_test",
    srcs = ["counter.rs"],
)
```

### 4. Build and verify

```bash
# Verify (produces stamp file on success)
bazel build //:counter_verified

# Run as test
bazel test //:counter_test
```

## Multi-File Crates

For crates with multiple source files, list all files in `srcs` and optionally specify a `crate_root`:

```starlark
verus_library(
    name = "my_proofs",
    srcs = [
        "src/lib.rs",
        "src/vec_proofs.rs",
        "src/map_proofs.rs",
    ],
    crate_root = "src/lib.rs",   # Optional: defaults to lib.rs in srcs, or srcs[0]
    crate_name = "my_proofs",    # Optional: defaults to target name
)
```

The `crate_root` file should contain `mod` declarations for the other source files:

```rust
// src/lib.rs
mod vec_proofs;
mod map_proofs;
```

## Cross-Crate Dependencies

Use `deps` to express verification dependencies between crates. Downstream targets automatically wait for upstream verification to complete.

```starlark
# Base verified library
verus_library(
    name = "foundation_proofs",
    srcs = ["foundation.rs"],
)

# Depends on foundation_proofs verification
verus_library(
    name = "runtime_proofs",
    srcs = ["runtime.rs"],
    deps = [":foundation_proofs"],
)

# Test that depends on both
verus_test(
    name = "integration_test",
    srcs = ["integration.rs"],
    deps = [
        ":foundation_proofs",
        ":runtime_proofs",
    ],
)
```

When `deps` are specified, the rule passes `--extern {crate_name}={stamp_path}` to Verus for each dependency, enabling cross-crate verification.

## API Reference

### verus_library

Verifies Rust source files with Verus. Produces a stamp file on success.

| Attribute | Type | Description |
|-----------|------|-------------|
| `srcs` | `label_list` | Rust source files to verify (`.rs`). **Required.** |
| `crate_root` | `label` | Explicit crate root file. If not set, uses `lib.rs` from srcs or `srcs[0]`. |
| `crate_name` | `string` | Crate name for `--crate-name` flag. Defaults to target name with hyphens as underscores. |
| `deps` | `label_list` | Other `verus_library` targets this depends on for `--extern` resolution. |
| `extra_flags` | `string_list` | Extra flags to pass to Verus (e.g., `["--multiple-errors", "5"]`). |

### verus_test

Test target that runs Verus verification. Passes if all proofs verify.

| Attribute | Type | Description |
|-----------|------|-------------|
| `srcs` | `label_list` | Rust source files to verify (`.rs`). **Required.** |
| `crate_root` | `label` | Explicit crate root file. If not set, uses `lib.rs` from srcs or `srcs[0]`. |
| `crate_name` | `string` | Crate name for `--crate-name` flag. Defaults to target name with hyphens as underscores. |
| `deps` | `label_list` | Other `verus_library` targets this depends on for `--extern` resolution. |
| `extra_flags` | `string_list` | Extra flags to pass to Verus. |

### `verus_strip`

Strip Verus verification annotations from Rust source files, producing plain Rust suitable for `cargo test`, `cargo kani`, `coq_of_rust`, or any standard Rust tooling.

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `srcs` | `label_list` | Yes | — | Verus-annotated Rust source files (`.rs`) to strip |

**Output:** One stripped `.rs` file per input (same basename), with all Verus annotations removed:
- `verus! { }` macro wrapper
- `use vstd::*` imports
- `pub open spec fn` / `pub closed spec fn` / `pub proof fn` (entire items)
- `requires` / `ensures` / `invariant` / `decreases` / `recommends` clauses
- Named return type bindings: `-> (name: Type)` becomes `-> Type`
- Verus `assert(...)` proof assertions (no `!`)
- `#[verifier::*]` and `#[trigger]` attributes

### `verus_strip_test`

Test that stripping Verus annotations from source files produces output matching expected plain Rust files.

| Attribute | Type | Required | Default | Description |
|-----------|------|----------|---------|-------------|
| `verus_srcs` | `label_list` | Yes | — | Verus-annotated Rust source files |
| `plain_srcs` | `label_list` | Yes | — | Expected plain Rust files (matched by basename) |

### CLI Usage

The `verus-strip` binary is also available for direct use:

```bash
# Strip to stdout
bazel run //tools/verus-strip:verus-strip -- input.rs

# Strip to file
bazel run //tools/verus-strip:verus-strip -- input.rs -o output.rs

# Check convergence between directories
bazel run //tools/verus-strip:verus-strip -- --check src/ plain/
```

## Kiln Integration Example

Verifying Kiln's safety-critical `StaticVec` bounded collection:

```starlark
verus_library(
    name = "kiln_static_vec_proofs",
    srcs = [
        "kiln-foundation/src/verus_proofs/mod.rs",
        "kiln-foundation/src/verus_proofs/static_vec_proofs.rs",
    ],
    crate_root = "kiln-foundation/src/verus_proofs/mod.rs",
    crate_name = "kiln_static_vec_proofs",
)

verus_test(
    name = "kiln_static_vec_verify",
    srcs = [
        "kiln-foundation/src/verus_proofs/mod.rs",
        "kiln-foundation/src/verus_proofs/static_vec_proofs.rs",
    ],
    crate_root = "kiln-foundation/src/verus_proofs/mod.rs",
    crate_name = "kiln_static_vec_proofs",
)
```

## Multi-Track Verification

`rules_verus` supports the multi-track verification pattern where Verus-annotated source code
is stripped to plain Rust for use with other verification and testing tools:

```
src/sem.rs (Verus-annotated)
  → verus_library (SMT/Z3 verification)
  → verus_strip → plain/src/sem.rs (plain Rust)
    → cargo test, cargo kani, cargo miri, coq_of_rust
```

```python
load("@rules_verus//verus:defs.bzl", "verus_library", "verus_strip", "verus_strip_test")

# Verify with Verus (SMT/Z3 track)
verus_library(
    name = "sem",
    srcs = ["src/sem.rs"],
)

# Strip annotations for other verification tracks
verus_strip(
    name = "sem_plain",
    srcs = ["src/sem.rs"],
)

# Ensure stripped output matches maintained plain/ directory
verus_strip_test(
    name = "sem_convergence",
    verus_srcs = ["src/sem.rs"],
    plain_srcs = ["plain/src/sem.rs"],
)
```

## Supported Platforms

| Platform | Status |
|----------|--------|
| macOS x86_64 | Supported |
| macOS aarch64 | Supported |
| Linux x86_64 | Supported |
| Windows x86_64 | Supported |

## How It Works

1. The module extension downloads pre-built Verus binaries from GitHub releases
2. The toolchain provides the Verus binary, Z3 SMT solver, and vstd standard library
3. `verus_library` runs Verus verification and produces a stamp file on success
4. `verus_test` wraps verification as a Bazel test target for CI integration
5. Cross-crate `deps` ensure verification ordering via stamp file dependencies
6. `verus_strip` removes Verus annotations to produce plain Rust for other tools

### Hermetic Rust Toolchain

`rules_verus` provisions the exact Rust toolchain version that `rust_verify` was built against
via `rules_rust`. This is determined from the Verus release's `version.json` and stored in
`_KNOWN_VERSIONS` in `extensions.bzl`. When a hermetic sysroot is available, verification runs
inside Bazel's sandbox (fully hermetic). Otherwise, it falls back to host `rustup`.

## License

Apache-2.0

---

<div align="center">

<sub>Part of <a href="https://github.com/pulseengine">PulseEngine</a> &mdash; formally verified WebAssembly toolchain for safety-critical systems</sub>

</div>
