---
name: mapmap-mcp-setup
description: Connect any MCP client (Claude Code, Claude Desktop, Cursor, Codex, VS Code, Windsurf, or code) to the MapMap navigation platform's MCP server — hosted endpoint, self-host configuration, tool reference, and error-handling patterns.
---

# MapMap MCP setup

MapMap's MCP server (`sn-mcp`) exposes eleven tools (the set grows — list
them live with `tools/list`): routing, along-route search, ADR dangerous-goods
compliance, geocoding, travel matrices, multi-vehicle route optimisation and
map styling. Full JSON Schemas and structured outputs — a model can call it
correctly first try.

## The hosted endpoint (fastest path)

Streamable HTTP, no key needed to connect, fair use:

```
https://mcp.mapmap.ai/mcp
```

Live today on the hosted endpoint: `route`, `matrix`, `check_adr_tunnel`,
`list_style_layers`, `get_style`. `geocode` and `optimise_routes` return tool
errors until their upstreams are enabled; style publishes are metered and may
be unavailable. Production traffic belongs on the REST API
(`https://api.mapmap.ai`) with an `snk_` key, or on a self-hosted server.

## Per-client configuration

**Claude Code**

```sh
claude mcp add --transport http mapmap https://mcp.mapmap.ai/mcp
```

**Claude Desktop** — `claude_desktop_config.json`:

```json
{ "mcpServers": { "mapmap": { "type": "http", "url": "https://mcp.mapmap.ai/mcp" } } }
```

**Cursor** — `.cursor/mcp.json` (project) or `~/.cursor/mcp.json` (global):

```json
{ "mcpServers": { "mapmap": { "url": "https://mcp.mapmap.ai/mcp" } } }
```

**Codex** — `~/.codex/config.toml`:

```toml
[mcp_servers.mapmap]
url = "https://mcp.mapmap.ai/mcp"
```

**VS Code (Copilot agent mode)** — `.vscode/mcp.json`:

```json
{ "servers": { "mapmap": { "type": "http", "url": "https://mcp.mapmap.ai/mcp" } } }
```

**Windsurf** — `~/.codeium/windsurf/mcp_config.json`:

```json
{ "mcpServers": { "mapmap": { "serverUrl": "https://mcp.mapmap.ai/mcp" } } }
```

**Claude API MCP connector** — pass in the request body:

```json
{ "mcp_servers": [ { "type": "url", "url": "https://mcp.mapmap.ai/mcp", "name": "mapmap" } ] }
```

## Tool reference

| Tool | What it does |
| --- | --- |
| `route` | Turn-by-turn route, costing `auto` or `truck`; truck profile `{height_m, width_m, length_m, gross_weight_t, hazmat, tunnel_code}` merges dimensional and ADR costing. Returns `{distance_m, duration_s, summary, maneuvers[], geometry_polyline6, applied_adr}` |
| `check_adr_tunnel` | Pure ADR 8.6.4 tunnel-entry decision — no network, answers instantly |
| `geocode` | Forward geocoding: `{query, limit?, focus?}` |
| `matrix` | Many-to-many travel matrix: `durations_s[i][j]` seconds, `distances_m[i][j]` metres, `null` = unreachable |
| `optimise_routes` | Multi-vehicle VRP with truck/ADR constraints; fair-use cap 200 unique locations |
| `search_along_route` | Stops from the API key's own uploaded places dataset along a route, ranked by honest detour cost (real added driving time, engine-measured). Needs a gateway key with a places dataset |
| `list_style_layers` | Palette slots, skeleton layer ids and source-layers a theme can restyle — local, no network |
| `get_style` | Fetch a hosted style's theme document and compiled style URL (public read) |
| `create_style` / `set_palette` / `set_layer_paint` | Create and restyle hosted maps — each publish is a new immutable version, metered |

Conventions across all tools: coordinates are named `{lat, lon}` objects
(never positional arrays), distances in metres, durations in seconds.

## Error handling for agents

- Upstream failures and invalid inputs come back as MCP **tool errors** with
  actionable messages — read the message and self-correct rather than retrying
  verbatim.
- An unconfigured tool names the exact environment variable the operator must
  set (e.g. `PHOTON_URL is not set`).
- Style publishes that fail validation return the accepted slot/layer names in
  the error, so correct and resubmit.

## Self-host configuration

The server is a thin front on a running MapMap deployment. One env var per
upstream; all optional at startup — a tool with a missing upstream errors
helpfully:

| Variable | Powers |
| --- | --- |
| `VALHALLA_URL` | `route`, `matrix`, `optimise_routes` |
| `VROOM_URL` | `optimise_routes` |
| `PHOTON_URL` | `geocode` |
| `STUDIO_URL` | style tools (the gateway hosting the style API) |
| `STUDIO_API_KEY` | style publishes only (`snk_` key); reads work without it |
| `GATEWAY_URL` / `GATEWAY_API_KEY` | `search_along_route` (falls back to the `STUDIO_*` pair — same gateway) |

Run from the self-host distro (`docker compose --profile mcp up -d`, default
port 8200, path `/mcp`) or build from source (`cargo build --release -p sn-mcp`).
Stdio for local clients: `sn-mcp --transport stdio` with the env vars set.

Security notes for self-host: the HTTP `/mcp` endpoint is **unauthenticated** —
run it inside your trust boundary or add auth at a reverse proxy. In
production pass `--allowed-host` (repeatable) to defend against DNS rebinding.

## Beyond MCP

Every MapMap deployment also serves `/llms.txt` (orientation) and
`/openapi.json` (the authoritative REST contract). Agents can self-serve an
API key with one call (`POST /v1/keys`) and pay per call via x402 on `402`
responses. Docs: https://mapmap.ai/docs/mcp (append `.md` for raw markdown).
