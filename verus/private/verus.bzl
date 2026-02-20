"""Implementation of Verus verification rules."""

VerusInfo = provider(
    doc = "Information about verified Verus sources",
    fields = {
        "srcs": "depset of File: The verified source files",
        "stamp": "File: Verification stamp file",
    },
)

def _verus_verify_impl(ctx):
    """Run Verus verification on Rust source files."""
    toolchain = ctx.toolchains["@rules_verus//verus:toolchain_type"]
    verus_info = toolchain.verus_info

    srcs = ctx.files.srcs
    if not srcs:
        fail("verus_library requires at least one source file")

    # Create stamp file to mark successful verification
    stamp = ctx.actions.declare_file(ctx.label.name + ".verus_verified")

    # Build the verus command
    # Verus expects VERUS_Z3_PATH to point to the Z3 binary
    args = ctx.actions.args()
    args.add("--crate-type", "lib")

    # Add extra flags from the rule
    for flag in ctx.attr.extra_flags:
        args.add(flag)

    # Add all source files (Verus verifies one file at a time)
    # For multi-file projects, the main entry point should be listed first
    main_src = srcs[0]

    # Collect all tool inputs
    tool_inputs = [verus_info.verus, verus_info.z3]
    if verus_info.vstd:
        tool_inputs.append(verus_info.vstd)
    if verus_info.vstd_rlib:
        tool_inputs.append(verus_info.vstd_rlib)

    inputs = depset(
        srcs + tool_inputs,
        transitive = [verus_info.builtin],
    )

    # Verus needs its support files in the same directory as the binary.
    # Use a wrapper script that sets up the environment.
    verus_bin = verus_info.verus
    z3_bin = verus_info.z3

    script_content = """\
#!/bin/bash
set -euo pipefail
export VERUS_Z3_PATH="{z3}"
"{verus}" --crate-type lib {extra_flags} "$@" && touch "{stamp}"
""".format(
        verus = verus_bin.path,
        z3 = z3_bin.path,
        extra_flags = " ".join(ctx.attr.extra_flags),
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
        arguments = [main_src.path],
        inputs = inputs,
        outputs = [stamp],
        tools = [script],
        mnemonic = "VerusVerify",
        progress_message = "Verifying %s with Verus" % ctx.label,
        use_default_shell_env = True,
    )

    return [
        DefaultInfo(
            files = depset([stamp]),
            runfiles = ctx.runfiles(files = srcs),
        ),
        VerusInfo(
            srcs = depset(srcs),
            stamp = stamp,
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
        "extra_flags": attr.string_list(
            default = [],
            doc = "Extra flags to pass to verus (e.g., ['--multiple-errors', '5'])",
        ),
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

    main_src = srcs[0]

    # Collect all tool inputs
    tool_files = [verus_info.verus, verus_info.z3]
    if verus_info.vstd:
        tool_files.append(verus_info.vstd)
    if verus_info.vstd_rlib:
        tool_files.append(verus_info.vstd_rlib)

    runfiles_list = srcs + tool_files
    runfiles_list += verus_info.builtin.to_list()

    verus_bin = verus_info.verus
    z3_bin = verus_info.z3

    # Create a test runner script
    script_content = """\
#!/bin/bash
set -euo pipefail

# Resolve paths relative to runfiles
VERUS="{verus}"
Z3="{z3}"
SRC="{src}"

export VERUS_Z3_PATH="$Z3"

echo "=== Verus Verification Test ==="
echo "Source: $SRC"
echo "Verus: $VERUS"
echo ""

"$VERUS" --crate-type lib {extra_flags} "$SRC"
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
        src = main_src.short_path,
        extra_flags = " ".join(ctx.attr.extra_flags),
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
        "extra_flags": attr.string_list(
            default = [],
            doc = "Extra flags to pass to verus",
        ),
    },
    toolchains = ["@rules_verus//verus:toolchain_type"],
    test = True,
    doc = "Test target that runs Verus verification. Passes if all proofs verify.",
)
