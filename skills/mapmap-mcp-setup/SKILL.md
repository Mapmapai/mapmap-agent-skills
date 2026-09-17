---
name: mapmap-mcp-setup
description: Connect any MCP client (Claude Code, Claude Desktop, Cursor, Codex, VS Code, Windsurf, or code) to the MapMap navigation platform's MCP server — hosted endpoint, self-host configuration, tool reference, and error-handling patterns.
---

# MapMap MCP setup

MapMap's MCP server (`sn-mcp`) exposes forty-three tools (the set grows fast —
it was eleven in June — so list them live with `tools/list` rather than
trusting any written count, including this one): routing, along-route search,
cheapest fuel on a route, EV journey planning and charge points, overhead
clearance against survey data, GPS trace matching, day planning, reachability,
elevation, nearby places and their category vocabulary, forward and reverse
geocoding, place verification, ADR dangerous-goods compliance, travel matrices,
multi-vehicle route optimisation with stop clustering, mid-shift re-planning
and an asynchronous lane for oversized problems, quota reporting, map
correction, integration feedback, map styling, coordinate-system validation and
ten no-network geometry helpers. Full JSON Schemas and structured outputs, so
a model can call it correctly first try.

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
| `validate_geodata` | Checks whether a dataset's DECLARED coordinate reference system actually describes its own coordinates, before you draw it. Catches the silent failures: swapped lat/lon axes, degrees labelled as metres, Web Mercator mislabelled with a UTM or national-grid code. Pass the declared CRS and a sample of raw coordinates as `{x, y}` in the dataset's OWN units — deliberately not `lon`/`lat`, because whether they are degrees is the question. Returns `consistent` / `suspect` / `impossible`, what is wrong in plain language, and where the numbers actually point read another way. A sanity check, never a reprojection. Local, no network, no quota |
| `plan_ev_route` | A whole electric-vehicle journey with its charge stops: consumption from a published road-load physics model over the route's own legs, and charge times integrated over the vehicle's charging curve rather than energy divided by peak power. `feasible: false` with a `reason` and the furthest reachable point is an ANSWER, not an error to retry. Always show the returned `coverage_note`. Needs a gateway |
| `cheapest_charging_along_route` | Charge points along a route, ranked most powerful first, each carrying its engine-measured detour; filter by `connectors`, `min_kw`, `available_only` and `max_detour_minutes`. Operator-published feeds only, so an empty result means "none from these operators within the detour budget", never "there are no chargers here": show the `coverage_note`. Needs a gateway |
| `check_clearance_on_route` | A vehicle's overhead clearance measured along a truck-costed route against surveyed point-cloud geometry: `pass`, `fail`, `indeterminate` or `no_verdict` with the limiting point, the measured headroom and its uncertainty bound. Measured geometry from a dated survey, never a posted or signed height, so `clearance_enforcement.route_certified` is always false and the caveat rides on every answer. Needs a gateway |
| `match_trace` | Snaps a recorded GPS trace (2 to 2,000 points, or a polyline6 string) onto the road network and says what it actually travelled over: roll-ups `by_road_class`, `by_admin` and `by_surface`, plus toll, bridge and tunnel totals. Pass the `costing` it was driven under, or a walk matched as `auto` snaps to the carriageway. Needs a gateway |
| `cluster` | Groups up to 5,000 stops into balanced geographic clusters so a day too large for one optimisation can be solved cluster by cluster, then `optimise_routes` per cluster. STRAIGHT-LINE distances, no road network consulted: right for deciding which stops belong together, wrong for deciding visiting order. Show the returned `basis`. Same `seed` gives the same clusters. Needs a gateway |
| `replan_routes` | Re-plans a fleet part-way through its shift. MapMap holds no dispatch state, so you send the original `optimise_routes` problem back in full plus `progress` and/or `changes`; completed stops are removed from the problem entirely rather than hinted at, so the solver cannot move them. Read the `replan` block: anything dropped or unresolved is named there. Needs a gateway |
| `submit_optimise_job` | The asynchronous lane for a problem too large to solve inside one request. `kind` is `optimise`, `replan` or `matrix` and `problem` takes exactly the synchronous tool's input. Ceilings are far higher: 2,000 unique locations against 200, 40,000 matrix elements against 10,000. Answers a job id, not a plan. Needs a gateway |
| `get_job` | Reads a job submitted with `submit_optimise_job`: `queued`, `running`, `succeeded` or `failed`, with the result inline once it finishes. Poll every few seconds while `terminal` is false. Polling is free: the gateway meters the submission, not the reads. Needs a gateway |
| `get_usage` | What your own key has spent, so you can decide mid-task whether to keep going: per-day and per-endpoint figures, month used against quota, and the prepaid balance. Counted in weighted quota UNITS, never a number of calls. Free to read, and only ever reports on the key that authenticates the call. Needs a gateway |
| `list_place_categories` | The canonical `category` tokens for `nearby_places` and `search_along_route`, each with its colloquial aliases and a one-line description. Read it before guessing: an off-list token matches nothing and returns empty rather than erroring. Cuisines, brands and names are not categories. Local, no network, no quota |
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
| `GATEWAY_URL` / `GATEWAY_API_KEY` | `search_along_route`, `nearby_places`, `cheapest_fuel_along_route`, `cheapest_charging_along_route`, `plan_ev_route`, `check_clearance_on_route`, `match_trace`, `cluster`, `replan_routes`, `submit_optimise_job`, `get_job`, `get_usage`, `submit_integration_retro` (falls back to the `STUDIO_*` pair — same gateway) |
| `SN_MAP_ISSUES_DIR` | `report_map_issue` review queue |
| `SN_RETROS_DIR` | `submit_integration_retro` fallback queue when the gateway cannot take it |

The ten `geo_*` tools and `check_adr_tunnel`, `list_place_categories`,
`list_style_layers`, `check_style_contrast` and `validate_geodata` need no
upstream at all:
they compute locally and cannot fail on a network.

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
