#!/usr/bin/env python3
"""Audit a Godot Framework directory for dependency and documentation contracts."""

from __future__ import annotations

import argparse
import re
import sys
from dataclasses import dataclass
from pathlib import Path
from typing import Iterable


TEXT_SUFFIXES = {".gd", ".md", ".cfg", ".godot", ".json", ".tres", ".tscn", ".yaml", ".yml"}
BUILTIN_TYPES = {
    "AABB", "Array", "Basis", "bool", "Callable", "CanvasItem", "Color", "Control",
    "Dictionary", "Error", "float", "GDScript", "int", "Logger", "Node", "Node2D", "Node3D",
    "NodePath", "Object", "PackedByteArray", "PackedColorArray", "PackedFloat32Array",
    "PackedFloat64Array", "PackedInt32Array", "PackedInt64Array", "PackedScene",
    "PackedStringArray", "PackedVector2Array", "PackedVector3Array", "Plane", "Projection",
    "Quaternion", "Rect2", "Rect2i", "RefCounted", "Resource", "RID", "SceneTree", "ScriptBacktrace",
    "Signal", "String", "StringName", "Transform2D", "Transform3D", "Variant", "Vector2", "Vector2i", "Vector3",
    "Vector3i", "Vector4", "Vector4i", "void",
}
DECLARATION_RE = re.compile(
    r"^(?P<indent>[ \t]*)(?:(?:@[A-Za-z_]\w*(?:\([^)]*\))?[ \t]+)*)"
    r"(?P<kind>signal|const|var|func|enum)\b"
)
ENUM_VALUE_RE = re.compile(r"^(?P<indent>[ \t]+)(?P<name>[A-Z][A-Z0-9_]*)\s*(?:=\s*[^,]+)?,$")
RES_PATH_RE = re.compile(r"res://[^\s\"'`)>,}]+")
CLASS_NAME_RE = re.compile(r"^\s*class_name\s+([A-Z]\w*)", re.MULTILINE)
LOCAL_CLASS_RE = re.compile(r"^\s*class\s+([A-Z]\w*)", re.MULTILINE)
ENUM_NAME_RE = re.compile(r"^\s*enum\s+([A-Z]\w*)", re.MULTILINE)
TYPE_PATTERNS = (
    re.compile(r"\bextends\s+([A-Z]\w*)"),
    re.compile(r":\s*([A-Z]\w*)"),
    re.compile(r"->\s*([A-Z]\w*)"),
    re.compile(r"\b(?:as|is)\s+([A-Z]\w*)"),
    re.compile(r"[\[,]\s*([A-Z]\w*)\s*[\],]"),
)
PLACEHOLDER_RE = re.compile(r"\b(?:TODO|TBD|FIXME)\b|待补充|占位", re.IGNORECASE)


@dataclass(frozen=True)
class Finding:
    rule: str
    path: Path
    line: int
    message: str


def _iter_text_files(root: Path) -> Iterable[Path]:
    for path in sorted(root.rglob("*")):
        if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES:
            yield path


def _strip_strings_and_comments(source: str) -> str:
    cleaned_lines: list[str] = []
    string_re = re.compile(r'"(?:\\.|[^"\\])*"|\'(?:\\.|[^\'\\])*\'')
    for line in source.splitlines():
        line = string_re.sub("", line)
        cleaned_lines.append(line.split("#", 1)[0])
    return "\n".join(cleaned_lines)


def _doc_block_before(lines: list[str], index: int, indent: str) -> tuple[int, str] | None:
    cursor = index - 1
    while cursor >= 0 and lines[cursor].strip().startswith("@"):
        cursor -= 1
    prefix = indent + "##"
    if cursor < 0 or not lines[cursor].startswith(prefix):
        return None
    end = cursor
    while cursor >= 0 and lines[cursor].startswith(prefix):
        cursor -= 1
    text = " ".join(line[len(prefix):].strip() for line in lines[cursor + 1:end + 1]).strip()
    return cursor + 1, text


def _validate_doc(
    findings: list[Finding], path: Path, line: int, block: tuple[int, str] | None, subject: str
) -> None:
    if block is None:
        findings.append(Finding("DOC001", path, line, f"{subject} 缺少紧邻的 ## 契约注释。"))
        return
    _, text = block
    if len(re.sub(r"\W", "", text, flags=re.UNICODE)) < 6 or PLACEHOLDER_RE.search(text):
        findings.append(Finding("DOC002", path, line, f"{subject} 的契约注释为空、过短或仍是占位内容。"))


def _audit_script_docs(path: Path, source: str) -> list[Finding]:
    findings: list[Finding] = []
    lines = source.splitlines()
    extends_index = next((i for i, line in enumerate(lines) if line.strip().startswith("extends ")), None)
    if extends_index is None:
        findings.append(Finding("DOC001", path, 1, "脚本缺少 extends，无法定位脚本类契约注释。"))
    else:
        cursor = extends_index + 1
        while cursor < len(lines) and not lines[cursor].strip():
            cursor += 1
        block = None
        if cursor < len(lines) and lines[cursor].startswith("##"):
            end = cursor
            while end < len(lines) and lines[end].startswith("##"):
                end += 1
            block = (cursor, " ".join(line[2:].strip() for line in lines[cursor:end]).strip())
        _validate_doc(findings, path, extends_index + 1, block, "脚本类")

    enum_ranges: list[tuple[int, int]] = []
    for index, line in enumerate(lines):
        match = DECLARATION_RE.match(line)
        if not match or match.group("indent"):
            continue
        kind = match.group("kind")
        _validate_doc(findings, path, index + 1, _doc_block_before(lines, index, ""), f"顶层 {kind} 声明")
        if kind == "enum":
            depth = line.count("{") - line.count("}")
            end = index
            while depth > 0 and end + 1 < len(lines):
                end += 1
                depth += lines[end].count("{") - lines[end].count("}")
            enum_ranges.append((index + 1, end))

    for start, end in enum_ranges:
        for index in range(start, end):
            match = ENUM_VALUE_RE.match(lines[index])
            if not match:
                continue
            indent = match.group("indent")
            _validate_doc(
                findings,
                path,
                index + 1,
                _doc_block_before(lines, index, indent),
                f"枚举值 {match.group('name')}",
            )
    return findings


def audit(
    root: Path,
    resource_prefix: str,
    allowed_types: set[str] | None = None,
    test_roots: Iterable[Path | str] = (),
    allowed_test_types: set[str] | None = None,
    allowed_test_resource_prefixes: Iterable[str] = (),
) -> list[Finding]:
    root = root.resolve()
    prefix = resource_prefix.rstrip("/") + "/"
    test_resource_prefixes = tuple(item.rstrip("/") + "/" for item in allowed_test_resource_prefixes)
    resolved_test_roots = tuple(
        (path if path.is_absolute() else root / path).resolve()
        for item in test_roots
        for path in (Path(item),)
    )

    def is_test_path(path: Path) -> bool:
        resolved = path.resolve()
        return any(resolved == test_root or test_root in resolved.parents for test_root in resolved_test_roots)

    findings: list[Finding] = []
    sources: dict[Path, str] = {}
    runtime_types = set(BUILTIN_TYPES)
    runtime_types.update(allowed_types or set())
    test_declared_types: set[str] = set()

    for path in _iter_text_files(root):
        try:
            source = path.read_text(encoding="utf-8")
        except UnicodeDecodeError:
            continue
        sources[path] = source
        if path.suffix.lower() == ".gd":
            declared_types = runtime_types if not is_test_path(path) else test_declared_types
            declared_types.update(CLASS_NAME_RE.findall(source))
            declared_types.update(ENUM_NAME_RE.findall(source))
            if is_test_path(path):
                declared_types.update(LOCAL_CLASS_RE.findall(source))

    test_types = runtime_types | test_declared_types | set(allowed_test_types or set())

    for path, source in sources.items():
        relative = path.relative_to(root)
        allowed_resource_prefixes = (prefix, *test_resource_prefixes) if is_test_path(path) else (prefix,)
        for line_number, line in enumerate(source.splitlines(), start=1):
            for resource_path in RES_PATH_RE.findall(line):
                if not resource_path.startswith(allowed_resource_prefixes):
                    findings.append(
                        Finding("DEP001", relative, line_number, f"资源引用越出插件目录：{resource_path}")
                    )
        if path.suffix.lower() != ".gd":
            continue
        findings.extend(
            Finding(item.rule, relative, item.line, item.message)
            for item in _audit_script_docs(relative, source)
        )
        declared_types = test_types if is_test_path(path) else runtime_types
        cleaned = _strip_strings_and_comments(source)
        for line_number, line in enumerate(cleaned.splitlines(), start=1):
            for pattern in TYPE_PATTERNS:
                for type_name in pattern.findall(line):
                    if type_name not in declared_types:
                        findings.append(
                            Finding("DEP002", relative, line_number, f"类型 {type_name} 不属于 Godot 内置类型或插件自身声明。")
                        )

    return sorted(set(findings), key=lambda item: (str(item.path), item.line, item.rule, item.message))


def main(argv: list[str] | None = None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("framework_root", type=Path, help="待审计的框架目录")
    parser.add_argument("--resource-prefix", required=True, help="允许的 res:// 目录前缀")
    parser.add_argument(
        "--allowed-type", action="append", default=[], help="额外允许的外部类型；插件核心通常不应使用"
    )
    parser.add_argument(
        "--test-root",
        action="append",
        default=[],
        help="相对于插件根的测试目录；该目录声明的类型不会反向满足运行时依赖",
    )
    parser.add_argument(
        "--allowed-test-type",
        action="append",
        default=[],
        help="仅允许测试目录使用的外部测试框架类型",
    )
    parser.add_argument(
        "--allowed-test-resource-prefix",
        action="append",
        default=[],
        help="仅允许测试目录引用的外部测试工具 res:// 前缀",
    )
    args = parser.parse_args(argv)
    if not args.framework_root.is_dir():
        parser.error(f"framework root does not exist: {args.framework_root}")

    findings = audit(
        args.framework_root,
        args.resource_prefix,
        set(args.allowed_type),
        args.test_root,
        set(args.allowed_test_type),
        args.allowed_test_resource_prefix,
    )
    for finding in findings:
        print(f"{finding.rule} {finding.path}:{finding.line} {finding.message}")
    print(f"Audited {args.framework_root}: {len(findings)} finding(s).")
    return 1 if findings else 0


if __name__ == "__main__":
    sys.exit(main())
