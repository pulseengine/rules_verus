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

    # Collect all tool inputs
    tool_inputs = [verus_info.verus, verus_info.z3]
    if verus_info.vstd:
        tool_inputs.append(verus_info.vstd)
    if verus_info.vstd_rlib:
        tool_inputs.append(verus_info.vstd_rlib)

    inputs = depset(
        srcs + tool_inputs + transitive_stamps.to_list(),
        transitive = [verus_info.builtin],
    )

    # Verus needs its support files in the same directory as the binary.
    # Use a wrapper script that sets up the environment.
    verus_bin = verus_info.verus
    z3_bin = verus_info.z3

    # Build flags string: extra_flags + extern flags + crate name
    all_flags = list(ctx.attr.extra_flags)
    all_flags.append("--crate-name")
    all_flags.append(crate_name)
    all_flags.extend(extern_flags)

    script_content = """\
#!/bin/bash
set -euo pipefail

# Verus needs rustup to locate the Rust sysroot.
# Ensure common rustup locations are on PATH.
HOME="${{HOME:-$(eval echo ~$(whoami))}}"
export HOME
for p in "$HOME/.cargo/bin" "$HOME/.rustup/shims" "/usr/local/bin"; do
    [ -d "$p" ] && export PATH="$p:$PATH"
done

export VERUS_Z3_PATH="{z3}"
"{verus}" --crate-type lib {flags} "$@" && touch "{stamp}"
""".format(
        verus = verus_bin.path,
        z3 = z3_bin.path,
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
            # Verus requires host rustup to find the Rust sysroot.
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

    # Collect all tool inputs
    tool_files = [verus_info.verus, verus_info.z3]
    if verus_info.vstd:
        tool_files.append(verus_info.vstd)
    if verus_info.vstd_rlib:
        tool_files.append(verus_info.vstd_rlib)

    runfiles_list = srcs + tool_files + transitive_stamps.to_list()
    runfiles_list += verus_info.builtin.to_list()

    verus_bin = verus_info.verus
    z3_bin = verus_info.z3

    # Build flags string
    all_flags = list(ctx.attr.extra_flags)
    all_flags.append("--crate-name")
    all_flags.append(crate_name)
    all_flags.extend(extern_flags)

    # Create a test runner script
    script_content = """\
#!/bin/bash
set -euo pipefail

# Verus needs rustup to locate the Rust sysroot.
HOME="${{HOME:-$(eval echo ~$(whoami))}}"
export HOME
for p in "$HOME/.cargo/bin" "$HOME/.rustup/shims" "/usr/local/bin"; do
    [ -d "$p" ] && export PATH="$p:$PATH"
done

# Resolve paths relative to runfiles
VERUS="{verus}"
Z3="{z3}"
SRC="{src}"

export VERUS_Z3_PATH="$Z3"

echo "=== Verus Verification Test ==="
echo "Crate: {crate_name}"
echo "Source: $SRC"
echo "Verus: $VERUS"
echo ""

"$VERUS" --crate-type lib {flags} "$SRC"
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
        verus = verus_bin.short_path,
        z3 = z3_bin.short_path,
        src = crate_root.short_path,
        crate_name = crate_name,
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
