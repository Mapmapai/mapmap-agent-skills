# Retro reminder hook — opt-in, disabled by default

This directory ships one Claude Code `Stop` hook,
`scripts/retro-reminder.sh`. It is **inert unless you switch it on**: the
script's first action is to exit silently when `MAPMAP_RETRO_HOOK=1` is
not set in your environment.

## What it does (when enabled)

At the end of a turn, if the session transcript mentions MapMap, it emits
one reminder per session suggesting the agent **offer** you an integration
retro via the `submit_integration_retro` MCP tool.

## What it never does

- It never submits feedback and never makes any network call — it only
  prints a local reminder message.
- It never reads your transcript beyond a case-insensitive search for the
  word "mapmap".
- Submission itself only ever happens through the MCP tool, and the skills
  instruct the agent to get your explicit approval first (or ask once and
  skip).

## Enable

```sh
export MAPMAP_RETRO_HOOK=1
```

(Add it to your shell profile, or to the `env` block of your Claude Code
`settings.json`, to keep it on.)

## Disable

Unset the variable (or never set it) — that is the default state. To remove
the hook entirely, uninstall the plugin.

Programme details, retention, and the exact fields ever sent:
https://mapmap.ai/legal/agent-feedback
