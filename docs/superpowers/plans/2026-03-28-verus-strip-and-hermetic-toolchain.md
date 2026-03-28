# verus-strip Integration & Hermetic Rust Nightly Toolchain

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Move verus-strip into rules_verus as a generalized tool with Bazel rules (`verus_strip`, `verus_strip_test`), add comprehensive testing, and provision Rust nightly hermetially via rules_rust to eliminate the host rustup dependency.

**Architecture:** rules_verus gains `rules_rust` as a bazel_dep. The module extension reads Verus's `version.json` to determine the required Rust nightly version, then configures rules_rust to provision it. verus-strip is built from source as a `rust_binary`, exposed via new `verus_strip` and `verus_strip_test` Bazel rules. Verification rules (`verus_library`, `verus_test`) switch from host rustup to the hermetically provisioned sysroot, removing `no-sandbox`.

**Tech Stack:** Bazel 8 (bzlmod), rules_rust 0.69.0, Rust (nightly for Verus, stable for verus-strip), syn/prettyplease/proc-macro2

---

## File Structure

```
rules_verus/
  MODULE.bazel                          # MODIFY: add rules_rust dep, configure nightly
  verus/
    defs.bzl                            # MODIFY: export verus_strip, verus_strip_test
    extensions.bzl                      # MODIFY: provision Rust nightly from version.json
    toolchain.bzl                       # MODIFY: add rust_sysroot to VerusToolchainInfo
    private/
      repo.bzl                          # MODIFY: expose rust_toolchain for nightly setup
      verus.bzl                         # MODIFY: use hermetic sysroot, remove no-sandbox
      strip.bzl                         # CREATE: verus_strip and verus_strip_test rules
  tools/
    verus-strip/
      BUILD.bazel                       # CREATE: rust_library + rust_binary + rust_test targets
      Cargo.toml                        # CREATE: package manifest
      src/
        lib.rs                          # CREATE: strip library (from gale, generalized)
        main.rs                         # CREATE: CLI entry point (from gale, generalized)
      tests/
        fixtures/
          simple_input.rs               # CREATE: test fixture — Verus-annotated source
          simple_expected.rs            # CREATE: test fixture — expected stripped output
          complex_input.rs              # CREATE: test fixture — multi-struct, deps, loops
          complex_expected.rs           # CREATE: test fixture — expected stripped output
          edge_nested_verus_input.rs    # CREATE: edge case fixture
          edge_nested_verus_expected.rs # CREATE: expected output
          edge_generics_input.rs        # CREATE: complex generic types fixture
          edge_generics_expected.rs     # CREATE: expected output
        integration_test.rs             # CREATE: parameterized convergence tests
```

---

### Task 1: Add rules_rust dependency and Rust stable toolchain for verus-strip

**Files:**
- Modify: `MODULE.bazel`

This task adds rules_rust as a dependency so we can build verus-strip from source. We start with stable Rust only (nightly comes in Task 7).

- [ ] **Step 1: Add rules_rust bazel_dep and crate_universe to MODULE.bazel**

```starlark
# In MODULE.bazel, after the existing bazel_dep entries:

# Rust rules — needed to build verus-strip from source
bazel_dep(name = "rules_rust", version = "0.69.0")

rust = use_extension("@rules_rust//rust:extensions.bzl", "rust")
rust.toolchain(
    edition = "2024",
    versions = ["1.85.0"],
)
use_repo(rust, "rust_toolchains")
register_toolchains("@rust_toolchains//:all")

# Crate dependencies for verus-strip
crate = use_extension("@rules_rust//crate_universe:extensions.bzl", "crate")
crate.from_cargo(
    name = "crates",
    cargo_lockfile = "//tools/verus-strip:Cargo.lock",
    manifests = ["//tools/verus-strip:Cargo.toml"],
)
use_repo(crate, "crates")
```

The complete MODULE.bazel should look like:

```starlark
"""Bazel Module for Verus verification rules.

Provides Bazel rules for Verus SMT-backed Rust verification.
Downloads pre-built Verus release binaries from GitHub.
"""

module(
    name = "rules_verus",
    version = "0.1.0",
    compatibility_level = 1,
)

# Core dependencies
bazel_dep(name = "bazel_skylib", version = "1.7.1")
bazel_dep(name = "platforms", version = "0.0.10")

# Rust rules — needed to build verus-strip from source
bazel_dep(name = "rules_rust", version = "0.69.0")

rust = use_extension("@rules_rust//rust:extensions.bzl", "rust")
rust.toolchain(
    edition = "2024",
    versions = ["1.85.0"],
)
use_repo(rust, "rust_toolchains")
register_toolchains("@rust_toolchains//:all")

# Crate dependencies for verus-strip
crate = use_extension("@rules_rust//crate_universe:extensions.bzl", "crate")
crate.from_cargo(
    name = "crates",
    cargo_lockfile = "//tools/verus-strip:Cargo.lock",
    manifests = ["//tools/verus-strip:Cargo.toml"],
)
use_repo(crate, "crates")

# Verus toolchain extension
verus = use_extension("//verus:extensions.bzl", "verus")
verus.toolchain(version = "0.2026.02.15")
use_repo(verus, "verus_toolchains")

register_toolchains("@verus_toolchains//:all")
```

- [ ] **Step 2: Commit**

```bash
git add MODULE.bazel
git commit -m "feat: add rules_rust dependency for verus-strip build"
```

---

### Task 2: Port verus-strip library from gale

**Files:**
- Create: `tools/verus-strip/Cargo.toml`
- Create: `tools/verus-strip/src/lib.rs`
- Create: `tools/verus-strip/src/main.rs`
- Create: `tools/verus-strip/BUILD.bazel`

Port the verus-strip source from `/Volumes/Home/git/pulseengine/gale/tools/verus-strip/`. The library is taken as-is (it's already well-structured). The main.rs CLI is taken as-is. The gale-specific gate test (`tests/gate.rs`) is NOT ported — we'll create a generalized version in Task 4.

- [ ] **Step 1: Create tools directory**

```bash
mkdir -p tools/verus-strip/src tools/verus-strip/tests
```

- [ ] **Step 2: Create Cargo.toml**

Write `tools/verus-strip/Cargo.toml`:

```toml
[package]
name = "verus-strip"
version = "0.2.0"
edition = "2024"
rust-version = "1.85"
description = "Strip Verus verification annotations from Rust source, producing plain Rust"
publish = false

[[bin]]
name = "verus-strip"
path = "src/main.rs"

[dependencies]
proc-macro2 = "1"
syn = { version = "2", features = ["full", "parsing", "visit"] }
prettyplease = "0.2"
```

- [ ] **Step 3: Generate Cargo.lock**

```bash
cd tools/verus-strip && cargo generate-lockfile && cd ../..
```

Expected: `tools/verus-strip/Cargo.lock` created.

- [ ] **Step 4: Copy lib.rs from gale**

```bash
cp /Volumes/Home/git/pulseengine/gale/tools/verus-strip/src/lib.rs tools/verus-strip/src/lib.rs
```

- [ ] **Step 5: Copy main.rs from gale**

```bash
cp /Volumes/Home/git/pulseengine/gale/tools/verus-strip/src/main.rs tools/verus-strip/src/main.rs
```

- [ ] **Step 6: Create BUILD.bazel**

Write `tools/verus-strip/BUILD.bazel`:

```starlark
load("@rules_rust//rust:defs.bzl", "rust_binary", "rust_library", "rust_test")

rust_library(
    name = "verus_strip_lib",
    srcs = ["src/lib.rs"],
    crate_name = "verus_strip",
    deps = [
        "@crates//:proc-macro2",
        "@crates//:syn",
        "@crates//:prettyplease",
    ],
    edition = "2024",
    visibility = ["//visibility:public"],
)

rust_binary(
    name = "verus-strip",
    srcs = ["src/main.rs"],
    deps = [":verus_strip_lib"],
    edition = "2024",
    visibility = ["//visibility:public"],
)

rust_test(
    name = "verus_strip_unit_test",
    crate = ":verus_strip_lib",
)
```

- [ ] **Step 7: Run unit tests**

```bash
bazel test //tools/verus-strip:verus_strip_unit_test
```

Expected: 9 tests PASS (the existing unit tests in lib.rs).

- [ ] **Step 8: Build the binary**

```bash
bazel build //tools/verus-strip:verus-strip
```

Expected: Binary built successfully.

- [ ] **Step 9: Commit**

```bash
git add tools/verus-strip/
git commit -m "feat: port verus-strip tool from gale into rules_verus"
```

---

### Task 3: Create test fixtures for verus-strip

**Files:**
- Create: `tools/verus-strip/tests/fixtures/simple_input.rs`
- Create: `tools/verus-strip/tests/fixtures/simple_expected.rs`
- Create: `tools/verus-strip/tests/fixtures/complex_input.rs`
- Create: `tools/verus-strip/tests/fixtures/complex_expected.rs`
- Create: `tools/verus-strip/tests/fixtures/edge_nested_verus_input.rs`
- Create: `tools/verus-strip/tests/fixtures/edge_nested_verus_expected.rs`
- Create: `tools/verus-strip/tests/fixtures/edge_generics_input.rs`
- Create: `tools/verus-strip/tests/fixtures/edge_generics_expected.rs`

These fixtures enable file-based round-trip testing. Each pair has a `_input.rs` (Verus-annotated) and `_expected.rs` (what strip should produce).

- [ ] **Step 1: Create fixtures directory**

```bash
mkdir -p tools/verus-strip/tests/fixtures
```

- [ ] **Step 2: Create simple_input.rs**

Write `tools/verus-strip/tests/fixtures/simple_input.rs`:

```rust
//! A simple counter module.

use vstd::prelude::*;
use std::cmp;

verus! {

pub struct Counter {
    pub count: u32,
    pub limit: u32,
}

impl Counter {
    pub open spec fn inv(&self) -> bool {
        self.count <= self.limit
    }

    pub fn new(limit: u32) -> (result: Self)
        requires
            limit > 0,
        ensures
            result.inv(),
            result.count == 0,
    {
        Counter { count: 0, limit }
    }

    pub fn increment(&mut self)
        requires
            old(self).inv(),
            old(self).count < old(self).limit,
        ensures
            self.inv(),
            self.count == old(self).count + 1,
    {
        self.count = self.count + 1;
    }

    pub fn value(&self) -> u32 {
        self.count
    }

    pub proof fn lemma_inv_preserved(c: Counter)
        requires
            c.inv(),
            c.count < c.limit,
        ensures
            (Counter { count: (c.count + 1) as u32, ..c }).inv(),
    {
    }
}

} // verus!
```

- [ ] **Step 3: Create simple_expected.rs**

Run verus-strip on simple_input.rs and capture the output. First build verus-strip with cargo (faster iteration):

```bash
cd tools/verus-strip && cargo build && cd ../..
```

Then:

```bash
./tools/verus-strip/target/debug/verus-strip tools/verus-strip/tests/fixtures/simple_input.rs -o tools/verus-strip/tests/fixtures/simple_expected.rs
```

Verify the output looks correct: no `verus!`, no `vstd`, no `spec fn`, no `proof fn`, no `requires`/`ensures`, named return types collapsed. The `value()` function and `struct Counter` should be preserved.

- [ ] **Step 4: Create complex_input.rs**

Write `tools/verus-strip/tests/fixtures/complex_input.rs`:

```rust
//! Complex verification example with loops, asserts, and multiple structs.

use vstd::prelude::*;

verus! {

#[verifier::reject_recursive_types(T)]
pub struct Stack<T> {
    data: Vec<T>,
    capacity: usize,
}

impl<T> Stack<T> {
    pub open spec fn inv(&self) -> bool {
        self.data.len() <= self.capacity
    }

    pub open spec fn is_empty_spec(&self) -> bool {
        self.data.len() == 0
    }

    pub fn new(capacity: usize) -> (result: Self)
        requires
            capacity > 0,
        ensures
            result.inv(),
            result.is_empty_spec(),
    {
        Stack {
            data: Vec::new(),
            capacity,
        }
    }

    #[verifier::when_used_as_spec(is_empty_spec)]
    pub fn is_empty(&self) -> bool {
        self.data.len() == 0
    }

    pub fn push(&mut self, item: T) -> (success: bool)
        requires
            old(self).inv(),
        ensures
            self.inv(),
    {
        if self.data.len() < self.capacity {
            self.data.push(item);
            true
        } else {
            false
        }
    }

    pub fn pop(&mut self) -> (result: Option<T>)
        requires
            old(self).inv(),
        ensures
            self.inv(),
    {
        if self.data.len() > 0 {
            let item = self.data.pop();
            item
        } else {
            None
        }
    }

    pub fn drain_all(&mut self)
        requires
            old(self).inv(),
        ensures
            self.inv(),
            self.is_empty_spec(),
    {
        let mut i: usize = 0;
        while i < self.data.len()
            invariant
                self.inv(),
                i <= self.data.len(),
            decreases
                self.data.len() - i,
        {
            assert(i < self.data.len());
            i = i + 1;
        }
        self.data = Vec::new();
    }
}

pub proof fn lemma_stack_push_pop<T>(s: Stack<T>, item: T)
    requires
        s.inv(),
        s.data.len() < s.capacity,
{
}

} // verus!
```

- [ ] **Step 5: Generate complex_expected.rs**

```bash
./tools/verus-strip/target/debug/verus-strip tools/verus-strip/tests/fixtures/complex_input.rs -o tools/verus-strip/tests/fixtures/complex_expected.rs
```

Verify: `#[verifier::*]` attrs stripped, `invariant`/`decreases` clauses in the loop stripped, proof assert stripped, proof fn stripped. Runtime code (`push`, `pop`, `drain_all`, `is_empty`) preserved.

- [ ] **Step 6: Create edge_nested_verus_input.rs**

Write `tools/verus-strip/tests/fixtures/edge_nested_verus_input.rs`:

```rust
//! Edge case: nested braces in ensures clauses.

use vstd::prelude::*;

verus! {

pub enum MyResult<T, E> {
    Ok(T),
    Err(E),
}

pub struct Semaphore {
    count: u32,
    limit: u32,
}

impl Semaphore {
    pub open spec fn inv(&self) -> bool {
        &&& self.limit > 0
        &&& self.count <= self.limit
    }

    pub fn init(count: u32, limit: u32) -> (result: MyResult<Self, i32>)
        ensures
            match result {
                MyResult::Ok(sem) => {
                    &&& sem.inv()
                    &&& sem.count == count
                },
                MyResult::Err(e) => {
                    &&& e == -1i32
                },
            },
    {
        if limit == 0 || count > limit {
            MyResult::Err(-1i32)
        } else {
            MyResult::Ok(Semaphore { count, limit })
        }
    }

    pub fn get_count(&self) -> u32 {
        self.count
    }
}

} // verus!
```

- [ ] **Step 7: Generate edge_nested_verus_expected.rs**

```bash
./tools/verus-strip/target/debug/verus-strip tools/verus-strip/tests/fixtures/edge_nested_verus_input.rs -o tools/verus-strip/tests/fixtures/edge_nested_verus_expected.rs
```

Verify: the complex `match` in ensures is stripped but enum and runtime code preserved.

- [ ] **Step 8: Create edge_generics_input.rs**

Write `tools/verus-strip/tests/fixtures/edge_generics_input.rs`:

```rust
//! Edge case: complex generic types with trait bounds.

use vstd::prelude::*;

verus! {

pub trait Bounded {
    spec fn bound(&self) -> nat;
}

pub struct Container<T: Bounded + Clone> {
    items: Vec<T>,
    max_size: usize,
}

impl<T: Bounded + Clone> Container<T> {
    pub open spec fn inv(&self) -> bool {
        self.items.len() <= self.max_size
    }

    pub fn new(max_size: usize) -> (result: Self)
        requires
            max_size > 0,
        ensures
            result.inv(),
    {
        Container {
            items: Vec::new(),
            max_size,
        }
    }

    pub fn len(&self) -> usize {
        self.items.len()
    }
}

} // verus!
```

- [ ] **Step 9: Generate edge_generics_expected.rs**

```bash
./tools/verus-strip/target/debug/verus-strip tools/verus-strip/tests/fixtures/edge_generics_input.rs -o tools/verus-strip/tests/fixtures/edge_generics_expected.rs
```

Verify: `spec fn bound` and `spec fn inv` stripped, trait preserved (without spec method), generic types preserved.

- [ ] **Step 10: Commit**

```bash
git add tools/verus-strip/tests/fixtures/
git commit -m "test: add verus-strip test fixtures for round-trip testing"
```

---

### Task 4: Add integration tests (fixture-based round-trip + convergence)

**Files:**
- Create: `tools/verus-strip/tests/integration_test.rs`
- Modify: `tools/verus-strip/BUILD.bazel`

- [ ] **Step 1: Write the integration test**

Write `tools/verus-strip/tests/integration_test.rs`:

```rust
//! Integration tests for verus-strip: fixture-based round-trip verification.
//!
//! For each pair of files in tests/fixtures/ (*_input.rs, *_expected.rs),
//! strips the input and asserts the output matches the expected file exactly.

use std::fs;
use std::path::{Path, PathBuf};

fn fixtures_dir() -> PathBuf {
    // When run via cargo test, CARGO_MANIFEST_DIR is the crate root.
    // When run via bazel test, we look relative to the runfiles.
    let cargo_dir = Path::new(env!("CARGO_MANIFEST_DIR")).join("tests/fixtures");
    if cargo_dir.exists() {
        return cargo_dir;
    }
    // Bazel runfiles fallback
    let runfiles = std::env::var("RUNFILES_DIR")
        .or_else(|_| std::env::var("TEST_SRCDIR"))
        .unwrap_or_else(|_| ".".to_string());
    Path::new(&runfiles)
        .join("rules_verus/tools/verus-strip/tests/fixtures")
        .to_path_buf()
}

fn discover_fixture_pairs(dir: &Path) -> Vec<(String, PathBuf, PathBuf)> {
    let mut pairs = Vec::new();
    if !dir.exists() {
        panic!("Fixtures directory not found: {}", dir.display());
    }

    let mut entries: Vec<_> = fs::read_dir(dir)
        .unwrap()
        .filter_map(|e| e.ok())
        .map(|e| e.path())
        .filter(|p| {
            p.extension().map_or(false, |ext| ext == "rs")
                && p.file_name()
                    .unwrap()
                    .to_str()
                    .unwrap()
                    .ends_with("_input.rs")
        })
        .collect();
    entries.sort();

    for input_path in entries {
        let stem = input_path
            .file_stem()
            .unwrap()
            .to_str()
            .unwrap()
            .strip_suffix("_input")
            .unwrap();
        let expected_path = dir.join(format!("{}_expected.rs", stem));
        if expected_path.exists() {
            pairs.push((stem.to_string(), input_path, expected_path));
        } else {
            panic!(
                "Missing expected file for fixture '{}': {}",
                stem,
                expected_path.display()
            );
        }
    }
    pairs
}

#[test]
fn fixture_round_trips() {
    let dir = fixtures_dir();
    let pairs = discover_fixture_pairs(&dir);
    assert!(!pairs.is_empty(), "No fixture pairs found in {}", dir.display());

    let mut failures = Vec::new();

    for (name, input_path, expected_path) in &pairs {
        let input = fs::read_to_string(input_path)
            .unwrap_or_else(|e| panic!("Cannot read {}: {e}", input_path.display()));
        let expected = fs::read_to_string(expected_path)
            .unwrap_or_else(|e| panic!("Cannot read {}: {e}", expected_path.display()));

        let result = verus_strip::strip_file(&input);

        if !result.errors.is_empty() {
            failures.push(format!("{name}: parse errors: {:?}", result.errors));
            continue;
        }

        if result.output != expected {
            let output_lines: Vec<&str> = result.output.lines().collect();
            let expected_lines: Vec<&str> = expected.lines().collect();
            let first_diff = output_lines
                .iter()
                .zip(expected_lines.iter())
                .enumerate()
                .find(|(_, (a, b))| a != b)
                .map(|(i, (a, b))| {
                    format!("  line {}: got {:?}, expected {:?}", i + 1, a, b)
                })
                .unwrap_or_else(|| {
                    format!(
                        "  length: got {} lines, expected {} lines",
                        output_lines.len(),
                        expected_lines.len()
                    )
                });
            failures.push(format!("{name}:\n{first_diff}"));
        }
    }

    if !failures.is_empty() {
        panic!(
            "Fixture round-trip failures ({}/{}):\n{}",
            failures.len(),
            pairs.len(),
            failures.join("\n\n")
        );
    }

    eprintln!("All {} fixture pairs passed", pairs.len());
}

/// Verify that stripping is idempotent: stripping already-stripped code produces identical output.
#[test]
fn strip_is_idempotent() {
    let dir = fixtures_dir();
    let pairs = discover_fixture_pairs(&dir);

    for (name, _, expected_path) in &pairs {
        let expected = fs::read_to_string(expected_path).unwrap();

        // Strip the already-stripped output
        let result = verus_strip::strip_file(&expected);

        assert_eq!(
            result.output, expected,
            "Stripping is not idempotent for fixture '{name}'"
        );
    }
}
```

- [ ] **Step 2: Add integration test to BUILD.bazel**

Append to `tools/verus-strip/BUILD.bazel`:

```starlark
rust_test(
    name = "verus_strip_integration_test",
    srcs = ["tests/integration_test.rs"],
    deps = [":verus_strip_lib"],
    edition = "2024",
    data = glob(["tests/fixtures/**"]),
    env = {
        "CARGO_MANIFEST_DIR": "tools/verus-strip",
    },
)
```

- [ ] **Step 3: Run integration tests**

```bash
bazel test //tools/verus-strip:verus_strip_integration_test
```

Expected: All fixture pairs pass, idempotency check passes.

- [ ] **Step 4: Commit**

```bash
git add tools/verus-strip/tests/integration_test.rs tools/verus-strip/BUILD.bazel
git commit -m "test: add fixture-based integration tests for verus-strip"
```

---

### Task 5: Create verus_strip Bazel rule

**Files:**
- Create: `verus/private/strip.bzl`
- Modify: `verus/defs.bzl`

- [ ] **Step 1: Write the verus_strip rule implementation**

Write `verus/private/strip.bzl`:

```starlark
"""Bazel rules for stripping Verus annotations from Rust source files."""

def _verus_strip_impl(ctx):
    """Strip Verus annotations from Rust source files, producing plain Rust."""
    strip_tool = ctx.executable._strip_tool
    srcs = ctx.files.srcs
    outputs = []

    for src in srcs:
        # Output file: same name, in this rule's output directory
        out = ctx.actions.declare_file(src.basename)
        outputs.append(out)

        ctx.actions.run(
            executable = strip_tool,
            arguments = [src.path, "-o", out.path],
            inputs = [src],
            outputs = [out],
            mnemonic = "VerusStrip",
            progress_message = "Stripping Verus annotations from %s" % src.short_path,
        )

    return [
        DefaultInfo(
            files = depset(outputs),
            runfiles = ctx.runfiles(files = outputs),
        ),
    ]

verus_strip = rule(
    implementation = _verus_strip_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".rs"],
            mandatory = True,
            doc = "Verus-annotated Rust source files to strip.",
        ),
        "_strip_tool": attr.label(
            default = Label("//tools/verus-strip:verus-strip"),
            executable = True,
            cfg = "exec",
            doc = "The verus-strip binary.",
        ),
    },
    doc = "Strip Verus verification annotations from Rust source files, producing plain Rust.",
)

def _verus_strip_test_impl(ctx):
    """Test that stripping verus_srcs produces output matching plain_srcs."""
    strip_tool = ctx.executable._strip_tool
    verus_srcs = ctx.files.verus_srcs
    plain_srcs = ctx.files.plain_srcs

    # Build a test script that strips each verus source and diffs against plain
    script_lines = [
        "#!/bin/bash",
        "set -euo pipefail",
        "STRIP_TOOL=\"$1\"",
        "shift",
        "FAILURES=0",
        "CHECKED=0",
    ]

    runfiles_list = verus_srcs + plain_srcs

    # Pair verus and plain files by basename
    plain_by_name = {}
    for f in plain_srcs:
        plain_by_name[f.basename] = f

    for verus_src in verus_srcs:
        plain_src = plain_by_name.get(verus_src.basename)
        if not plain_src:
            fail("No matching plain source for %s" % verus_src.basename)

        script_lines.append('CHECKED=$((CHECKED + 1))')
        script_lines.append(
            'STRIPPED=$("$STRIP_TOOL" "{verus}")'.format(verus = verus_src.short_path),
        )
        script_lines.append(
            'EXPECTED=$(cat "{plain}")'.format(plain = plain_src.short_path),
        )
        script_lines.append('if [ "$STRIPPED" = "$EXPECTED" ]; then')
        script_lines.append('  echo "  OK    %s"' % verus_src.basename)
        script_lines.append("else")
        script_lines.append('  echo "  DIFF  %s"' % verus_src.basename)
        script_lines.append(
            '  diff <(echo "$STRIPPED") "{plain}" | head -20 || true'.format(
                plain = plain_src.short_path,
            ),
        )
        script_lines.append("  FAILURES=$((FAILURES + 1))")
        script_lines.append("fi")

    script_lines.extend([
        "echo",
        'echo "Checked $CHECKED files: $((CHECKED - FAILURES)) OK, $FAILURES diverged"',
        'if [ "$FAILURES" -gt 0 ]; then exit 1; fi',
    ])

    script_content = "\n".join(script_lines) + "\n"
    test_script = ctx.actions.declare_file(ctx.label.name + "_test.sh")
    ctx.actions.write(
        output = test_script,
        content = script_content,
        is_executable = True,
    )

    runfiles = ctx.runfiles(files = runfiles_list + [strip_tool])

    return [
        DefaultInfo(
            executable = test_script,
            runfiles = runfiles,
        ),
    ]

verus_strip_test = rule(
    implementation = _verus_strip_test_impl,
    attrs = {
        "verus_srcs": attr.label_list(
            allow_files = [".rs"],
            mandatory = True,
            doc = "Verus-annotated Rust source files.",
        ),
        "plain_srcs": attr.label_list(
            allow_files = [".rs"],
            mandatory = True,
            doc = "Expected plain Rust source files (stripped output should match these).",
        ),
        "_strip_tool": attr.label(
            default = Label("//tools/verus-strip:verus-strip"),
            executable = True,
            cfg = "exec",
            doc = "The verus-strip binary.",
        ),
    },
    test = True,
    doc = "Test that stripping Verus annotations from verus_srcs produces output matching plain_srcs.",
)
```

- [ ] **Step 2: Export the new rules from defs.bzl**

Read the current `verus/defs.bzl` and add the strip exports. The file should become:

```starlark
"""Public API for rules_verus.

Users should load rules from this file:
    load("@rules_verus//verus:defs.bzl", "verus_library", "verus_test", "verus_strip", "verus_strip_test")
"""

load("//verus/private:verus.bzl", _verus_library = "verus_library", _verus_test = "verus_test")
load("//verus/private:strip.bzl", _verus_strip = "verus_strip", _verus_strip_test = "verus_strip_test")

verus_library = _verus_library
verus_test = _verus_test
verus_strip = _verus_strip
verus_strip_test = _verus_strip_test
```

- [ ] **Step 3: Create a BUILD.bazel test target using the new rules**

Append to root `BUILD.bazel`:

```starlark
load("//verus:defs.bzl", "verus_strip", "verus_strip_test")

# Example: strip test fixtures
verus_strip(
    name = "strip_simple_fixture",
    srcs = ["//tools/verus-strip/tests/fixtures:simple_input.rs"],
)

# Example: convergence test using fixtures
verus_strip_test(
    name = "strip_simple_convergence_test",
    verus_srcs = ["//tools/verus-strip/tests/fixtures:simple_input.rs"],
    plain_srcs = ["//tools/verus-strip/tests/fixtures:simple_expected.rs"],
)
```

- [ ] **Step 4: Add exports_files to fixtures BUILD**

Create `tools/verus-strip/tests/fixtures/BUILD.bazel`:

```starlark
exports_files(glob(["*.rs"]))
```

- [ ] **Step 5: Test the verus_strip rule**

```bash
bazel build //:strip_simple_fixture
```

Expected: Produces a stripped `.rs` output file.

- [ ] **Step 6: Test the verus_strip_test rule**

```bash
bazel test //:strip_simple_convergence_test
```

Expected: PASS — stripped output matches expected.

- [ ] **Step 7: Commit**

```bash
git add verus/private/strip.bzl verus/defs.bzl BUILD.bazel tools/verus-strip/tests/fixtures/BUILD.bazel
git commit -m "feat: add verus_strip and verus_strip_test Bazel rules"
```

---

### Task 6: Run all tests and validate

**Files:** (none modified)

- [ ] **Step 1: Run all unit tests**

```bash
bazel test //tools/verus-strip:verus_strip_unit_test
```

Expected: 9 tests PASS.

- [ ] **Step 2: Run integration tests**

```bash
bazel test //tools/verus-strip:verus_strip_integration_test
```

Expected: All fixture pairs pass, idempotency check passes.

- [ ] **Step 3: Run Bazel rule tests**

```bash
bazel test //:strip_simple_convergence_test
```

Expected: PASS.

- [ ] **Step 4: Run all tests together**

```bash
bazel test //...
```

Expected: All targets build and test successfully.

- [ ] **Step 5: Commit (if any fixes were needed)**

Only if fixes were applied in this step.

---

### Task 7: Provision Rust nightly hermetially via rules_rust

**Files:**
- Modify: `verus/extensions.bzl`
- Modify: `verus/private/repo.bzl`
- Modify: `verus/toolchain.bzl`
- Modify: `MODULE.bazel`

This is the key hermeticity improvement. The Verus extension reads `version.json` from the downloaded release to determine the required Rust nightly version, then we configure rules_rust to provision that nightly. The VerusToolchainInfo gains a `rust_sysroot` field pointing to the hermetically provisioned sysroot.

**Important context:** rules_rust nightly format is `"nightly/YYYY-MM-DD"`. Verus's `version.json` contains a toolchain field like `"1.93.0-nightly"` or `"nightly-2024-10-17"` — we need to parse this into the rules_rust format. The exact format in version.json needs to be verified at build time.

**Note:** This task requires careful investigation of how Verus's version.json actually encodes the nightly date. The repo rule already extracts the version number (e.g., `"1.93.0"`), but for rules_rust we need either the exact nightly date or the stable version. Since Verus may use a nightly that's pegged to a specific date, we may need to:
1. Store the nightly date in `_KNOWN_VERSIONS` alongside the SHA-256 hashes
2. Or extract it from version.json at repository rule time and pass it to the module extension

The simpler approach: **add a `rust_nightly` field to `_KNOWN_VERSIONS`** that maps to the exact nightly date string rules_rust expects. This is filled in when a new Verus version is added, just like SHA-256 hashes.

- [ ] **Step 1: Add rust_nightly to _KNOWN_VERSIONS in extensions.bzl**

Modify `verus/extensions.bzl` — update `_KNOWN_VERSIONS` to include the nightly date:

```starlark
_KNOWN_VERSIONS = {
    "0.2026.02.15": {
        "tag": "0.2026.02.15.61aa1bf",
        "rust_nightly": "nightly/2025-01-30",  # Rust nightly that rust_verify was built against
        "sha256": {
            "aarch64-apple-darwin": "185ac0631d3639da5ba09d6e50218af43efffa58383625dd070e6c2ecc11da65",
            "x86_64-apple-darwin": "bfb79474f078782104d6a80b21069f104eed8f7bac51d16a0216ca07d0b021e6",
            "x86_64-unknown-linux-gnu": "d02ce8c026e3304e3d463355678dced46d5d8340fdebd9a8cdaea27c29338e0b",
            "x86_64-pc-windows-msvc": "63ba4e37a530a27bac3fab5bb47f6885888ab181e6d5c95bae1d5a01fcd6956d",
        },
    },
}
```

**To determine the correct nightly date:** Download the Verus release, check `version.json`, and find the exact nightly date. Run:

```bash
# Download and check the version.json from the Verus release
curl -sL "https://github.com/verus-lang/verus/releases/download/release/0.2026.02.15.61aa1bf/verus-0.2026.02.15.61aa1bf-arm64-macos.zip" -o /tmp/verus.zip && unzip -o /tmp/verus.zip -d /tmp/verus-check && cat /tmp/verus-check/verus-arm64-macos/version.json
```

The nightly date in `_KNOWN_VERSIONS` must match what version.json says.

- [ ] **Step 2: Update MODULE.bazel to register nightly toolchain**

The challenge: bzlmod module extensions run before repository rules, so we can't dynamically read version.json at extension time. Instead, `_KNOWN_VERSIONS` carries the nightly date statically.

Update `MODULE.bazel` to declare both stable (for verus-strip build) and nightly (for Verus verification):

```starlark
# Rust toolchains — stable for building verus-strip, nightly for Verus verification
rust = use_extension("@rules_rust//rust:extensions.bzl", "rust")
rust.toolchain(
    edition = "2024",
    versions = [
        "1.85.0",            # stable: builds verus-strip
        "nightly/2025-01-30", # nightly: matches Verus's rust_verify
    ],
)
use_repo(rust, "rust_toolchains")
register_toolchains("@rust_toolchains//:all")
```

**Important:** The nightly date here MUST match `_KNOWN_VERSIONS["0.2026.02.15"]["rust_nightly"]`. When adding a new Verus version, both must be updated together.

Add to `.bazelrc` (create if needed):

```
# Verus verification requires Rust nightly for the correct sysroot
build:verus --@rules_rust//rust/toolchain/channel=nightly
```

- [ ] **Step 3: Update VerusToolchainInfo to include rust_sysroot**

Modify `verus/toolchain.bzl` — add `rust_sysroot` field:

In the `VerusToolchainInfo` provider fields dict, add:

```starlark
"rust_sysroot": "String: Path to the Rust sysroot provisioned by rules_rust (empty if not available)",
```

In `_verus_toolchain_info_impl`, add to the struct:

```starlark
rust_sysroot = ctx.attr.rust_sysroot,
```

In `verus_toolchain_info` rule attrs, add:

```starlark
"rust_sysroot": attr.string(
    default = "",
    doc = "Path to the hermetically provisioned Rust sysroot",
),
```

- [ ] **Step 4: Update repo.bzl BUILD template to pass rust_sysroot**

In `verus/private/repo.bzl`, update `_BUILD_FILE_CONTENT` to include the `rust_sysroot` field in the `verus_toolchain_info` rule call. After `rust_toolchain = "{rust_toolchain}"`, add:

```starlark
    rust_sysroot = "",  # Will be populated when hermetic Rust is available
```

For now the sysroot is empty — Task 8 will wire this up once we verify the nightly toolchain works.

- [ ] **Step 5: Verify nightly toolchain downloads**

```bash
bazel build @rust_toolchains//:all --config=verus
```

Expected: Nightly Rust toolchain downloaded and registered.

- [ ] **Step 6: Commit**

```bash
git add verus/extensions.bzl verus/toolchain.bzl verus/private/repo.bzl MODULE.bazel .bazelrc
git commit -m "feat: provision Rust nightly via rules_rust for hermetic Verus verification"
```

---

### Task 8: Wire hermetic sysroot into verus_library and verus_test

**Files:**
- Modify: `verus/private/verus.bzl`

This task modifies the verification rules to use the hermetically provisioned Rust sysroot when available, falling back to host rustup when not. Once confirmed working, `no-sandbox` can be removed.

- [ ] **Step 1: Update _verus_verify_impl script to check for hermetic sysroot**

In `verus/private/verus.bzl`, modify the `script_content` in `_verus_verify_impl` (line 139-187). Replace the entire sysroot detection block with one that tries the hermetic sysroot first:

Replace lines 139-187 with:

```starlark
    script_content = """\
#!/bin/bash
set -euo pipefail

# Determine Rust sysroot for rust_verify.
# Priority: 1) hermetically provisioned sysroot, 2) host rustup
SYSROOT=""
RUST_TC="{rust_toolchain}"

# Try hermetic sysroot from rules_rust (if configured)
if [ -n "{rust_sysroot}" ] && [ -d "{rust_sysroot}" ]; then
    SYSROOT="{rust_sysroot}"
fi

# Fallback: host rustup
if [ -z "$SYSROOT" ]; then
    REAL_HOME=$(eval echo ~$(id -un 2>/dev/null) 2>/dev/null || echo "${{HOME:-/root}}")
    if [ -d "$REAL_HOME/.rustup" ]; then
        export HOME="$REAL_HOME"
    fi
    for p in "$HOME/.cargo/bin" "$HOME/.rustup/shims" "/usr/local/bin"; do
        [ -d "$p" ] && export PATH="$p:$PATH"
    done

    if [ -n "$RUST_TC" ]; then
        SYSROOT=$(rustc +"$RUST_TC" --print sysroot 2>/dev/null || true)
    fi
    if [ -z "$SYSROOT" ]; then
        SYSROOT=$(rustc --print sysroot 2>/dev/null || true)
    fi
fi

if [ -z "$SYSROOT" ]; then
    echo "ERROR: Cannot determine Rust sysroot." >&2
    echo "Either configure hermetic Rust nightly or install rustc/rustup with toolchain $RUST_TC" >&2
    exit 1
fi

# rust_verify needs rustc's libraries and Verus libraries
TOOLCHAIN_DIR=$(dirname "{rust_verify}")
case "$(uname)" in
    Darwin) export DYLD_LIBRARY_PATH="$SYSROOT/lib:$TOOLCHAIN_DIR:${{DYLD_LIBRARY_PATH:-}}" ;;
    *)      export LD_LIBRARY_PATH="$SYSROOT/lib:$TOOLCHAIN_DIR:${{LD_LIBRARY_PATH:-}}" ;;
esac

# Put z3 on PATH so rust_verify can find it
export PATH="$(dirname "{z3}"):$PATH"

"{rust_verify}" --edition=2021 --crate-type lib --sysroot "$SYSROOT" \\
    {builtin_extern_flags} {flags} "$@" && touch "{stamp}"
""".format(
        rust_verify = rust_verify.path,
        z3 = z3.path,
        rust_toolchain = rust_toolchain,
        rust_sysroot = verus_info.rust_sysroot,
        builtin_extern_flags = builtin_extern_flags,
        flags = " ".join(all_flags),
        stamp = stamp.path,
    )
```

- [ ] **Step 2: Conditionally remove no-sandbox when hermetic sysroot is available**

In `_verus_verify_impl`, update the `execution_requirements` block (around line 204):

```starlark
    execution_requirements = {}
    if not verus_info.rust_sysroot:
        execution_requirements["no-sandbox"] = "1"

    ctx.actions.run(
        executable = script,
        arguments = [crate_root.path],
        inputs = inputs,
        outputs = [stamp],
        tools = [script],
        mnemonic = "VerusVerify",
        progress_message = "Verifying %s with Verus" % ctx.label,
        execution_requirements = execution_requirements,
    )
```

- [ ] **Step 3: Apply the same changes to _verus_test_impl**

Apply the same sysroot detection pattern to the test script in `_verus_test_impl` (lines 316-388). Replace the sysroot detection section with the same hermetic-first approach. Also conditionally remove `no-sandbox` from the `testing.ExecutionInfo`:

```starlark
    exec_info = {}
    if not verus_info.rust_sysroot:
        exec_info["no-sandbox"] = "1"

    return [
        DefaultInfo(
            executable = test_script,
            runfiles = ctx.runfiles(files = runfiles_list),
        ),
        testing.ExecutionInfo(exec_info),
    ]
```

- [ ] **Step 4: Test verification still works**

```bash
bazel test //... 2>&1
```

Expected: All existing tests still pass. Verification rules fall back to host rustup since `rust_sysroot` is empty for now.

- [ ] **Step 5: Commit**

```bash
git add verus/private/verus.bzl
git commit -m "feat: use hermetic Rust sysroot when available, remove no-sandbox conditionally"
```

---

### Task 9: Update README and documentation

**Files:**
- Modify: `README.md`

- [ ] **Step 1: Update README with verus_strip documentation**

Add a new section to `README.md` after the existing API reference section. Include:

1. **verus_strip rule** — description, attributes (`srcs`), usage example
2. **verus_strip_test rule** — description, attributes (`verus_srcs`, `plain_srcs`), usage example
3. **CLI usage** — how to use the `verus-strip` binary directly
4. **Multi-track verification** — example showing Verus-annotated source stripped for cargo test/kani/coq_of_rust
5. **Hermetic Rust nightly** — note about the `rust_nightly` field in `_KNOWN_VERSIONS` and `.bazelrc` config

Example BUILD.bazel to add to docs:

```starlark
load("@rules_verus//verus:defs.bzl", "verus_library", "verus_strip", "verus_strip_test")

# Verify with Verus (SMT/Z3)
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

- [ ] **Step 2: Commit**

```bash
git add README.md
git commit -m "docs: add verus_strip rules and hermetic toolchain documentation"
```

---

### Task 10: Final validation

**Files:** (none modified)

- [ ] **Step 1: Run full test suite**

```bash
bazel test //...
```

Expected: All targets pass.

- [ ] **Step 2: Verify rivet artifacts are valid**

```bash
rivet validate
```

Expected: PASS.

- [ ] **Step 3: Verify binary works standalone**

```bash
bazel run //tools/verus-strip:verus-strip -- --help
```

Expected: Usage information printed.

- [ ] **Step 4: Verify strip rule produces correct output**

```bash
bazel build //:strip_simple_fixture
cat bazel-bin/simple_input.rs  # should be clean Rust with no Verus annotations
```

Expected: Plain Rust output, no `verus!`, `vstd`, `spec fn`, `proof fn`, `requires`, `ensures`.
