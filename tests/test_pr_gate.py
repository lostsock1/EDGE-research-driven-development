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
    print(os.environ.get("FAKE_SLUG", "owner/repo"))
elif args[:2] == ["pr", "list"]:
    if "--head" in args:
        state = os.environ.get("FAKE_ASSOC_STATE", "none")
        print(json.dumps([] if state == "none" else [{"state": state}]))
    else:
        if os.environ.get("FAKE_OPEN_PRS") == "none":
            print("[]")
        else:
            print(json.dumps([{"number": 1, "title": "feat: change", "headRefName": "cm/change", "headRefOid": "abc123", "baseRefName": os.environ.get("FAKE_BASE", "main"), "baseRefOid": "base123", "mergeable": os.environ.get("FAKE_MERGEABLE", "MERGEABLE"), "mergeStateStatus": os.environ.get("FAKE_MERGE_STATE", "CLEAN"), "isDraft": False, "url": "https://example/pr/1"}]))
elif args[:2] == ["pr", "checks"]:
    if mode == "no-ci": print("[]")
    elif mode == "missing": print(json.dumps([{"name":"tests","bucket":"pass"}]))
    elif mode == "skipping": print(json.dumps([{"name":"tests","bucket":"pass"},{"name":"lint","bucket":"skipping"}]))
    elif mode == "cancel": print(json.dumps([{"name":"tests","bucket":"pass"},{"name":"lint","bucket":"cancel"}]))
    else: print(json.dumps([{"name":"tests","bucket":"pass"},{"name":"lint","bucket":"pass"}]))
elif args[:2] == ["api", "user"]:
    print(json.dumps({"login":"trusted-bot"}))
elif args and args[0] == "api" and "issues/1/comments" in " ".join(args):
    review = os.environ.get("FAKE_REVIEW", "pass")
    author = os.environ.get("FAKE_REVIEW_AUTHOR", "trusted-bot")
    if review == "missing": print("[]")
    else: print(json.dumps([{"user":{"login":author}, "body":f"<!-- edge-review-gate sha=abc123 class=nontrivial verdict={review} ready={'yes' if review.startswith('pass') else 'no'} trust=model-reported -->"}]))
elif args and args[0] == "api" and "branches?" in " ".join(args):
    print(os.environ.get("FAKE_BRANCHES", "main\tbase123\ncm/change\tabc123"))
elif args and args[0] == "api" and "/compare/" in " ".join(args):
    compare = os.environ.get("FAKE_COMPARE", "")
    if compare == "FAIL":
        sys.exit(1)
    print(compare)
elif args and args[0] == "api" and "git/ref/heads/" in " ".join(args):
    print(json.dumps({"object":{"sha":os.environ.get("FAKE_REF_SHA", "abc123")}}))
else:
    print("[]")
'''


class PrGateTests(unittest.TestCase):
    def run_gate(self, mode, review="pass", base="main", author="trusted-bot", merge_state="CLEAN", **extra):
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
                        "RDD_GATE_STATE_DIR": str(root / "state"), "FAKE_CHECK_MODE": mode,
                        "FAKE_REVIEW": review, "FAKE_BASE": base, "FAKE_REVIEW_AUTHOR": author,
                        "FAKE_MERGE_STATE": merge_state, **extra})
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

    def test_skipped_check_counts_as_satisfied_and_is_actionable(self):
        # Regression: a path-filtered / conditional required job reports bucket
        # "skipping" — terminal and non-failing. The gate must read the PR green
        # and mint its merge action, matching edge-coder-run.sh's CI watcher. The
        # old classifier saw "skipping" as pending and never offered the merge, so
        # a green PR the watcher had already announced sat un-mergeable in the gate.
        result = self.run_gate("skipping")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("pending eg:", result.stdout)
        self.assertIn("review=pass", result.stdout)

    def test_cancelled_check_is_red_and_not_actionable(self):
        # "cancel" is terminal and did not succeed; it must read red (never
        # pending), so the PR is not offered for merge and rides the coder loop.
        result = self.run_gate("cancel")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("CI RED", result.stdout)
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

    def test_marker_from_untrusted_comment_author_is_rejected(self):
        result = self.run_gate("green", author="random-commenter")
        self.assertIn("missing reviewer marker by trusted-bot", result.stdout)
        self.assertNotIn("pending eg:", result.stdout)

    def test_pr_targeting_nontrunk_base_is_not_actionable(self):
        result = self.run_gate("green", base="release")
        self.assertIn("targets release, not protected trunk main", result.stdout)
        self.assertNotIn("pending eg:", result.stdout)

    def test_nonclean_merge_state_is_not_actionable(self):
        result = self.run_gate("green", merge_state="BEHIND")
        self.assertIn("merge state BEHIND", result.stdout)
        self.assertNotIn("pending eg:", result.stdout)

    def test_compare_failure_does_not_mint_normal_prune(self):
        result = self.run_gate("green", FAKE_BRANCHES="main\tbase123\nold\tdeadbeef", FAKE_COMPARE="FAIL", FAKE_OPEN_PRS="none")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("pending eg:", result.stdout)

    def test_orphan_ahead_by_does_not_mint_normal_prune(self):
        result = self.run_gate("green", FAKE_BRANCHES="main\tbase123\nold\tdeadbeef", FAKE_COMPARE="2", FAKE_OPEN_PRS="none")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertNotIn("pending eg:", result.stdout)

    def test_closed_unmerged_branch_mints_explicit_destructive_kind(self):
        result = self.run_gate("green", FAKE_BRANCHES="main\tbase123\nold\tdeadbeef",
                               FAKE_ASSOC_STATE="CLOSED", FAKE_OPEN_PRS="none")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn("DESTRUCTIVE delete closed-unmerged branch old", result.stdout)
        self.assertIn("DESTRUCTIVE delete closed-unmerged branch old", result.stdout)

    def test_duplicate_canonical_repositories_are_rejected_before_actions(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td); bindir = root / "bin"; bindir.mkdir()
            gh = bindir / "gh"; gh.write_text(FAKE_GH); gh.chmod(0o755)
            cfg = root / "cfg"; cfg.mkdir()
            for name in ("a.env", "b.env"):
                repo = root / name.removesuffix(".env"); (repo / ".git").mkdir(parents=True)
                (cfg / name).write_text(f"RDD_REPO_DIR={repo}\nRDD_MAIN_BRANCH=main\n")
            env = os.environ.copy(); env.update({"PATH": f"{bindir}:{env['PATH']}",
                "RDD_GATE_CONFIG_DIR": str(cfg), "RDD_GATE_STATE_DIR": str(root / "state")})
            result = subprocess.run([str(SCRIPT), "sweep", "--dry-run"], env=env,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("duplicate canonical GitHub repo owner/repo", result.stdout)
            self.assertNotIn("pending eg:", result.stdout)

    def test_act_refuses_prune_when_branch_sha_changed_after_approval(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            bindir = root / "bin"; bindir.mkdir()
            gh = bindir / "gh"; gh.write_text(FAKE_GH); gh.chmod(0o755)
            repo = root / "repo"; (repo / ".git").mkdir(parents=True)
            cfg = root / "cfg"; cfg.mkdir()
            project = cfg / "demo.env"
            project.write_text(f"RDD_REPO_DIR={repo}\nRDD_MAIN_BRANCH=main\n")
            state_dir = root / "state"; state_dir.mkdir()
            state = {
                "actions": {"deadbeef": {
                    "key": "prune:cm/change:abc123", "label": "repo", "cfg": str(project),
                    "repo": "owner/repo", "trunk": "main", "kind": "prune",
                    "branch": "cm/change", "reason": "no unique commits", "ref_sha": "abc123",
                    "status": "pending", "created": 1,
                }},
                "posts": {},
            }
            (state_dir / "state.json").write_text(json.dumps(state))
            env = os.environ.copy()
            env.update({"PATH": f"{bindir}:{env['PATH']}", "RDD_GATE_CONFIG_DIR": str(cfg),
                        "RDD_GATE_STATE_DIR": str(state_dir), "FAKE_REF_SHA": "new456"})
            result = subprocess.run([str(SCRIPT), "act", "eg:deadbeef"], env=env,
                                    text=True, capture_output=True)
            self.assertEqual(result.returncode, 5, result.stdout + result.stderr)
            self.assertIn("changed after approval", result.stdout)
            saved = json.loads((state_dir / "state.json").read_text())
            self.assertEqual(saved["actions"]["deadbeef"]["status"], "failed")


if __name__ == "__main__":
    unittest.main()
