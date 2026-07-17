---
name: mapmap-fleet-optimisation
description: Solve multi-vehicle VRP problems on the MapMap API — vehicles, jobs and shipments with time windows, capacities and skills, truck/ADR constraints carried into the travel-time matrix, the 200-location fair-use cap, and the errors that break plans.
---

# Fleet optimisation with MapMap

`POST /optimise` (alias `/optimize`) solves multi-vehicle, multi-stop
problems: which vehicle visits which stops, in what order, within time
windows and capacities. The gateway never lets the solver do its own
routing — it computes the full travel-time/distance matrix through its own
engine (with your `costing`, `costing_options` and `adr` profile applied)
and hands the solver explicit matrices. Optimise with `costing: "truck"`
and an `adr` profile and the plan never assumes a leg a lorry cannot
legally drive — same constraints as `/route` and `/matrix`.

Base URL: `https://api.mapmap.ai` (or any self-hosted gateway — identical).
Auth: `Authorization: Bearer snk_…`. Locations on this endpoint are
`{ "lat": …, "lon": … }` objects with named keys — no coordinate-order
ambiguity. Durations are seconds, distances metres.

## Modelling the problem

**Vehicles** (required, ≥ 1): `id` (integer, echoed back), `start` and/or
`end` as `{lat, lon}` (at least one; no `end` means the route finishes at
its last stop), `capacity` (integer array, multidimensional), `skills`
(integer array — a task requiring a skill the vehicle lacks is never
assigned to it), `time_window` (`[start, end]` seconds), `breaks`,
`max_travel_time` (seconds of driving, excludes service/setup/waiting — a
daily driving limit maps here), `max_tasks`, and `costs`
(`{fixed, per_hour, per_task_hour, per_km}` for cost-optimal rather than
time-optimal plans).

**Jobs** — single stops: `id`, `location`, optional `service_s`,
`delivery`/`pickup` (integer arrays matching vehicle `capacity` length),
`skills`, `time_windows` (array of `[start, end]`).

**Shipments** — pickup+delivery pairs that must ride the same vehicle,
pickup first: `pickup` and `delivery` objects (each `id`, `location`,
optional `service_s`, `time_windows`), plus optional `amount` and `skills`.

At least one job **or** shipment is required.

**Times** are plain seconds on any consistent epoch **you** choose (e.g.
seconds since midnight: `28800` = 08:00). Response `arrival` values come
back on the same scale.

**Driver hours:** give a vehicle a `breaks` array (mandatory rests with no
location — `id`, `time_windows`, optional `service_s`, `max_load`,
`description`) or set top-level `eu_drivers_hours: true` to auto-generate a
Regulation (EC) No 561/2006 break (45 min after at most 4.5 h driving) for
every vehicle with a `time_window` but no explicit `breaks`. Override with
`{"driving_before_break_s": …, "break_duration_s": …}`. Single-shift
approximation only — post-validate for split breaks and daily/weekly rest.
Breaks appear as steps of `type: "break"`.

## Worked example

London depot, deliveries in Birmingham and Manchester, back to the depot,
artic carrying hazmat with ADR tunnel code C:

```sh
curl -fsS -X POST "$BASE/optimise" \
  -H "Authorization: Bearer $API_KEY" \
  -H "Content-Type: application/json" \
  -d '{
  "vehicles": [
    { "id": 1,
      "start": { "lat": 51.5074, "lon": -0.1278 },
      "end":   { "lat": 51.5074, "lon": -0.1278 },
      "capacity": [10], "time_window": [28800, 64800] }
  ],
  "jobs": [
    { "id": 10, "location": { "lat": 52.4862, "lon": -1.8904 },
      "service_s": 300, "delivery": [2] },
    { "id": 11, "location": { "lat": 53.4808, "lon": -2.2426 },
      "service_s": 300, "delivery": [3] }
  ],
  "costing": "truck",
  "adr": {
    "dimensions": { "height_m": 4.0, "width_m": 2.55,
                    "length_m": 16.5, "gross_weight_t": 40.0 },
    "tunnel_code": "C",
    "hazmat": true
  }
}'
```

Response (shape-complete):

```json
{
  "code": 0,
  "profile": "truck",
  "summary": { "cost": 26000, "routes": 1, "unassigned": 0,
               "duration": 26000, "service": 600, "waiting_time": 0,
               "distance": 655000 },
  "unassigned": [],
  "routes": [
    { "vehicle": 1, "cost": 26000, "duration": 26000, "distance": 655000,
      "service": 600, "waiting_time": 0,
      "steps": [
        { "type": "start", "arrival": 28800, "duration": 0,
          "service": 0, "waiting_time": 0, "load": [5],
          "location": { "lat": 51.5074, "lon": -0.1278 } },
        { "type": "job", "id": 10, "arrival": 35400, "duration": 6600,
          "service": 300, "waiting_time": 0, "load": [3],
          "location": { "lat": 52.4862, "lon": -1.8904 } },
        { "type": "job", "id": 11, "arrival": 41000, "duration": 11900,
          "service": 300, "waiting_time": 0, "load": [0],
          "location": { "lat": 53.4808, "lon": -2.2426 } },
        { "type": "end", "arrival": 55400, "duration": 26000,
          "service": 0, "waiting_time": 0, "load": [0],
          "location": { "lat": 51.5074, "lon": -0.1278 } }
      ] }
  ]
}
```

Reading it: `code` is always `0` on HTTP 200 (solver failures surface as
HTTP errors, never a non-zero code); `profile` echoes the matrix costing;
`cost` equals travel time in seconds with the gateway's matrices; step
`duration` is cumulative travel time; unassignable tasks are never silently
dropped — each appears in `unassigned` as `{id, type, location}`. If a
duration looks absurdly large (millions of seconds), a location pair is
unreachable under the chosen costing — the matrix cell gets a sentinel
cost, not an error; check coordinates and truck constraints.

## Rules that prevent errors

1. **`adr` requires `"costing": "truck"`** — otherwise `400`. The profile
   (`dimensions`, `tunnel_code`, `hazmat` — same shape as `POST /route`) is
   merged into `costing_options.truck`.
2. **No geometry from the solver.** `options.g` is not supported —
   `{"g": true}` is a `400`. Fetch each leg's line from `POST /route`.
3. **At least one job or shipment**, at least one vehicle, and every
   vehicle needs `start` and/or `end` — else `400 bad-request`.
4. **200 unique locations max** (fair-use cap) → `422
   urn:sn-gateway:problem:optimisation-too-large`, body carries
   `max_locations` and `locations`. Split the problem (or talk to sales for
   larger sustained problems).
5. **Retry logic:** your input's fault is `400` (don't retry), the solver's
   fault is `502 upstream-error` (transient — retry). `429` bodies carry
   `retry_after`. Errors are RFC 9457 `problem+json`; a 4xx-answered
   request is never charged.
6. **Self-host:** the solver is an optional vroom-express sidecar. Without
   `SN_VROOM_URL` set on the gateway, the endpoint returns `503
   urn:sn-gateway:problem:optimisation-not-enabled` — the operator must
   enable it; retrying won't help.

## Billing and MCP

One optimisation request bills a **flat 10 calls** of its class regardless
of problem size — Standard for `costing: "auto"` (the default), Premium
for truck/ADR — and the internal N×N matrix is not billed separately.

The same capability is the `optimise_routes` MCP tool, so an agent can plan
a fleet's day end to end: check compliance with `check_adr_tunnel`,
optimise the visits, then fetch geometries per leg via `POST /route`.
Full docs: https://mapmap.ai/docs/optimisation (append `.md` for raw
markdown).
