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

## API Reference

### verus_library

Verifies Rust source files with Verus. Produces a stamp file on success.

| Attribute | Description |
|-----------|-------------|
| `srcs` | Rust source files to verify (`.rs`) |
| `extra_flags` | Extra flags to pass to Verus (e.g., `["--multiple-errors", "5"]`) |

### verus_test

Test target that runs Verus verification. Passes if all proofs verify.

| Attribute | Description |
|-----------|-------------|
| `srcs` | Rust source files to verify (`.rs`) |
| `extra_flags` | Extra flags to pass to Verus |

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

## License

Apache-2.0

---

<div align="center">

<sub>Part of <a href="https://github.com/pulseengine">PulseEngine</a> &mdash; formally verified WebAssembly toolchain for safety-critical systems</sub>

</div>
