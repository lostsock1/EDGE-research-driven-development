#!/usr/bin/env bash
# edge-pr-gate.sh — EDGE GitHub PR gate: periodic repo sweep + operator-approved
# agent-executed merges and branch hygiene.
#
# Part of the "EDGE — Evidence-Driven Git Engineering" template.
#
# WHAT IT DOES
#   On `/gate sweep` (and after a dispatch reaches a green CI verdict), the
#   agent scans every configured project. For each project this:
#     - lists open PRs and their CI verdict (green / red / pending)
#     - lists every non-trunk branch and classifies it (active PR head,
#       merged/closed-PR leftover, orphan with/without unique commits)
#     - turns actionable items into single-use pending ACTIONS (merge a green
#       PR, prune a stale branch) stored in a state file
#     - posts ONE approval message per project to its own chat thread, with an
#       inline button per action (callback value `eg:<id>`) — so the operator
#       approves from the phone with one tap (or a 👍/✅ reaction + "approve")
#   When the operator taps a button, the channel delivers the callback value to
#   the agent as text; the agent then runs `act <id>`, which RE-VERIFIES the
#   preconditions (PR still open + checks still green; branch still stale) and
#   only then executes via gh, posts the outcome back to the thread, and marks
#   the action done. Trunks stay clean: merges use --delete-branch and prunes
#   delete stale remote branches, converging every project to trunk-only.
#
# THE HUMAN GATE IS UNCHANGED IN SPIRIT: nothing merges without an explicit
# operator approval — the approval surface just moves from the GitHub UI to a
# button in the project thread. Actions are single-use, minted only by sweep
# from observed repo state, re-verified at execution time, and the agent never
# runs `gh pr merge` / branch deletion outside `act`.
#
# MODES
#   sweep [--dry-run]   scan all projects, mint/reconcile actions, post approval
#                       buttons (dry-run prints payloads instead of sending).
#                       Prints a per-project summary; last line is ALL_CLEAN
#                       when nothing needs attention anywhere.
#   act <id>            execute one pending action after operator approval
#   pending [label]     list pending actions (optionally one project)
#   status              state summary: pending actions + recent results
#
# CONFIGURATION
#   Projects = every *.env file in $RDD_GATE_CONFIG_DIR (default
#   ~/.config/edge-rdd) that defines RDD_REPO_DIR. The same files the dispatch
#   wrapper (edge-coder-run.sh) uses — no second registry to drift.
#   Per-file keys used here: RDD_REPO_DIR, RDD_MAIN_BRANCH, RDD_TG_CHANNEL,
#   RDD_TG_TARGET, RDD_TG_THREAD, RDD_OPENCLAW, RDD_REQUIRED_CHECKS. Shared
#   runtime policy is inherited from config.env; project identity is not.
#   Gate knobs (environment, with defaults):
#     RDD_GATE_CONFIG_DIR    ~/.config/edge-rdd
#     RDD_GATE_STATE_DIR     ~/.local/state/edge-rdd/pr-gate
#     RDD_GATE_LOG           $RDD_GATE_STATE_DIR/gate.log
#     RDD_GATE_MERGE_METHOD  squash   (squash|merge|rebase)
#     RDD_GATE_REASK_HOURS   24       (re-post an unchanged ask after this)
#     RDD_GATE_MAX_BUTTONS   6        (per project message; rest listed as text)
#     RDD_GATE_PATH_PREPEND  prepended to PATH (gh under systemd-spawned shells)
#
# SAFETY RAILS
#   - trunk (RDD_MAIN_BRANCH) is never merged from, deleted, or pruned
#   - merge requires: PR open, not draft, every check green, every configured
#     required context present/pass, and an eligible current-head reviewer marker
#   - a PR with no CI is never chat-merge actionable
#   - prune requires: branch is not trunk and not the head of any open PR
#   - action ids are single-use; unknown/consumed ids are refused with the
#     current pending list
#   - every gh call has a hard timeout; state writes are flock-serialized
#
# Usage: edge-pr-gate.sh sweep [--dry-run] | act <id> | pending [label] | status

set -uo pipefail

# gh/python3 often live outside a systemd-spawned PATH (gateway exec). Prepend
# RDD_GATE_PATH_PREPEND, falling back to the default project config's
# RDD_PATH_PREPEND — the dispatch wrapper's own mechanism for the same problem.
GATE_CFG_DIR="${RDD_GATE_CONFIG_DIR:-$HOME/.config/edge-rdd}"
if [ -z "${RDD_GATE_PATH_PREPEND:-}" ] && [ -f "$GATE_CFG_DIR/config.env" ]; then
  RDD_GATE_PATH_PREPEND="$(sed -n 's/^RDD_PATH_PREPEND=//p' "$GATE_CFG_DIR/config.env" | tail -1 | tr -d '"'"'"'')"
fi
[ -n "${RDD_GATE_PATH_PREPEND:-}" ] && export PATH="$RDD_GATE_PATH_PREPEND:$PATH"

command -v gh >/dev/null 2>&1 || { echo "edge-pr-gate: gh CLI not found in PATH" >&2; exit 2; }
command -v python3 >/dev/null 2>&1 || { echo "edge-pr-gate: python3 not found" >&2; exit 2; }

exec python3 - "$@" <<'PY'
import fcntl, hashlib, json, os, re, secrets, shlex, subprocess, sys, time
from pathlib import Path

HOME = Path.home()
CFG_DIR = Path(os.environ.get("RDD_GATE_CONFIG_DIR", HOME / ".config/edge-rdd"))
STATE_DIR = Path(os.environ.get("RDD_GATE_STATE_DIR", HOME / ".local/state/edge-rdd/pr-gate"))
LOG_FILE = Path(os.environ.get("RDD_GATE_LOG", STATE_DIR / "gate.log"))
MERGE_METHOD = os.environ.get("RDD_GATE_MERGE_METHOD", "squash")
REASK_HOURS = float(os.environ.get("RDD_GATE_REASK_HOURS", "24"))
MAX_BUTTONS = int(os.environ.get("RDD_GATE_MAX_BUTTONS", "6"))
STATE_FILE = STATE_DIR / "state.json"

STATE_DIR.mkdir(parents=True, exist_ok=True)
os.chmod(STATE_DIR, 0o700)


def log(msg):
    with open(LOG_FILE, "a") as f:
        f.write(f"[{time.strftime('%Y-%m-%dT%H:%M:%S%z')}] {msg}\n")


def run(cmd, cwd=None, timeout=30):
    """Run a command, return (rc, stdout, stderr). Never raises."""
    try:
        p = subprocess.run(cmd, cwd=cwd, timeout=timeout,
                           capture_output=True, text=True)
        return p.returncode, p.stdout.strip(), p.stderr.strip()
    except subprocess.TimeoutExpired:
        return 124, "", f"timeout after {timeout}s: {' '.join(map(str, cmd))}"
    except Exception as e:  # missing binary etc.
        return 127, "", str(e)


def gh_json(args, timeout=30):
    rc, out, err = run(["gh"] + args, timeout=timeout)
    if rc != 0 or not out:
        return None, err or f"gh {' '.join(args)} rc={rc}"
    try:
        return json.loads(out), None
    except json.JSONDecodeError as e:
        return None, f"bad json from gh: {e}"


# ---- project configs (the wrapper's own env files — single registry) --------

def parse_env_file(path):
    d = {}
    for line in Path(path).read_text().splitlines():
        line = line.strip()
        if not line or line.startswith("#") or "=" not in line:
            continue
        k, v = line.split("=", 1)
        raw = v.strip()
        try:
            parsed = shlex.split(raw, posix=True)
        except ValueError:
            parsed = []
        # Config values are scalar. Fail closed on malformed/multiword values;
        # shell-quoted whitespace remains one scalar.
        if len(parsed) == 1:
            d[k.strip()] = parsed[0]
        elif raw in ("", "''", '""'):
            d[k.strip()] = ""
    return d


def projects():
    out = []
    shared = parse_env_file(CFG_DIR / "config.env") if (CFG_DIR / "config.env").exists() else {}
    shared_keys = {k: v for k, v in shared.items() if k in {
        "RDD_OPENCLAW", "RDD_REQUIRED_CHECKS", "RDD_PATH_PREPEND"}}
    for f in sorted(CFG_DIR.glob("*.env")):
        project_env = parse_env_file(f)
        env = {**shared_keys, **project_env}
        repo_dir = project_env.get("RDD_REPO_DIR")
        if not repo_dir:
            continue
        out.append({
            "cfg": str(f),
            # Display label is separate from canonical GitHub identity.
            "label": Path(repo_dir).name,
            "repo_dir": repo_dir,
            "trunk": env.get("RDD_MAIN_BRANCH", "main"),
            "channel": env.get("RDD_TG_CHANNEL", "telegram"),
            "target": env.get("RDD_TG_TARGET", ""),
            "thread": env.get("RDD_TG_THREAD", ""),
            "openclaw": env.get("RDD_OPENCLAW", str(HOME / ".local/bin/openclaw")),
            "required_checks": [c.strip() for c in env.get("RDD_REQUIRED_CHECKS", "").split(",") if c.strip()],
        })
    return out


# ---- the ONE gate thread -----------------------------------------------------
# Every gate message (all projects' approval asks AND action confirmations) goes
# to a single hub thread — the EDGE thread — so the operator has one place to
# approve from and per-project chatter never buries a gate ask. Resolved from
# env, else a `gate.env` next to the project configs (it has no RDD_REPO_DIR so
# it is NOT picked up as a project), else the first project's thread (single-
# project fallback keeps the template's one-thread setup working).

def hub_dest():
    env = {}
    hub_file = CFG_DIR / "gate.env"
    if hub_file.exists():
        env = parse_env_file(hub_file)

    def pick(key):
        return os.environ.get(key) or env.get(key)

    channel = pick("RDD_GATE_TG_CHANNEL")
    target = pick("RDD_GATE_TG_TARGET")
    thread = pick("RDD_GATE_TG_THREAD")
    openclaw = pick("RDD_OPENCLAW")
    if not target:  # fallback: first project that has a chat target
        for p in projects():
            if p["target"]:
                channel = channel or p["channel"]
                target = target or p["target"]
                thread = thread if thread is not None else p["thread"]
                openclaw = openclaw or p["openclaw"]
                break
    return {
        "label": "gate-hub",
        "channel": channel or "telegram",
        "target": target or "",
        "thread": thread or "",
        "openclaw": openclaw or str(HOME / ".local/bin/openclaw"),
    }


# ---- state -------------------------------------------------------------------

def load_state():
    if STATE_FILE.exists():
        try:
            return json.loads(STATE_FILE.read_text())
        except json.JSONDecodeError:
            log("WARN state.json corrupt — starting fresh (old file kept as .bad)")
            STATE_FILE.rename(STATE_FILE.with_suffix(".json.bad"))
    return {"actions": {}, "posts": {}}


def save_state(state):
    tmp = STATE_FILE.with_suffix(".json.tmp")
    tmp.write_text(json.dumps(state, indent=1))
    tmp.replace(STATE_FILE)


class Locked:
    def __enter__(self):
        self.fd = open(STATE_DIR / "gate.lock", "w")
        fcntl.flock(self.fd, fcntl.LOCK_EX)
        return self

    def __exit__(self, *a):
        fcntl.flock(self.fd, fcntl.LOCK_UN)
        self.fd.close()


# ---- chat delivery -------------------------------------------------------------

def send_message(dest, text, buttons=None, dry=False):
    """Send to a resolved dest dict (channel/target/thread/openclaw).
    buttons: list of (label, callback_value). Returns True on success."""
    if not dest["target"]:
        log("NOTE gate hub has no target (set RDD_GATE_TG_TARGET or a project "
            "RDD_TG_TARGET) — message not sent")
        return False
    cmd = [dest["openclaw"], "message", "send",
           "--channel", dest["channel"], "--target", dest["target"],
           "--message", text]
    if dest["thread"]:
        cmd += ["--thread-id", dest["thread"]]
    if buttons:
        # IMPORTANT: use "command" actions, NOT "callback". OpenClaw encodes a
        # callback button's value into an OPAQUE payload (tgcb1:…) and its
        # Telegram handler DROPS opaque callbacks that no plugin claims — so a
        # tap does nothing. A "command" action encodes as a native command that
        # IS delivered to the agent as text ("/gate act eg:<id>"), which the
        # gate skill runs. Each button's value here is that command string.
        blocks = [{"type": "buttons",
                   "buttons": [{"label": lab,
                                "action": {"type": "command", "command": val}}]}
                  for lab, val in buttons]
        cmd += ["--presentation", json.dumps({"blocks": blocks})]
    if dry:
        print(f"  DRY-RUN send -> {dest['channel']}:{dest['target']}"
              f"{':' + dest['thread'] if dest['thread'] else ''}")
        print("  " + text.replace("\n", "\n  "))
        for lab, val in (buttons or []):
            print(f"    [button] {lab}  ->  {val}")
        return True
    rc, out, err = run(cmd, timeout=30)
    if rc != 0:
        log(f"SEND FAIL hub rc={rc} {err[:200]}")
        return False
    return True


# ---- repo facts ------------------------------------------------------------------

def repo_slug(proj):
    rc, out, err = run(["gh", "repo", "view", "--json", "nameWithOwner",
                        "--jq", ".nameWithOwner"], cwd=proj["repo_dir"], timeout=25)
    slug = out.strip()
    return (slug, None) if rc == 0 and slug else (None, err or "no slug")


def pr_checks_verdict(slug, number, required):
    """Return a strict CI verdict and explanation."""
    rc, out, err = run(["gh", "pr", "checks", str(number), "-R", slug,
                        "--json", "name,bucket"], timeout=30)
    # `gh pr checks` may exit nonzero when valid JSON contains failed checks,
    # so parse stdout whenever present. A nonzero with no JSON is unavailable,
    # except GitHub's explicit no-checks response.
    if not out:
        if "no checks" in (err or "").lower():
            return "no-ci", "no checks reported"
        if rc != 0:
            return "unavailable", f"checks query failed ({(err or f'rc={rc}')[:160]})"
        return "no-ci", "no checks reported"
    try:
        checks = json.loads(out)
    except json.JSONDecodeError:
        return "unavailable", "checks response was not JSON"
    if not checks:
        return "no-ci", "no checks reported"
    by_name = {c.get("name"): c.get("bucket") for c in checks}
    # Bucket semantics are the single source of truth in edge-coder-run.sh's
    # strict_ci_verdict: gh maps pass=SUCCESS, skipping=SKIPPED/NEUTRAL,
    # fail=ERROR/FAILURE/TIMED_OUT/ACTION_REQUIRED, cancel=CANCELLED, pending=rest.
    # skipping and cancel are TERMINAL — they never become pass. Treating every
    # non-pass bucket as "pending" (the old behaviour here) wedged a green PR
    # whose path-filtered / conditional job SKIPPED at "pending" forever, so this
    # gate never minted the merge action even though the dispatch CI watcher had
    # already reported the same PR green — the "take me to the merge decision"
    # button then dead-ended. A skipped/neutral check is done and not failing
    # (satisfied); a cancelled check did not succeed (red).
    if any(c.get("bucket") == "fail" for c in checks):
        return "red", "failing checks present"
    if any(c.get("bucket") == "cancel" for c in checks):
        return "red", "cancelled checks present"
    missing = [name for name in required if name not in by_name]
    if missing:
        return "missing-required", "missing required: " + ", ".join(missing)
    if any(c.get("bucket") not in ("pass", "skipping") for c in checks):
        return "pending", "checks not all passed"
    return "green", "all checks passed or skipped; required contexts present"


_GH_LOGIN = None


def current_gh_login():
    """Resolve the authenticated account that is allowed to attest markers."""
    global _GH_LOGIN
    if _GH_LOGIN:
        return _GH_LOGIN, None
    user, err = gh_json(["api", "user"], timeout=20)
    if not isinstance(user, dict) or not user.get("login"):
        return None, err or "authenticated GitHub login unavailable"
    _GH_LOGIN = user["login"]
    return _GH_LOGIN, None


def reviewer_gate(slug, number, head_sha):
    expected_author, author_err = current_gh_login()
    if not expected_author:
        return False, f"review marker author unavailable ({author_err})"
    comments, err = gh_json(["api", f"repos/{slug}/issues/{number}/comments?per_page=100"], timeout=30)
    if comments is None:
        return False, f"review marker unavailable ({err})"
    pattern = re.compile(r"<!-- edge-review-gate sha=([0-9a-f]+) class=(trivial|nontrivial) verdict=([a-z-]+) ready=(yes|no) trust=model-reported -->")
    for comment in reversed(comments):
        if comment.get("user", {}).get("login") != expected_author:
            continue
        match = pattern.search(comment.get("body", ""))
        if match and match.group(1) == head_sha:
            task_class, verdict, ready = match.group(2), match.group(3), match.group(4)
            internally_eligible = task_class == "trivial" or verdict in ("pass", "pass-with-risks")
            if ready == "yes" and internally_eligible:
                return True, f"review={verdict} ({task_class}; model-reported by {expected_author})"
            return False, f"review={verdict} ({task_class}; not ready or inconsistent marker)"
    return False, f"missing reviewer marker by {expected_author} for current head"


def gather(proj):
    """Return (facts dict, error string or None)."""
    if not Path(proj["repo_dir"], ".git").is_dir():
        return None, f"repo dir {proj['repo_dir']} is not a git repo — skipped"
    slug, err = repo_slug(proj)
    if not slug:
        return None, f"cannot resolve GitHub repo ({err}) — skipped"

    prs, err = gh_json(["pr", "list", "-R", slug, "--state", "open", "--json",
                        "number,title,headRefName,headRefOid,baseRefName,baseRefOid,isDraft,url,mergeable,mergeStateStatus"], timeout=30)
    if prs is None:
        return None, f"gh pr list failed ({err}) — skipped"
    for pr in prs:
        pr["verdict"], pr["verdict_detail"] = pr_checks_verdict(
            slug, pr["number"], proj["required_checks"])
        pr["review_ready"], pr["review_detail"] = reviewer_gate(
            slug, pr["number"], pr["headRefOid"])

    rc, out, err = run(["gh", "api", f"repos/{slug}/branches?per_page=100",
                        "--paginate", "--jq", '.[] | [.name, .commit.sha] | @tsv'], timeout=40)
    if rc != 0:
        return None, f"branch list failed ({err[:120]}) — skipped"
    branch_refs = {}
    for line in out.splitlines():
        if not line:
            continue
        name, sep, sha = line.partition("\t")
        if sep and name and sha:
            branch_refs[name] = sha
    branches = list(branch_refs)
    open_heads = {pr["headRefName"] for pr in prs}

    # Entries are (branch, reason, observed ref SHA, action kind). Compare
    # failures are unavailable evidence and never mint a normal prune.
    stale = []
    for br in branches:
        if br == proj["trunk"] or br in open_heads:
            continue
        assoc, _ = gh_json(["pr", "list", "-R", slug, "--head", br,
                            "--state", "all", "--json", "state"], timeout=25)
        states = {p["state"] for p in (assoc or [])}
        if "MERGED" in states:
            # Normal prune is offered only with successful compare evidence that
            # the branch has no commits ahead of trunk.
            rc, ahead, _ = run(["gh", "api",
                                f"repos/{slug}/compare/{proj['trunk']}...{br}",
                                "--jq", ".ahead_by"], timeout=25)
            if rc == 0 and ahead == "0":
                stale.append((br, "PR merged", branch_refs[br], "prune"))
            else:
                log(f"COMPARE UNAVAILABLE/NONZERO {slug} {proj['trunk']}...{br} — no prune action minted")
            continue
        if "CLOSED" in states:
            stale.append((br, "PR closed unmerged — DELETING THIS BRANCH IS DESTRUCTIVE", branch_refs[br], "delete-closed-unmerged"))
            continue
        rc, ahead, _ = run(["gh", "api",
                            f"repos/{slug}/compare/{proj['trunk']}...{br}",
                            "--jq", ".ahead_by"], timeout=25)
        if rc != 0 or not re.fullmatch(r"\d+", ahead or ""):
            log(f"COMPARE UNAVAILABLE {slug} {proj['trunk']}...{br} — no prune action minted")
            continue
        if ahead == "0":
            stale.append((br, "no unique commits", branch_refs[br], "prune"))
        else:
            log(f"ORPHAN AHEAD {slug} {proj['trunk']}...{br} ahead_by={ahead} — no prune action minted")
    return {"slug": slug, "prs": prs, "branches": branches, "stale": stale}, None


# ---- sweep --------------------------------------------------------------------

def ack_text(a):
    """Instant 'on it' feedback posted the moment an approval is acted, before
    the slow gh calls — so a tap is never met with silence."""
    k = a["kind"]
    if k == "merge":
        return (f"⏳ On it — merging PR #{a['pr']} into {a['trunk']} and cleaning up "
                f"{a['branch']}. I'll confirm in a moment.")
    if k == "prune":
        return f"⏳ On it — deleting stale branch {a['branch']}. Confirming shortly."
    if k == "delete-closed-unmerged":
        return (f"⏳ On it — re-verifying the DESTRUCTIVE closed-unmerged deletion of "
                f"{a['branch']}. Confirming shortly.")
    if k == "batch":
        return (f"⏳ On it — running every approved item for {a['label']} now; "
                f"I'll post the result when they finish.")
    return ""


def action_explainer(a):
    """The per-action human brief: What it does / Consequence / Why it's offered.
    Plain text (no markdown emphasis — Telegram MarkdownV2 would choke on the
    punctuation); one block per pending action, paired with its button below."""
    trunk = a["trunk"]
    if a["kind"] == "merge":
        return (
            f"▸ Merge PR #{a['pr']} — {a['title']}\n"
            f"   What it does: squash-merges every commit on the PR into "
            f"{trunk}, then deletes the source branch {a['branch']}.\n"
            f"   Consequence: those changes become part of {trunk}, your "
            f"shippable line — and if you deploy from {trunk} this is what "
            f"reaches production. The PR closes and the branch is gone. "
            f"Every reported CI check is green, every named required context is present, "
            f"and the current-head reviewer marker is eligible right now, so nothing "
            f"known-failing goes in. Reviewer evidence is model-reported and the wrapper "
            f"cannot prove the reviewer actually ran; CI only proves what it tests — green is not a "
            f"substitute for you being happy with the change.\n"
            f"   Why it's offered: the coder finished this work, opened the PR, "
            f"and the configured gates passed — it's sitting ready with nothing blocking it. When "
            f"you approve I re-check, at that moment, that it is still open, all checks "
            f"and named contexts still pass, and reviewer evidence still matches the head; "
            f"if any gate changed, I refuse rather than merge "
            f"a stale approval.\n"
            f"   Link: {a['url']}"
        )
    if a["kind"] in ("prune", "delete-closed-unmerged"):
        reason = a.get("reason", "")
        if a["kind"] == "delete-closed-unmerged":
            return (
                f"▸ DESTRUCTIVE DELETE — closed-unmerged branch {a['branch']}\n"
                f"   CONFIRMATION REQUIRED: this permanently deletes {a['branch']} even though its PR was closed without merging.\n"
                f"   Consequence: commits not in {trunk} may be lost permanently. Approve only if you explicitly intend to discard this work.\n"
                f"   Why it's offered: {reason}. I will reverify the closed-unmerged PR state and exact branch ref at execution time."
            )
        if "unmerged commit" in reason:
            conseq = (
                f"this branch has commits that are NOT in {trunk}. Deleting it "
                f"discards that work permanently — there is no PR carrying it to "
                f"safety. Only approve if you know this line of work is "
                f"abandoned; if you're unsure, skip it and I'll ask again next "
                f"sweep."
            )
        else:
            conseq = (
                f"its work already lives in {trunk} (or it never had any), so "
                f"nothing is lost — this is pure housekeeping."
            )
        return (
            f"▸ Delete branch {a['branch']}\n"
            f"   What it does: permanently removes the branch {a['branch']} from "
            f"GitHub.\n"
            f"   Consequence: {conseq}\n"
            f"   Why it's offered: {reason}. It is no longer the head of any open "
            f"PR, so on the branch list it is just clutter. Removing it moves the "
            f"repo toward the one-branch, trunk-only state you asked for."
        )
    return f"▸ {a.get('desc', a.get('kind', 'action'))}"


def desired_actions(proj, facts):
    """key -> action template. Only things an operator can approve."""
    out = {}
    for pr in facts["prs"]:
        if (pr["isDraft"] or pr["baseRefName"] != proj["trunk"]
                or pr.get("mergeable") != "MERGEABLE" or pr.get("mergeStateStatus") != "CLEAN"
                or pr["verdict"] != "green" or not pr["review_ready"]):
            continue
        # Bind approval to the exact reviewed head. A new commit supersedes the
        # old action and requires a fresh operator-facing ask.
        key = f"merge:{pr['number']}:{pr['headRefOid']}:{pr['baseRefOid']}"
        note = f" ({pr['review_detail']})"
        out[key] = {
            "kind": "merge", "pr": pr["number"], "branch": pr["headRefName"],
            "head_sha": pr["headRefOid"], "base_sha": pr["baseRefOid"],
            "title": pr["title"][:60], "url": pr["url"],
            "desc": f"merge PR #{pr['number']} “{pr['title'][:48]}” into "
                    f"{proj['trunk']}{note}, then delete {pr['headRefName']}",
            "button": f"✅ Merge PR #{pr['number']}: {pr['title'][:28]}",
        }
    for item in facts["stale"]:
        br, reason, ref_sha, kind = item if len(item) == 4 else (*item, "prune")
        key = f"{kind}:{br}:{ref_sha}"
        if kind == "delete-closed-unmerged":
            out[key] = {
                "kind": kind, "branch": br, "reason": reason, "ref_sha": ref_sha,
                "desc": f"DESTRUCTIVE delete closed-unmerged branch {br}",
                "button": f"🛑 CONFIRM DELETE {br[:30]} (closed-unmerged)",
            }
        else:
            warn = "⚠️ " if "unmerged commit" in reason else "\U0001f9f9 "
            out[key] = {
                "kind": kind, "branch": br, "reason": reason, "ref_sha": ref_sha,
                "desc": f"delete branch {br} ({reason})",
                "button": f"{warn}Delete {br[:34]} ({reason[:24]})",
            }
    return out


def sweep(dry=False):
    now = time.time()
    all_clean = True
    dest = hub_dest()
    configured = projects()
    # Resolve and reject duplicate canonical repositories before touching state
    # or minting any actions. Sorting projects() makes the winner/rejection
    # deterministic across runs.
    canonical_by_repo = {}
    duplicate_cfgs = set()
    for proj in configured:
        slug, err = repo_slug(proj)
        if slug:
            key = slug.strip().lower()
            canonical_by_repo.setdefault(key, []).append(proj["cfg"])
    for key, cfgs in canonical_by_repo.items():
        if len(cfgs) > 1:
            duplicate_cfgs.update(cfgs)
    with Locked():
        state = load_state()
        for proj in configured:
            if proj["cfg"] in duplicate_cfgs:
                slug = next((s for s, cfgs in canonical_by_repo.items() if proj["cfg"] in cfgs), "unknown")
                print(f"project {proj['label']} (cfg {Path(proj['cfg']).name}, trunk {proj['trunk']})")
                print(f"  !! duplicate canonical GitHub repo {slug} — refusing ambiguous project state")
                all_clean = False
                continue
            label = proj["label"]
            print(f"project {label} (cfg {Path(proj['cfg']).name}, trunk {proj['trunk']})")
            facts, err = gather(proj)
            if err:
                print(f"  !! {err}")
                all_clean = False
                continue
            project_key = facts["slug"].strip().lower()

            # info lines
            red = [p for p in facts["prs"] if p["verdict"] == "red"]
            pend = [p for p in facts["prs"] if p["verdict"] in ("pending", "missing-required", "no-ci", "unavailable")]
            wrong_base = [p for p in facts["prs"] if p["baseRefName"] != proj["trunk"]]
            merge_blocked = [p for p in facts["prs"] if p["baseRefName"] == proj["trunk"] and (p.get("mergeable") != "MERGEABLE" or p.get("mergeStateStatus") != "CLEAN")]
            review_blocked = [p for p in facts["prs"] if p["baseRefName"] == proj["trunk"] and p.get("mergeable") == "MERGEABLE" and p.get("mergeStateStatus") == "CLEAN" and p["verdict"] == "green" and not p["review_ready"]]
            drafts = [p for p in facts["prs"] if p["isDraft"]]
            print(f"  repo {facts['slug']}: {len(facts['branches'])} branch(es), "
                  f"{len(facts['prs'])} open PR(s)")
            for p in red:
                print(f"  ❌ PR #{p['number']} CI RED — {p['title'][:60]} {p['url']}")
            for p in pend:
                print(f"  ⏳ PR #{p['number']} CI {p['verdict']} ({p['verdict_detail']}) — {p['title'][:60]}")
            for p in wrong_base:
                print(f"  ⛔ PR #{p['number']} targets {p['baseRefName']}, not protected trunk {proj['trunk']} — {p['title'][:60]}")
            for p in merge_blocked:
                print(f"  ⛔ PR #{p['number']} merge state {p.get('mergeStateStatus')} / {p.get('mergeable')} — refresh/update branch first")
            for p in review_blocked:
                print(f"  ⛔ PR #{p['number']} reviewer gate blocked ({p['review_detail']}) — {p['title'][:60]}")
            for p in drafts:
                print(f"  \U0001f4dd PR #{p['number']} draft — {p['title'][:60]}")

            desired = desired_actions(proj, facts)

            # reconcile pending actions for this project
            existing = {a["key"]: (aid, a) for aid, a in state["actions"].items()
                        if a.get("project_key", a.get("repo", "").lower()) == project_key and a["status"] == "pending"}
            for key, (aid, a) in existing.items():
                if key not in desired:
                    a["status"] = "superseded"
                    a["result"] = "repo state changed before approval"
            actions = []  # (id, action)
            for key, tpl in desired.items():
                if key in existing and existing[key][1]["status"] == "pending":
                    actions.append((existing[key][0], existing[key][1]))
                    continue
                aid = secrets.token_hex(6)
                a = {"key": key, "label": label, "project_key": project_key, "cfg": proj["cfg"],
                     "repo": facts["slug"], "trunk": proj["trunk"],
                     "status": "pending", "created": now, **tpl}
                state["actions"][aid] = a
                actions.append((aid, a))

            if not actions:
                if red or pend or wrong_base or merge_blocked or review_blocked:
                    all_clean = False
                    print("  no approvals needed (CI/reviewer-blocked PRs ride the coder loop)")
                else:
                    print("  clean ✓ (trunk-only or only active PR work)")
                state["posts"].setdefault(project_key, {})["fingerprint"] = ""
                continue

            all_clean = False
            fp = hashlib.sha1(json.dumps(sorted(desired.keys())).encode()).hexdigest()
            post = state["posts"].get(project_key, {})
            fresh = post.get("fingerprint") != fp
            aged = now - post.get("ts", 0) >= REASK_HOURS * 3600
            snoozed = now < post.get("snoozed_until", 0)
            for aid, a in actions:
                print(f"  pending eg:{aid}  {a['desc']}")
            if snoozed and not fresh:
                print(f"  (snoozed until {time.strftime('%H:%M', time.localtime(post['snoozed_until']))} — not re-posting)")
                continue
            if not (fresh or aged):
                h = (now - post.get("ts", now)) / 3600
                print(f"  (asked {h:.1f}h ago, unchanged — not re-posting; re-ask after {REASK_HOURS:.0f}h)")
                continue

            shown = actions[:MAX_BUTTONS]
            overflow = actions[MAX_BUTTONS:]
            lines = [
                f"\U0001f6a6 {label} — GitHub gate needs your call",
                f"Repo {facts['slug']}, trunk {proj['trunk']}. "
                f"{len(shown)} item(s) below need a yes/no from you. I only ever "
                f"act on your explicit approval — nothing merges or deletes until "
                f"you tap.",
                "",
            ]
            for aid, a in shown:
                lines.append(action_explainer(a))
                lines.append("")
            if red or pend or wrong_base or merge_blocked or review_blocked:
                aware = []
                for p in red:
                    aware.append(f"   • PR #{p['number']} CI is RED — {p['title'][:50]} "
                                 f"(I won't offer a red PR; it goes back through the coder loop)")
                for p in pend:
                    aware.append(f"   • PR #{p['number']} CI is {p['verdict']} — {p['verdict_detail']} "
                                 f"(not merge-actionable)")
                for p in wrong_base:
                    aware.append(f"   • PR #{p['number']} targets {p['baseRefName']}, not protected trunk {proj['trunk']} "
                                 f"(not merge-actionable)")
                for p in merge_blocked:
                    aware.append(f"   • PR #{p['number']} merge state is {p.get('mergeStateStatus')} / {p.get('mergeable')} "
                                 f"(update/reconcile before approval)")
                for p in review_blocked:
                    aware.append(f"   • PR #{p['number']} reviewer gate blocked — {p['review_detail']} "
                                 f"(model-reported evidence is a trust limit, not proof)")
                lines.append("For your awareness (not actionable here):")
                lines.extend(aware)
                lines.append("")
            if overflow:
                lines.append(f"+{len(overflow)} more pending action(s) not shown as buttons "
                             f"(button cap {MAX_BUTTONS}) — say “gate pending” to list them all.")
                lines.append("")
            do_all = len(actions) >= 2
            approve_help = (
                "How to approve: tap a button below, or react \U0001f44d/✅ to this message, "
                "or reply “approve” — for a single pending item I act it; if several match "
                "I'll ask which.")
            if do_all:
                approve_help += (f" To clear the whole project in one go, tap “Do all "
                                 f"{len(actions)} of the above” — I run every item, "
                                 f"re-verifying each before it executes.")
            approve_help += (f" Not ready? Tap “Not now” to snooze this project's asks "
                             f"for {REASK_HOURS:.0f}h.")
            lines.append(approve_help)

            buttons = [(a["button"], f"/gate act eg:{aid}") for aid, a in shown]
            # Supersede any prior pending batch/snooze for this project — a new ask
            # replaces them so a stale "do all" can't fire against old state.
            for sid, sa in state["actions"].items():
                if (sa.get("project_key", sa.get("repo", "").lower()) == project_key
                        and sa["status"] == "pending"
                        and sa["kind"] in ("snooze", "batch")):
                    sa["status"] = "superseded"
                    sa["result"] = "newer gate ask posted"
            if do_all:
                batch_id = secrets.token_hex(6)
                state["actions"][batch_id] = {
                    "key": f"batch:{int(now)}", "label": label, "project_key": project_key, "cfg": proj["cfg"],
                    "repo": facts["slug"], "trunk": proj["trunk"], "kind": "batch",
                    "desc": f"do all {len(actions)} pending action(s) for {label}",
                    "button": f"☑️ Do all {len(actions)} of the above",
                    "status": "pending", "created": now,
                }
                buttons.append((f"☑️ Do all {len(actions)} of the above", f"/gate act eg:{batch_id}"))
            snooze_id = secrets.token_hex(6)
            state["actions"][snooze_id] = {
                "key": f"snooze:{int(now)}", "label": label, "project_key": project_key, "cfg": proj["cfg"],
                "repo": facts["slug"], "trunk": proj["trunk"], "kind": "snooze",
                "desc": f"snooze {label} gate asks for {REASK_HOURS:.0f}h",
                "button": "⏸ Not now (snooze 24h)",
                "status": "pending", "created": now,
            }
            buttons.append((f"⏸ Not now (snooze {REASK_HOURS:.0f}h)", f"/gate act eg:{snooze_id}"))
            ok = send_message(dest, "\n".join(lines), buttons, dry=dry)
            if ok and not dry:
                state["posts"][project_key] = {"fingerprint": fp, "ts": now,
                                         "snoozed_until": post.get("snoozed_until", 0)}
                print(f"  posted approval message ({len(buttons)} buttons) to gate hub "
                      f"{dest['channel']} thread {dest['thread'] or '-'}")
                log(f"POSTED {label} {len(actions)} action(s) fp={fp[:8]} -> hub "
                    f"{dest['target']}:{dest['thread'] or '-'}")
        if not dry:
            save_state(state)
    if all_clean:
        print("ALL_CLEAN")


# ---- act ------------------------------------------------------------------------

def find_proj(action):
    # State predating project_key is supported via the canonical repo slug. Do
    # not use display labels/basenames: two projects may share one basename.
    wanted = action.get("project_key") or action.get("repo", "").strip().lower()
    if not wanted:
        return None
    matches = []
    for p in projects():
        slug, _ = repo_slug(p)
        if slug and slug.strip().lower() == wanted:
            matches.append(p)
    return matches[0] if len(matches) == 1 else None


def act(aid):
    # Accept the raw button payload too: a tapped inline button is delivered as
    # "callback_data: eg:<id>", and the operator may paste "eg:<id>" or just "<id>".
    aid = aid.strip()
    if aid.lower().startswith("callback_data:"):
        aid = aid.split(":", 1)[1].strip()
    aid = aid.removeprefix("eg:").strip()
    with Locked():
        state = load_state()
        a = state["actions"].get(aid)
        if not a:
            print(f"FAILED unknown action id '{aid}'. Current pending:")
            _pending(state)
            sys.exit(4)
        if a["status"] != "pending":
            print(f"REFUSED action eg:{aid} is already {a['status']}"
                  f" ({a.get('result', '')}) — actions are single-use.")
            sys.exit(4)
        proj = find_proj(a)
        if not proj:
            print(f"FAILED project config for {a['label']} no longer exists")
            sys.exit(4)

        # Quick feedback: acknowledge the approval immediately, before the slow
        # gh merge/delete calls, so the operator never taps into silence.
        if a["kind"] != "snooze":
            send_message(hub_dest(), ack_text(a))

        if a["kind"] == "batch":
            # "Do all of the above": execute EVERY still-pending merge/prune for
            # this project (covers overflow beyond the shown buttons too). Each
            # goes through execute()'s own re-verification independently, so a
            # PR that went red since the ask is skipped, not force-merged.
            siblings = [(sid, sa) for sid, sa in state["actions"].items()
                        if sa.get("project_key", sa.get("repo", "").lower()) == a.get("project_key", a.get("repo", "").lower())
                        and sa["status"] == "pending"
                        and sa["kind"] in ("merge", "prune", "delete-closed-unmerged")]
            siblings.sort(key=lambda r: r[1]["created"])
            if not siblings:
                outcome, ok = f"{a['label']}: nothing left to do (all items already handled)", True
            else:
                results, ok = [], True
                for sid, sa in siblings:
                    o, k = execute(sa, proj)
                    sa["status"] = "done" if k else "failed"
                    sa["result"] = o
                    sa["acted"] = time.time()
                    results.append(("✅ " if k else "❌ ") + o)
                    ok = ok and k
                outcome = (f"{a['label']}: ran {len(siblings)} action(s) "
                           f"[{sum(1 for _, s in siblings if s['status'] == 'done')} ok, "
                           f"{sum(1 for _, s in siblings if s['status'] == 'failed')} failed]:\n"
                           + "\n".join(results))
        else:
            outcome, ok = execute(a, proj)
        a["status"] = "done" if ok else "failed"
        a["result"] = outcome
        a["acted"] = time.time()
        if a["kind"] == "snooze" and ok:
            post_key = a.get("project_key") or a.get("repo", "").strip().lower()
            state["posts"].setdefault(post_key, {})["snoozed_until"] = \
                time.time() + REASK_HOURS * 3600
        save_state(state)
    log(f"ACT eg:{aid} {a['kind']} {a['label']} -> {a['status']}: {outcome[:160]}")
    prefix = "DONE" if ok else "FAILED"
    print(f"{prefix} {outcome}")
    if a["kind"] != "snooze":
        icon = "✅" if ok else "❌"
        send_message(hub_dest(), f"{icon} gate: {outcome}")
    sys.exit(0 if ok else 5)


def execute(a, proj):
    slug, trunk = a["repo"], a["trunk"]
    if a["kind"] == "snooze":
        return f"{a['label']}: gate asks snoozed for {REASK_HOURS:.0f}h", True

    if a["kind"] == "merge":
        pr, err = gh_json(["pr", "view", str(a["pr"]), "-R", slug, "--json",
                           "state,isDraft,headRefName,headRefOid,baseRefName,baseRefOid,title,url,mergeable,mergeStateStatus"], timeout=25)
        if pr is None:
            return f"could not re-verify PR #{a['pr']} ({err})", False
        if pr["state"] != "OPEN" or pr["isDraft"]:
            return f"PR #{a['pr']} is {pr['state']}{' (draft)' if pr['isDraft'] else ''} — not merging", False
        if pr["baseRefName"] != trunk:
            return f"PR #{a['pr']} now targets {pr['baseRefName']}, not protected trunk {trunk} — not merging", False
        if pr["headRefName"] != a["branch"] or pr["headRefOid"] != a.get("head_sha"):
            return f"PR #{a['pr']} head changed after approval — run a fresh gate sweep", False
        if pr["baseRefOid"] != a.get("base_sha"):
            return f"protected trunk advanced after approval — update/recheck PR #{a['pr']} and run a fresh gate sweep", False
        if pr.get("mergeable") != "MERGEABLE" or pr.get("mergeStateStatus") != "CLEAN":
            return f"PR #{a['pr']} merge state is {pr.get('mergeStateStatus')} / {pr.get('mergeable')} — not merging", False
        verdict, detail = pr_checks_verdict(slug, a["pr"], proj["required_checks"])
        review_ready, review_detail = reviewer_gate(slug, a["pr"], pr["headRefOid"])
        if verdict != "green":
            return f"PR #{a['pr']} checks are {verdict} ({detail}) now — not merging", False
        if not review_ready:
            return f"PR #{a['pr']} reviewer gate is blocked ({review_detail}) — not merging", False
        rc, out, err = run(["gh", "pr", "merge", str(a["pr"]), "-R", slug,
                            f"--{MERGE_METHOD}", "--delete-branch"],
                           cwd=proj["repo_dir"], timeout=60)
        if rc != 0:
            return f"merge of PR #{a['pr']} failed: {(err or out)[:200]}", False
        sync_local(proj)
        return (f"{a['label']}: merged PR #{a['pr']} “{pr['title'][:48]}” into "
                f"{trunk} ({MERGE_METHOD}) and deleted {pr['headRefName']} — {pr['url']}"), True

    if a["kind"] in ("prune", "delete-closed-unmerged"):
        br = a["branch"]
        if br == trunk:
            return f"refusing to delete trunk {trunk}", False
        heads, _ = gh_json(["pr", "list", "-R", slug, "--head", br,
                            "--state", "open", "--json", "number"], timeout=25)
        if heads:
            return f"branch {br} is now head of open PR #{heads[0]['number']} — not deleting", False
        if a["kind"] == "delete-closed-unmerged":
            closed, closed_err = gh_json(["pr", "list", "-R", slug, "--head", br,
                                          "--state", "all", "--json", "state"], timeout=25)
            if closed is None or not any(p.get("state") == "CLOSED" for p in closed) \
                    or any(p.get("state") == "MERGED" for p in closed):
                return f"branch {br} is no longer verified as closed-unmerged ({closed_err or 'state changed'}) — not deleting", False
        ref, ref_err = gh_json(["api", f"repos/{slug}/git/ref/heads/{br}"], timeout=25)
        current_sha = (ref or {}).get("object", {}).get("sha")
        if not current_sha:
            return f"cannot re-verify branch {br} ref ({ref_err or 'missing SHA'}) — not deleting", False
        if current_sha != a.get("ref_sha"):
            return f"branch {br} changed after approval ({a.get('ref_sha')} → {current_sha}) — run a fresh gate sweep", False
        # Compare/ref/PR state is reverified at act. Unavailable or malformed
        # compare output is refusal, never evidence for deletion.
        rc_cmp, ahead_cmp, err_cmp = run(["gh", "api",
                                          f"repos/{slug}/compare/{trunk}...{br}",
                                          "--jq", ".ahead_by"], timeout=25)
        if rc_cmp != 0 or not re.fullmatch(r"\d+", ahead_cmp or ""):
            return f"cannot re-verify compare for {br} ({err_cmp or 'malformed response'}) — not deleting", False
        if a["kind"] == "prune":
            was_unique = "unmerged commit" in a.get("reason", "")
            if (was_unique and ahead_cmp == "0") or (not was_unique and ahead_cmp != "0"):
                return f"branch {br} compare state changed (ahead_by={ahead_cmp}) — run a fresh gate sweep", False
        rc, out, err = run(["gh", "api", "-X", "DELETE",
                            f"repos/{slug}/git/refs/heads/{br}"], timeout=25)
        if rc != 0:
            return f"delete of {br} failed: {(err or out)[:200]}", False
        sync_local(proj)
        return f"{a['label']}: deleted stale branch {br} ({a.get('reason', '')})", True

    return f"unknown action kind {a['kind']}", False


def sync_local(proj):
    """Best-effort: keep the coder's clone converged on the fresh trunk."""
    d = proj["repo_dir"]
    run(["git", "-C", d, "fetch", "--prune", "origin"], timeout=40)
    rc, cur, _ = run(["git", "-C", d, "rev-parse", "--abbrev-ref", "HEAD"], timeout=10)
    rc2, dirty, _ = run(["git", "-C", d, "status", "--porcelain"], timeout=10)
    if rc == 0 and cur == proj["trunk"] and rc2 == 0 and not dirty:
        run(["git", "-C", d, "pull", "--ff-only"], timeout=40)


# ---- pending / status ---------------------------------------------------------------

def _pending(state, label=None):
    rows = [(aid, a) for aid, a in state["actions"].items()
            if a["status"] == "pending" and a["kind"] not in ("snooze", "batch")
            and (label is None or a["label"].lower() == label.lower()
                 or a.get("project_key", a.get("repo", "").lower()) == label.lower())]
    if not rows:
        print("no pending actions" + (f" for {label}" if label else ""))
        return
    for aid, a in sorted(rows, key=lambda r: r[1]["created"]):
        age = (time.time() - a["created"]) / 3600
        print(f"PENDING eg:{aid}  [{a['label']}] {a['desc']}  ({age:.1f}h old)")


def main():
    args = sys.argv[1:]
    if not args:
        print(__doc__ or "usage: edge-pr-gate.sh sweep [--dry-run] | act <id> | pending [label] | status")
        sys.exit(2)
    mode, rest = args[0], args[1:]
    if mode == "sweep":
        sweep(dry="--dry-run" in rest or os.environ.get("EDGE_GATE_DRYRUN") == "1")
    elif mode == "act":
        if not rest:
            print("usage: edge-pr-gate.sh act <id>")
            sys.exit(2)
        act(rest[0])
    elif mode == "pending":
        _pending(load_state(), rest[0] if rest else None)
    elif mode == "status":
        state = load_state()
        _pending(state)
        done = [(aid, a) for aid, a in state["actions"].items()
                if a["status"] in ("done", "failed")]
        for aid, a in sorted(done, key=lambda r: r[1].get("acted", 0))[-8:]:
            print(f"{a['status'].upper()} eg:{aid}  [{a['label']}] {a.get('result', '')[:100]}")
    else:
        print(f"unknown mode '{mode}' — sweep | act <id> | pending [label] | status")
        sys.exit(2)


main()
PY
