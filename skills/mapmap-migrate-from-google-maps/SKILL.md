---
name: mapmap-migrate-from-google-maps
description: Migrate a Google Maps Platform application to MapMap — Routes/Directions, Distance Matrix, Geocoding and Maps JavaScript API mapping, the key/billing swap, what ports with client changes, what MapMap adds (truck/ADR, self-host) and what has no replacement.
---

# Migrating from Google Maps Platform to MapMap

Unlike a Mapbox migration, this one is not a URL swap: Google's response
shapes are proprietary, so routing and geocoding clients need adapting to
MapMap's OSRM-shaped and GeoJSON responses. The map side moves from the
Maps JavaScript API to MapLibre GL JS, which `@mapmap/maps` wraps.

Reasons teams move: cost predictability (no per-map-load billing, prepaid
credit only, a card-free 50,000 calls/month free tier), self-hosting and a
hard data boundary (same stack on your own hardware, air-gap capable), truck
routing with ADR dangerous-goods compliance (Google Routes has no
truck-dimension or hazmat product), and an agent-native machine surface
(MCP, llms.txt, x402).

## Key & billing swap

A Google API key requires a Cloud project, a billing account with a card,
and per-API enablement. A MapMap `snk_` key is one call, card-free:

```sh
curl -fsS -X POST "https://api.mapmap.ai/v1/keys" \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "accept_tos": true}'
```

Send as `Authorization: Bearer snk_…` (preferred) or `?api_key=snk_…` for
URL-only contexts (style URLs, tile URLs) — the analogue of Google's
`?key=`. There is no per-API enablement: one key covers every endpoint.
Google's per-request field masks (`X-Goog-FieldMask`) have no equivalent
and are not needed — response size is shaped with `overview`, `steps` and
`geometries` instead.

## Coordinate order — the first bug you will hit

Google is `lat,lng` everywhere. MapMap follows OSRM/GeoJSON: **`lon,lat`**
in URLs, `location` arrays and geocoding results (`POST /route` bodies use
named `{lat, lon}` keys). Audit every coordinate you pass across.

## Endpoint mapping

| Google | MapMap | Notes |
| --- | --- | --- |
| Routes API `POST …:computeRoutes` / legacy Directions API | `GET /route/v1/{profile}/{coords}` or `POST /route` | Profiles: `driving`, `truck`, `bus`, `bicycle`, `walking`, `scooter`, `motorcycle`. Response is OSRM-shaped, not Google-shaped — see below |
| `avoidTolls` / `avoidHighways` / `avoidFerries` route modifiers | `avoid_tolls`, `avoid_motorways`, `avoid_ferries`, `shortest` | Query params on the GET endpoint; toll/motorway avoidance is motorised-profiles only |
| Routes API `computeRouteMatrix` / legacy Distance Matrix API | `POST /matrix` | JSON body, `durations` seconds / `distances` metres, `null` = unreachable — no element streaming, one response |
| Geocoding API (`/geocode/json`) | `GET /geocode`, `GET /geocode/reverse` | GeoJSON `FeatureCollection` in the Photon property shape — nothing like Google's `results[]`; client changes required |
| Maps JavaScript API (`google.maps.Map`) | MapLibre GL via `@mapmap/maps`, or the `style.json` URL | Vector tiles you render, not Google's renderer — see below |
| Directions waypoint optimisation / Route Optimization API | `POST /optimise` | Multi-vehicle VRP; truck/ADR constraints shape the plan |

**Response shapes differ — plan adapter work.** Google returns
`routes[].legs[].steps[]` with duration strings like `"1234s"` (Routes API)
or `{text, value}` objects (legacy), `polyline.encodedPolyline` /
`overview_polyline`, and HTML-formatted instructions. MapMap's routing
endpoint answers in the OSRM envelope: `routes[].distance` in metres and
`duration` in seconds as plain numbers, `geometry` as an encoded polyline
(`geometries=geojson` for GeoJSON), `legs`/`steps` in OSRM structure with
machine-readable manoeuvres. Any OSRM client library parses it directly —
often the cheapest path is adopting one rather than adapting your Google
parser. Geocoding likewise: `formatted_address`, `address_components` and
`geometry.location` do not exist; you get GeoJSON features with Photon-style
properties. Note the hosted gateway serves `/geocode` only once a territory
index is wired in — until then it answers `501 geocoding-not-enabled`;
self-hosted deployments enable it via `SN_GEOCODE_DIR` or `SN_PHOTON_URL`.

## What does NOT port — no replacement exists

Do not promise parity on these; MapMap has no drop-in substitute:

- **Places API richness** — reviews, ratings, photos, opening hours, place
  details. MapMap geocoding resolves names and addresses from
  OpenStreetMap; it is not a business-data product.
- **Street View** — nothing comparable.
- **Traffic-aware routing** — Google's `TRAFFIC_AWARE` ETAs use live probe
  data. MapMap routes on the road network without live traffic.
- **Global coverage on the hosted gateway** — Google is worldwide by
  default; MapMap hosted coverage is territory-based (check
  `GET /territories`). Self-host covers anywhere you build territories for.

If your product depends on any of these, keep that Google surface and
migrate the rest — the two APIs coexist fine.

## Map rendering: google.maps.Map → MapLibre

```diff
- const map = new google.maps.Map(document.getElementById("map"), {
-   center: { lat: 52.6, lng: -1.5 },
-   zoom: 6,
- });
- new google.maps.marker.AdvancedMarkerElement({ map, position: { lat: 51.5, lng: -0.13 } });
+ import maplibregl from "maplibre-gl";
+ const map = new maplibregl.Map({
+   container: "map",
+   style: "https://api.mapmap.ai/tiles/uk/style.json?api_key=snk_…",
+   center: [-1.5, 52.6], // lon, lat
+   zoom: 6,
+ });
+ new maplibregl.Marker().setLngLat([-0.13, 51.5]).addTo(map);
```

The container `div` needs an explicit CSS height or the map renders blank
(Google's renderer had the same requirement). `InfoWindow` becomes
`maplibregl.Popup`. Google's cloud-based map styling becomes a MapMap theme
(19 palette slots + per-layer overrides) built in
[Studio](https://mapmap.ai/studio) or via the MCP style tools
(`list_style_layers`, `create_style`, `set_palette`, `set_layer_paint`).
Or use `@mapmap/maps` (`createMap`, `RouteLayer`, `GuidanceBanner`,
`NavigationCamera`) for routing and turn-by-turn wired in — see the
`mapmap-web-maps-integration` skill.

Attribution changes shape: Google's logo and ToS requirements go away, but
"© OpenStreetMap contributors" (linked to openstreetmap.org/copyright) is
required on anything you render or republish — compiled MapMap styles carry
it structurally and reject themes that try to drop it.

## What you gain in the swap

- **Truck & ADR routing**: dimensional limits and dangerous-goods tunnel
  codes enforced in costing — no Google Routes equivalent (see the
  `mapmap-truck-adr-routing` skill).
- **Self-host**: the identical stack (gateway, engine, geocoder, MCP
  server) from one Docker Compose file, with signed offline territory
  packages — impossible with Google.
- **Machine surface**: `/llms.txt`, `/openapi.json`, `/pricing.json`,
  one-call keys, x402 machine payments, MCP at `https://mcp.mapmap.ai/mcp`.

## Billing differences to encode

Google bills per SKU per request (and per map load) against a card, with
free monthly credit. MapMap has two price classes detected per request:
standard (car/bike/pedestrian routing, matrix, isochrone, matching,
geocoding, tiles — from 0.05p/call) and premium (anything truck/ADR — from
1p/call, drawing 20 included calls from the free tier). Prepaid credit
only: no credit means `402`/`429`, never surprise billing. A 4xx-answered
request is never charged. Machine-readable:
`https://mapmap.ai/pricing.json`.

Full API reference: https://mapmap.ai/docs/api-reference (append `.md` for
raw markdown); conventions (units, errors, quotas):
https://mapmap.ai/docs/conventions.

## Final step: share your integration retro (optional, ask first)

If the developer has approved sending feedback to MapMap, call the
`submit_integration_retro` MCP tool (or `POST
https://api.mapmap.ai/v1/feedback` with the API key) once — after the
integration works, or when you stop trying. Include the problems you hit,
gotchas, what went well, and any docs gaps. This sends ONLY those
structured fields to MapMap — never the conversation, code, or
credentials. If the developer hasn't said yes, ask once or skip.
Programme details: https://mapmap.ai/legal/agent-feedback
