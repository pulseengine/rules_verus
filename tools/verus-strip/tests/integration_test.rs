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

/// Regression: verify that input files contain Verus constructs and stripped output does not.
/// This catches regressions where the stripper stops removing certain constructs.
#[test]
fn stripped_output_has_no_verus_constructs() {
    let dir = fixtures_dir();
    let pairs = discover_fixture_pairs(&dir);

    let verus_markers = &[
        "verus!",
        "use vstd",
        "spec fn",
        "proof fn",
        "requires",
        "ensures",
        "#[verifier",
        "#[trigger]",
    ];

    for (name, input_path, _) in &pairs {
        let input = fs::read_to_string(input_path).unwrap();
        let result = verus_strip::strip_file(&input);

        assert!(
            result.errors.is_empty(),
            "{name}: strip produced parse errors: {:?}",
            result.errors
        );

        // Input should contain at least some Verus constructs (otherwise it's a bad fixture)
        let input_has_verus = verus_markers.iter().any(|m| input.contains(m));
        assert!(
            input_has_verus,
            "{name}: input fixture has no Verus constructs — not a useful test"
        );

        // Stripped output must not contain any Verus constructs in code lines
        // (comments may mention Verus keywords — that's fine)
        let code_lines: Vec<&str> = result
            .output
            .lines()
            .filter(|l| {
                let t = l.trim();
                !t.is_empty() && !t.starts_with("//")
            })
            .collect();
        let code_text = code_lines.join("\n");

        for marker in verus_markers {
            assert!(
                !code_text.contains(marker),
                "{name}: stripped code still contains '{marker}':\n{}",
                code_lines
                    .iter()
                    .filter(|l| l.contains(marker))
                    .copied()
                    .collect::<Vec<_>>()
                    .join("\n")
            );
        }
    }
}

/// Regression: verify that stripped output preserves runtime code.
/// Checks that struct definitions, impl blocks, and runtime fn signatures survive stripping.
#[test]
fn stripped_output_preserves_runtime_code() {
    let dir = fixtures_dir();

    // Simple fixture: should preserve struct Counter, fn new, fn increment, fn value
    let input = fs::read_to_string(dir.join("simple_input.rs")).unwrap();
    let result = verus_strip::strip_file(&input);
    assert!(result.errors.is_empty());

    for expected in &["struct Counter", "fn new", "fn increment", "fn value"] {
        assert!(
            result.output.contains(expected),
            "simple: stripped output missing '{expected}'"
        );
    }

    // Complex fixture: should preserve struct Stack, fn new, fn push, fn pop, fn drain_all, fn is_empty
    let input = fs::read_to_string(dir.join("complex_input.rs")).unwrap();
    let result = verus_strip::strip_file(&input);
    assert!(result.errors.is_empty());

    for expected in &["struct Stack", "fn new", "fn push", "fn pop", "fn drain_all", "fn is_empty"] {
        assert!(
            result.output.contains(expected),
            "complex: stripped output missing '{expected}'"
        );
    }
}
