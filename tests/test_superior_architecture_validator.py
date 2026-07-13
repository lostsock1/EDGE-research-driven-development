import datetime as dt
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "validate-superior-architecture.py"


class SuperiorArchitectureValidatorTests(unittest.TestCase):
    def run_validator(self, spec=None, architecture=None, extra_name=None, heartbeat=False):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            notes = root / "projects" / "demo" / "notes"
            notes.mkdir(parents=True)
            if spec is not None:
                (notes / "demo-north-star.md").write_text(spec)
            if extra_name:
                (notes / extra_name).write_text("authoritative " * 100)
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

    def test_scaffold_blocks_and_requests_model_only_with_valid_spec(self):
        result = self.run_validator(spec="product definition " * 80, architecture="{{PROJECT_NAME}} YYYY-MM-DD <stage 1>", heartbeat=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("scaffold/placeholder", result.stdout)
        self.assertIn("MODEL_ACTION", result.stdout)

    def test_substantive_sourced_versioned_fresh_document_passes(self):
        today = dt.date.today().isoformat()
        architecture = f"""---
status: living
updated: {today}
sources: [S1]
---
# Superior Demo Architecture

## Architecture overview
""" + ("Evidence-weighted mechanism and rival analysis. " * 50) + f"""

## Subsystem decisions
The best-known choice is supported by field evidence and compared against a concrete rival.

## What changed — version log
| Version | Date | Change | Evidence |
|---|---|---|---|
| v1.0 | {today} | Model-authored synthesis | S1 |

## Sources index
| # | Source (external or internal) | Key finding |
|---|---|---|
| S1 | https://example.org/paper | Mechanism evidence |
"""
        result = self.run_validator(spec="product definition " * 80, architecture=architecture)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS:", result.stdout)


if __name__ == "__main__":
    unittest.main()
