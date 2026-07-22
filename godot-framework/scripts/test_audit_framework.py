#!/usr/bin/env python3
"""Regression tests for audit_framework.py using isolated framework fixtures."""

from __future__ import annotations

import tempfile
import unittest
from pathlib import Path

from audit_framework import audit


VALID_SCRIPT = """@abstract
class_name GFProbe
extends RefCounted

## 管理一个独立测试生命周期，不负责外部资源。

## 描述测试对象从创建到结束的状态。
enum Lifecycle {
    ## 对象已经创建但尚未运行。
    CREATED,
    ## 对象已经完成全部工作。
    STOPPED,
}

## 当前测试状态，只由 finish 推进。
var lifecycle := Lifecycle.CREATED

## 结束测试生命周期；重复调用保持最终状态不变。
func finish() -> void:
    lifecycle = Lifecycle.STOPPED
"""


class AuditFrameworkTests(unittest.TestCase):
    def _audit_fixture(self, files: dict[str, str], **audit_options):
        with tempfile.TemporaryDirectory() as temporary_directory:
            root = Path(temporary_directory) / "framework"
            root.mkdir()
            for relative_path, content in files.items():
                path = root / relative_path
                path.parent.mkdir(parents=True, exist_ok=True)
                path.write_text(content, encoding="utf-8")
            return audit(root, "res://portable_framework/", **audit_options)

    def test_valid_contract_and_internal_resource_reference_pass(self) -> None:
        findings = self._audit_fixture(
            {"core/probe.gd": VALID_SCRIPT, "README.md": "`res://portable_framework/core/probe.gd`"}
        )
        self.assertEqual([], findings)

    def test_missing_member_comment_and_placeholder_comment_fail(self) -> None:
        invalid = VALID_SCRIPT.replace(
            "## 当前测试状态，只由 finish 推进。\nvar lifecycle",
            "var lifecycle",
        ).replace(
            "## 结束测试生命周期；重复调用保持最终状态不变。",
            "## TODO",
        )
        findings = self._audit_fixture({"core/probe.gd": invalid})
        self.assertEqual({"DOC001", "DOC002"}, {finding.rule for finding in findings})

    def test_external_resource_reference_fails(self) -> None:
        findings = self._audit_fixture(
            {"core/probe.gd": VALID_SCRIPT, "README.md": "`res://consumer_project/main.tscn`"}
        )
        self.assertIn("DEP001", {finding.rule for finding in findings})

    def test_enum_value_without_contract_comment_fails(self) -> None:
        invalid = VALID_SCRIPT.replace("    ## 对象已经完成全部工作。\n", "")
        findings = self._audit_fixture({"core/probe.gd": invalid})
        self.assertIn("DOC001", {finding.rule for finding in findings})

    def test_external_project_type_fails(self) -> None:
        invalid = VALID_SCRIPT.replace("extends RefCounted", "extends ConsumerScreen")
        findings = self._audit_fixture({"core/probe.gd": invalid})
        self.assertIn("DEP002", {finding.rule for finding in findings})

    def test_local_variables_do_not_require_comments(self) -> None:
        script = VALID_SCRIPT.replace(
            "    lifecycle = Lifecycle.STOPPED",
            "    var next_state := Lifecycle.STOPPED\n    lifecycle = next_state",
        )
        findings = self._audit_fixture({"core/probe.gd": script})
        self.assertEqual([], findings)

    def test_test_dependency_is_allowed_only_under_declared_test_root(self) -> None:
        external_test_script = VALID_SCRIPT.replace("extends RefCounted", "extends ExternalTestBase")
        test_findings = self._audit_fixture(
            {"tests/test_probe.gd": external_test_script},
            test_roots=["tests"],
            allowed_test_types={"ExternalTestBase"},
        )
        runtime_findings = self._audit_fixture(
            {"core/probe.gd": external_test_script},
            test_roots=["tests"],
            allowed_test_types={"ExternalTestBase"},
        )

        self.assertEqual([], test_findings)
        self.assertIn("DEP002", {finding.rule for finding in runtime_findings})

    def test_test_declared_type_cannot_satisfy_runtime_dependency(self) -> None:
        runtime_script = VALID_SCRIPT.replace("extends RefCounted", "extends TestOnlyHelper")
        test_helper = VALID_SCRIPT.replace("class_name GFProbe", "class_name TestOnlyHelper")
        findings = self._audit_fixture(
            {
                "core/probe.gd": runtime_script,
                "tests/test_only_helper.gd": test_helper,
            },
            test_roots=["tests"],
        )

        self.assertIn("DEP002", {finding.rule for finding in findings})

    def test_test_resource_prefix_is_allowed_only_under_declared_test_root(self) -> None:
        test_findings = self._audit_fixture(
            {"tests/README.md": "Runner: `res://addons/external_test/runner.gd`"},
            test_roots=["tests"],
            allowed_test_resource_prefixes=["res://addons/external_test/"],
        )
        runtime_findings = self._audit_fixture(
            {"README.md": "Runner: `res://addons/external_test/runner.gd`"},
            test_roots=["tests"],
            allowed_test_resource_prefixes=["res://addons/external_test/"],
        )

        self.assertEqual([], test_findings)
        self.assertIn("DEP001", {finding.rule for finding in runtime_findings})


if __name__ == "__main__":
    unittest.main()
