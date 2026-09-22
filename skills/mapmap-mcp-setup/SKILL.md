---
name: mapmap-mcp-setup
description: Connect any MCP client (Claude Code, Claude Desktop, Cursor, Codex, VS Code, Windsurf, or code) to the MapMap navigation platform's MCP server — hosted endpoint, self-host configuration, tool reference, and error-handling patterns.
---

# MapMap MCP setup

MapMap's MCP server (`sn-mcp`) exposes forty-seven tools (the set grows fast,
it was eleven in June, so list them live with `tools/list` rather than
trusting any written count, including this one): routing, along-route search,
cheapest fuel on a route, EV journey planning and charge points, overhead
clearance against survey data, GPS trace matching, day planning, errand chains
against a deadline, reachability, elevation, nearby places, directional
lookup ("what is that over there"), what a journey passes and the heritage it
goes by, the place-category vocabulary, forward and reverse geocoding, place
verification, ADR dangerous-goods compliance, travel matrices, multi-vehicle
route optimisation with stop clustering, mid-shift re-planning and an
asynchronous lane for oversized problems, quota reporting, map correction,
integration feedback, map styling, coordinate-system validation and ten
no-network geometry helpers. Full JSON Schemas and structured outputs, so
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
| `route` | Turn-by-turn route, costing `auto` or `truck`; truck profile `{height_m, width_m, length_m, gross_weight_t, hazmat, tunnel_code}` merges dimensional and ADR costing. Returns `{distance_m, duration_s, summary, maneuvers[], geometry_polyline6, applied_adr}` Set `scenic: true` (auto only) for a PEER OFFER beside the route rather than instead of it: `scenic.reason` is the plain sentence justifying it and a null one means nothing measured above the floor, which is an answer; `scenic.rejections[]` says why each candidate lost. The route itself is never swapped. Costs up to two extra metered route computations |
| `check_adr_tunnel` | Pure ADR 8.6.4 tunnel-entry decision — no network, answers instantly |
| `geocode` | Forward geocoding: `{query, limit?, focus?}` |
| `reverse_geocode` | The inverse: coordinates to the nearest places, nearest first, with `distance_m` and POI display tags (opening hours, website, phone) where the index carries them |
| `nearby_places` | What is NEAR a point — by `category` (`cafe`, `fuel`, `charging_station`, `parking`, `pharmacy`, …), by `name` for a brand, or both to disambiguate. Use this, not `geocode`, for proximity questions: `geocode` ranks a brand's branches worldwide and only biases by proximity, so it will hand back one in another city over the one 100 m away. Needs a gateway |
| `places_in_view` | What is over THERE: give a position AND a `bearing_deg` (clockwise from true north) and it returns the places in that cone, each with `distance_m`, its own bearing, a signed `angular_offset_deg` and a spoken `direction`. READ THE `visibility` BLOCK BEFORE SAYING ANYTHING: `clear` means nothing in the data is in the way, `occluded` names what is, and `unknown` means no check could run, so say you cannot tell rather than that it is visible. A non-zero `out_of_sector` means there ARE matching places nearby, just not in that direction. Use `nearby_places` instead when the question is about what is near rather than what is in a direction. Needs a gateway |
| `plan_errands` | A chain of errands ordered against a hard arrival time. Give `origin`, `destination`, `arrive_by` (RFC 3339 with an offset) and 1 to 5 `errands`, each either a `category` or a `place` the driver already knows. The server picks the order and the actual shops over engine-computed times: do not attempt the arithmetic yourself. `feasible: false` is an ANSWER, not an error to retry: it names the `blocking_errand`, says how late the chain would run, and returns the shorter chain that DOES fit with `dropped` naming what had to go. `hours` is `open_on_the_tag` or `unknown`, never "open". Always show `usage_note`. Needs a gateway |
| `route_observations` | What a journey PASSES, in sentences ready to read aloud with their position along the route: named rivers and canals it crosses, the road it runs on and for how far, settlements it goes through, protected landscapes it enters and how high the road climbs. None of this is in a route object, so pass `geometry_polyline6` from `route` and let this compute it. The silence budget is the design: `min_gap_m` is a floor and the gap widens on its own past `max_observations`, so a short list on a long route is correct. READ `coverage` BEFORE REPORTING AN EMPTY LIST: `tiles_read` of 0 means no data was read, which is not the same claim as quiet countryside. Never names a hill, never reads a junction number. 10 units. Needs a gateway |
| `heritage_narration` | Three to five short spoken lines an hour about the ground a route is on, each at the point it belongs. Every line was written from a public-domain plaque inscription and reviewed by a person, compiled into the gateway binary: nothing is generated while anybody is driving. Pass `duration_s` with the geometry or the budget falls back to a distance. Coverage is ONE corridor on purpose, so no lines is the ordinary answer: read the `census`, where everything in `beyond_reach` means the feature does not cover this journey and entries in `silenced_by_budget` mean it does and the budget is holding them back. No line claims anything is visible or names a side of the road. 1 unit. Needs a gateway |
| `matrix` | Many-to-many travel matrix: `durations_s[i][j]` seconds, `distances_m[i][j]` metres, `null` = unreachable |
| `optimise_routes` | Multi-vehicle VRP with truck/ADR constraints; fair-use cap 200 unique locations |
| `search_along_route` | Stops from the API key's own uploaded places dataset along a route, ranked by honest detour cost (real added driving time, engine-measured). Needs a gateway key with a places dataset |
| `cheapest_fuel_along_route` | Cheapest fuel on a route from the live open-data price feeds (UK Fuel Finder, FR prix-carburants, DE Tankerkoenig), each station carrying the engine-measured detour, a 24-hour staleness flag and the saving against the cheapest on-route baseline. `say` is ALWAYS present and is the whole answer as one short spoken line, safe to read to a driver verbatim and safe on an empty result, where it names the cause instead of implying there is no fuel on the road; a stale price's line states the day it was last seen and claims no saving. Needs a gateway |
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
| `cheapest_charging_along_route` | Charge points along a route, ranked most powerful first, each carrying its engine-measured detour; filter by `connectors`, `min_kw`, `available_only` and `max_detour_minutes`. Operator-published feeds only, so an empty result means "none from these operators within the detour budget", never "there are no chargers here". `say` is ALWAYS present and is the whole answer as one short spoken line with the coverage inside the claim rather than appended to it, so an empty result's line says the emptiness is about those operators and not about the road. Read `say`, and show the `coverage_note`. Needs a gateway |
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

## Worked examples

Two shapes agents get wrong most often. Both turn on reading a field that
is easy to skip.

### Directional lookup: "what is that over there"

`nearby_places` answers "what is near me". It cannot answer "what is that
building I am looking at", because it has no idea which way the user is
facing. `places_in_view` takes a bearing and answers the question actually
asked.

```json
{
  "name": "places_in_view",
  "arguments": {
    "lat": 51.5045, "lon": -0.0865,
    "bearing_deg": 95,
    "fov_deg": 45,
    "radius_m": 1200,
    "category": "building",
    "eye_height_m": 1.6
  }
}
```

```json
{
  "results": [
    { "name": "The Shard", "distance_m": 410, "bearing_deg": 98,
      "angular_offset_deg": 3,
      "direction": "directly ahead, about 400 metres",
      "visibility": { "verdict": "clear", "basis": "terrain-and-buildings",
                      "checks": { "terrain": "clear", "buildings": "clear" } } },
    { "name": "Guy's Tower", "distance_m": 780, "bearing_deg": 104,
      "angular_offset_deg": 9,
      "direction": "ahead and slightly to your right, about 800 metres",
      "visibility": { "verdict": "occluded", "basis": "terrain-and-buildings",
                      "obstruction": { "kind": "building", "distance_m": 300,
                                       "building_height_m": 95,
                                       "building_height_basis": "tagged" } } }
  ],
  "out_of_sector": 6,
  "coverage": "Visibility was checked against the elevation model and building footprints.",
  "caveat": "Visibility is modelled from maps, not observed."
}
```

**Read `visibility` before you say anything.** Say "that is The Shard,
about 400 metres ahead". Do NOT say Guy's Tower is in view: a 95 m
building stands in front of it. And if `verdict` is `unknown`, say you
cannot tell, never that it is visible. The `out_of_sector: 6` is worth
relaying too: there are six more buildings nearby, just not in that
direction, which is a different answer from "nothing nearby".

Follow it with `route_observations` on a journey rather than a standing
position: same instinct, whole route, with each sentence positioned at the
point it belongs.

### Errand chains: let the server say no

"Pick up a prescription, get petrol, and be at the school by quarter past
three" is `plan_errands`, not three calls and some arithmetic. Convert the
time to RFC 3339 with an offset yourself; resolve any named place with
`geocode` first and pass the coordinate, never an invented one.

```json
{
  "name": "plan_errands",
  "arguments": {
    "origin": { "lat": 51.4545, "lon": -2.5879 },
    "destination": { "lat": 51.4712, "lon": -2.6031 },
    "destination_name": "the school",
    "arrive_by": "2026-09-22T15:15:00+01:00",
    "errands": [
      { "category": "pharmacy", "dwell_minutes": 8 },
      { "category": "fuel", "dwell_minutes": 6 }
    ]
  }
}
```

```json
{
  "feasible": false,
  "blocking_errand": "pharmacy",
  "over_by_s": 540,
  "stops": [
    { "errand": "fuel", "name": "Esso Coronation Road",
      "arrive": "2026-09-22T14:51:00+01:00",
      "depart": "2026-09-22T14:57:00+01:00",
      "hours": "open_on_the_tag", "place_id": "gx:4471209" }
  ],
  "dropped": ["pharmacy"],
  "slack_s": 420,
  "usage_note": "Plan this before setting off or hand it to a passenger. Never at the wheel."
}
```

**`feasible: false` is the answer, not an error to retry.** Do not re-run
it with fewer errands hoping for a 200: the reduced chain that fits is
already in `stops`, and what had to go is in `dropped`. Tell the driver:
"Petrol fits and you will still be nine minutes early, but the pharmacy
would put you nine minutes late at the school." Name only shops the answer
returned, each of which carries its own `place_id`, and treat
`open_on_the_tag` as evidence rather than a promise: most places carry no
hours at all and come back `unknown`.

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
