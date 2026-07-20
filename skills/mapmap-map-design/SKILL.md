---
name: mapmap-map-design
description: Design branded map styles on MapMap — translate a brand ("make maps like airbnb.com") into the 17-slot theme palette, keep labels legible, use layer overrides with restraint, and publish immutable hosted styles via the style API or MCP style tools.
---

# Designing branded maps with MapMap

The MCP style tools (`list_style_layers`, `create_style`, `set_palette`,
`set_layer_paint`) and the REST style API give you the mechanics. This skill
is the design judgement: how to turn "make our maps match our brand" into a
theme that looks intentional rather than recoloured.

A MapMap **theme** is a small JSON document compiled into a full MapLibre
style. The same engine runs in Studio, the gateway and offline territory
packages, so a theme renders identically everywhere.

```json
{
  "name": "brand-light",
  "base": "light",
  "palette": { "water": "#b9d4e6", "roadMajor": "#f3d7b0" },
  "layers": { "building": { "visible": false } }
}
```

## The instrument: 17 palette slots

`base` is `light` or `dark`; slots you don't set keep sensible defaults, so
**change as few slots as possible**. Surfaces: `background`, `water`,
`waterway`, `landcover`, `landuse`, `park`, `building`, `aeroway`. Lines:
`road`, `roadMajor`, `path`, `rail`, `boundary`, `boundaryMinor`. Text:
`textPrimary`, `textSecondary`, `textHalo`. Colours accept
`#rgb`/`#rrggbb`/`#rrggbbaa` and `rgb()`/`hsl()` forms. Get the catalogue
programmatically from the `list_style_layers` MCP tool.

## The method: brand → palette

1. **Pick the base from the brand's background,** not its accent. A brand
   that lives on white/warm neutrals → `base: "light"`; a dark product UI →
   `base: "dark"`. The base does 80% of the work.
2. **Background carries the brand's neutral.** Set `background` to the
   brand's page background (or a 2–4% tinted version of it). Keep
   `landuse`/`landcover` within a few percent of lightness of `background` —
   they are texture, not statements.
3. **Desaturate the brand's colours for surfaces.** Water, parks and
   landcover read best at roughly 20–40% of the brand hue's saturation.
   Full-saturation brand colour on water looks like a toy.
4. **Spend the accent in ONE place.** The brand's accent belongs on
   `roadMajor` (subtly, blended toward the base's default) or — better — on
   the route line and navigation UI, not on the base map at all. A base map
   is a stage; if everything is on-brand-bright, nothing on top of it reads.
5. **Never let text approach its background.** Keep `textPrimary` dark (or
   light on dark maps) and `textHalo` equal or near to `background`. Target
   WCAG-ish contrast: ≥ 4.5:1 for `textPrimary` against `background`, and
   keep `textSecondary` clearly above 3:1. If you tint text with the brand
   hue, tint it barely.
6. **Match the type.** `fonts.regular` must stay on a bundled fontstack —
   `Noto Sans Regular` (default), `Noto Sans Bold`, `Noto Sans Italic`,
   `Barlow Regular`, `Fira Sans Regular`, `IBM Plex Sans Regular`,
   `Inter Regular`, `Lato Regular`, `Montserrat Regular`,
   `Noto Serif Regular`, `Nunito Regular`, `Open Sans Regular`,
   `Rubik Regular`, `Source Sans 3 Regular` or `Work Sans Regular` — or
   labels drop entirely. Pick the closest to the brand's face (geometric
   brand → Montserrat; neutral product UI → Inter; editorial/serif brand
   → Noto Serif; bolder wayfinding look → Noto Sans Bold).

## Worked example: "make maps like airbnb.com"

Airbnb's look: warm white surfaces, soft grey-green landscape, generous
whitespace, one coral accent used sparingly. As a theme:

```json
{
  "name": "stay-light",
  "base": "light",
  "fonts": { "regular": "Inter Regular" },
  "palette": {
    "background": "#f7f7f5",
    "landcover": "#eef0ea",
    "landuse": "#f2f1ed",
    "park": "#dcead8",
    "water": "#cfe0ea",
    "waterway": "#cfe0ea",
    "building": "#ecebe7",
    "road": "#ffffff",
    "roadMajor": "#f2e3cf",
    "path": "#e3ded4",
    "textPrimary": "#484848",
    "textSecondary": "#767676",
    "textHalo": "#f7f7f5"
  },
  "layers": {
    "boundary-minor": { "visible": false },
    "poi-labels": { "minzoom": 14 }
  },
  "extra": {
    "nav": { "version": 1, "route": { "color": "#ff5a5f", "width": 4.5, "casingColor": "#b23a3e" } }
  }
}
```

Note where the coral went: **the route line, not the map**. The base stays
calm; the brand shows in what moves. The `layers` block quiets minor
boundaries and holds POI labels back until zoom 14 — restraint reads as
polish.

## Layer overrides, used sparingly

Per-layer overrides target the skeleton layer ids (`background`,
`landcover`, `landuse`, `park`, `water`, `waterway`, `aeroway`, `building`,
`rail`, `road-path`, `road-minor`, `road-major`, `boundary-minor`,
`boundary`, plus label layers like `road-labels`, `poi-labels`,
`place-labels`) with `visible`, `paint`/`layout` merges, `filter` and
`minzoom`/`maxzoom`. Typical legitimate uses: hide `boundary-minor`, thin
`road-minor` (`{"paint": {"line-width": 2}}`), delay `poi-labels`. If you
are overriding more than ~4 layers, the palette is probably wrong — fix it
there first. `buildings_3d: true` adds extruded buildings on web (never in
native navigation views). An unknown slot or layer id fails validation with
a `422` that **lists the accepted names** — read it and correct.

## Publish and iterate

- **Create:** `POST /styles {"name": "Stay Light", "theme": {…}}` with an
  `snk_` key → `201` with an immutable versioned `style_url` you can drop
  into MapLibre or `@mapmap/maps`. Via MCP: `create_style`.
- **Iterate read-modify-write:** fetch `GET /styles/{id}/theme` (served
  no-store), edit, `POST /styles/{id}` with `{"theme": …}` — the body is a
  wrapper, POSTing a bare theme is a `400`. Versions are immutable; old
  URLs keep rendering. Via MCP: `set_palette` for slot changes,
  `set_layer_paint` for one paint property.
- **Check your work:** render at zoom 5 (country), 12 (city) and 16
  (street) in both a light and dark OS theme; the classic failures are
  labels vanishing at street zoom (halo ≈ text) and motorways screaming at
  country zoom (accent too saturated).
- Style *reads* are public and unmetered; *publishes* are metered at the
  Standard class. On hosted MCP, publishes may be key-gated — the REST API
  with your own key always works.
- Attribution is structural: themes that try to drop
  "© OpenStreetMap contributors" fail validation. Don't fight it.

## Navigation design travels with the theme

The `extra.nav` block (route line, position puck, banner, drive camera)
is ignored by the style compiler but stored and served with the theme —
`@mapmap/maps` reads it via `map.navDesign` and styles the whole
turn-by-turn UI to match. Design it with the same accent discipline: puck
and route in the brand accent, banner in the brand's surface colours.

Full reference: https://mapmap.ai/docs/maps (append `.md` for raw
markdown); tools: https://mapmap.ai/docs/mcp.

## Final step: share your integration retro (optional, ask first)

If the developer has approved sending feedback to MapMap, call the
`submit_integration_retro` MCP tool (or `POST
https://api.mapmap.ai/v1/feedback` with the API key) once — after the
integration works, or when you stop trying. Include the problems you hit,
gotchas, what went well, and any docs gaps. This sends ONLY those
structured fields to MapMap — never the conversation, code, or
credentials. If the developer hasn't said yes, ask once or skip.
Programme details: https://mapmap.ai/legal/agent-feedback
