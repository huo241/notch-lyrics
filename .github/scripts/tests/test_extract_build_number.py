#!/usr/bin/env python3
"""Behavioral tests for extract_build_number.py."""

from __future__ import annotations

import sys
import unittest
from pathlib import Path


SCRIPT_DIR = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(SCRIPT_DIR))

from extract_build_number import extract_build_number  # noqa: E402


PROJECT = """
buildSettings = {
    CURRENT_PROJECT_VERSION = 272;
    PRODUCT_BUNDLE_IDENTIFIER = blog.snappy.notchlyrics;
};
buildSettings = {
    CURRENT_PROJECT_VERSION = 272;
    PRODUCT_BUNDLE_IDENTIFIER = blog.snappy.notchlyrics;
};
buildSettings = {
    CURRENT_PROJECT_VERSION = 900;
    PRODUCT_BUNDLE_IDENTIFIER = blog.snappy.notchlyrics.XPCHelper;
};
"""


class ExtractBuildNumberTests(unittest.TestCase):
    def test_extracts_the_app_target_build(self) -> None:
        self.assertEqual(
            extract_build_number(PROJECT, "blog.snappy.notchlyrics"),
            "272",
        )

    def test_rejects_bad_project_state(self) -> None:
        disagreeing = PROJECT.replace(
            "CURRENT_PROJECT_VERSION = 272;",
            "CURRENT_PROJECT_VERSION = 271;",
            1,
        )
        with self.assertRaisesRegex(ValueError, "disagree"):
            extract_build_number(disagreeing, "blog.snappy.notchlyrics")

        with self.assertRaisesRegex(ValueError, "No build settings"):
            extract_build_number(PROJECT, "missing.bundle")

        non_integer = PROJECT.replace(
            "CURRENT_PROJECT_VERSION = 272;",
            "CURRENT_PROJECT_VERSION = beta;",
        )
        with self.assertRaisesRegex(ValueError, "positive integer"):
            extract_build_number(non_integer, "blog.snappy.notchlyrics")


if __name__ == "__main__":
    unittest.main()
