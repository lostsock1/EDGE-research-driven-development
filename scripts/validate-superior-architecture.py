#!/usr/bin/env python3
"""Validate a project's model-authored Superior Architecture artifact.

This validator never invents product definitions or architecture prose. In heartbeat
mode it emits a synthesis prompt only when an authoritative north-star spec exists.
"""
from __future__ import annotations

import argparse
import datetime as dt
import re
import sys
from pathlib import Path

PLACEHOLDERS = (
    r"\{\{[^}]+\}\}", r"YYYY-MM-DD", r"<stage\b", r"<Slot name>",
    r"\bADAPT:", r"\| … \|", r"^- …$",
)


def parse_frontmatter(text: str) -> dict[str, str]:
    if not text.startswith("---\n"):
        return {}
    try:
        block = text.split("---\n", 2)[1]
    except IndexError:
        return {}
    values: dict[str, str] = {}
    for line in block.splitlines():
        if ":" in line:
            key, value = line.split(":", 1)
            values[key.strip()] = value.strip()
    return values


def validate(workspace: Path, slug: str, max_age_days: int) -> tuple[list[str], list[str], Path, Path]:
    notes = workspace / "projects" / slug / "notes"
    spec = notes / f"{slug}-north-star.md"
    arch = notes / "SUPERIOR_ARCHITECTURE.md"
    blockers: list[str] = []
    warnings: list[str] = []

    candidates = [p for p in notes.glob("*.md") if "north" in p.name.lower() and "star" in p.name.lower() and p.name.lower() != "superior_architecture.md"] if notes.exists() else []
    if not spec.is_file():
        blockers.append(f"missing authoritative spec: {spec}")
        if candidates:
            blockers.append("north-star filename inconsistency: expected " + spec.name + "; found " + ", ".join(p.name for p in candidates))
    else:
        spec_text = spec.read_text(errors="replace")
        if len(spec_text.strip()) < 500 or any(re.search(p, spec_text, re.I | re.M) for p in (r"\{\{", r"YYYY-MM-DD", r"<project")):
            blockers.append("authoritative spec is empty, too short, or still contains template placeholders")

    if not arch.is_file():
        blockers.append(f"missing Superior Architecture: {arch}")
        return blockers, warnings, spec, arch

    text = arch.read_text(errors="replace")
    fm = parse_frontmatter(text)
    found = [p for p in PLACEHOLDERS if re.search(p, text, re.I | re.M)]
    if found:
        blockers.append("Superior Architecture is still scaffold/placeholder content")
    if len(text.strip()) < 1500:
        blockers.append("Superior Architecture is too short to be a substantive synthesis")

    sources = fm.get("sources", "")
    source_rows = re.findall(r"^\|\s*S\d+\s*\|\s*(?!…|—|\s*\|)(.+?)\s*\|", text, re.M)
    if sources in ("", "[]") and not source_rows:
        blockers.append("sources are missing (frontmatter sources and Sources index are empty)")

    versions = re.findall(r"^\|\s*v\d+(?:\.\d+)*\s*\|\s*(\d{4}-\d{2}-\d{2})\s*\|", text, re.M)
    if not versions:
        blockers.append("version log has no concrete version/date entry")

    updated = fm.get("updated", "")
    try:
        updated_date = dt.date.fromisoformat(updated)
    except ValueError:
        blockers.append("frontmatter updated must be a concrete ISO date")
        updated_date = None
    if updated_date:
        age = (dt.date.today() - updated_date).days
        if age > max_age_days:
            blockers.append(f"Superior Architecture is stale: updated {age} days ago (limit {max_age_days})")
        authoritative = [p for p in notes.glob("*.md") if p != arch and p.is_file()]
        newer = [p.name for p in authoritative if dt.date.fromtimestamp(p.stat().st_mtime) > updated_date]
        if newer:
            blockers.append("authoritative inputs newer than synthesis: " + ", ".join(sorted(newer)))
    return blockers, warnings, spec, arch


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--max-age-days", type=int, default=45)
    parser.add_argument("--heartbeat", action="store_true", help="emit a safe model-synthesis instruction when appropriate")
    args = parser.parse_args()
    blockers, warnings, spec, arch = validate(args.workspace, args.project, args.max_age_days)
    for warning in warnings:
        print(f"WARNING: {warning}")
    if blockers:
        for blocker in blockers:
            print(f"BLOCKED: {blocker}")
        if args.heartbeat and spec.is_file():
            print(f"MODEL_ACTION: Read {spec} and authoritative project evidence, then author {arch}; do not invent missing product definitions or sources.")
        return 1
    print(f"PASS: {arch} is substantive, sourced, versioned, and fresh")
    return 0


if __name__ == "__main__":
    sys.exit(main())
