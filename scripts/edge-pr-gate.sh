#!/usr/bin/env bash
# edge-pr-gate.sh — EDGE GitHub PR gate: periodic repo sweep + operator-approved
# agent-executed merges and branch hygiene.
#
# Part of the "EDGE — Evidence-Driven Git Engineering" template.
#
# WHAT IT DOES
#   Every heartbeat tick (default: a 6h task in the research agent's
#   HEARTBEAT.md) the agent runs `sweep`. For every configured project this:
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
#   RDD_TG_TARGET, RDD_TG_THREAD, RDD_OPENCLAW.
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
#   - merge requires: PR open, not draft, zero failing AND zero pending checks
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
        d[k.strip()] = v.strip().strip('"').strip("'")
    return d


def projects():
    out = []
    for f in sorted(CFG_DIR.glob("*.env")):
        env = parse_env_file(f)
        repo_dir = env.get("RDD_REPO_DIR")
        if not repo_dir:
            continue
        out.append({
            "cfg": str(f),
            "label": Path(repo_dir).name,
            "repo_dir": repo_dir,
            "trunk": env.get("RDD_MAIN_BRANCH", "main"),
            "channel": env.get("RDD_TG_CHANNEL", "telegram"),
            "target": env.get("RDD_TG_TARGET", ""),
            "thread": env.get("RDD_TG_THREAD", ""),
            "openclaw": env.get("RDD_OPENCLAW", str(HOME / ".local/bin/openclaw")),
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
    return (out, None) if rc == 0 and out else (None, err or "no slug")


def pr_checks_verdict(slug, number):
    """green | red | pending | no-ci"""
    rc, out, err = run(["gh", "pr", "checks", str(number), "-R", slug,
                        "--json", "bucket"], timeout=30)
    if not out:
        return "no-ci"
    try:
        buckets = [c.get("bucket") for c in json.loads(out)]
    except json.JSONDecodeError:
        return "no-ci"
    if not buckets:
        return "no-ci"
    if any(b == "fail" for b in buckets):
        return "red"
    if any(b == "pending" for b in buckets):
        return "pending"
    return "green"


def gather(proj):
    """Return (facts dict, error string or None)."""
    if not Path(proj["repo_dir"], ".git").is_dir():
        return None, f"repo dir {proj['repo_dir']} is not a git repo — skipped"
    slug, err = repo_slug(proj)
    if not slug:
        return None, f"cannot resolve GitHub repo ({err}) — skipped"

    prs, err = gh_json(["pr", "list", "-R", slug, "--state", "open", "--json",
                        "number,title,headRefName,isDraft,url"], timeout=30)
    if prs is None:
        return None, f"gh pr list failed ({err}) — skipped"
    for pr in prs:
        pr["verdict"] = pr_checks_verdict(slug, pr["number"])

    rc, out, err = run(["gh", "api", f"repos/{slug}/branches?per_page=100",
                        "--paginate", "--jq", ".[].name"], timeout=40)
    if rc != 0:
        return None, f"branch list failed ({err[:120]}) — skipped"
    branches = [b for b in out.splitlines() if b]
    open_heads = {pr["headRefName"] for pr in prs}

    stale = []  # (branch, reason)
    for br in branches:
        if br == proj["trunk"] or br in open_heads:
            continue
        assoc, _ = gh_json(["pr", "list", "-R", slug, "--head", br,
                            "--state", "all", "--json", "state"], timeout=25)
        states = {p["state"] for p in (assoc or [])}
        if "MERGED" in states:
            stale.append((br, "PR merged"))
            continue
        if "CLOSED" in states:
            stale.append((br, "PR closed unmerged"))
            continue
        rc, ahead, _ = run(["gh", "api",
                            f"repos/{slug}/compare/{proj['trunk']}...{br}",
                            "--jq", ".ahead_by"], timeout=25)
        if rc == 0 and ahead == "0":
            stale.append((br, "no unique commits"))
        else:
            n = ahead if rc == 0 else "?"
            stale.append((br, f"NO PR, {n} unmerged commit(s) — deleting discards them"))
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
        return f"⏳ On it — deleting branch {a['branch']}. Confirming shortly."
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
            f"Required CI checks are green right now, so nothing failing goes "
            f"in; but CI only proves what it tests — a green check is not a "
            f"substitute for you being happy with the change.\n"
            f"   Why it's offered: the coder finished this work, opened the PR, "
            f"and CI passed — it's sitting ready with nothing blocking it. When "
            f"you approve I re-check, at that moment, that it is still open and "
            f"still green; if CI has gone red since, I refuse rather than merge "
            f"a stale approval.\n"
            f"   Link: {a['url']}"
        )
    if a["kind"] == "prune":
        reason = a.get("reason", "")
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
        if pr["isDraft"] or pr["verdict"] not in ("green", "no-ci"):
            continue
        key = f"merge:{pr['number']}"
        note = "" if pr["verdict"] == "green" else " (repo has no CI checks)"
        out[key] = {
            "kind": "merge", "pr": pr["number"], "branch": pr["headRefName"],
            "title": pr["title"][:60], "url": pr["url"],
            "desc": f"merge PR #{pr['number']} “{pr['title'][:48]}” into "
                    f"{proj['trunk']}{note}, then delete {pr['headRefName']}",
            "button": f"✅ Merge PR #{pr['number']}: {pr['title'][:28]}",
        }
    for br, reason in facts["stale"]:
        key = f"prune:{br}"
        warn = "⚠️ " if "unmerged commit" in reason else "\U0001f9f9 "
        out[key] = {
            "kind": "prune", "branch": br, "reason": reason,
            "desc": f"delete branch {br} ({reason})",
            "button": f"{warn}Delete {br[:34]} ({reason[:24]})",
        }
    return out


def sweep(dry=False):
    now = time.time()
    all_clean = True
    dest = hub_dest()
    with Locked():
        state = load_state()
        for proj in projects():
            label = proj["label"]
            print(f"project {label} (cfg {Path(proj['cfg']).name}, trunk {proj['trunk']})")
            facts, err = gather(proj)
            if err:
                print(f"  !! {err}")
                all_clean = False
                continue

            # info lines
            red = [p for p in facts["prs"] if p["verdict"] == "red"]
            pend = [p for p in facts["prs"] if p["verdict"] == "pending"]
            drafts = [p for p in facts["prs"] if p["isDraft"]]
            print(f"  repo {facts['slug']}: {len(facts['branches'])} branch(es), "
                  f"{len(facts['prs'])} open PR(s)")
            for p in red:
                print(f"  ❌ PR #{p['number']} CI RED — {p['title'][:60]} {p['url']}")
            for p in pend:
                print(f"  ⏳ PR #{p['number']} CI pending — {p['title'][:60]}")
            for p in drafts:
                print(f"  \U0001f4dd PR #{p['number']} draft — {p['title'][:60]}")

            desired = desired_actions(proj, facts)

            # reconcile pending actions for this project
            existing = {a["key"]: (aid, a) for aid, a in state["actions"].items()
                        if a["label"] == label and a["status"] == "pending"}
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
                a = {"key": key, "label": label, "cfg": proj["cfg"],
                     "repo": facts["slug"], "trunk": proj["trunk"],
                     "status": "pending", "created": now, **tpl}
                state["actions"][aid] = a
                actions.append((aid, a))

            if not actions:
                if red or pend:
                    all_clean = False
                    print("  no approvals needed (red/pending PRs ride the coder loop)")
                else:
                    print("  clean ✓ (trunk-only or only active PR work)")
                state["posts"].setdefault(label, {})["fingerprint"] = ""
                continue

            all_clean = False
            fp = hashlib.sha1(json.dumps(sorted(desired.keys())).encode()).hexdigest()
            post = state["posts"].get(label, {})
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
            if red or pend:
                aware = []
                for p in red:
                    aware.append(f"   • PR #{p['number']} CI is RED — {p['title'][:50]} "
                                 f"(I won't offer a red PR; it goes back through the coder loop)")
                for p in pend:
                    aware.append(f"   • PR #{p['number']} CI still running — {p['title'][:50]} "
                                 f"(I'll offer it once it's green)")
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
                if (sa["label"] == label and sa["status"] == "pending"
                        and sa["kind"] in ("snooze", "batch")):
                    sa["status"] = "superseded"
                    sa["result"] = "newer gate ask posted"
            if do_all:
                batch_id = secrets.token_hex(6)
                state["actions"][batch_id] = {
                    "key": f"batch:{int(now)}", "label": label, "cfg": proj["cfg"],
                    "repo": facts["slug"], "trunk": proj["trunk"], "kind": "batch",
                    "desc": f"do all {len(actions)} pending action(s) for {label}",
                    "button": f"☑️ Do all {len(actions)} of the above",
                    "status": "pending", "created": now,
                }
                buttons.append((f"☑️ Do all {len(actions)} of the above", f"/gate act eg:{batch_id}"))
            snooze_id = secrets.token_hex(6)
            state["actions"][snooze_id] = {
                "key": f"snooze:{int(now)}", "label": label, "cfg": proj["cfg"],
                "repo": facts["slug"], "trunk": proj["trunk"], "kind": "snooze",
                "desc": f"snooze {label} gate asks for {REASK_HOURS:.0f}h",
                "button": "⏸ Not now (snooze 24h)",
                "status": "pending", "created": now,
            }
            buttons.append((f"⏸ Not now (snooze {REASK_HOURS:.0f}h)", f"/gate act eg:{snooze_id}"))
            ok = send_message(dest, "\n".join(lines), buttons, dry=dry)
            if ok and not dry:
                state["posts"][label] = {"fingerprint": fp, "ts": now,
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
    for p in projects():
        if p["cfg"] == action["cfg"] or p["label"] == action["label"]:
            return p
    return None


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
                        if sa["label"] == a["label"] and sa["status"] == "pending"
                        and sa["kind"] in ("merge", "prune")]
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
            state["posts"].setdefault(a["label"], {})["snoozed_until"] = \
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
                           "state,isDraft,headRefName,title,url"], timeout=25)
        if pr is None:
            return f"could not re-verify PR #{a['pr']} ({err})", False
        if pr["state"] != "OPEN" or pr["isDraft"]:
            return f"PR #{a['pr']} is {pr['state']}{' (draft)' if pr['isDraft'] else ''} — not merging", False
        verdict = pr_checks_verdict(slug, a["pr"])
        if verdict not in ("green", "no-ci"):
            return f"PR #{a['pr']} checks are {verdict} now (were green at ask time) — not merging", False
        rc, out, err = run(["gh", "pr", "merge", str(a["pr"]), "-R", slug,
                            f"--{MERGE_METHOD}", "--delete-branch"],
                           cwd=proj["repo_dir"], timeout=60)
        if rc != 0:
            return f"merge of PR #{a['pr']} failed: {(err or out)[:200]}", False
        sync_local(proj)
        return (f"{a['label']}: merged PR #{a['pr']} “{pr['title'][:48]}” into "
                f"{trunk} ({MERGE_METHOD}) and deleted {pr['headRefName']} — {pr['url']}"), True

    if a["kind"] == "prune":
        br = a["branch"]
        if br == trunk:
            return f"refusing to delete trunk {trunk}", False
        heads, _ = gh_json(["pr", "list", "-R", slug, "--head", br,
                            "--state", "open", "--json", "number"], timeout=25)
        if heads:
            return f"branch {br} is now head of open PR #{heads[0]['number']} — not deleting", False
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
            and (label is None or a["label"].lower() == label.lower())]
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
