import base64
import json
import os
import re
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


class CiWatcherPollingTests(unittest.TestCase):
    """The detached CI watcher polls fast at first, then at the steady interval.

    The watcher runs in a detached background subshell reached only on a real
    dispatch's success path, so — like the button-cap guard — its shape is pinned
    at the source level. The invariants that matter: a short initial interval
    exists (so a quick check reports in ~CI_FAST_SECS, not a full CI_POLL_SECS),
    and the fast phase is ADDED to (never subtracted from) the steady
    CI_POLL_MAX × CI_POLL_SECS budget, so slow CI keeps its full watch window.
    """

    src = SCRIPT.read_text()

    def _default(self, name):
        m = re.search(rf'{name}=\$\{{RDD_{name}:-(\d+)\}}', self.src)
        self.assertIsNotNone(m, f"{name} default missing or not env-overridable")
        return int(m.group(1))

    def test_fast_poll_knobs_are_overridable_with_defaults(self):
        self.assertRegex(self.src, r'CI_FAST_SECS=\$\{RDD_CI_FAST_SECS:-\d+\}')
        self.assertRegex(self.src, r'CI_FAST_POLLS=\$\{RDD_CI_FAST_POLLS:-\d+\}')

    def test_first_verdict_latency_is_below_the_steady_interval(self):
        self.assertLess(self._default("CI_FAST_SECS"), self._default("CI_POLL_SECS"))
        self.assertGreater(self._default("CI_FAST_POLLS"), 0)

    def test_fast_phase_is_additive_not_a_budget_cut(self):
        # total_polls = CI_FAST_POLLS + CI_POLL_MAX — the fast polls are extra and
        # up front, so a slow build still gets the full steady CI_POLL_MAX budget.
        self.assertIn("total_polls=$((CI_FAST_POLLS + CI_POLL_MAX))", self.src)
        self.assertRegex(self.src, r'while \[ \$n -lt \$total_polls \]')
        self.assertIn(
            'if [ $n -lt "$CI_FAST_POLLS" ]; then sleep "$CI_FAST_SECS"; '
            'else sleep "$CI_POLL_SECS"; fi', self.src)

    def test_timeout_message_counts_the_fast_phase(self):
        # The "no verdict after N min" line must include the fast-phase seconds so
        # it does not under-report the actual watch window.
        self.assertIn("CI_FAST_SECS*CI_FAST_POLLS + CI_POLL_SECS*CI_POLL_MAX", self.src)


class ChatButtonTests(unittest.TestCase):
    """The chat-button surface: run metadata, follow-up verbs, and the byte cap.

    Telegram caps callback_data at 64 bytes and encodes a command button as
    "tgcmd:<command>". Over that, the channel adapter drops the button with no
    error anywhere — the operator just sees a message missing an option. These
    tests fail at authoring time instead.
    """

    # "run-" + YYYYMMDD + "-" + HHMMSS + "-" + $RANDOM (max 32767, 5 digits)
    LONGEST_RUN_ID = "run-20260721-035500-32767"
    TG_CMD_MAX_BYTES = 58

    def test_declared_cap_matches_telegram_limit(self):
        # 64-byte callback_data minus the 6-byte "tgcmd:" prefix the Telegram
        # adapter adds. If OpenClaw ever changes either, this is the tripwire.
        src = SCRIPT.read_text()
        self.assertIn(f"TG_CMD_MAX_BYTES={self.TG_CMD_MAX_BYTES}", src)

    def button_commands(self, src):
        """Every command the script can put on a button, in both spellings.

        Buttons are written either as a literal `$'\\t'"/verb $RUN_ID"` spec or,
        inside the CI watcher, via the `btn <label> <verb>` helper that omits the
        button entirely for a --fg run. Both must be checked, or moving a command
        between the two forms silently drops it out of this guard.
        """
        literal = re.findall(r'\$\'\\t\'"(/[a-z]+ [^"]*)"', src)
        helper = [f"/dispatch {verb} $RUN_ID"
                  for verb in re.findall(r'\$\(btn "[^"]*" ([a-z-]+)\)', src)]
        return literal + helper

    def test_every_button_command_fits_the_cap(self):
        # Expand each command the script can emit at its worst case and assert it
        # still fits, so a future longer verb cannot ship invisible.
        src = SCRIPT.read_text()
        commands = self.button_commands(src)
        self.assertTrue(commands, "no button commands found — did the quoting change?")
        for cmd in commands:
            expanded = cmd.replace("$RUN_ID", self.LONGEST_RUN_ID)
            self.assertNotIn("$", expanded, f"unexpanded variable in button command: {cmd}")
            self.assertLessEqual(
                len(expanded.encode()), self.TG_CMD_MAX_BYTES,
                f"button command would be silently dropped by Telegram: {expanded!r}")

    def test_both_button_spellings_are_covered(self):
        # Guards the guard: if the CI watcher's helper is renamed or the literal
        # quoting changes, the cap test above would silently check fewer commands
        # instead of failing. Both forms are in use today.
        src = SCRIPT.read_text()
        self.assertTrue(re.search(r'\$\'\\t\'"/[a-z]+ ', src), "literal button form vanished")
        self.assertTrue(re.search(r'\$\(btn "[^"]*" [a-z-]+\)', src), "btn helper form vanished")
        self.assertGreaterEqual(len(self.button_commands(src)), 12)

    def test_every_button_verb_is_a_real_subcommand(self):
        # A button whose verb no subcommand handles is a dead tap. Cross-check
        # every /dispatch verb on a button against the SUBCMD case list.
        src = SCRIPT.read_text()
        declared = set(re.search(r'case "\$\{1:-\}" in\n\s*([a-z|-]+)\)', src).group(1).split("|"))
        for cmd in self.button_commands(src):
            if cmd.startswith("/dispatch "):
                verb = cmd.split()[1]
                self.assertIn(verb, declared,
                              f"button fires /dispatch {verb}, which SUBCMD does not declare")

    def make_run(self, td, **meta):
        root = Path(td)
        runs = root / "runs"; runs.mkdir(parents=True, exist_ok=True)
        rid = self.LONGEST_RUN_ID
        (runs / f"{rid}.log").write_text("fake run output\n")
        body = "".join(f"{k}={v}\n" for k, v in meta.items())
        (runs / f"{rid}.meta").write_text(f"run_id={rid}\n{body}")
        home = root / "home"; home.mkdir(exist_ok=True)
        env = os.environ.copy()
        env.pop("EDGE_RDD_CONFIG", None)
        env.update({"HOME": str(home),
                    "RDD_SHARED_CONFIG": str(root / "none.env"),
                    "RDD_RUNS_DIR": str(runs),
                    "RDD_LOG": str(root / "run.log"),
                    "RDD_LOCKDIR": str(root / "locks")})
        return rid, env

    def run_verb(self, env, *args):
        return subprocess.run([str(SCRIPT), *args], env=env, text=True, capture_output=True)

    def test_follow_up_verbs_need_a_wellformed_run_id(self):
        with tempfile.TemporaryDirectory() as td:
            _, env = self.make_run(td)
            for verb in ("log", "diff", "ci", "retry", "fix"):
                r = self.run_verb(env, verb, "; rm -rf /")
                self.assertEqual(r.returncode, 2, f"{verb} accepted a malformed id")
                self.assertIn("usage:", r.stderr)

    def test_unknown_run_id_is_rejected(self):
        with tempfile.TemporaryDirectory() as td:
            _, env = self.make_run(td)
            r = self.run_verb(env, "log", "run-19990101-000000-1")
            self.assertEqual(r.returncode, 4)
            self.assertIn("unknown run", r.stderr)

    def test_list_reports_recorded_project_and_pr(self):
        with tempfile.TemporaryDirectory() as td:
            rid, env = self.make_run(td, project="NAIRRATOR", branch="cm/x", pr="52")
            r = self.run_verb(env, "list")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn(rid, r.stdout)
            self.assertIn("NAIRRATOR", r.stdout)
            self.assertIn("PR #52", r.stdout)

    def test_fix_refuses_without_a_pr(self):
        with tempfile.TemporaryDirectory() as td:
            rid, env = self.make_run(td, config=str(Path(td) / "none.env"))
            Path(td, "none.env").write_text("")
            r = self.run_verb(env, "fix", rid)
            self.assertEqual(r.returncode, 4)
            self.assertIn("no PR", r.stderr)

    def test_retry_refuses_without_a_recorded_task(self):
        with tempfile.TemporaryDirectory() as td:
            rid, env = self.make_run(td, config=str(Path(td) / "none.env"))
            Path(td, "none.env").write_text("")
            r = self.run_verb(env, "retry", rid)
            self.assertEqual(r.returncode, 4)
            self.assertIn("no recorded task", r.stderr)

    def test_task_survives_metadata_round_trip(self):
        # The task is base64'd precisely because it may contain newlines, quotes
        # and shell metacharacters; retry must hand back the original bytes.
        task = 'fix "the" thing\nwith $VARS && `backticks`'
        with tempfile.TemporaryDirectory() as td:
            rid, env = self.make_run(
                td, config=str(Path(td) / "proj.env"),
                task_b64=base64.b64encode(task.encode()).decode())
            # No RDD_REPO_DIR: retry re-execs and the dispatch guard stops it
            # there, after the task has been recovered and echoed.
            Path(td, "proj.env").write_text("")
            r = self.run_verb(env, "retry", rid)
            self.assertIn("re-dispatching (retry)", r.stdout)

    def test_foreground_run_writes_no_metadata(self):
        # A --fg run has no run id, so every meta_set call site passes an empty
        # string. Unguarded that writes $RUNS_DIR/.meta (and fg.meta) — junk no
        # reader can ever resolve, since only a valid run id is addressable.
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"; home.mkdir()
            repo = root / "repo"; subprocess.run(["git", "init", "-q", str(repo)], check=True)
            fake = root / "opencode"
            fake.write_text('''#!/usr/bin/env bash
if [[ "$*" == *"say hello"* ]]; then printf '%s\\n' '{"type":"text","text":"hello"}'; exit 0; fi
printf '%s\\n' '{"type":"text","text":"=== LOOP STATUS ===\\nREVIEWER: Pass — fake\\n=== END ==="}'
exit 0
''')
            fake.chmod(0o755)
            runs = root / "runs"
            shared = root / "config.env"
            shared.write_text(
                f'RDD_OPENCODE={fake}\nRDD_MODELS="fake/model"\n'
                'RDD_TIMEOUTS_BG="5"\nRDD_TIMEOUTS_FG="5"\n'
                f'RDD_LOG={root}/run.log\nRDD_RUNS_DIR={runs}\nRDD_LOCKDIR={root}/locks\n'
            )
            project = root / "project.env"; project.write_text(f'RDD_REPO_DIR={repo}\n')
            env = os.environ.copy()
            env.update({"HOME": str(home), "RDD_SHARED_CONFIG": str(shared),
                        "EDGE_RDD_CONFIG": str(project)})
            subprocess.run([str(SCRIPT), "--fg", "test task"], env=env,
                           text=True, capture_output=True)
            stray = sorted(p.name for p in runs.iterdir() if p.name.endswith(".meta"))
            self.assertEqual(stray, [], f"foreground run wrote metadata: {stray}")

    def test_metadata_is_never_sourced_as_shell(self):
        # A .meta value is untrusted-ish input written by the wrapper; reading it
        # must not evaluate it. If it were sourced, this would create the file.
        with tempfile.TemporaryDirectory() as td:
            canary = Path(td) / "pwned"
            rid, env = self.make_run(td, project=f"$(touch {canary})")
            r = self.run_verb(env, "list")
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertFalse(canary.exists(), "meta value was evaluated as shell")


class GreenMergeOfferTests(unittest.TestCase):
    """On CI-green the detached watcher offers THIS PR's merge ask
    (`edge-pr-gate.sh offer <dir> <pr>`) straight to the gate thread, instead of
    firing a whole-repo sweep the operator must then trigger and hunt through.
    The watcher runs detached on a live success path, so this is pinned at source
    level like the button-cap guard."""

    src = SCRIPT.read_text()

    def test_green_branch_offers_this_pr_not_a_whole_repo_sweep(self):
        self.assertIn('"$GATE_SCRIPT" offer "$DIR" "$pr_num"', self.src)
        # No path in the wrapper auto-runs a whole-repo sweep (the "/gate sweep"
        # chat button is a manual fallback, a different string).
        self.assertNotIn('"$GATE_SCRIPT" sweep', self.src)


if __name__ == "__main__":
    unittest.main()
