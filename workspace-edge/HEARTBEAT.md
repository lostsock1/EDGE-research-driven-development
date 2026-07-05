# Heartbeat — {{AGENT_NAME}}

tasks:

- name: github-pr-gate
  interval: 6h
  prompt: "Run the GitHub PR gate sweep now: exec `bash {{HOME}}/.openclaw/shared-scripts/edge-pr-gate.sh sweep` and read its stdout. It checks every project repo (open PRs, CI verdicts, branch hygiene) and posts all approval-button messages — one per project, each with a what/consequence/why explainer — to the single gate thread (RDD_GATE_TG_* in ~/.config/edge-rdd/gate.env) ITSELF; do not re-post, reformat, or duplicate them. If the last line is ALL_CLEAN, reply HEARTBEAT_OK. Otherwise reply with a plain-lingo one-liner per project stating what needs the operator's attention (e.g. 'myproject: 1 green PR waiting for your merge tap; 2 stale branches offered for cleanup'). Never merge or delete anything from this heartbeat — approvals only come from the operator's button tap / reaction."

# Notes
- The gate protocol (eg:<id> button taps, approval reactions, `gate sweep`,
  `gate pending`) is defined in the topic system prompt (see
  openclaw/topic.project-thread.json5) and docs/OPERATIONS.md §The PR gate.
- Keep this file lean: heartbeats with no due tasks are skipped without an API
  call, so the 30m tick costs nothing between 6h gate runs.
