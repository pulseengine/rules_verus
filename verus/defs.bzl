"""Public API for Verus verification rules."""

load("//verus/private:verus.bzl", _verus_library = "verus_library", _verus_test = "verus_test")

verus_library = _verus_library
verus_test = _verus_test
