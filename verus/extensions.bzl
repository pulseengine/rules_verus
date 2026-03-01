"""Module extension for Verus toolchain setup.

Downloads pre-built Verus release binaries from GitHub for the host platform.
"""

load("//verus/private:repo.bzl", "verus_release")

# Known release versions and their SHA-256 hashes per platform.
# Empty string means hash verification is skipped (fill in for reproducibility).
_KNOWN_VERSIONS = {
    "0.2026.02.15": {
        "tag": "0.2026.02.15.61aa1bf",
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
        )

    # Create a hub repo that aliases to the correct platform-specific repo
    _verus_hub_repo(
        name = "verus_toolchains",
        platforms = platforms,
    )

    return module_ctx.extension_metadata(reproducible = True)

def _verus_hub_repo_impl(rctx):
    """Create a hub repo that re-exports all platform toolchains."""
    platforms = rctx.attr.platforms

    toolchain_entries = []
    for platform in platforms:
        repo_name = "verus_toolchains_" + platform.replace("-", "_")
        toolchain_entries.append(
            '    "@{repo}//:verus_toolchain",'.format(repo = repo_name),
        )

    build_content = """\
package(default_visibility = ["//visibility:public"])

# Re-export all platform toolchains.
# Bazel's toolchain resolution selects the correct one based on exec platform.
alias(
    name = "all",
    actual = ":toolchain_group",
)

# Toolchain group — register all platform variants
{entries}
""".format(
        entries = "\n".join([
            'alias(name = "toolchain_{i}", actual = "{entry}")'.format(
                i = i,
                entry = entry.strip().rstrip(",").strip('"'),
            )
            for i, entry in enumerate(toolchain_entries)
        ]),
    )

    # Simpler approach: just create aliases for register_toolchains
    # register_toolchains("@verus_toolchains//:all") needs to work
    lines = ['package(default_visibility = ["//visibility:public"])', ""]
    for platform in platforms:
        repo_name = "verus_toolchains_" + platform.replace("-", "_")
        slug = platform.replace("-", "_")
        lines.append('alias(name = "{slug}", actual = "@{repo}//:verus_toolchain")'.format(
            slug = slug,
            repo = repo_name,
        ))
        lines.append("")

    # The :all alias that register_toolchains expects
    # For multi-platform, we register each individually
    # Create a filegroup as the :all target
    if platforms:
        first_repo = "verus_toolchains_" + platforms[0].replace("-", "_")
        lines.append('alias(name = "all", actual = "@{repo}//:verus_toolchain")'.format(
            repo = first_repo,
        ))

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
