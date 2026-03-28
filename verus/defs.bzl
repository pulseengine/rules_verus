"""Public API for rules_verus.

Users should load rules from this file:
    load("@rules_verus//verus:defs.bzl", "verus_library", "verus_test", "verus_strip", "verus_strip_test")
"""

load("//verus/private:verus.bzl", _verus_library = "verus_library", _verus_test = "verus_test")
load("//verus/private:strip.bzl", _verus_strip = "verus_strip", _verus_strip_test = "verus_strip_test")

verus_library = _verus_library
verus_test = _verus_test
verus_strip = _verus_strip
verus_strip_test = _verus_strip_test
