# verus-strip Integration & Hermetic Rust Nightly Toolchain — Design Spec

## Summary

Evolve rules_verus from a verification-only Bazel module into a complete Verus build toolkit by:
1. Moving verus-strip from pulseengine/gale into rules_verus as a generalized, reusable tool
2. Adding `verus_strip` and `verus_strip_test` Bazel rules
3. Provisioning Rust nightly hermetially via rules_rust, eliminating host rustup dependency

## Architecture

```
rules_verus (MODULE.bazel)
  ├── bazel_dep: rules_rust 0.69.0 (stable + nightly)
  ├── bazel_dep: bazel_skylib, platforms
  │
  ├── verus/ (Bazel rules package)
  │   ├── defs.bzl         — exports: verus_library, verus_test, verus_strip, verus_strip_test
  │   ├── extensions.bzl   — module extension: downloads Verus + configures nightly info
  │   ├── toolchain.bzl    — VerusToolchainInfo provider (+ rust_sysroot)
  │   └── private/
  │       ├── repo.bzl     — repository rule for Verus binaries
  │       ├── verus.bzl    — verus_library, verus_test (hermetic sysroot)
  │       └── strip.bzl    — verus_strip, verus_strip_test (NEW)
  │
  └── tools/verus-strip/   — Rust source (built from source via rules_rust)
      ├── BUILD.bazel      — rust_library + rust_binary + rust_test
      ├── Cargo.toml       — proc-macro2, syn, prettyplease
      └── src/
          ├── lib.rs       — strip library (ported from gale, generalized)
          └── main.rs      — CLI entry point
```

## Decisions

| Decision | Choice | Rationale |
|----------|--------|-----------|
| verus-strip location | Inside rules_verus | Any Verus user needs it; single dependency |
| Distribution | Build from source | Simpler; rules_rust already needed for nightly |
| Bazel rule API | Separate `verus_strip` + `verus_strip_test` | Composable: strip without verify, verify without strip |
| Rust nightly | Static in `_KNOWN_VERSIONS` | bzlmod extensions run before repo rules; can't read version.json dynamically |
| Sandbox | Conditional: hermetic = sandboxed, fallback = no-sandbox | Gradual migration path |

## Rule APIs

### verus_strip

| Attribute | Type | Required | Purpose |
|-----------|------|----------|---------|
| `srcs` | label_list(.rs) | Yes | Verus-annotated sources to strip |

Outputs: one stripped `.rs` file per input, same basename.

### verus_strip_test

| Attribute | Type | Required | Purpose |
|-----------|------|----------|---------|
| `verus_srcs` | label_list(.rs) | Yes | Verus-annotated sources |
| `plain_srcs` | label_list(.rs) | Yes | Expected plain Rust (must match by basename) |

Test: strips each verus source, diffs against matching plain source.

## Test Strategy

1. **Unit tests** (9 existing from gale + expansion): individual transformations
2. **Fixture-based round-trip tests**: input/expected pairs in `tests/fixtures/`, auto-discovered
3. **Idempotency tests**: stripping already-stripped code produces identical output
4. **Convergence tests via Bazel rule**: `verus_strip_test` rule as integration test

## Hermetic Toolchain

`_KNOWN_VERSIONS` gains a `rust_nightly` field (e.g., `"nightly/2025-01-30"`). MODULE.bazel registers both stable (for building verus-strip) and nightly (for Verus verification) via rules_rust. When `rust_sysroot` is populated, verification rules run in sandbox; otherwise fall back to host rustup with `no-sandbox`.
