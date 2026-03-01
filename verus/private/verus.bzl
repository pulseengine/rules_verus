"""Implementation of Verus verification rules."""

VerusInfo = provider(
    doc = "Information about verified Verus sources",
    fields = {
        "srcs": "depset of File: The verified source files",
        "stamp": "File: Verification stamp file",
        "crate_name": "String: The crate name for --extern resolution",
        "transitive_stamps": "depset of File: All dependency verification stamps",
    },
)

def _resolve_crate_root(ctx):
    """Determine the crate root file.

    Priority:
    1. Explicit crate_root attribute
    2. lib.rs if present in srcs
    3. First file in srcs (original behavior)
    """
    srcs = ctx.files.srcs
    if not srcs:
        fail("{} requires at least one source file".format(ctx.attr._rule_kind))

    # 1. Explicit crate_root
    if ctx.file.crate_root:
        return ctx.file.crate_root

    # 2. Look for lib.rs in srcs
    for src in srcs:
        if src.basename == "lib.rs":
            return src

    # 3. Fall back to first source file
    return srcs[0]

def _resolve_crate_name(ctx):
    """Determine the crate name.

    Priority:
    1. Explicit crate_name attribute
    2. Target name with hyphens replaced by underscores
    """
    if ctx.attr.crate_name:
        return ctx.attr.crate_name
    return ctx.label.name.replace("-", "_")

def _collect_dep_info(ctx):
    """Collect dependency information from deps.

    Returns:
        tuple of (extern_flags list, dep_stamps depset, dep_inputs depset)
    """
    extern_flags = []
    dep_stamps = []
    all_transitive_stamps = []

    for dep in ctx.attr.deps:
        info = dep[VerusInfo]
        extern_flags.append("--extern")
        extern_flags.append("{name}={stamp}".format(
            name = info.crate_name,
            stamp = info.stamp.path,
        ))
        dep_stamps.append(info.stamp)
        all_transitive_stamps.append(info.transitive_stamps)

    transitive_stamps = depset(
        dep_stamps,
        transitive = all_transitive_stamps,
    )

    return extern_flags, transitive_stamps

def _verus_verify_impl(ctx):
    """Run Verus verification on Rust source files."""
    toolchain = ctx.toolchains["@rules_verus//verus:toolchain_type"]
    verus_info = toolchain.verus_info

    srcs = ctx.files.srcs
    if not srcs:
        fail("verus_library requires at least one source file")

    crate_root = _resolve_crate_root(ctx)
    crate_name = _resolve_crate_name(ctx)

    # Create stamp file to mark successful verification
    stamp = ctx.actions.declare_file(ctx.label.name + ".verus_verified")

    # Collect dependency info
    extern_flags, transitive_stamps = _collect_dep_info(ctx)

    # Collect all tool inputs — use rust_verify instead of verus wrapper
    rust_verify = verus_info.rust_verify
    z3 = verus_info.z3
    builtin_rlib = verus_info.builtin_rlib
    builtin_macros_dylib = verus_info.builtin_macros_dylib
    vstd_rlib = verus_info.vstd_rlib

    tool_inputs = [rust_verify, z3]
    if builtin_rlib:
        tool_inputs.append(builtin_rlib)
    if builtin_macros_dylib:
        tool_inputs.append(builtin_macros_dylib)
    if verus_info.vstd:
        tool_inputs.append(verus_info.vstd)
    if vstd_rlib:
        tool_inputs.append(vstd_rlib)

    inputs = depset(
        srcs + tool_inputs + transitive_stamps.to_list(),
        transitive = [verus_info.builtin],
    )

    # Build flags string: extra_flags + extern flags + crate name
    all_flags = list(ctx.attr.extra_flags)
    all_flags.append("--crate-name")
    all_flags.append(crate_name)
    all_flags.extend(extern_flags)

    # Build --extern flags for builtin crates
    builtin_extern_flags = ""
    if builtin_rlib:
        builtin_extern_flags += ' --extern builtin="{builtin_rlib}"'.format(
            builtin_rlib = builtin_rlib.path,
        )
    if builtin_macros_dylib:
        builtin_extern_flags += ' --extern builtin_macros="{builtin_macros}"'.format(
            builtin_macros = builtin_macros_dylib.path,
        )
    if vstd_rlib:
        builtin_extern_flags += ' --extern vstd="{vstd_rlib}"'.format(
            vstd_rlib = vstd_rlib.path,
        )

    # Get the Rust toolchain version for sysroot detection
    rust_toolchain = verus_info.rust_toolchain

    script_content = """\
#!/bin/bash
set -euo pipefail

# Locate Rust sysroot for rust_verify (modified rustc driver).
# Bazel sets HOME to a temp directory inside its execroot, so ~/.cargo/bin and
# ~/.rustup won't be found. We detect the real home from the password database.
REAL_HOME=$(eval echo ~$(id -un 2>/dev/null) 2>/dev/null || echo "${{HOME:-/root}}")
if [ -d "$REAL_HOME/.rustup" ]; then
    export HOME="$REAL_HOME"
fi
for p in "$HOME/.cargo/bin" "$HOME/.rustup/shims" "/usr/local/bin"; do
    [ -d "$p" ] && export PATH="$p:$PATH"
done

# rust_verify is compiled against a specific Rust toolchain version.
# Use that exact version for the sysroot to get matching librustc_driver.
RUST_TC="{rust_toolchain}"
if [ -n "$RUST_TC" ]; then
    SYSROOT=$(rustc +"$RUST_TC" --print sysroot 2>/dev/null || true)
fi
if [ -z "${{SYSROOT:-}}" ]; then
    SYSROOT=$(rustc --print sysroot 2>/dev/null || true)
fi
if [ -z "${{SYSROOT:-}}" ]; then
    echo "ERROR: Cannot determine Rust sysroot. Is rustc installed?" >&2
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

"{rust_verify}" --edition=2021 --crate-type lib --sysroot "$SYSROOT" \
    {builtin_extern_flags} {flags} "$@" && touch "{stamp}"
""".format(
        rust_verify = rust_verify.path,
        z3 = z3.path,
        rust_toolchain = rust_toolchain,
        builtin_extern_flags = builtin_extern_flags,
        flags = " ".join(all_flags),
        stamp = stamp.path,
    )

    script = ctx.actions.declare_file(ctx.label.name + "_verus.sh")
    ctx.actions.write(
        output = script,
        content = script_content,
        is_executable = True,
    )

    ctx.actions.run(
        executable = script,
        arguments = [crate_root.path],
        inputs = inputs,
        outputs = [stamp],
        tools = [script],
        mnemonic = "VerusVerify",
        progress_message = "Verifying %s with Verus" % ctx.label,
        execution_requirements = {
            # rust_verify requires host rustc sysroot.
            # TODO: Bundle Rust sysroot in the toolchain for full hermeticity.
            "no-sandbox": "1",
        },
    )

    return [
        DefaultInfo(
            files = depset([stamp]),
            runfiles = ctx.runfiles(files = srcs),
        ),
        VerusInfo(
            srcs = depset(srcs),
            stamp = stamp,
            crate_name = crate_name,
            transitive_stamps = depset(
                [stamp],
                transitive = [transitive_stamps],
            ),
        ),
    ]

verus_library = rule(
    implementation = _verus_verify_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".rs"],
            mandatory = True,
            doc = "Rust source files to verify with Verus",
        ),
        "crate_root": attr.label(
            allow_single_file = [".rs"],
            doc = "Explicit crate root file. If not set, uses lib.rs from srcs or srcs[0].",
        ),
        "crate_name": attr.string(
            doc = "Crate name for --crate-name flag. Defaults to target name with hyphens as underscores.",
        ),
        "deps": attr.label_list(
            providers = [VerusInfo],
            doc = "Other verus_library targets this depends on for --extern resolution.",
        ),
        "extra_flags": attr.string_list(
            default = [],
            doc = "Extra flags to pass to verus (e.g., ['--multiple-errors', '5'])",
        ),
        "_rule_kind": attr.string(default = "verus_library"),
    },
    toolchains = ["@rules_verus//verus:toolchain_type"],
    doc = "Verify Rust source files with Verus. Produces a stamp file on success.",
)

def _verus_test_impl(ctx):
    """Run Verus verification as a test target."""
    toolchain = ctx.toolchains["@rules_verus//verus:toolchain_type"]
    verus_info = toolchain.verus_info

    srcs = ctx.files.srcs
    if not srcs:
        fail("verus_test requires at least one source file")

    crate_root = _resolve_crate_root(ctx)
    crate_name = _resolve_crate_name(ctx)

    # Collect dependency info
    extern_flags, transitive_stamps = _collect_dep_info(ctx)

    # Collect all tool inputs — use rust_verify instead of verus wrapper
    rust_verify = verus_info.rust_verify
    z3 = verus_info.z3
    builtin_rlib = verus_info.builtin_rlib
    builtin_macros_dylib = verus_info.builtin_macros_dylib
    vstd_rlib = verus_info.vstd_rlib

    tool_files = [rust_verify, z3]
    if builtin_rlib:
        tool_files.append(builtin_rlib)
    if builtin_macros_dylib:
        tool_files.append(builtin_macros_dylib)
    if verus_info.vstd:
        tool_files.append(verus_info.vstd)
    if vstd_rlib:
        tool_files.append(vstd_rlib)

    runfiles_list = srcs + tool_files + transitive_stamps.to_list()
    runfiles_list += verus_info.builtin.to_list()

    # Build flags string
    all_flags = list(ctx.attr.extra_flags)
    all_flags.append("--crate-name")
    all_flags.append(crate_name)
    all_flags.extend(extern_flags)

    # Build --extern flags for builtin crates
    builtin_extern_flags = ""
    if builtin_rlib:
        builtin_extern_flags += ' --extern builtin="{builtin_rlib}"'.format(
            builtin_rlib = builtin_rlib.short_path,
        )
    if builtin_macros_dylib:
        builtin_extern_flags += ' --extern builtin_macros="{builtin_macros}"'.format(
            builtin_macros = builtin_macros_dylib.short_path,
        )
    if vstd_rlib:
        builtin_extern_flags += ' --extern vstd="{vstd_rlib}"'.format(
            vstd_rlib = vstd_rlib.short_path,
        )

    # Get the Rust toolchain version for sysroot detection
    rust_toolchain = verus_info.rust_toolchain

    # Create a test runner script
    script_content = """\
#!/bin/bash
set -euo pipefail

# Locate Rust sysroot for rust_verify (modified rustc driver).
# Bazel sets HOME to a temp directory inside its execroot, so ~/.cargo/bin and
# ~/.rustup won't be found. We detect the real home from the password database.
REAL_HOME=$(eval echo ~$(id -un 2>/dev/null) 2>/dev/null || echo "${{HOME:-/root}}")
if [ -d "$REAL_HOME/.rustup" ]; then
    export HOME="$REAL_HOME"
fi
for p in "$HOME/.cargo/bin" "$HOME/.rustup/shims" "/usr/local/bin"; do
    [ -d "$p" ] && export PATH="$p:$PATH"
done

# rust_verify is compiled against a specific Rust toolchain version.
# Use that exact version for the sysroot to get matching librustc_driver.
RUST_TC="{rust_toolchain}"
if [ -n "$RUST_TC" ]; then
    SYSROOT=$(rustc +"$RUST_TC" --print sysroot 2>/dev/null || true)
fi
if [ -z "${{SYSROOT:-}}" ]; then
    SYSROOT=$(rustc --print sysroot 2>/dev/null || true)
fi
if [ -z "${{SYSROOT:-}}" ]; then
    echo "ERROR: Cannot determine Rust sysroot. Is rustc/rustup installed?" >&2
    echo "rust_verify requires Rust toolchain $RUST_TC" >&2
    echo "Attempted HOME=$HOME, PATH includes: $(echo $PATH | tr ':' '\\n' | grep -E 'cargo|rustup' || echo none)" >&2
    exit 1
fi

# rust_verify needs rustc's libraries and Verus libraries
RUST_VERIFY="{rust_verify}"
TOOLCHAIN_DIR=$(dirname "$RUST_VERIFY")
case "$(uname)" in
    Darwin) export DYLD_LIBRARY_PATH="$SYSROOT/lib:$TOOLCHAIN_DIR:${{DYLD_LIBRARY_PATH:-}}" ;;
    *)      export LD_LIBRARY_PATH="$SYSROOT/lib:$TOOLCHAIN_DIR:${{LD_LIBRARY_PATH:-}}" ;;
esac

# Put z3 on PATH so rust_verify can find it
export PATH="$(dirname "{z3}"):$PATH"

SRC="{src}"

echo "=== Verus Verification Test ==="
echo "Crate: {crate_name}"
echo "Source: $SRC"
echo "Verifier: $RUST_VERIFY"
echo "Rust sysroot: $SYSROOT"
echo ""

"$RUST_VERIFY" --edition=2021 --crate-type lib --sysroot "$SYSROOT" \
    {builtin_extern_flags} {flags} "$SRC"
STATUS=$?

if [ $STATUS -eq 0 ]; then
    echo ""
    echo "=== PASSED ==="
else
    echo ""
    echo "=== FAILED ==="
fi

exit $STATUS
""".format(
        rust_verify = rust_verify.short_path,
        z3 = z3.short_path,
        src = crate_root.short_path,
        crate_name = crate_name,
        rust_toolchain = rust_toolchain,
        builtin_extern_flags = builtin_extern_flags,
        flags = " ".join(all_flags),
    )

    test_script = ctx.actions.declare_file(ctx.label.name + "_test.sh")
    ctx.actions.write(
        output = test_script,
        content = script_content,
        is_executable = True,
    )

    return [
        DefaultInfo(
            executable = test_script,
            runfiles = ctx.runfiles(files = runfiles_list),
        ),
        # Disable sandbox so rust_verify can access host rustc/rustup for sysroot
        testing.ExecutionInfo({"no-sandbox": "1"}),
    ]

verus_test = rule(
    implementation = _verus_test_impl,
    attrs = {
        "srcs": attr.label_list(
            allow_files = [".rs"],
            mandatory = True,
            doc = "Rust source files to verify with Verus",
        ),
        "crate_root": attr.label(
            allow_single_file = [".rs"],
            doc = "Explicit crate root file. If not set, uses lib.rs from srcs or srcs[0].",
        ),
        "crate_name": attr.string(
            doc = "Crate name for --crate-name flag. Defaults to target name with hyphens as underscores.",
        ),
        "deps": attr.label_list(
            providers = [VerusInfo],
            doc = "Other verus_library targets this depends on for --extern resolution.",
        ),
        "extra_flags": attr.string_list(
            default = [],
            doc = "Extra flags to pass to verus",
        ),
        "_rule_kind": attr.string(default = "verus_test"),
    },
    toolchains = ["@rules_verus//verus:toolchain_type"],
    test = True,
    doc = "Test target that runs Verus verification. Passes if all proofs verify.",
)
