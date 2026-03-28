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

# Bundled Rust sysroot (librustc_driver and friends)
filegroup(
    name = "rust_sysroot_files",
    srcs = glob(["rust_sysroot/**"]),
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
    rust_sysroot = ":rust_sysroot_files",
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

    # Download the matching Rust sysroot (librustc_driver + rust-std).
    # rust_verify is dynamically linked against librustc_driver and needs
    # libstd/libcore/liballoc for compilation. Both must match exactly.
    rust_version = rctx.attr.rust_version
    if not rust_version and rust_toolchain:
        # Fallback: use version extracted from version.json
        rust_version = rust_toolchain
    if rust_version:
        # 1. Download rustc component (librustc_driver, rustc binary)
        rctx.download_and_extract(
            url = "https://static.rust-lang.org/dist/rustc-{v}-{t}.tar.xz".format(
                v = rust_version, t = platform,
            ),
            output = "rust_sysroot",
            stripPrefix = "rustc-{v}-{t}/rustc".format(
                v = rust_version, t = platform,
            ),
        )

        # 2. Download rust-std component (libstd, libcore, liballoc, etc.)
        rctx.download_and_extract(
            url = "https://static.rust-lang.org/dist/rust-std-{v}-{t}.tar.xz".format(
                v = rust_version, t = platform,
            ),
            output = "rust_std_tmp",
            stripPrefix = "rust-std-{v}-{t}/rust-std-{t}".format(
                v = rust_version, t = platform,
            ),
        )

        # Merge rust-std into sysroot (cp -R lib/rustlib into rust_sysroot/lib/rustlib)
        rctx.execute(["cp", "-R", "rust_std_tmp/lib/rustlib", "rust_sysroot/lib/rustlib"])
        rctx.execute(["rm", "-rf", "rust_std_tmp"])
    else:
        # No version known — create empty sysroot directory
        rctx.execute(["mkdir", "-p", "rust_sysroot/lib"])

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
        "rust_version": attr.string(
            default = "",
            doc = "Rust version for the sysroot to bundle (e.g., '1.93.0'). Matches version.json.",
        ),
    },
    doc = "Downloads a pre-built Verus release binary from GitHub.",
)
