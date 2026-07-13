#!/usr/bin/env python3
"""Validate a project's model-authored Superior Architecture artifact.

The validator checks structure, source traceability, age, and a SHA-256 binding to
its north-star input. It never generates product or architecture prose. Heartbeat
mode emits a synthesis instruction only when operator authority is explicitly
attested in the spec metadata; that attestation is not created by this script.
"""
from __future__ import annotations

import argparse
import datetime as dt
import hashlib
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


def sha256_text(text: str) -> str:
    return hashlib.sha256(text.encode()).hexdigest()


def spec_status(text: str) -> tuple[bool, bool, str]:
    """Return (structurally_valid, operator_attested, reason)."""
    fm = parse_frontmatter(text)
    substantive = len(text.strip()) >= 500
    placeholder = any(re.search(p, text, re.I | re.M) for p in (r"\{\{", r"YYYY-MM-DD", r"<project"))
    typed = fm.get("type", "").lower() == "north-star-spec"
    legacy_shape = bool(
        re.search(r"^#\s+.+North[ -]Star Specification\s*$", text, re.I | re.M)
        and re.search(r"\*\*Status:\*\*\s*North-star specification", text, re.I)
    )
    valid = substantive and not placeholder and (typed or legacy_shape)
    authority = fm.get("authority", "").lower() in {"operator", "operator-supplied", "operator-approved"}
    if not substantive:
        reason = "too short"
    elif placeholder:
        reason = "contains template placeholders"
    elif not (typed or legacy_shape):
        reason = "missing north-star-spec type/title and status provenance"
    else:
        reason = "ok"
    return valid, authority, reason


def validate(
    workspace: Path, slug: str, max_age_days: int
) -> tuple[list[str], list[str], Path, Path, bool, bool]:
    notes = workspace / "projects" / slug / "notes"
    spec = notes / f"{slug}-north-star.md"
    arch = notes / "SUPERIOR_ARCHITECTURE.md"
    blockers: list[str] = []
    warnings: list[str] = []

    candidates = [
        p for p in notes.glob("*.md")
        if "north" in p.name.lower() and "star" in p.name.lower()
        and p.name.lower() != "superior_architecture.md"
    ] if notes.exists() else []
    spec_valid = False
    spec_authorized = False
    spec_text = ""
    if not spec.is_file():
        blockers.append(f"missing authoritative spec: {spec}")
        if candidates:
            blockers.append(
                "north-star filename inconsistency: expected " + spec.name
                + "; found " + ", ".join(p.name for p in candidates)
            )
    else:
        spec_text = spec.read_text(errors="replace")
        spec_valid, spec_authorized, reason = spec_status(spec_text)
        if not spec_valid:
            blockers.append(f"north-star spec is not structurally eligible: {reason}")
        elif not spec_authorized:
            blockers.append(
                "north-star spec lacks operator authority attestation; only the operator may add "
                "frontmatter authority: operator-supplied"
            )

    if not arch.is_file():
        blockers.append(f"missing Superior Architecture: {arch}")
        return blockers, warnings, spec, arch, spec_valid, spec_authorized

    text = arch.read_text(errors="replace")
    fm = parse_frontmatter(text)
    found = [p for p in PLACEHOLDERS if re.search(p, text, re.I | re.M)]
    if found:
        blockers.append("Superior Architecture is still scaffold/placeholder content")
    if len(text.strip()) < 1500:
        blockers.append("Superior Architecture is too short to be a substantive synthesis")

    # A sources declaration is not evidence by itself. Scope parsing to the
    # Sources-index section, require concrete rows, and resolve every declared
    # local Markdown input under notes/. Hashes detect later evidence drift.
    sources = fm.get("sources", "")
    source_section_match = re.search(
        r"^## Sources index\s*$\n(.*?)(?=^##\s|\Z)", text, re.M | re.S | re.I
    )
    source_section = source_section_match.group(1) if source_section_match else ""
    source_rows = re.findall(r"^\|\s*(S?\d+)\s*\|\s*(?!…|—|\s*\|)(.+?)\s*\|", source_section, re.M)
    if not source_rows:
        blockers.append("Sources index has no concrete source rows")
    source_index_text = "\n".join(f"{label} {entry}" for label, entry in source_rows)
    declared = set(re.findall(r"\bS\d+\b|[A-Za-z0-9_.-]+\.md", sources))
    unresolved = sorted(token for token in declared if token not in source_index_text)
    if unresolved:
        blockers.append("frontmatter sources missing from Sources index: " + ", ".join(unresolved))

    hash_declarations = {
        name: digest.lower()
        for name, digest in re.findall(
            r"([A-Za-z0-9_.-]+\.md)=([0-9a-fA-F]{64})",
            fm.get("local_source_sha256", ""),
        )
    }
    local_sources = sorted(token for token in declared if token.endswith(".md") and token != spec.name)
    for name in local_sources:
        source_path = notes / name
        if not source_path.is_file():
            blockers.append(f"declared local source does not exist under notes/: {name}")
            continue
        expected_source_hash = hash_declarations.get(name)
        if not expected_source_hash:
            blockers.append(f"local_source_sha256 missing binding for {name}")
            continue
        actual_source_hash = sha256_text(source_path.read_text(errors="replace"))
        if expected_source_hash != actual_source_hash:
            blockers.append(
                f"local source changed after synthesis: {name} expected {expected_source_hash}, got {actual_source_hash}"
            )

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
        if age < 0:
            blockers.append(f"frontmatter updated is in the future: {updated_date.isoformat()}")
        elif age > max_age_days:
            blockers.append(f"Superior Architecture is stale: updated {age} days ago (limit {max_age_days})")

    # Bind synthesis to the exact product-authority bytes. Filesystem mtimes are
    # unusable after clone/copy; the hash deterministically catches spec drift.
    expected_hash = fm.get("north_star_sha256", "").lower()
    if not re.fullmatch(r"[0-9a-f]{64}", expected_hash):
        blockers.append("frontmatter north_star_sha256 must bind the exact north-star spec bytes")
    elif spec_text:
        actual_hash = sha256_text(spec_text)
        if expected_hash != actual_hash:
            blockers.append(
                "north-star spec changed after synthesis: expected sha256 "
                f"{expected_hash}, got {actual_hash}"
            )

    return blockers, warnings, spec, arch, spec_valid, spec_authorized


def main() -> int:
    parser = argparse.ArgumentParser()
    parser.add_argument("--workspace", type=Path, required=True)
    parser.add_argument("--project", required=True)
    parser.add_argument("--max-age-days", type=int, default=45)
    parser.add_argument("--heartbeat", action="store_true", help="emit a safe model-synthesis instruction when appropriate")
    args = parser.parse_args()
    blockers, warnings, spec, arch, spec_valid, spec_authorized = validate(
        args.workspace, args.project, args.max_age_days
    )
    for warning in warnings:
        print(f"WARNING: {warning}")
    if blockers:
        for blocker in blockers:
            print(f"BLOCKED: {blocker}")
        if args.heartbeat and spec_valid and spec_authorized:
            print(
                f"MODEL_ACTION: Read {spec} and authoritative project evidence, compute "
                f"north_star_sha256, then author {arch}; do not invent missing product definitions or sources."
            )
        elif args.heartbeat and spec_valid and not spec_authorized:
            print(
                "AUTHORITY_REQUIRED: operator must attest the canonical spec with "
                "frontmatter authority: operator-supplied; agents must not create that attestation"
            )
        return 1
    print(f"PASS: {arch} is substantive, source-indexed, versioned, fresh, and bound to its north-star SHA-256")
    return 0


if __name__ == "__main__":
    sys.exit(main())
