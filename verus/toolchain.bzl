"""Verus toolchain definitions."""

# Provider for Verus toolchain information
VerusToolchainInfo = provider(
    doc = "Information about a Verus verification toolchain",
    fields = {
        "verus": "File: The verus verifier binary",
        "z3": "File: The Z3 SMT solver binary",
        "vstd": "File: The vstd pre-verified standard library (vstd.vir)",
        "vstd_rlib": "File: The vstd compiled library (libvstd.rlib)",
        "builtin": "depset of File: The builtin crate sources",
        "version": "String: Verus version",
    },
)

def _verus_toolchain_info_impl(ctx):
    """Create a VerusToolchainInfo provider for the toolchain."""
    verus_files = ctx.files.verus
    verus = verus_files[0] if verus_files else None

    z3_files = ctx.files.z3
    z3 = z3_files[0] if z3_files else None

    vstd_files = ctx.files.vstd
    vstd = None
    for f in vstd_files:
        if f.basename == "vstd.vir":
            vstd = f
            break

    vstd_rlib_files = ctx.files.vstd_rlib
    vstd_rlib = vstd_rlib_files[0] if vstd_rlib_files else None

    verus_info = struct(
        verus = verus,
        z3 = z3,
        vstd = vstd,
        vstd_rlib = vstd_rlib,
        builtin = depset(ctx.files.builtin),
        version = ctx.attr.version,
    )

    return [
        platform_common.ToolchainInfo(
            verus_info = verus_info,
        ),
    ]

verus_toolchain_info = rule(
    implementation = _verus_toolchain_info_impl,
    attrs = {
        "verus": attr.label(
            allow_files = True,
            doc = "The verus verifier binary",
        ),
        "z3": attr.label(
            allow_files = True,
            doc = "The Z3 SMT solver binary",
        ),
        "vstd": attr.label(
            allow_files = True,
            doc = "The vstd standard library files",
        ),
        "vstd_rlib": attr.label(
            allow_files = True,
            doc = "The vstd compiled rlib",
        ),
        "builtin": attr.label(
            allow_files = True,
            doc = "The builtin crate sources",
        ),
        "version": attr.string(
            doc = "Verus version string",
        ),
    },
    doc = "Provides Verus toolchain information",
)
