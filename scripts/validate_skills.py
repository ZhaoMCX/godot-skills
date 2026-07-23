#!/usr/bin/env python3
"""验证仓库中的技能结构、可移植性与相互独立性。"""

from __future__ import annotations

import re
import sys
from pathlib import Path


ROOT = Path(__file__).resolve().parents[1]
SKILLS = ("godot-framework", "godot-change-tree")
TEXT_SUFFIXES = {".gd", ".json", ".md", ".py", ".toml", ".txt", ".yaml", ".yml"}


def fail(message: str) -> None:
    print(f"ERROR: {message}", file=sys.stderr)
    raise SystemExit(1)


def read_utf8(path: Path) -> str:
    payload = path.read_bytes()
    if payload.startswith(b"\xef\xbb\xbf"):
        fail(f"中文文件必须使用 UTF-8 without BOM：{path.relative_to(ROOT)}")
    try:
        return payload.decode("utf-8").replace("\r\n", "\n")
    except UnicodeDecodeError as error:
        fail(f"文件不是有效 UTF-8：{path.relative_to(ROOT)}（{error}）")


def text_files(skill_root: Path) -> list[Path]:
    return [
        path
        for path in skill_root.rglob("*")
        if path.is_file() and path.suffix.lower() in TEXT_SUFFIXES
    ]


def validate_skill(skill_name: str) -> None:
    skill_root = ROOT / skill_name
    skill_file = skill_root / "SKILL.md"
    agent_file = skill_root / "agents" / "openai.yaml"
    if not skill_file.is_file():
        fail(f"缺少 {skill_name}/SKILL.md")
    if not agent_file.is_file():
        fail(f"缺少 {skill_name}/agents/openai.yaml")

    skill_text = read_utf8(skill_file)
    frontmatter = re.match(r"\A---\n(.*?)\n---\n", skill_text, re.DOTALL)
    if frontmatter is None:
        fail(f"{skill_name}/SKILL.md 缺少规范 frontmatter")
    name_match = re.search(r"(?m)^name:\s*([^\n]+)$", frontmatter.group(1))
    if name_match is None or name_match.group(1).strip().strip('"\'') != skill_name:
        fail(f"{skill_name}/SKILL.md 的 name 必须等于目录名")

    agent_text = read_utf8(agent_file)
    if f"${skill_name}" not in agent_text:
        fail(f"{skill_name}/agents/openai.yaml 的默认提示必须引用自身技能")

    forbidden_names = set(SKILLS) - {skill_name}
    for path in text_files(skill_root):
        text = read_utf8(path)
        relative_path = path.relative_to(ROOT)
        for forbidden in forbidden_names:
            if re.search(rf"(?<![\w-])\$?{re.escape(forbidden)}(?![\w-])", text):
                fail(f"技能之间不得互相引用：{relative_path} -> {forbidden}")
        if ".agents/skills" in text or "res://.agents/skills" in text:
            fail(f"不得硬编码项目级安装路径：{relative_path}")
        if re.search(r"(?i)(?:^|[\s\"'])(?:[a-z]:\\|/home/|/users/)", text):
            fail(f"不得包含机器绝对路径：{relative_path}")

    if skill_name == "godot-framework":
        lowered = "\n".join(read_utf8(path).lower() for path in text_files(skill_root))
        if "guttest" in lowered or "addons/gut" in lowered:
            fail("godot-framework 不得依赖 GUT")


def main() -> int:
    actual_skills = sorted(
        path.name for path in ROOT.iterdir() if path.is_dir() and (path / "SKILL.md").is_file()
    )
    if actual_skills != sorted(SKILLS):
        fail(f"技能目录必须恰好为 {', '.join(SKILLS)}；当前为 {', '.join(actual_skills)}")
    for skill_name in SKILLS:
        validate_skill(skill_name)
    print("技能仓库验证通过：2 个技能彼此独立，路径可移植，UTF-8 编码有效。")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
