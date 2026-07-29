---
name: mapmap-mcp-setup
description: Connect any MCP client (Claude Code, Claude Desktop, Cursor, Codex, VS Code, Windsurf, or code) to the MapMap navigation platform's MCP server — hosted endpoint, self-host configuration, tool reference, and error-handling patterns.
---

# MapMap MCP setup

MapMap's MCP server (`sn-mcp`) exposes thirty-two tools (the set grows fast —
it was eleven in June — so list them live with `tools/list` rather than
trusting any written count, including this one): routing, along-route search,
cheapest fuel on a route, day planning, reachability, elevation, nearby
places, forward and reverse geocoding, place verification, ADR dangerous-goods
compliance, travel matrices, multi-vehicle route optimisation, map correction,
integration feedback, map styling and ten no-network geometry helpers. Full
JSON Schemas and structured outputs, so a model can call it correctly first
try.

## The hosted endpoint (fastest path)

Streamable HTTP, no key needed to connect, fair use:

```
https://mcp.mapmap.ai/mcp
```

Most of the surface answers there today, including `route`, `matrix`,
`check_adr_tunnel`, `geocode`, `reverse_geocode`, `nearby_places`,
`elevation`, `verify_places`, `optimise_routes`, `list_style_layers` and
`get_style`. Two caveats that do not change: style **publishes**
(`create_style`, `set_palette`, `set_layer_paint`) are refused on the hosted
endpoint because publishing signs with a gateway key, and any tool whose
dataset a given deployment does not carry answers empty or with a clear tool
error rather than a guess — `cheapest_fuel_along_route` returns no stations on
a deployment with no fuel-price feed. Don't take this paragraph's word for it:
call the tool and read the result. Production traffic belongs on the REST API
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
| `reverse_geocode` | The inverse: coordinates to the nearest places, nearest first, with `distance_m` and POI display tags (opening hours, website, phone) where the index carries them |
| `nearby_places` | What is NEAR a point — by `category` (`cafe`, `fuel`, `charging_station`, `parking`, `pharmacy`, …), by `name` for a brand, or both to disambiguate. Use this, not `geocode`, for proximity questions: `geocode` ranks a brand's branches worldwide and only biases by proximity, so it will hand back one in another city over the one 100 m away. Needs a gateway |
| `matrix` | Many-to-many travel matrix: `durations_s[i][j]` seconds, `distances_m[i][j]` metres, `null` = unreachable |
| `optimise_routes` | Multi-vehicle VRP with truck/ADR constraints; fair-use cap 200 unique locations |
| `search_along_route` | Stops from the API key's own uploaded places dataset along a route, ranked by honest detour cost (real added driving time, engine-measured). Needs a gateway key with a places dataset |
| `cheapest_fuel_along_route` | Cheapest fuel on a route from the live open-data price feeds (UK Fuel Finder, FR prix-carburants, DE Tankerkoenig), each station carrying the engine-measured detour, a 24-hour staleness flag and the saving against the cheapest on-route baseline. Needs a gateway |
| `plan_day` | An itinerary (place names or coordinates, optional dwell times) composed into one navigable multi-stop route with per-stop ETAs; `optimise: true` reorders the stops |
| `reachable_area` | Isochrone rings as GeoJSON: where you can get to inside one or more time budgets, on foot, by bike or by car |
| `order_stops` | One vehicle's stops put in the best visiting order, with arrival offsets, total duration and distance |
| `elevation` | Terrain elevation for a list of points, or an along-route profile from an encoded polyline. `elevation_m` is null wherever the terrain tiles have no coverage, never a guess |
| `verify_places` | Checks whether places and itineraries a model mentioned are real, findable and physically possible. Three verdicts, never a boolean: `verified`, `contradicted`, `unverified`. Always pass a `locality` |
| `report_map_issue` | Queue a first-party map correction for review. Never an automatic OSM edit |
| `submit_integration_retro` | Consent-gated end-of-integration retro. Only call it if the developer has approved sending feedback, and at most once |
| `list_style_layers` | Palette slots, skeleton layer ids and source-layers a theme can restyle — local, no network |
| `get_style` | Fetch a hosted style's theme document and compiled style URL (public read) |
| `check_style_contrast` | WCAG 2.1 contrast audit of a style's palette, across both light and dark variants. Advisory: it never blocks a publish |
| `create_style` / `set_palette` / `set_layer_paint` | Create and restyle hosted maps — each publish is a new immutable version, metered |
| `geo_distance` / `geo_bearing` / `geo_destination` / `geo_point_in_polygon` / `geo_bbox` / `geo_centroid` / `geo_length` / `geo_area` / `geo_simplify` / `geo_nearest_point_on_line` | Ten pure-computation geometry helpers over the coordinates you supply: no network, no upstream to fail, instant. `geo_distance` is straight-line, **not** driving distance — use `route` or `matrix` for travel time and distance. `geo_simplify`'s `tolerance_deg` is in degrees, not metres |

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
| `VALHALLA_URL` | `route`, `matrix`, `optimise_routes`, `search_along_route`, `cheapest_fuel_along_route`, `plan_day`, `reachable_area`, `order_stops`, `elevation` |
| `VROOM_URL` | `optimise_routes`, `order_stops`, `plan_day` with `optimise` |
| `PHOTON_URL` | `geocode`, `reverse_geocode`, and the name lookups inside `search_along_route` and `plan_day` |
| `STUDIO_URL` | style tools (the gateway hosting the style API) |
| `STUDIO_API_KEY` | style publishes only (`snk_` key); reads work without it |
| `GATEWAY_URL` / `GATEWAY_API_KEY` | `search_along_route`, `nearby_places`, `cheapest_fuel_along_route`, `submit_integration_retro` (falls back to the `STUDIO_*` pair — same gateway) |
| `SN_MAP_ISSUES_DIR` | `report_map_issue` review queue |
| `SN_RETROS_DIR` | `submit_integration_retro` fallback queue when the gateway cannot take it |

The ten `geo_*` tools and `check_adr_tunnel`, `list_style_layers` and
`check_style_contrast` need no upstream at all: they compute locally and
cannot fail on a network.

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

## Final step: share your integration retro (optional, ask first)

If the developer has approved sending feedback to MapMap, call the
`submit_integration_retro` MCP tool (or `POST
https://api.mapmap.ai/v1/feedback` with the API key) once — after the
integration works, or when you stop trying. Include the problems you hit,
gotchas, what went well, and any docs gaps. This sends ONLY those
structured fields to MapMap — never the conversation, code, or
credentials. If the developer hasn't said yes, ask once or skip.
Programme details: https://mapmap.ai/legal/agent-feedback
