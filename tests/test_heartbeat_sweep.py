import json
import os
import subprocess
import tempfile
import unittest
from pathlib import Path

SCRIPT = Path(__file__).parents[1] / "scripts" / "rdd-heartbeat-sweep.sh"


class HeartbeatMergeBacklogTests(unittest.TestCase):
    """Part 4 of the heartbeat sweep surfaces PR-gate actions already awaiting
    approval, reading gate STATE only (no GitHub), snapshot-deduped so a stable
    backlog posts once — not every beat (the 2026-07-14 heartbeat-spam lesson).

    The sweep is isolated with a temp HOME (state + snapshot), an empty workspace
    (no projects -> the validator loop is a no-op), no research transfer dir, and
    an unreachable OpenScience base (fast-fails to a stable 'DOWN' line, which the
    dedup test tolerates because it is identical across runs).
    """

    def _run(self, td, gate_actions):
        root = Path(td)
        home = root / "home"; home.mkdir(exist_ok=True)
        ws = root / "ws"; ws.mkdir(exist_ok=True)
        xfer = root / "xfer"; xfer.mkdir(exist_ok=True)
        gate = root / "gate"; gate.mkdir(exist_ok=True)
        (gate / "state.json").write_text(
            json.dumps({"actions": gate_actions, "posts": {}}))
        env = os.environ.copy()
        env.update({
            "HOME": str(home),
            "RDD_WORKSPACE": str(ws),
            "RDD_RESEARCH_XFER": str(xfer),
            "RDD_RESEARCH_STATE": str(root / "research"),
            "RDD_RESEARCH_OS_BASE": "http://127.0.0.1:1",  # refused -> fast DOWN
            "RDD_GATE_STATE_DIR": str(gate),
        })
        return subprocess.run(["bash", str(SCRIPT)], env=env, text=True,
                              capture_output=True)

    def _last_line(self, out):
        return out.strip().splitlines()[-1]

    def test_pending_gate_actions_are_surfaced_with_a_button(self):
        with tempfile.TemporaryDirectory() as td:
            r = self._run(td, {
                "m1": {"status": "pending", "kind": "merge"},
                "p1": {"status": "pending", "kind": "prune"},
                "s1": {"status": "pending", "kind": "snooze"},  # excluded
            })
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertIn("2 gate action(s) awaiting your approval", r.stdout)
            self.assertIn("ACTION: 🚦 Review the gate queue\t/gate sweep", r.stdout)
            self.assertEqual(self._last_line(r.stdout), "CHANGED")

    def test_stable_backlog_is_deduped_to_no_change(self):
        with tempfile.TemporaryDirectory() as td:
            actions = {"m1": {"status": "pending", "kind": "merge"}}
            first = self._run(td, actions)
            self.assertEqual(self._last_line(first.stdout), "CHANGED", first.stdout)
            # Same HOME -> same snapshot; identical output must dedup.
            second = self._run(td, actions)
            self.assertEqual(self._last_line(second.stdout), "NO_CHANGE", second.stdout)
            self.assertIn("1 gate action(s) awaiting your approval", second.stdout)

    def test_no_pending_actions_emits_no_backlog_line(self):
        with tempfile.TemporaryDirectory() as td:
            r = self._run(td, {
                "m1": {"status": "done", "kind": "merge"},
                "s1": {"status": "pending", "kind": "snooze"},
            })
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertNotIn("gate action(s) awaiting your approval", r.stdout)

    def test_missing_gate_state_is_not_an_error(self):
        with tempfile.TemporaryDirectory() as td:
            root = Path(td)
            home = root / "home"; home.mkdir()
            ws = root / "ws"; ws.mkdir()
            env = os.environ.copy()
            env.update({
                "HOME": str(home), "RDD_WORKSPACE": str(ws),
                "RDD_RESEARCH_XFER": str(root / "xfer"),
                "RDD_RESEARCH_STATE": str(root / "research"),
                "RDD_RESEARCH_OS_BASE": "http://127.0.0.1:1",
                "RDD_GATE_STATE_DIR": str(root / "no-such-gate"),
            })
            r = subprocess.run(["bash", str(SCRIPT)], env=env, text=True,
                               capture_output=True)
            self.assertEqual(r.returncode, 0, r.stderr)
            self.assertNotIn("gate action(s) awaiting your approval", r.stdout)


if __name__ == "__main__":
    unittest.main()
