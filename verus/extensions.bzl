"""Module extension for Verus toolchain setup.

Downloads pre-built Verus release binaries from GitHub for the host platform.
"""

load("//verus/private:repo.bzl", "verus_release")

# Known release versions and their SHA-256 hashes per platform.
# Empty string means hash verification is skipped (fill in for reproducibility).
_KNOWN_VERSIONS = {
    "0.2026.02.15": {
        "tag": "0.2026.02.15.61aa1bf",
        "rust_version": "1.93.0",  # Stable Rust version for librustc_driver (auto-downloaded)
        "sha256": {
            "aarch64-apple-darwin": "185ac0631d3639da5ba09d6e50218af43efffa58383625dd070e6c2ecc11da65",
            "x86_64-apple-darwin": "bfb79474f078782104d6a80b21069f104eed8f7bac51d16a0216ca07d0b021e6",
            "x86_64-unknown-linux-gnu": "d02ce8c026e3304e3d463355678dced46d5d8340fdebd9a8cdaea27c29338e0b",
            "x86_64-pc-windows-msvc": "63ba4e37a530a27bac3fab5bb47f6885888ab181e6d5c95bae1d5a01fcd6956d",
        },
    },
}

_VerusToolchainTag = tag_class(
    doc = "Configuration for Verus toolchain download",
    attrs = {
        "version": attr.string(
            doc = "Verus release version (e.g., '0.2026.02.15'). Maps to GitHub release tag.",
            default = "0.2026.02.15",
        ),
        "sha256": attr.string_dict(
            doc = "Per-platform SHA-256 hashes. Keys are platform triples. Empty to skip.",
            default = {},
        ),
    },
)

def _detect_platform(module_ctx):
    """Detect the host platform triple."""
    # In Bazel, we create repos for all platforms and let toolchain resolution pick.
    # But for simplicity, we can detect the host and create just that one.
    # For cross-platform support, create all platform repos.
    return [
        "aarch64-apple-darwin",
        "x86_64-apple-darwin",
        "x86_64-unknown-linux-gnu",
    ]

def _verus_impl(module_ctx):
    """Implementation of Verus toolchain extension."""
    configs = []
    for mod in module_ctx.modules:
        for toolchain in mod.tags.toolchain:
            configs.append(toolchain)

    if configs:
        config = configs[0]
        version_key = config.version
        sha256_overrides = config.sha256
    else:
        version_key = "0.2026.02.15"
        sha256_overrides = {}

    # Resolve version to full release tag
    version_info = _KNOWN_VERSIONS.get(version_key)
    if version_info:
        release_tag = version_info["tag"]
        known_hashes = version_info["sha256"]
    else:
        # Assume the version string is the full tag
        release_tag = version_key
        known_hashes = {}

    # Resolve Rust version for bundled sysroot (librustc_driver)
    rust_version = ""
    if version_info:
        rust_version = version_info.get("rust_version", "")

    # Create a repository for each supported platform
    platforms = _detect_platform(module_ctx)
    for platform in platforms:
        sha256 = sha256_overrides.get(platform, known_hashes.get(platform, ""))

        repo_name = "verus_toolchains_" + platform.replace("-", "_")
        verus_release(
            name = repo_name,
            version = release_tag,
            platform = platform,
            sha256 = sha256,
            rust_version = rust_version,
        )

    # Create a hub repo that aliases to the correct platform-specific repo
    _verus_hub_repo(
        name = "verus_toolchains",
        platforms = platforms,
    )

    return module_ctx.extension_metadata(reproducible = True)

# Mapping from platform triple to Bazel exec_compatible_with constraints.
# Kept in sync with the per-platform `exec_constraints` branch in
# verus/private/repo.bzl (_verus_release_impl).
_PLATFORM_CONSTRAINTS = {
    "aarch64-apple-darwin": ["@platforms//os:macos", "@platforms//cpu:aarch64"],
    "x86_64-apple-darwin": ["@platforms//os:macos", "@platforms//cpu:x86_64"],
    "x86_64-unknown-linux-gnu": ["@platforms//os:linux", "@platforms//cpu:x86_64"],
    "x86_64-pc-windows-msvc": ["@platforms//os:windows", "@platforms//cpu:x86_64"],
}

def _verus_hub_repo_impl(rctx):
    """Create a hub repo that registers each platform's Verus toolchain.

    The hub repo emits one `toolchain()` declaration per supported platform,
    each wrapping the platform-specific `verus_toolchain_info` provider from
    the downloaded release repo. Declaring `toolchain()` rules (rather than
    aliases) in the hub repo means `register_toolchains("@verus_toolchains//:all")`
    resolves via Bazel's wildcard-package target expansion and registers all
    platforms at once — native toolchain resolution then picks the right one
    based on `exec_compatible_with`.

    We deliberately do not emit a target literally named `all`: that name
    shadows the wildcard, and the ambiguity previously caused
    `register_toolchains` to resolve to a single-platform alias rather than
    iterating over the package.
    """
    platforms = rctx.attr.platforms

    lines = [
        'package(default_visibility = ["//visibility:public"])',
        "",
    ]

    # Emit one toolchain() wrapper per supported platform. Each wraps the
    # platform-specific verus_toolchain_info provider, with matching
    # exec/target constraints. Bazel's toolchain resolution then selects
    # the correct one for the current exec platform.
    for platform in platforms:
        repo_name = "verus_toolchains_" + platform.replace("-", "_")
        slug = platform.replace("-", "_")
        constraints = _PLATFORM_CONSTRAINTS.get(platform)
        if not constraints:
            # Platform supported at download time but no constraint mapping —
            # skip rather than emitting an un-gated toolchain that could be
            # picked for the wrong host.
            continue
        constraints_list = "[" + ", ".join(['"{}"'.format(c) for c in constraints]) + "]"
        lines.append("toolchain(")
        lines.append('    name = "{}_toolchain",'.format(slug))
        lines.append('    toolchain = "@{}//:verus_toolchain_info",'.format(repo_name))
        lines.append('    toolchain_type = "@rules_verus//verus:toolchain_type",')
        lines.append("    exec_compatible_with = {},".format(constraints_list))
        lines.append("    target_compatible_with = {},".format(constraints_list))
        lines.append(")")
        lines.append("")

    rctx.file("BUILD.bazel", "\n".join(lines) + "\n")

_verus_hub_repo = repository_rule(
    implementation = _verus_hub_repo_impl,
    attrs = {
        "platforms": attr.string_list(
            doc = "List of platform triples with available repos",
        ),
    },
)

verus = module_extension(
    doc = "Verus verification toolchain extension. Downloads pre-built binaries from GitHub releases.",
    implementation = _verus_impl,
    tag_classes = {
        "toolchain": _VerusToolchainTag,
    },
)
