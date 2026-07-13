import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "edge-pr-gate.sh"

FAKE_GH = r'''#!/usr/bin/env python3
import json, os, sys
args = sys.argv[1:]
mode = os.environ.get("FAKE_CHECK_MODE", "green")
if args[:2] == ["repo", "view"]:
    print("owner/repo")
elif args[:2] == ["pr", "list"]:
    print(json.dumps([{"number": 1, "title": "feat: change", "headRefName": "cm/change", "headRefOid": "abc123", "isDraft": False, "url": "https://example/pr/1"}]))
elif args[:2] == ["pr", "checks"]:
    if mode == "no-ci": print("[]")
    elif mode == "missing": print(json.dumps([{"name":"tests","bucket":"pass"}]))
    else: print(json.dumps([{"name":"tests","bucket":"pass"},{"name":"lint","bucket":"pass"}]))
elif args and args[0] == "api" and "issues/1/comments" in " ".join(args):
    review = os.environ.get("FAKE_REVIEW", "pass")
    if review == "missing": print("[]")
    else: print(json.dumps([{"body":f"<!-- edge-review-gate sha=abc123 class=nontrivial verdict={review} ready={'yes' if review.startswith('pass') else 'no'} trust=model-reported -->"}]))
elif args and args[0] == "api" and "branches?" in " ".join(args):
    print("main\ncm/change")
else:
    print("[]")
'''


class PrGateTests(unittest.TestCase):
    def run_gate(self, mode, review="pass"):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            bindir = root / "bin"; bindir.mkdir()
            gh = bindir / "gh"; gh.write_text(FAKE_GH); gh.chmod(0o755)
            repo = root / "repo"; (repo / ".git").mkdir(parents=True)
            cfg = root / "cfg"; cfg.mkdir()
            (cfg / "config.env").write_text('RDD_REQUIRED_CHECKS="tests,lint"\n')
            (cfg / "demo.env").write_text(f"RDD_REPO_DIR={repo}\nRDD_MAIN_BRANCH=main\n")
            env = os.environ.copy()
            env.update({"PATH": f"{bindir}:{env['PATH']}", "RDD_GATE_CONFIG_DIR": str(cfg),
                        "RDD_GATE_STATE_DIR": str(root / "state"), "FAKE_CHECK_MODE": mode, "FAKE_REVIEW": review})
            return subprocess.run([str(SCRIPT), "sweep", "--dry-run"], env=env, text=True, capture_output=True)

    def test_all_named_required_checks_must_be_present(self):
        result = self.run_gate("missing")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("missing-required", result.stdout)
        self.assertNotIn("pending eg:", result.stdout)

    def test_no_ci_is_never_chat_merge_actionable(self):
        result = self.run_gate("no-ci")
        self.assertIn("CI no-ci", result.stdout)
        self.assertNotIn("pending eg:", result.stdout)

    def test_green_required_checks_and_review_marker_are_actionable(self):
        result = self.run_gate("green")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pending eg:", result.stdout)
        self.assertIn("review=pass", result.stdout)

    def test_nontrivial_missing_or_failed_review_is_not_actionable(self):
        for review in ("missing", "fail", "not-run"):
            with self.subTest(review=review):
                result = self.run_gate("green", review)
                self.assertIn("reviewer gate blocked", result.stdout)
                self.assertNotIn("pending eg:", result.stdout)


if __name__ == "__main__":
    unittest.main()
