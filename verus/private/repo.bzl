"""Repository rule for downloading Verus release binaries."""

# Platform-specific release artifact names
_PLATFORM_MAP = {
    "aarch64-apple-darwin": "arm64-macos",
    "x86_64-apple-darwin": "x86-macos",
    "x86_64-unknown-linux-gnu": "x86-linux",
    "x86_64-pc-windows-msvc": "x86-win",
}

# BUILD file template for the downloaded Verus toolchain
_BUILD_FILE_CONTENT = '''
load("@rules_verus//verus:toolchain.bzl", "verus_toolchain_info")

package(default_visibility = ["//visibility:public"])

# Verus wrapper binary (kept for reference; rust_verify is preferred)
filegroup(
    name = "verus_bin",
    srcs = ["verus"],
)

# rust_verify binary (the actual rustc driver — preferred over verus wrapper)
filegroup(
    name = "rust_verify_bin",
    srcs = ["rust_verify"],
)

# Z3 SMT solver
filegroup(
    name = "z3_bin",
    srcs = ["z3"],
)

# Pre-verified vstd library
filegroup(
    name = "vstd_files",
    srcs = glob(["vstd.vir", ".vstd-fingerprint"]),
)

# Compiled vstd rlib
filegroup(
    name = "vstd_rlib",
    srcs = ["libvstd.rlib"],
)

# Compiled builtin rlib
filegroup(
    name = "builtin_rlib",
    srcs = ["libverus_builtin.rlib"],
)

# Compiled builtin_macros proc-macro (platform-dependent extension)
filegroup(
    name = "builtin_macros_dylib",
    srcs = glob(["libverus_builtin_macros.*"]),
)

# Builtin crate sources
filegroup(
    name = "builtin_srcs",
    srcs = glob(["builtin/**"]),
)

# All Verus files (for runfiles)
filegroup(
    name = "all_files",
    srcs = glob(["**"]),
)

verus_toolchain_info(
    name = "verus_toolchain_info",
    verus = ":verus_bin",
    rust_verify = ":rust_verify_bin",
    z3 = ":z3_bin",
    vstd = ":vstd_files",
    vstd_rlib = ":vstd_rlib",
    builtin = ":builtin_srcs",
    builtin_rlib = ":builtin_rlib",
    builtin_macros_dylib = ":builtin_macros_dylib",
    version = "{version}",
    rust_toolchain = "{rust_toolchain}",
)

toolchain(
    name = "verus_toolchain",
    toolchain = ":verus_toolchain_info",
    toolchain_type = "@rules_verus//verus:toolchain_type",
    exec_compatible_with = {exec_constraints},
)

alias(
    name = "all",
    actual = ":verus_toolchain",
)
'''

def _verus_release_impl(rctx):
    """Download and extract a Verus release binary."""
    version = rctx.attr.version
    platform = rctx.attr.platform

    platform_slug = _PLATFORM_MAP.get(platform)
    if not platform_slug:
        fail("Unsupported platform: {}. Supported: {}".format(
            platform,
            ", ".join(_PLATFORM_MAP.keys()),
        ))

    # Construct download URL
    artifact_name = "verus-{version}-{platform}.zip".format(
        version = version,
        platform = platform_slug,
    )
    url = "https://github.com/verus-lang/verus/releases/download/release/{version}/{artifact}".format(
        version = version,
        artifact = artifact_name,
    )

    # Download and extract
    rctx.download_and_extract(
        url = url,
        sha256 = rctx.attr.sha256,
        stripPrefix = "verus-{platform}".format(platform = platform_slug),
    )

    # Make binaries executable (important for macOS)
    rctx.execute(["chmod", "+x", "verus"])
    rctx.execute(["chmod", "+x", "rust_verify"])
    rctx.execute(["chmod", "+x", "z3"])

    # Remove macOS quarantine if on macOS
    if "macos" in platform_slug:
        rctx.execute(["xattr", "-cr", "."], quiet = True)

    # Determine exec_compatible_with constraints
    if "arm64-macos" == platform_slug:
        exec_constraints = '["@platforms//os:macos", "@platforms//cpu:aarch64"]'
    elif "x86-macos" == platform_slug:
        exec_constraints = '["@platforms//os:macos", "@platforms//cpu:x86_64"]'
    elif "x86-linux" == platform_slug:
        exec_constraints = '["@platforms//os:linux", "@platforms//cpu:x86_64"]'
    elif "x86-win" == platform_slug:
        exec_constraints = '["@platforms//os:windows", "@platforms//cpu:x86_64"]'
    else:
        exec_constraints = "[]"

    # Extract the Rust toolchain version from version.json
    # Verus bundles this file with the release and it specifies which
    # Rust toolchain rust_verify was compiled against.
    rust_toolchain = ""
    result = rctx.execute(["python3", "-c",
        "import json; d=json.load(open('version.json')); print(d['verus']['toolchain'].split('-')[0])",
    ])
    if result.return_code == 0:
        rust_toolchain = result.stdout.strip()

    # Write BUILD file
    rctx.file("BUILD.bazel", _BUILD_FILE_CONTENT.format(
        version = version,
        exec_constraints = exec_constraints,
        rust_toolchain = rust_toolchain,
    ))

verus_release = repository_rule(
    implementation = _verus_release_impl,
    attrs = {
        "version": attr.string(
            mandatory = True,
            doc = "Verus release version (e.g., '0.2026.02.15.61aa1bf')",
        ),
        "platform": attr.string(
            mandatory = True,
            doc = "Target platform triple",
        ),
        "sha256": attr.string(
            default = "",
            doc = "SHA-256 hash of the release zip (empty to skip verification)",
        ),
    },
    doc = "Downloads a pre-built Verus release binary from GitHub.",
)
