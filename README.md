# MapMap Agent Skills

[![Skills](https://img.shields.io/badge/skills-11-2563eb)](https://mapmap.ai/docs/skills)
[![MCP server](https://img.shields.io/badge/MCP-mcp.mapmap.ai-2563eb)](https://mapmap.ai/docs/mcp)
[![Licence: MIT](https://img.shields.io/badge/licence-MIT-green)](./LICENSE)

Knowledge modules that teach AI coding agents how to build with
[MapMap](https://mapmap.ai) — the self-hostable navigation platform for
fleets and AI agents.

Skills are the **how-to knowledge** layer. They complement the
[MapMap MCP server](https://mapmap.ai/docs/mcp), which gives agents **live
tools** (routing, ADR compliance, geocoding, matrix, optimisation and map
styling at `https://mcp.mapmap.ai/mcp`). Install both: the MCP server lets
your agent call MapMap; these skills teach it to build with MapMap correctly
on the first try.

## Install

```sh
# All skills
npx skills add Mapmapai/mapmap-agent-skills

# One skill
npx skills add Mapmapai/mapmap-agent-skills --skill mapmap-truck-adr-routing

# See what's available
npx skills add Mapmapai/mapmap-agent-skills --list
```

Works with Claude Code, Cursor, Codex, VS Code with Copilot and other agents
that read `SKILL.md` modules. Manual install for Claude Code:

```sh
git clone https://github.com/Mapmapai/mapmap-agent-skills.git
cd your-project
mkdir -p .claude && ln -s ../mapmap-agent-skills/skills .claude/skills
```

## Skills

| Skill | Teaches |
| --- | --- |
| `mapmap-mcp-setup` | Connecting any MCP client to MapMap — hosted endpoint, self-host, per-client config, tool reference |
| `mapmap-truck-adr-routing` | Truck routing with dimensional limits and ADR dangerous-goods tunnel codes — parameters, semantics, gotchas |
| `mapmap-web-maps-integration` | `@mapmap/maps` in web apps — maps, routing, turn-by-turn guidance, navigation camera, Studio themes |
| `mapmap-map-design` | Designing branded map styles — brand → 19-slot palette ("make maps like airbnb.com"), legibility rules, publishing immutable styles |
| `mapmap-fleet-optimisation` | Multi-vehicle VRP — vehicles, jobs, shipments, time windows, capacities, truck/ADR constraints in the matrix, the 200-location cap |
| `mapmap-fleet-sync` | The morning-dispatch loop against a telematics platform you already run — read today's stops and vehicles, geocode and sanity-check, optimise, write the ordered route back or export it, then follow it live with the stateless progress endpoint |
| `mapmap-offline-territories` | Offline maps — signed territory packages, verifying-key pinning, differential OTA updates, the download allowance |
| `mapmap-migrate-from-mapbox` | Moving a Mapbox GL / Directions API app to MapMap — endpoint mapping, tokens to keys, style migration |
| `mapmap-migrate-from-google-maps` | Moving a Google Maps Platform app to MapMap — Routes/Matrix/Geocoding mapping, what ports and what has no replacement |
| `mapmap-x402-payments` | How agents pay per call — 402 vs 429 dispatch, prepaid credit, inline x402 where configured, refund and polling rules |
| `mapmap-self-host-ops` | Running the whole stack yourself — Docker Compose distro, keys, territories, production notes |

## Claude Code plugin

This repository is also an installable Claude Code plugin (named `mapmap`)
and its own plugin marketplace:

```sh
claude plugin marketplace add Mapmapai/mapmap-agent-skills
claude plugin install mapmap@mapmap
```

Installing the plugin gives you:

- **All 11 skills**, namespaced as `/mapmap:<skill-name>`
  (e.g. `/mapmap:mapmap-truck-adr-routing`).
- **The hosted MapMap MCP server** (`https://mcp.mapmap.ai/mcp`) via the
  bundled `.mcp.json` — live routing, ADR, matrix, optimisation and map
  styling tools.
- **An opt-in retro reminder hook — disabled by default.** A small `Stop`
  hook that does nothing unless you set `MAPMAP_RETRO_HOOK=1`. When
  enabled, and only when a session mentions MapMap, it reminds the agent
  (once per session) to *offer* you an integration retro. It never submits
  anything and makes no network calls — see [`hooks/README.md`](./hooks/README.md).

## Feedback programme

Each skill ends with an **optional, ask-first** final step: if you approve,
your agent can send MapMap a structured integration retro — what it built,
problems hit, gotchas, wins, and docs gaps — via the
`submit_integration_retro` MCP tool or `POST
https://api.mapmap.ai/v1/feedback` (API-key auth, limited to 5 per key per
day). This sends **only those structured fields** — never your
conversation, code, or credentials — and your agent should ask you before
sending (or skip it). It exists so real integration friction reaches the
people who can fix it. Full programme details, fields, and retention:
[mapmap.ai/legal/agent-feedback](https://mapmap.ai/legal/agent-feedback).

## The machine surface

MapMap is built agent-first. Before scraping anything, an agent should read:

- `https://api.mapmap.ai/llms.txt` — orientation: endpoints, auth, pricing, MCP
- `https://mapmap.ai/pricing.json` — machine-readable prices
- `https://api.mapmap.ai/openapi.json` — the authoritative API contract
- Every docs page is served as raw markdown: append `.md` to the URL

Keys are self-serve (`POST /v1/keys`, one call, card-free) and payments are
machine-native (x402 on `402`). See [mapmap.ai/agents](https://mapmap.ai/agents).

## Licence

MIT. Map data referenced in examples derives from OpenStreetMap — anything
you render or republish must credit "© OpenStreetMap contributors".
