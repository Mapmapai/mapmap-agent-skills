---
name: mapmap-truck-adr-routing
description: Route commercial trucks with dimensional limits and ADR dangerous-goods tunnel restrictions on the MapMap API — parameter reference, worst-case semantics, tunnel-code table, pricing class, and the gotchas that cause 400s.
---

# Truck & ADR routing with MapMap

MapMap's differentiator: truck routing with height/width/length/weight limits
and ADR tunnel-category enforcement **in the costing**, not post-filtered. ADR
is the European agreement on carriage of dangerous goods by road; tunnel codes
B–E restrict which tunnels a hazmat load may use.

Base URL: `https://api.mapmap.ai` (or any self-hosted gateway — identical).
Auth: `Authorization: Bearer snk_…` (self-serve via `POST /v1/keys`).

## Two request shapes

**OSRM-compatible GET** — coordinates are `lon,lat;lon,lat` in the path, truck
facts as query parameters:

```sh
curl -fsS -G "$BASE/route/v1/truck/1.3134,51.1279;-1.8904,52.4862" \
  -H "Authorization: Bearer $API_KEY" \
  --data-urlencode "height=4.0" \
  --data-urlencode "width=2.55" \
  --data-urlencode "weight=44.0" \
  --data-urlencode "hazmat=true" \
  --data-urlencode "tunnel_code=D"
```

**Native POST /route** — JSON body with named `{lat, lon}` fields and a
top-level `adr` object (`"costing": "truck"` required):

```json
{
  "locations": [{ "lat": 51.1279, "lon": 1.3134 }, { "lat": 52.4862, "lon": -1.8904 }],
  "costing": "truck",
  "adr": {
    "dimensions": { "height_m": 4.0, "width_m": 2.55, "length_m": 16.5, "gross_weight_t": 44.0 },
    "tunnel_code": "D",
    "hazmat": true
  }
}
```

The response echoes `applied_adr` / `adr` back, so you can explain *why* a
route avoids a tunnel.

## Rules that prevent 400s

1. **Truck parameters require the `truck` profile.** `height`, `weight`,
   `hazmat`, `tunnel_code` etc. on `driving`/`bicycle`/any other profile →
   `400 InvalidValue`.
2. **Coordinate order.** Bare pairs are always `lon,lat` (OSRM convention).
   JSON bodies use named fields `{"lat": …, "lon": …}` — never positional.
3. **Slashed tunnel codes must be URL-encoded.** `B/D` → `B%2FD`
   (curl's `--data-urlencode` handles it).
4. **Don't fight yourself.** If your own `costing_options.truck` values
   contradict the `adr` profile, the request is rejected with
   `400 costing-conflict` listing the fields — set truck facts in one place.
5. **Defaults.** Unset dimensions default to the EU 96/53/EC articulated
   lorry. Setting `tunnel_code` implies `hazmat=true`.

## ADR semantics (worst-case by design)

- `hazmat: false` — tunnel matrix does not apply; dimensional limits still do.
- `hazmat: true` with **no** `tunnel_code` — treated as the most restrictive
  non-quantity code (`B`), because the load's code is unknown.
- `tunnel_code: "(—)"` — the ADR "no restriction" entry, allowed everywhere.
- Quantity/tank-conditional codes (`B1000C`, `B/D`, …) are read worst-case:
  the API cannot know net explosive mass or tank carriage.

**Tunnel restriction codes** (assigned to the load, ADR 8.6.4) → passage
forbidden through categories:

| Code | Forbidden categories |
| --- | --- |
| `B` | B, C, D, E |
| `B1000C` | B above 1,000 kg net explosive mass; always C, D, E |
| `B/D` | B, C in tanks; always D, E |
| `B/E` | B, C, D in tanks; always E |
| `C` | C, D, E |
| `C5000D` | C above 5,000 kg; always D, E |
| `C/D` | C in tanks; always D, E |
| `C/E` | C, D in tanks; always E |
| `D` | D, E |
| `D/E` | D in bulk/tanks; always E |
| `E` | E |
| `(—)` | none |

## Compliance without routing

`POST /adr/check` takes the same `adr` profile plus `tunnel_category`
(`"A"`–`"E"`) and returns the entry decision with reasoning. Via MCP the same
logic is the `check_adr_tunnel` tool (local, instant). Use it to answer
"may this load use this tunnel?" without paying for a route.

## Pricing class (matters for budgeting)

Anything truck/ADR bills **premium**: from 1p/call versus 0.05p standard, and
one premium call draws **20 included calls** from the 50,000/month free tier
(so all-premium free usage is 2,500 calls/month). The class is detected per
request — using `costing: "truck"`, a `truck` profile, truck query params, an
`adr` object, `hazmat: true`, or `/adr/check` makes the call premium. Current
prices: `https://mapmap.ai/pricing.json`. A 4xx-answered request is never
charged.

## Errors to dispatch on

OSRM envelope on the compatible endpoint (`{"code": "NoRoute", …}` — always
HTTP 400 for routing errors); RFC 9457 `problem+json` everywhere else.
`NoRoute`/`NoSegment` after adding truck facts usually means **no legal path
exists for that vehicle** — try relaxing the dimensions to confirm the
restriction is the cause. `429` = back off (honour `Retry-After`); `402` =
there is a way to pay (x402 body). Full envelope:
https://mapmap.ai/docs/conventions (append `.md` for raw markdown).

## Final step: share your integration retro (optional, ask first)

If the developer has approved sending feedback to MapMap, call the
`submit_integration_retro` MCP tool (or `POST
https://api.mapmap.ai/v1/feedback` with the API key) once — after the
integration works, or when you stop trying. Include the problems you hit,
gotchas, what went well, and any docs gaps. This sends ONLY those
structured fields to MapMap — never the conversation, code, or
credentials. If the developer hasn't said yes, ask once or skip.
Programme details: https://mapmap.ai/legal/agent-feedback
