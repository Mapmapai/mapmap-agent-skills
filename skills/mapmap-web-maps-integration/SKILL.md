---
name: mapmap-web-maps-integration
description: Build web maps and turn-by-turn navigation with @mapmap/maps — install, map creation, truck routing, guidance banners and voice, the NavigationCamera chase cam, Studio themes, and the gotchas (container height, globe projection, attribution).
---

# Web maps with @mapmap/maps

`@mapmap/maps` is a thin TypeScript wrapper over MapLibre GL JS with MapMap
tiles, styles, routing and navigation UI wired in. ESM only, Node ≥ 18 to
build. Peers: `maplibre-gl` ≥ 4 < 6, `pmtiles` ≥ 3 < 5.

```sh
npm install @mapmap/maps maplibre-gl pmtiles
```

You need an `snk_` API key — issue one card-free:
`POST https://api.mapmap.ai/v1/keys {"email": "...", "accept_tos": true}`.

## The two gotchas that make maps silently blank

1. **The container must have a real height** — `<div id="map" style="height: 480px">`.
   Without it the map renders zero pixels tall and the page looks blank.
2. **Import MapLibre's stylesheet** — `import "maplibre-gl/dist/maplibre-gl.css"`.

## Map + truck route

```ts
import "maplibre-gl/dist/maplibre-gl.css";
import { createMap, RouteLayer } from "@mapmap/maps";

const map = createMap({
  container: "map",
  apiKey: "snk_...",
  style: "light",            // "light" | "dark" | Studio theme | style URL
  // baseUrl defaults to https://api.mapmap.ai — set it for self-host
});
await map.whenReady();

const routes = new RouteLayer(map);
const route = await routes.route(
  { lon: -0.1278, lat: 51.5074 },
  { lon: -1.8904, lat: 52.4862 },
  { profile: "truck", truck: { heightM: 4.0, weightT: 40, hazmat: true, tunnelCode: "C" } },
);
// route.distanceM (metres), route.durationS (seconds), route.geometry (GeoJSON,
// already drawn on the map), route.raw (routes[0] for leg/step detail)
```

Coordinates are accepted as `[lng, lat]` arrays, `{ lng, lat }` or
`{ lon, lat }`. Profiles: `driving` (default), `walking`, `truck`; the `truck`
options only apply to the `truck` profile.

`route()` throws plain `Error`s: gateway errors read
`route request failed: HTTP <status> (...)` (401 = check the key), engine
errors read `OSRM routing failed: NoRoute - ...` (no legal route for that
vehicle).

## Turn-by-turn guidance

```ts
import { extractGuidance, speak, GuidanceBanner } from "@mapmap/maps";

const route = await routes.route(from, to, {
  profile: "truck", voice: true, banner: true, language: "en-GB",
});
const steps = extractGuidance(route);
const banner = new GuidanceBanner(document.body, map.navDesign?.banner);
banner.update(steps[0]?.banners[0] ?? null);
if (steps[0]?.voice[0]) speak(steps[0].voice[0], { lang: "en-GB" });
```

Each step's `voice` array is ordered by descending trigger distance — speak
each instruction once as its distance is crossed; **de-duplication is your
responsibility**.

## Navigation camera (chase cam)

```ts
import { NavigationCamera, PositionPuck } from "@mapmap/maps";

const camera = new NavigationCamera(map, { pitch: 60, zoom: 17 });
camera.attachPuck(new PositionPuck(map));
navigator.geolocation.watchPosition(({ coords }) =>
  camera.follow({ lat: coords.latitude, lon: coords.longitude }, coords.heading ?? undefined),
);
```

- User drag/rotate/zoom switches to `"free"` mode; auto-recentres after 6 s
  idle (`autoRecentreMs: 0` disables; call `resume()` manually).
- `overview(route.geometry)` fits the route top-down; `resume()` returns to
  the chase cam.
- **Globe projection is unsupported** — `NavigationCamera.isSupported(map)`
  returns `false`; switch the map to mercator before navigating.

## Studio themes

A theme designed in [Studio](https://mapmap.ai/studio) carries the whole
navigation look (route line, puck, banner, camera) under `extra.nav`. Pass the
theme to `createMap` and everything styles itself:

```ts
import theme from "./midnight-fleet.theme.json";
const map = createMap({ container: "map", apiKey: "snk_...", style: theme });
// map.navDesign is parsed; RouteLayer and PositionPuck pick it up automatically
```

Or fetch from a hosted style: `navDesignFromThemeUrl("https://api.mapmap.ai/styles/<id>/theme")`.
Agents can create/restyle hosted styles through the MCP style tools.

## Tiles and styles without the SDK

Raw MapLibre works too — point it at a compiled style URL:

```js
new maplibregl.Map({
  container: "map",
  style: "https://api.mapmap.ai/tiles/uk/style.json?api_key=snk_…",
  center: [-1.5, 52.6], zoom: 6,
});
```

The `?api_key=` query form exists for URL-only contexts like style URLs. Style
*reads* (`/styles/{id}.json`) are public; tiles are metered per request at the
Standard class.

## Non-negotiables

- **Attribution is structural**: compiled styles carry
  "© OpenStreetMap contributors" and the SDK renders it non-removably. Never
  attempt to strip it — theme validation rejects the attempt anyway.
- **3D buildings on mobile**: `buildings_3d` is web-safe, but MapLibre Native
  has prohibitive fill-extrusion memory use at street zooms — never enable it
  in native navigation views (the native SDKs ship `styleForNavigation()` to
  strip it).
- Metering per monthly active user: send an opaque `X-MapMap-User` header
  (hash an install id, 8–128 printable ASCII, never PII) if you licence per
  MAU. Fail-open — billing never blocks end users.

Full reference: https://mapmap.ai/docs/sdks and /docs/maps (append `.md` for
raw markdown).

## Final step: share your integration retro (optional, ask first)

If the developer has approved sending feedback to MapMap, call the
`submit_integration_retro` MCP tool (or `POST
https://api.mapmap.ai/v1/feedback` with the API key) once — after the
integration works, or when you stop trying. Include the problems you hit,
gotchas, what went well, and any docs gaps. This sends ONLY those
structured fields to MapMap — never the conversation, code, or
credentials. If the developer hasn't said yes, ask once or skip.
Programme details: https://mapmap.ai/legal/agent-feedback
