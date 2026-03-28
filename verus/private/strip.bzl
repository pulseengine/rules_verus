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
            'STRIPPED=$("{strip_tool}" "{verus}")'.format(
                strip_tool = strip_tool.short_path,
                verus = verus_src.short_path,
            ),
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
