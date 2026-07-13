import datetime as dt
import hashlib
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "validate-superior-architecture.py"


def valid_spec(authority=True):
    auth = "authority: operator-supplied\n" if authority else ""
    return f"""---
type: north-star-spec
status: unprocessed
{auth}---
# Demo North Star Specification

""" + ("Operator product definition and non-negotiable intent. " * 30)


def architecture_for(spec, *, date=None, sources="[S1]", include_source=True,
                     source_entry="https://example.org/paper", local_hashes="[]"):
    date = date or dt.date.today().isoformat()
    digest = hashlib.sha256(spec.encode()).hexdigest()
    source_rows = f"| S1 | {source_entry} | Mechanism evidence |" if include_source else ""
    return f"""---
status: living
updated: {date}
sources: {sources}
north_star_sha256: {digest}
local_source_sha256: {local_hashes}
---
# Superior Demo Architecture

## Architecture overview
""" + ("Evidence-weighted mechanism and rival analysis. " * 50) + f"""

## Subsystem decisions
The best-known choice is supported by field evidence and compared against a concrete rival.

## What changed — version log
| Version | Date | Change | Evidence |
|---|---|---|---|
| v1.0 | {date} | Model-authored synthesis | S1 |

## Sources index
| # | Source (external or internal) | Key finding |
|---|---|---|
{source_rows}
"""


class SuperiorArchitectureValidatorTests(unittest.TestCase):
    def run_validator(self, spec=None, architecture=None, extra_name=None, heartbeat=False, local_files=None):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            notes = root / "projects" / "demo" / "notes"
            notes.mkdir(parents=True)
            if spec is not None:
                (notes / "demo-north-star.md").write_text(spec)
            if extra_name:
                (notes / extra_name).write_text("authoritative " * 100)
            for name, content in (local_files or {}).items():
                (notes / name).write_text(content)
            if architecture is not None:
                (notes / "SUPERIOR_ARCHITECTURE.md").write_text(architecture)
            cmd = [str(SCRIPT), "--workspace", str(root), "--project", "demo"]
            if heartbeat:
                cmd.append("--heartbeat")
            return subprocess.run(cmd, text=True, capture_output=True)

    def test_missing_spec_blocks_without_synthesis_prompt(self):
        result = self.run_validator(architecture="# architecture\n", heartbeat=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("missing authoritative spec", result.stdout)
        self.assertNotIn("MODEL_ACTION", result.stdout)

    def test_inconsistent_spec_filename_is_reported(self):
        result = self.run_validator(extra_name="Demo_North_Star.md")
        self.assertIn("filename inconsistency", result.stdout)

    def test_scaffold_requests_model_only_with_operator_attested_spec(self):
        spec = valid_spec(authority=True)
        result = self.run_validator(spec=spec, architecture="{{PROJECT_NAME}} YYYY-MM-DD <stage 1>", heartbeat=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("scaffold/placeholder", result.stdout)
        self.assertIn("MODEL_ACTION", result.stdout)

    def test_structural_spec_without_operator_attestation_never_authorizes_model(self):
        spec = valid_spec(authority=False)
        result = self.run_validator(spec=spec, architecture="{{PROJECT_NAME}} YYYY-MM-DD", heartbeat=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("AUTHORITY_REQUIRED", result.stdout)
        self.assertNotIn("MODEL_ACTION", result.stdout)

    def test_complete_architecture_cannot_pass_without_operator_attestation(self):
        spec = valid_spec(authority=False)
        result = self.run_validator(spec=spec, architecture=architecture_for(spec))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("lacks operator authority attestation", result.stdout)
        self.assertNotIn("PASS:", result.stdout)

    def test_invalid_spec_never_authorizes_model_synthesis(self):
        result = self.run_validator(spec="{{PROJECT_NAME}}", architecture="# architecture\n", heartbeat=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("north-star spec is not structurally eligible", result.stdout)
        self.assertNotIn("MODEL_ACTION", result.stdout)

    def test_substantive_sourced_versioned_fresh_document_passes(self):
        spec = valid_spec()
        result = self.run_validator(spec=spec, architecture=architecture_for(spec))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS:", result.stdout)

    def test_unresolved_frontmatter_source_is_rejected(self):
        spec = valid_spec()
        result = self.run_validator(spec=spec, architecture=architecture_for(spec, sources="[S999]"))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("S999", result.stdout)

    def test_sources_index_rows_are_required(self):
        spec = valid_spec()
        result = self.run_validator(spec=spec, architecture=architecture_for(spec, include_source=False))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("Sources index has no concrete source rows", result.stdout)

    def test_declared_local_source_must_exist(self):
        spec = valid_spec()
        architecture = architecture_for(spec, sources="[missing.md]", source_entry="missing.md")
        result = self.run_validator(spec=spec, architecture=architecture)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("declared local source does not exist", result.stdout)

    def test_changed_local_source_hash_is_rejected(self):
        spec = valid_spec()
        original = "accepted evidence\n"
        digest = hashlib.sha256(original.encode()).hexdigest()
        architecture = architecture_for(
            spec, sources="[evidence.md]", source_entry="evidence.md",
            local_hashes=f"[evidence.md={digest}]",
        )
        result = self.run_validator(
            spec=spec, architecture=architecture,
            local_files={"evidence.md": "changed evidence\n"},
        )
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("local source changed after synthesis", result.stdout)

    def test_changed_north_star_hash_is_rejected(self):
        spec = valid_spec()
        architecture = architecture_for(spec)
        changed_spec = spec + "\nOperator-added requirement.\n"
        result = self.run_validator(spec=changed_spec, architecture=architecture)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("north-star spec changed after synthesis", result.stdout)

    def test_future_updated_date_is_rejected(self):
        spec = valid_spec()
        future = (dt.date.today() + dt.timedelta(days=1)).isoformat()
        result = self.run_validator(spec=spec, architecture=architecture_for(spec, date=future))
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("updated is in the future", result.stdout)


if __name__ == "__main__":
    unittest.main()
