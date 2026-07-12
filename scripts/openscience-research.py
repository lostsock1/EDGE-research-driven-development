#!/usr/bin/env python3
"""openscience-research.py — EDGE ⇄ OpenScience research dispatch (API-automated).

EDGE writes a research ASSIGNMENT, this driver dispatches it to the local,
sandboxed, research-only OpenScience server (127.0.0.1:3457) over its HTTP API,
captures the produced RESEARCH PACKET (markdown + JSON sidecar) into the mailbox,
and posts a one-tap approval back to the ORIGINATING Telegram thread.

Per-project: `--thread <topic>` routes the packet + buttons back to the thread the
assignment came from (each project thread, or the home/hub thread); `--project <name>`
tags the packet and scopes the knowledge base (`~/edge-research-kb/<project>/`).

OpenScience is research + knowledge-base ONLY (code execution disabled). Nothing
here implements, branches, opens PRs, dispatches opencode, or auto-ingests into a
repo — a packet becomes EDGE knowledge only when the operator taps Accept.

Verbs:
  assign "<q>" [--project P] [--thread T] [--context "<text>"]   mint an assignment (prints ERA id)
  followup <OSR-id|handle> "<q>" [--project P] [--thread T]             mint a follow-up (prints ERA id)
  dispatch <ERA-id>                                              run OpenScience, produce a packet
  list | status | health
  show <OSR-id|handle>
  accept <OSR-id|handle>   (single-use → project KB)
  reject <OSR-id|handle>   (single-use → archive)

Config: ~/.config/edge-rdd/research.env (RDD_RESEARCH_* keys), sourced by the bash wrapper.
Buttons carry a short `handle` (not the long OSR id) to stay under Telegram's 64-byte limit.
"""
import fcntl, json, os, re, secrets, subprocess, sys, time, urllib.request, urllib.error
from datetime import datetime, timezone
from pathlib import Path

HOME = Path.home()
OS_BASE   = os.environ.get("RDD_RESEARCH_OS_BASE", "http://127.0.0.1:3457")
AGENT     = os.environ.get("RDD_RESEARCH_AGENT", "research")
TIMEOUT   = int(os.environ.get("RDD_RESEARCH_TIMEOUT", "1200"))
# OpenScience exposes reasoning controls to the HTTP API as a model "variant".
# Provider-specific (e.g. a high-reasoning variant name); empty = provider default.
VARIANT   = (os.environ.get("RDD_RESEARCH_VARIANT") or os.environ.get("RDD_RESEARCH_THINKING_LEVEL") or "").strip()
OPENCLAW  = os.environ.get("RDD_OPENCLAW", "openclaw")
TG_CHAN   = os.environ.get("RDD_RESEARCH_TG_CHANNEL", "telegram")
TG_TARGET = os.environ.get("RDD_RESEARCH_TG_TARGET", "")
TG_THREAD = os.environ.get("RDD_RESEARCH_TG_THREAD", "")  # default/home thread

XFER   = Path(os.environ.get("RDD_RESEARCH_XFER", HOME / "edge-research-transfer"))
KB     = Path(os.environ.get("RDD_RESEARCH_KB", HOME / "edge-research-kb"))
ASSIGN = XFER / "assignments"
INCOM  = XFER / "incoming"
ARCH   = XFER / "archived"
STATED = Path(os.environ.get("RDD_RESEARCH_STATE", HOME / ".local/state/edge-rdd/research"))
STATE  = STATED / "state.json"
LOG    = STATED / "research.log"

DEFAULT_PROFILE = os.environ.get("RDD_RESEARCH_PROFILE", "software")
PROFILE_GUIDANCE = {
    "software": """Software development research profile (default):
- Optimize for implementation decisions, not generic background essays.
- Prefer primary/current sources in this order: official docs/API references, release notes/changelogs, source repository code/README/examples, standards/RFCs/specs, security advisories/CVEs, maintainer issue/PR discussions, reputable benchmark or postmortem evidence.
- Always capture version, release date, runtime/platform constraints, deprecations, API defaults, migration notes, compatibility risks, performance/security implications, and known failure modes when relevant.
- Compare alternatives by when to use, when to avoid, operational tradeoffs, and what would change in code/config/tests.
- Turn findings into EDGE-actionable guidance: exact docs to update, ADR/work-order implications, validation commands/tests to run, rollback or feature-flag needs, and open questions.
- Treat stale blogs, AI-generated summaries, and unsourced benchmarks as weak evidence; use them only as leads unless corroborated by primary sources.""",
}


if DEFAULT_PROFILE not in PROFILE_GUIDANCE:
    DEFAULT_PROFILE = "software"


def profile_guidance(profile):
    return PROFILE_GUIDANCE.get(profile, PROFILE_GUIDANCE["software"])

for d in (ASSIGN, INCOM, ARCH, KB, STATED):
    d.mkdir(parents=True, exist_ok=True)


def log(msg):
    try:
        with open(LOG, "a") as f:
            f.write(f"{datetime.now().isoformat(timespec='seconds')} {msg}\n")
    except OSError:
        pass


def slug(text, n=6):
    return "-".join(re.findall(r"[a-z0-9]+", text.lower())[:n]) or "topic"


def pslug(project):
    return re.sub(r"[^a-z0-9_-]", "", (project or "general").lower()) or "general"


def stamp():
    return datetime.now().strftime("%Y%m%d-%H%M")


def iso():
    return datetime.now(timezone.utc).isoformat()


# ---- state (flock-serialized) ----------------------------------------------------
def _with_state(mutator):
    STATED.mkdir(parents=True, exist_ok=True)
    with open(STATED / ".lock", "w") as lk:
        fcntl.flock(lk, fcntl.LOCK_EX)
        data = {"packets": {}, "handles": {}}
        if STATE.exists():
            try:
                data = json.loads(STATE.read_text())
            except (OSError, ValueError):
                pass
        data.setdefault("packets", {})
        data.setdefault("handles", {})
        result = mutator(data)
        tmp = STATE.with_suffix(".tmp")
        tmp.write_text(json.dumps(data, indent=2))
        tmp.replace(STATE)
        return result


def state_read():
    if STATE.exists():
        try:
            d = json.loads(STATE.read_text())
            d.setdefault("packets", {})
            d.setdefault("handles", {})
            return d
        except (OSError, ValueError):
            pass
    return {"packets": {}, "handles": {}}


def resolve(arg):
    """Accept a full OSR-id or a short handle; return the OSR-id or None."""
    if arg.startswith("OSR-"):
        return arg if arg in state_read()["packets"] else None
    return state_read()["handles"].get(arg)


# ---- OpenScience HTTP API --------------------------------------------------------
def api(method, path, body=None, timeout=30):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(OS_BASE + path, data=data, method=method,
                                 headers={"content-type": "application/json"})
    with urllib.request.urlopen(req, timeout=timeout) as r:
        raw = r.read().decode()
    return json.loads(raw) if raw else {}


def os_up():
    try:
        api("GET", "/session", timeout=8)
        return True
    except Exception:
        return False


# ---- Telegram (reuse the proven gate mechanism: command-type buttons) ------------
def send_tg(text, buttons=None, thread=None):
    if not TG_TARGET:
        log("NOTE no RDD_RESEARCH_TG_TARGET — message not sent")
        return False
    cmd = [OPENCLAW, "message", "send", "--channel", TG_CHAN,
           "--target", TG_TARGET, "--message", text]
    th = str(thread or TG_THREAD or "")
    if th:
        cmd += ["--thread-id", th]
    if buttons:
        blocks = [{"type": "buttons",
                   "buttons": [{"label": lab,
                                "action": {"type": "command", "command": val}}]}
                  for lab, val in buttons]
        cmd += ["--presentation", json.dumps({"blocks": blocks})]
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=45)
        if p.returncode != 0:
            log(f"SEND FAIL rc={p.returncode} {p.stderr[:200]}")
            return False
        return True
    except (subprocess.SubprocessError, OSError) as e:
        log(f"SEND ERROR {e}")
        return False


# ---- research prompt -------------------------------------------------------------
PROMPT = """You are a research analyst producing a RESEARCH PACKET for the EDGE engineering system{proj}.
You are research-only: gather evidence, compare, and recommend — do NOT write, run, or commit code yourself, and do NOT claim to have run experiments.

RESEARCH PROFILE: {profile}
{profile_guidance}

RESEARCH QUESTION:
{question}
{context}
Produce a concise, evidence-driven markdown packet with EXACTLY these sections:
## Summary
## Key Findings
## Sources
(list each with its URL)
## Counterevidence / Caveats
## Confidence
(state low, medium, or high, with one line of reasoning)
## Recommended EDGE action
(choose ONE: no-action | accept-as-knowledge | request-followup | create-architecture-proposal | create-edge-work-order — with a one-line why)

Cite real sources with URLs. Be explicit about uncertainty. Keep it tight.
Finish with a single final line, exactly this shape and nothing after it:
META: {{"confidence":"<low|medium|high>","recommended_action":"<one of the five above>"}}
"""


def extract_text(resp):
    parts = resp.get("parts") or resp.get("info", {}).get("parts") or []
    return "\n".join(p["text"] for p in parts
                     if p.get("type") == "text" and p.get("text")).strip()


ALLOWED_CONFIDENCE = {"low", "medium", "high"}
ALLOWED_ACTIONS = {
    "no-action",
    "accept-as-knowledge",
    "request-followup",
    "create-architecture-proposal",
    "create-edge-work-order",
}


def parse_meta(text):
    m = re.search(r'META:\s*(\{.*\})\s*$', text, re.MULTILINE)
    if m:
        try:
            j = json.loads(m.group(1))
            confidence = j.get("confidence", "low")
            action = j.get("recommended_action", "request-followup")
            if confidence not in ALLOWED_CONFIDENCE:
                confidence = "low"
            if action not in ALLOWED_ACTIONS:
                action = "request-followup"
            return confidence, action
        except ValueError:
            pass
    return "low", "request-followup"


# ---- flag parsing ----------------------------------------------------------------
def parse_flags(args):
    project = context = thread = ""
    profile = DEFAULT_PROFILE
    rest, i = [], 0
    while i < len(args):
        a = args[i]
        if a == "--project" and i + 1 < len(args):
            project = args[i + 1]; i += 2
        elif a == "--context" and i + 1 < len(args):
            context = args[i + 1]; i += 2
        elif a == "--thread" and i + 1 < len(args):
            thread = re.sub(r"\D", "", args[i + 1]); i += 2
        elif a == "--profile" and i + 1 < len(args):
            profile = re.sub(r"[^a-z0-9_-]", "", args[i + 1].lower()) or DEFAULT_PROFILE
            i += 2
        else:
            rest.append(a); i += 1
    if profile not in PROFILE_GUIDANCE:
        profile = DEFAULT_PROFILE
    return rest, project, context, thread, profile


# ---- verbs -----------------------------------------------------------------------
def _write_assignment(question, project="", context="", thread="", profile=DEFAULT_PROFILE):
    era = f"ERA-{stamp()}-{slug(question)}-{secrets.token_hex(2)}"
    body = [f"# Research Assignment: {question}", "",
            f"## Assignment ID\n{era}", "",
            f"## Requested By\noperator via EDGE (topic {thread or TG_THREAD or '-'})", "",
            f"## Project\n{project or '(none)'}", "",
            f"## Return Thread\n{thread or ''}", "",
            f"## Profile\n{profile}", "",
            f"## Research Question\n{question}", "",
            f"## Context\n{context or '(none)'}", "",
            "## Boundaries\nResearch only. No code, branches, PRs, opencode, deploys, or direct messaging.", "",
            f"## Created\n{iso()}", ""]
    (ASSIGN / f"{era}.md").write_text("\n".join(body))
    log(f"ASSIGN {era} project={project or '-'} thread={thread or '-'} profile={profile}")
    return era


def cmd_assign(args):
    rest, project, context, thread, profile = parse_flags(args)
    question = " ".join(rest).strip()
    if not question:
        print("usage: assign \"<question>\" [--project P] [--thread T] [--profile software] [--context \"<text>\"]", file=sys.stderr)
        return 2
    print(_write_assignment(question, project, context, thread, profile))
    return 0


def cmd_followup(args):
    rest, project, context, thread, profile = parse_flags(args)
    if len(rest) < 2:
        print("usage: followup <OSR-id|handle> \"<question>\" [--project P] [--thread T] [--profile software]", file=sys.stderr)
        return 2
    parent, q = rest[0], " ".join(rest[1:]).strip()
    ctx = (context + " " if context else "") + f"Follow-up to packet {parent}."
    print(_write_assignment(q, project, ctx, thread, profile))
    return 0


def cmd_dispatch(args):
    if not args:
        print("usage: dispatch <ERA-id>", file=sys.stderr); return 2
    era = args[0].removesuffix(".md")
    af = ASSIGN / f"{era}.md"
    if not af.exists():
        print(f"no such assignment: {era}", file=sys.stderr); return 2
    text = af.read_text()
    qm = re.search(r"## Research Question\n(.+?)\n\n", text, re.DOTALL)
    cm = re.search(r"## Context\n(.+?)\n\n", text, re.DOTALL)
    pm = re.search(r"## Project\n(.+?)\n", text)
    tm = re.search(r"## Return Thread\n(\d*)", text)
    profm = re.search(r"## Profile\n(.+?)\n", text)
    question = qm.group(1).strip() if qm else era
    context = cm.group(1).strip() if cm else ""
    project = pm.group(1).strip() if pm else ""
    project = "" if project == "(none)" else project
    rthread = tm.group(1).strip() if tm else ""
    profile = profm.group(1).strip() if profm else DEFAULT_PROFILE
    if profile not in PROFILE_GUIDANCE:
        profile = DEFAULT_PROFILE
    ctx = f"\nCONTEXT:\n{context}\n" if context and context != "(none)" else "\n"
    proj = f" (project: {project})" if project else ""

    if not os_up():
        send_tg(f"❌ Research dispatch failed for {era}: OpenScience server is down.", thread=rthread)
        log(f"DISPATCH {era} FAIL server down"); return 1

    t0 = time.time()
    try:
        ses = api("POST", "/session", {"title": era}, timeout=20)
        sid = ses.get("id")
        if not sid:
            raise RuntimeError(f"no session id: {ses}")
        payload = {"agent": AGENT,
                   "parts": [{"type": "text",
                              "text": PROMPT.format(question=question, context=ctx, proj=proj, profile=profile, profile_guidance=profile_guidance(profile))}]}
        if VARIANT:
            payload["variant"] = VARIANT
        resp = api("POST", f"/session/{sid}/message", payload, timeout=TIMEOUT)
    except Exception as e:
        send_tg(f"❌ Research dispatch failed for {era}: {str(e)[:200]}", thread=rthread)
        log(f"DISPATCH {era} ERROR {e}"); return 1

    answer = extract_text(resp)
    info = resp.get("info", {})
    model = info.get("modelID") or "?"
    err = info.get("error")
    if err or not answer:
        send_tg(f"❌ Research produced no usable output for {era}"
                f"{': ' + str(err)[:160] if err else ''}.", thread=rthread)
        log(f"DISPATCH {era} EMPTY err={err}"); return 1

    conf, act = parse_meta(answer)
    body = re.sub(r'\n*META:\s*\{.*\}\s*$', '', answer, flags=re.DOTALL).rstrip()
    osr = f"OSR-{stamp()}-{slug(question)}-{secrets.token_hex(2)}"
    handle = secrets.token_hex(3)
    title = question if len(question) <= 90 else question[:87] + "..."
    dur = int(time.time() - t0)

    variant_label = VARIANT or "default"
    md = [f"# Research Packet: {title}", "",
          f"- Packet: `{osr}`  |  Assignment: `{era}`  |  Project: {project or '(none)'}  |  Profile: {profile}",
          f"- Produced by: OpenScience ({model}, variant {variant_label}, {dur}s)  |  {iso()}",
          f"- Confidence: **{conf}**  |  Recommended EDGE action: **{act}**",
          "", "---", "", body, ""]
    (INCOM / f"{osr}.md").write_text("\n".join(md))
    (INCOM / f"{osr}.json").write_text(json.dumps({
        "packet_id": osr, "assignment_id": era, "title": title, "project": project,
        "profile": profile, "return_thread": rthread, "status": "candidate", "promotion_state": "candidate",
        "confidence": conf, "recommended_action": act,
        "requires_user_approval": True, "implementation_allowed": False,
        "created_by": "openscience", "consumed_by": "edge",
        "model": model, "variant": variant_label, "question": question, "handle": handle, "created_at": iso(),
    }, indent=2))

    def add(d):
        d["packets"][osr] = {"status": "candidate", "assignment": era, "title": title,
                             "project": project, "thread": rthread, "profile": profile,
                             "variant": variant_label,
                             "confidence": conf, "recommended_action": act,
                             "handle": handle, "created": iso()}
        d["handles"][handle] = osr
    _with_state(add)
    log(f"DISPATCH {era} -> {osr} project={project or '-'} thread={rthread or 'default'} "
        f"handle={handle} profile={profile} variant={variant_label} conf={conf} act={act} {dur}s")

    sm = re.search(r"## Summary\n(.+?)\n##", body, re.DOTALL)
    summary = (sm.group(1).strip() if sm else body)[:500]
    tag = f"[{project}] " if project else ""
    card = (f"🔬 {tag}Research packet ready: {title}\n"
            f"profile: {profile} · conf: {conf} · recommends: {act} · {model} · variant {variant_label} · {dur}s\n\n"
            f"{summary}\n\n`{osr}`")
    send_tg(card, thread=rthread,
            buttons=[("✅ Accept → KB", f"/research accept {handle}"),
                     ("❌ Reject", f"/research reject {handle}")])
    return 0


def cmd_accept(args):
    if not args:
        print("usage: accept <OSR-id|handle>", file=sys.stderr); return 2
    osr = resolve(args[0])
    if osr is None:
        print(f"unknown packet: {args[0]}", file=sys.stderr); return 4
    p = state_read()["packets"].get(osr, {})
    if p.get("status") != "candidate":
        print(f"{osr} already {p.get('status') or 'unknown'} — no action."); return 0
    src = INCOM / f"{osr}.md"
    if not src.exists():
        print(f"packet file missing: {src}", file=sys.stderr); return 4
    kbdir = KB / pslug(p.get("project"))
    kbdir.mkdir(parents=True, exist_ok=True)
    (kbdir / f"{osr}.md").write_text(src.read_text())        # knowledge → project KB
    src.replace(ARCH / f"{osr}.md")                          # clear the mailbox
    j = INCOM / f"{osr}.json"
    if j.exists():
        j.replace(ARCH / f"{osr}.json")
    _with_state(lambda d: d["packets"][osr].update(status="accepted", accepted_at=iso()))
    log(f"ACCEPT {osr} -> KB/{kbdir.name}")
    print(f"accepted {osr} → research KB (edge-research-kb/{kbdir.name}/). "
          f"Promote to a repo work order separately via EDGE if warranted.")
    return 0


def cmd_reject(args):
    if not args:
        print("usage: reject <OSR-id|handle>", file=sys.stderr); return 2
    osr = resolve(args[0])
    if osr is None:
        print(f"unknown packet: {args[0]}", file=sys.stderr); return 4
    st = state_read()["packets"].get(osr, {}).get("status")
    if st != "candidate":
        print(f"{osr} already {st or 'unknown'} — no action."); return 0
    for ext in (".md", ".json"):
        f = INCOM / f"{osr}{ext}"
        if f.exists():
            f.replace(ARCH / f"{osr}{ext}")
    _with_state(lambda d: d["packets"][osr].update(status="rejected", rejected_at=iso()))
    log(f"REJECT {osr}")
    print(f"rejected {osr} — archived, not added to the KB.")
    return 0


def cmd_list(_):
    s = state_read()["packets"]
    print("ASSIGNMENTS:")
    for f in sorted(ASSIGN.glob("ERA-*.md")):
        print(f"  {f.stem}")
    print("PACKETS (incoming, awaiting approval):")
    for f in sorted(INCOM.glob("OSR-*.md")):
        p = s.get(f.stem, {})
        print(f"  {f.stem}  project={p.get('project') or '-'} handle={p.get('handle','?')} "
              f"conf={p.get('confidence','?')} rec={p.get('recommended_action','?')}")
    print("RESOLVED:")
    for osr, p in s.items():
        if p.get("status") in ("accepted", "rejected"):
            print(f"  {osr}  [{p['status']}] project={p.get('project') or '-'}")
    return 0


def cmd_show(args):
    if not args:
        print("usage: show <OSR-id>", file=sys.stderr); return 2
    osr = resolve(args[0]) or args[0]
    for f in [INCOM / f"{osr}.md", ARCH / f"{osr}.md", *sorted(KB.rglob(f"{osr}.md"))]:
        if f.exists():
            print(f.read_text()); return 0
    print(f"packet not found: {args[0]}", file=sys.stderr); return 4


def cmd_status(_):
    from collections import Counter
    s = state_read()["packets"]
    c = Counter(p.get("status") for p in s.values())
    proj = Counter(p.get("project") or "-" for p in s.values())
    print(f"OpenScience: {'up' if os_up() else 'DOWN'} @ {OS_BASE}")
    print(f"packets: {dict(c)}  by-project: {dict(proj)}  total={len(s)}")
    return 0


def cmd_health(_):
    up = os_up()
    print(f"OpenScience {OS_BASE}: {'UP' if up else 'DOWN'}")
    return 0 if up else 1


VERBS = {"assign": cmd_assign, "followup": cmd_followup, "dispatch": cmd_dispatch,
         "list": cmd_list, "show": cmd_show, "accept": cmd_accept, "reject": cmd_reject,
         "status": cmd_status, "health": cmd_health}


def main(argv):
    if not argv or argv[0] not in VERBS:
        print("verbs: " + " | ".join(VERBS), file=sys.stderr)
        return 2
    return VERBS[argv[0]](argv[1:])


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
