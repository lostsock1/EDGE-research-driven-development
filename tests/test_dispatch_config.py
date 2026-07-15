import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "edge-coder-run.sh"


class DispatchConfigTests(unittest.TestCase):
    def run_dispatch(self, shared, project, effort=None):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"; home.mkdir()
            repo = root / "repo"; subprocess.run(["git", "init", "-q", str(repo)], check=True)
            shared_path = root / "config.env"
            project_path = root / "project.env"
            shared_path.write_text(shared.replace("$REPO", str(repo)))
            project_path.write_text(project.replace("$REPO", str(repo)))
            env = os.environ.copy()
            env.update({"HOME": str(home), "RDD_SHARED_CONFIG": str(shared_path),
                        "EDGE_RDD_CONFIG": str(project_path)})
            if effort:
                env["EDGE_CODER_EFFORT"] = effort
            return subprocess.run([str(SCRIPT), "--fg", "test task"], env=env, text=True, capture_output=True)

    def test_selected_project_cannot_inherit_shared_repo_identity(self):
        shared = 'RDD_REPO_DIR=$REPO\nRDD_MODELS="a b"\nRDD_TIMEOUTS_BG="1 1"\nRDD_TIMEOUTS_FG="1 1"\n'
        result = self.run_dispatch(shared, "RDD_PROJECT_SLUG=other\n")
        self.assertEqual(result.returncode, 2)
        self.assertIn("has no RDD_REPO_DIR", result.stderr)

    def test_timeout_arrays_must_align_with_models(self):
        shared = 'RDD_MODELS="a b"\nRDD_TIMEOUTS_BG="1 1"\nRDD_TIMEOUTS_FG="1"\n'
        result = self.run_dispatch(shared, "RDD_REPO_DIR=$REPO\n")
        self.assertEqual(result.returncode, 2)
        self.assertIn("RDD_TIMEOUTS_FG has 1 value", result.stderr)

    def test_max_requires_explicit_aligned_variant_map(self):
        shared = 'RDD_MODELS="a b"\nRDD_TIMEOUTS_BG="1 1"\nRDD_TIMEOUTS_FG="1 1"\nRDD_VARIANT_POLICY=auto\n'
        result = self.run_dispatch(shared, "RDD_REPO_DIR=$REPO\n", effort="max")
        self.assertEqual(result.returncode, 2)
        self.assertIn("effort=max requires an explicit RDD_VARIANTS_MAX", result.stderr)

    def run_with_fake_opencode(self, project_extra=""):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"; home.mkdir()
            repo = root / "repo"; subprocess.run(["git", "init", "-q", str(repo)], check=True)
            fake = root / "opencode"
            fake.write_text(r'''#!/usr/bin/env bash
if [[ "$*" == *"say hello"* ]]; then
  if [ "${FAKE_EMPTY_PROBE:-0}" = 1 ]; then
    printf '%s\n' '{"type":"text","text":"   "}'
  else
    printf '%s\n' '{"type":"text","text":"hello"}'
  fi
  exit 0
fi
if [ "${FAKE_EMPTY_TASK:-0}" = 1 ]; then
  printf '%s\n' '{"type":"text","text":""}'
else
  printf '%s\n' '{"type":"text","text":"=== LOOP STATUS ===\nREVIEWER: Pass — fake\n=== END ==="}'
fi
exit 7
''')
            fake.chmod(0o755)
            shared = root / "config.env"
            shared.write_text(
                f'RDD_OPENCODE={fake}\nRDD_MODELS="fake/model"\n'
                'RDD_TIMEOUTS_BG="5"\nRDD_TIMEOUTS_FG="5"\n'
                f'RDD_LOG={root}/run.log\nRDD_RUNS_DIR={root}/runs\nRDD_LOCKDIR={root}/locks\n'
            )
            project = root / "project.env"
            project.write_text(f'RDD_REPO_DIR={repo}\n{project_extra}')
            env = os.environ.copy()
            env.update({"HOME": str(home), "RDD_SHARED_CONFIG": str(shared),
                        "EDGE_RDD_CONFIG": str(project)})
            return subprocess.run([str(SCRIPT), "--fg", "test task"], env=env,
                                  text=True, capture_output=True)

    def test_nonzero_opencode_exit_is_failure_even_with_text_event(self):
        result = self.run_with_fake_opencode()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("all 1 model tiers failed", result.stderr)

    def test_whitespace_only_probe_text_is_failure(self):
        with tempfile.TemporaryDirectory() as td:
            result = self.run_with_fake_opencode_extra(td, FAKE_EMPTY_PROBE="1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("all 1 model tiers failed", result.stderr)

    def test_empty_task_text_is_failure(self):
        with tempfile.TemporaryDirectory() as td:
            result = self.run_with_fake_opencode_extra(td, FAKE_EMPTY_TASK="1")
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("all 1 model tiers failed", result.stderr)

    def run_with_fake_opencode_extra(self, td, **extra):
        # Reuse the fixture setup while injecting stream-shape controls.
        # The temporary directory is intentionally retained for the subprocess.
        root = Path(td)
        home = root / "home"; home.mkdir()
        repo = root / "repo"; subprocess.run(["git", "init", "-q", str(repo)], check=True)
        fake = root / "opencode"
        fake.write_text('''#!/usr/bin/env bash
if [[ "$*" == *"say hello"* ]]; then
  if [ "${FAKE_EMPTY_PROBE:-0}" = 1 ]; then printf '%s\\n' '{"type":"text","text":"   "}'; else printf '%s\\n' '{"type":"text","text":"hello"}'; fi
  exit 0
fi
if [ "${FAKE_EMPTY_TASK:-0}" = 1 ]; then printf '%s\\n' '{"type":"text","text":""}'; else printf '%s\\n' '{"type":"text","text":"ok"}'; fi
exit 0
''')
        fake.chmod(0o755)
        shared = root / "config.env"
        shared.write_text(f'RDD_OPENCODE={fake}\nRDD_MODELS="fake/model"\nRDD_TIMEOUTS_BG="5"\nRDD_TIMEOUTS_FG="5"\nRDD_LOG={root}/run.log\nRDD_RUNS_DIR={root}/runs\nRDD_LOCKDIR={root}/locks\n')
        project = root / "project.env"; project.write_text(f'RDD_REPO_DIR={repo}\n')
        env = os.environ.copy(); env.update({"HOME": str(home), "RDD_SHARED_CONFIG": str(shared), "EDGE_RDD_CONFIG": str(project), **extra})
        return subprocess.run([str(SCRIPT), "--fg", "test task"], env=env, text=True, capture_output=True)

    def test_project_file_cannot_override_shared_runtime_policy(self):
        result = self.run_with_fake_opencode('RDD_MODELS="evil/one evil/two"\nRDD_TIMEOUTS_FG="1 1"\n')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertNotIn("arrays must be index-aligned", result.stderr)

    # ---- CI verdict classification (strict_ci_verdict via the ci-verdict seam) ----
    def ci_verdict(self, checks, required=""):
        # The read-only `ci-verdict` subcommand exits before any dispatch guard, so
        # a bare HOME and a nonexistent shared config are enough to exercise it.
        with tempfile.TemporaryDirectory() as td:
            home = Path(td) / "home"; home.mkdir()
            env = os.environ.copy()
            env.pop("EDGE_RDD_CONFIG", None)
            env.update({"HOME": str(home),
                        "RDD_SHARED_CONFIG": str(Path(td) / "none.env"),
                        "RDD_REQUIRED_CHECKS": required})
            return subprocess.run([str(SCRIPT), "ci-verdict", json.dumps(checks)],
                                  env=env, text=True, capture_output=True)

    def test_ci_verdict_skipped_check_counts_as_satisfied(self):
        # A path-filtered / conditional job reports bucket "skipping" — terminal and
        # non-failing. It must NOT wedge the verdict at pending (the old bug).
        r = self.ci_verdict([{"name": "tests", "bucket": "pass"},
                             {"name": "e2e", "bucket": "skipping"}],
                            required="tests,e2e")
        self.assertEqual(r.returncode, 0, r.stderr)
        self.assertTrue(r.stdout.startswith("green"), r.stdout)

    def test_ci_verdict_cancelled_check_is_red(self):
        # "cancel" is terminal and did not succeed; it must read red, not pending.
        r = self.ci_verdict([{"name": "tests", "bucket": "pass"},
                             {"name": "build", "bucket": "cancel"}])
        self.assertTrue(r.stdout.startswith("red"), r.stdout)
        self.assertIn("cancelled: build", r.stdout)

    def test_ci_verdict_failing_check_is_red(self):
        r = self.ci_verdict([{"name": "tests", "bucket": "fail"}])
        self.assertTrue(r.stdout.startswith("red"), r.stdout)
        self.assertIn("failing: tests", r.stdout)

    def test_ci_verdict_in_progress_check_stays_pending(self):
        r = self.ci_verdict([{"name": "tests", "bucket": "pass"},
                             {"name": "slow", "bucket": "pending"}])
        self.assertTrue(r.stdout.startswith("pending"), r.stdout)

    def test_ci_verdict_missing_required_context(self):
        r = self.ci_verdict([{"name": "tests", "bucket": "pass"}],
                            required="tests,coverage")
        self.assertTrue(r.stdout.startswith("missing-required"), r.stdout)
        self.assertIn("coverage", r.stdout)

    # ---- failure classification + partial-work handoff regressions ----
    def test_classify_failure_labels_provider_error_from_stream(self):
        # A {"type":"error"} stream event must be classified, not swallowed as bare
        # empty output. The parser prints "opencode error: ..." to the tier stderr
        # file, which classify_failure greps — regression for the dead branch where
        # that stderr never reached the classification temp file.
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"; home.mkdir()
            repo = root / "repo"; subprocess.run(["git", "init", "-q", str(repo)], check=True)
            fake = root / "opencode"
            fake.write_text('''#!/usr/bin/env bash
if [[ "$*" == *"say hello"* ]]; then printf '%s\\n' '{"type":"text","text":"hello"}'; exit 0; fi
printf '%s\\n' '{"type":"error","error":"tool call failed"}'
exit 1
''')
            fake.chmod(0o755)
            shared = root / "config.env"
            shared.write_text(
                f'RDD_OPENCODE={fake}\nRDD_MODELS="fake/model"\n'
                'RDD_TIMEOUTS_BG="5"\nRDD_TIMEOUTS_FG="5"\n'
                f'RDD_LOG={root}/run.log\nRDD_RUNS_DIR={root}/runs\nRDD_LOCKDIR={root}/locks\n'
            )
            project = root / "project.env"; project.write_text(f'RDD_REPO_DIR={repo}\n')
            env = os.environ.copy()
            env.update({"HOME": str(home), "RDD_SHARED_CONFIG": str(shared),
                        "EDGE_RDD_CONFIG": str(project)})
            result = subprocess.run([str(SCRIPT), "--fg", "test task"], env=env,
                                    text=True, capture_output=True)
            log = (root / "run.log").read_text()
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn("reason=provider-error", log)

    def test_preexisting_dirty_tree_is_not_reported_as_partial_work(self):
        # Regression: a tree already dirty BEFORE dispatch must not be narrated to a
        # fallback tier as "partial work from a previous attempt". Tier one probe-
        # fails (touches nothing); the pre-existing dirt must be ignored on tier two.
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"; home.mkdir()
            repo = root / "repo"
            subprocess.run(["git", "init", "-q", str(repo)], check=True)
            subprocess.run(["git", "-C", str(repo), "symbolic-ref", "HEAD", "refs/heads/main"], check=True)
            (repo / "seed.txt").write_text("seed\n")
            subprocess.run(["git", "-C", str(repo), "add", "seed.txt"], check=True)
            subprocess.run(["git", "-C", str(repo), "-c", "user.email=t@t",
                            "-c", "user.name=t", "commit", "-qm", "seed"], check=True)
            (repo / "seed.txt").write_text("dirty before any dispatch\n")  # pre-existing dirt
            fake = root / "opencode"
            fake.write_text('''#!/usr/bin/env bash
if [[ "$*" == *"say hello"* ]]; then
  if [[ "$*" == *"fake/one"* ]]; then printf '%s\\n' '{"type":"text","text":"   "}'; else printf '%s\\n' '{"type":"text","text":"hello"}'; fi
  exit 0
fi
printf '%s\\n' '{"type":"text","text":"=== LOOP STATUS ===\\nREVIEWER: Pass — fake\\n=== END ==="}'
exit 0
''')
            fake.chmod(0o755)
            shared = root / "config.env"
            shared.write_text(
                f'RDD_OPENCODE={fake}\nRDD_MODELS="fake/one fake/two"\n'
                'RDD_TIMEOUTS_BG="5 5"\nRDD_TIMEOUTS_FG="5 5"\n'
                f'RDD_LOG={root}/run.log\nRDD_RUNS_DIR={root}/runs\nRDD_LOCKDIR={root}/locks\n'
            )
            project = root / "project.env"; project.write_text(f'RDD_REPO_DIR={repo}\n')
            env = os.environ.copy()
            env.update({"HOME": str(home), "RDD_SHARED_CONFIG": str(shared),
                        "EDGE_RDD_CONFIG": str(project)})
            result = subprocess.run([str(SCRIPT), "--fg", "test task"], env=env,
                                    text=True, capture_output=True)
            log = (root / "run.log").read_text()
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn("PARTIAL-WORK handoff", log)


if __name__ == "__main__":
    unittest.main()
