"""Verus toolchain definitions."""

# Provider for Verus toolchain information
VerusToolchainInfo = provider(
    doc = "Information about a Verus verification toolchain",
    fields = {
        "verus": "File: The verus wrapper binary (kept for compatibility)",
        "rust_verify": "File: The rust_verify binary (preferred verifier driver)",
        "z3": "File: The Z3 SMT solver binary",
        "vstd": "File: The vstd pre-verified standard library (vstd.vir)",
        "vstd_rlib": "File: The vstd compiled library (libvstd.rlib)",
        "builtin": "depset of File: The builtin crate sources",
        "builtin_rlib": "File: The builtin compiled library (libverus_builtin.rlib)",
        "builtin_macros_dylib": "File: The builtin_macros proc-macro library",
        "version": "String: Verus version",
        "rust_toolchain": "String: Rust toolchain version that rust_verify was built against (e.g., '1.93.0')",
    },
)

def _verus_toolchain_info_impl(ctx):
    """Create a VerusToolchainInfo provider for the toolchain."""
    verus_files = ctx.files.verus
    verus = verus_files[0] if verus_files else None

    rust_verify_files = ctx.files.rust_verify
    rust_verify = rust_verify_files[0] if rust_verify_files else None

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

    builtin_rlib_files = ctx.files.builtin_rlib
    builtin_rlib = builtin_rlib_files[0] if builtin_rlib_files else None

    builtin_macros_files = ctx.files.builtin_macros_dylib
    builtin_macros_dylib = builtin_macros_files[0] if builtin_macros_files else None

    verus_info = struct(
        verus = verus,
        rust_verify = rust_verify,
        z3 = z3,
        vstd = vstd,
        vstd_rlib = vstd_rlib,
        builtin = depset(ctx.files.builtin),
        builtin_rlib = builtin_rlib,
        builtin_macros_dylib = builtin_macros_dylib,
        version = ctx.attr.version,
        rust_toolchain = ctx.attr.rust_toolchain,
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
            doc = "The verus wrapper binary",
        ),
        "rust_verify": attr.label(
            allow_files = True,
            doc = "The rust_verify binary (modified rustc driver)",
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
        "builtin_rlib": attr.label(
            allow_files = True,
            doc = "The builtin compiled rlib (libverus_builtin.rlib)",
        ),
        "builtin_macros_dylib": attr.label(
            allow_files = True,
            doc = "The builtin_macros proc-macro library",
        ),
        "version": attr.string(
            doc = "Verus version string",
        ),
        "rust_toolchain": attr.string(
            default = "",
            doc = "Rust toolchain version that rust_verify was built against (e.g., '1.93.0')",
        ),
    },
    doc = "Provides Verus toolchain information",
)
