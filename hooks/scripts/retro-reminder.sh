#!/usr/bin/env bash
# MapMap integration-retro reminder (Claude Code Stop hook).
#
# OPT-IN AND DISABLED BY DEFAULT: unless MAPMAP_RETRO_HOOK=1 is set in the
# environment, this script reads nothing, emits nothing, and exits 0.
#
# What it does when enabled: after a session turn ends, if the session
# transcript mentions MapMap, it emits ONE reminder (at most once per
# session) suggesting the agent OFFER the developer an integration retro
# via the `submit_integration_retro` MCP tool.
#
# What it never does: it NEVER submits feedback, NEVER makes any network
# call, and NEVER reads anything beyond a case-insensitive grep for
# "mapmap" in the local transcript. Submission only ever happens through
# the MCP tool, with the developer's explicit approval.
# Programme details: https://mapmap.ai/legal/agent-feedback

set -eu

# Hard gate: opt-in only.
if [ "${MAPMAP_RETRO_HOOK:-0}" != "1" ]; then
  exit 0
fi

input="$(cat)"

# Extract session_id and transcript_path from the hook's JSON stdin
# without external dependencies (no jq).
session_id="$(printf '%s' "$input" | sed -n 's/.*"session_id"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"
transcript_path="$(printf '%s' "$input" | sed -n 's/.*"transcript_path"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p')"

[ -n "$transcript_path" ] && [ -f "$transcript_path" ] || exit 0

# Cheap heuristic: does this session involve MapMap at all?
grep -qi 'mapmap' "$transcript_path" || exit 0

# Remind at most once per session.
marker_dir="${TMPDIR:-/tmp}/mapmap-retro-hook"
mkdir -p "$marker_dir"
marker="$marker_dir/${session_id:-unknown}"
[ -e "$marker" ] && exit 0
: > "$marker"

cat <<'JSON'
{
  "hookSpecificOutput": {
    "hookEventName": "Stop",
    "additionalContext": "MapMap retro reminder (from the mapmap plugin's opt-in hook; the developer enabled MAPMAP_RETRO_HOOK=1): this session appears to involve MapMap. If the integration is done (working, or abandoned), consider OFFERING the developer an integration retro: with their explicit approval, call the submit_integration_retro MCP tool with the problems hit, gotchas, wins, and docs gaps. That sends ONLY those structured fields to MapMap — never the conversation, code, or credentials. If the developer declines or has not approved, do not submit. Programme: https://mapmap.ai/legal/agent-feedback"
  }
}
JSON
exit 0
