---
name: mapmap-migrate-from-mapbox
description: Migrate a Mapbox GL JS / Directions API application to MapMap — endpoint and token mapping, style migration to MapLibre, what ports unchanged, what MapMap adds (truck/ADR, self-host) and what it does not offer.
---

# Migrating from Mapbox to MapMap

MapMap's routing endpoint is OSRM-compatible and its guidance output is
Mapbox-shaped, so most Mapbox routing clients port with a URL and token swap.
The map side moves from Mapbox GL JS to MapLibre GL JS (the API-compatible
open-source fork), which `@mapmap/maps` wraps.

Reasons teams move: self-hosting (same stack on your own hardware, air-gap
capable), truck routing with ADR dangerous-goods compliance (Mapbox has no
ADR product), a free tier without a card (50,000 calls/month, commercial use
allowed), and an agent-native machine surface (MCP, llms.txt, x402).

## Token → key

Mapbox `pk.…` tokens become MapMap `snk_` keys, self-served in one call:

```sh
curl -fsS -X POST "https://api.mapmap.ai/v1/keys" \
  -H "Content-Type: application/json" \
  -d '{"email": "you@example.com", "accept_tos": true}'
```

Send as `Authorization: Bearer snk_…` (preferred) or `?api_key=snk_…` for
URL-only contexts (style URLs, tile URLs) — the analogue of Mapbox's
`?access_token=`.

## Endpoint mapping

| Mapbox | MapMap | Notes |
| --- | --- | --- |
| `GET /directions/v5/mapbox/{profile}/{coords}` | `GET /route/v1/{profile}/{coords}` | Same OSRM shape: `lon,lat;lon,lat`, `distance` metres, `duration` seconds, encoded polyline. Profiles: `driving`, `truck`, `bus`, `bicycle`, `walking`, `scooter`, `motorcycle` |
| `voice_instructions=true&banner_instructions=true` | same parameters | Output is Mapbox-shaped: `voiceInstructions` (incl. SSML) and `bannerInstructions` (incl. lane diagrams) — existing consumers work |
| `GET /directions-matrix/v1/…` | `POST /matrix` | JSON body, `durations` seconds / `distances` metres, `null` = unreachable |
| `GET /isochrone/v1/…` | `POST /isochrone` | GeoJSON contours |
| `GET /matching/v5/…` | `POST /trace_route`, `POST /trace_attributes` | Map matching |
| `GET /geocoding/v5/…` | `GET /geocode`, `GET /geocode/reverse` | Photon-backed; response shape differs — this is the one endpoint needing client changes |
| `GET /optimized-trips/v1/…` | `POST /optimise` | Multi-vehicle VRP; truck/ADR constraints shape the plan |
| Mapbox Styles API | `POST /styles`, `GET /styles/{id}.json` | Versioned, immutable publishes; theme documents instead of raw style edits |
| `mapbox://` tile URLs | `GET /tiles/{territory}/{z}/{x}/{y}.mvt` + `/tiles/{territory}/style.json` | Standard XYZ over HTTPS, TileJSON 3.0 |
| Static Images API (`GET /styles/v1/{user}/{style}/static/…`) | `GET`/`POST https://mapmap.ai/api/static-map` | Website-hosted (mapmap.ai, not api.mapmap.ai), no API key, rate-limited. Camera by `center`+`zoom`, `bbox`, or auto-fit to the overlay; `route=` encoded polyline (`precision=6` default, pass `precision=5` for `GET /route/v1` output), `geojson=` or a JSON POST body with simplestyle `stroke`/`fill` honoured, `markers=`. Capped: at most 20 shapes and 50 markers per image, GeoJSON up to 512 KB per POST body, `route=` polylines thinned beyond 4,000 points, images up to 1280×1280 px (append `@2x` for retina). Full parameters: https://mapmap.ai/docs/api-reference (Static map images section) |

What MapMap does **not** offer: Mapbox's global POI search stack, and
worldwide hosted tile coverage on day one. Hosted coverage is
territory-based (check `GET /territories`); self-host covers anywhere you
build.

## Map rendering: Mapbox GL JS → MapLibre

MapLibre GL JS is the **API-compatible** fork (same `Map`, `Marker`, `Popup`,
style-spec v8), but MapLibre 6 is ESM-only: no UMD build, no browser global, no
default export. Swap the packages, delete the token global, switch to a
namespace import, and add the worker setup if your bundler cannot rewrite the
worker URL:

```diff
- import mapboxgl from "mapbox-gl";
- mapboxgl.accessToken = "pk.…";
- const map = new mapboxgl.Map({ container: "map", style: "mapbox://styles/mapbox/streets-v12" });
+ import * as maplibregl from "maplibre-gl";
+
+ // Turbopack and any other bundler that cannot rewrite the worker URL.
+ maplibregl.setWorkerUrl("/vendor/maplibre/maplibre-gl-worker.mjs");
+
+ const map = new maplibregl.Map({
+   container: "map",
+   style: "https://api.mapmap.ai/tiles/uk/style.json?api_key=snk_…",
+ });
```

**Bundlers that cannot rewrite the worker URL (Turbopack among them) need
`setWorkerUrl`.** MapLibre 6 ships its worker as a separate ES module beside
its entry point, and where the bundler does not rewrite that URL the map shows
no tiles and logs nothing at all: no console error, no `error` event, no
failed request. Serve both files, `maplibre-gl-worker.mjs` and
`maplibre-gl-shared.mjs` (the worker imports the shared chunk, so serving the
worker alone fails the same silent way), and point MapLibre at the worker
before the first `new Map`. In a Next.js app:

```sh
mkdir -p public/vendor/maplibre
cp node_modules/maplibre-gl/dist/maplibre-gl-worker.mjs public/vendor/maplibre/
cp node_modules/maplibre-gl/dist/maplibre-gl-shared.mjs public/vendor/maplibre/
```

`setWorkerUrl` does not exist on MapLibre 5, so an app that supports both
majors must feature-detect it:
`(maplibregl as { setWorkerUrl?: (u: string) => void }).setWorkerUrl?.(url)`.
The SDK deliberately does not wrap it: the host owns the files it serves, and
a wrapper would be a silent no-op on 5.x. A page that loads MapLibre from a
real https URL (CDN plus import map) needs none of this.

Or use `@mapmap/maps` (`createMap`, `RouteLayer`, `GuidanceBanner`,
`NavigationCamera`) for routing and turn-by-turn wired in — see the
`mapmap-web-maps-integration` skill.

Custom Mapbox styles: MapLibre reads style-spec v8, but `mapbox://` source
URLs, Mapbox fonts and sprites must be repointed. The pragmatic path is
recreating the look as a MapMap theme (19 palette slots + per-layer
overrides) in [Studio](https://mapmap.ai/studio) — or let an agent do it via
the MCP style tools (`list_style_layers`, `create_style`, `set_palette`,
`set_layer_paint`).

## What you gain in the swap

- **Truck & ADR routing**: dimensional limits and dangerous-goods tunnel
  codes enforced in costing — parameters Mapbox Directions does not have
  (see the `mapmap-truck-adr-routing` skill).
- **Self-host**: the identical stack (gateway, engine, geocoder, MCP server)
  from one Docker Compose file, with signed offline territory packages.
- **Machine surface**: `/llms.txt`, `/openapi.json`, `/pricing.json`,
  one-call keys, x402 machine payments, MCP at `https://mcp.mapmap.ai/mcp`.

## Billing differences to encode

Two price classes detected per request: standard (car/bike/pedestrian
routing, matrix, isochrone, matching, geocoding — from 0.05p/call) and
premium (anything truck/ADR — from 1p/call, drawing 20 included calls from
the free tier). Prepaid credit only: no credit means `402`/`429`, never
surprise billing. A 4xx-answered request is never charged. Machine-readable:
`https://mapmap.ai/pricing.json`.

## Attribution

Mapbox required its logo + OSM credit; MapMap requires
"© OpenStreetMap contributors" (compiled styles carry it structurally).
Remove Mapbox wordmark assets during the migration, keep the OSM credit.

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
