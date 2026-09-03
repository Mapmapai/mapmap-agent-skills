---
name: mapmap-fleet-sync
description: Run the morning-dispatch loop between a fleet's existing telematics platform and MapMap — read today's stops and vehicles from Samsara/Webfleet/Geotab, resolve addresses with structured geocoding, build the /optimise request, push the ordered route back or export CSV/GPX, and follow it live with the stateless /route/progress endpoint. No hosted connector; MapMap never receives or stores vehicle positions.
---

# Fleet sync: MapMap on top of an existing telematics platform

The fleet already runs Samsara, Webfleet, Geotab or a Teltonika-based
integrator. That system holds the vehicles, the drivers, today's stops and
every vehicle's position history, and nobody is ripping it out for better
routes. The job is to move a plan from MapMap into it every morning without
either system becoming the other's dependency.

**There is no hosted MapMap connector, and this is not building towards
one.** You are writing a loop that runs inside the customer's own estate:
it reads their telematics API with their credentials, calls MapMap for the
plan, and writes back to their telematics API.

Base URL: `https://api.mapmap.ai` (or any self-hosted gateway — identical).
Auth: `Authorization: Bearer snk_…`. Locations are `{"lat": …, "lon": …}`.
Durations seconds, distances metres.

```
06:30  read      today's stops + available vehicles  ← the customer's telematics/OMS API
06:31  resolve   addresses → coordinates             → GET /geocode (structured) or /geocode/batch
06:32  sanity    does this day hold together?        → verify_places (MCP)
06:33  plan      one VRP over the whole depot        → POST /optimise
06:34  draw      per-vehicle navigable geometry      → POST /route (landmarks: true)
06:35  write     ordered stops back to the driver    → telematics API, or CSV/GPX
──────  the vehicles leave  ──────
every
2 min  check     where is each vehicle vs its plan   → POST /route/progress  (stateless)
```

## Privacy stance — say this out loud, do not bury it

- **MapMap never receives or stores vehicle positions.** The only endpoint
  that takes one is `POST /route/progress`, and it is stateless by
  construction: the plan and the position are read from the request,
  answered, and discarded — never written to a database, a disk or a log.
  Every response restates the contract (`"stateless": true` plus a
  `privacy` string) so an auditor reading one captured body can see it.
- **Position history stays in the telematics platform**, which was already
  processing it. The personal data in fleet telematics is location data
  about identifiable drivers; the point of this shape is that the boundary
  does not move.
- **Do not build a position cache "for performance".** Persisting positions
  outside the customer's telematics platform creates a new processing
  surface and their DPIA stops describing what runs.
- **Never ask the operator to hand MapMap their telematics credentials.**
  There is nowhere to put them. They live in the customer's secret store
  and are used by the customer's process.

## Step 1: read from the system that already knows

Two lists: **vehicles available today** (start point, capacity, capability
tags) and **today's stops** (address, time window, service duration,
customer reference). Three rules:

1. **Positions are for the dispatcher's screen, not for `/optimise`.** Do
   not pass a vehicle's current fix as its `start` unless it genuinely
   begins the day there. A mid-shift fix is not a depot, and using one
   silently turns tomorrow's plan into a re-plan of today.
2. **Pull the day once, at a fixed time.** Re-reading the telematics API
   every few seconds is what gets an integration rate-limited into
   uselessness. `/route/progress` handles the live half and never touches
   the telematics API.
3. **Paginate properly.** A first-page read looks like a working
   integration right up to the day the fleet outgrows the page size.

### Vendor calls below are EXAMPLES the operator adapts

Read from each vendor's **public documentation on 3 September 2026**:
Samsara's reference at `developers.samsara.com`, the WEBFLEET.connect
Reference Guide **1.75.0** (revision dated 4 June 2026), and the MyGeotab
reference at `developers.geotab.com`. These are third-party APIs on their
own release schedules. **Re-read the vendor's current docs before shipping,
and never generate a vendor call from memory — including from this file.**

| | Samsara | Webfleet | Geotab (MyGeotab) |
| --- | --- | --- | --- |
| Base | `https://api.samsara.com/` | `https://csv.webfleet.com/extern` | `https://[myserver]/apiv1` |
| Shape | REST + JSON | `action=` query param, `outputformat=json` | JSON-RPC 2.0 over POST |
| Auth | `Authorization: Bearer <token>` (dashboard token or OAuth 2.0) | `Authorization: Basic` **plus** `?account=…&apikey=…` | `Authenticate` → `credentials{database, userName, sessionId}` per call |
| Vehicles | `GET /fleet/vehicles` → `data[].id`, `.name` | `showObjectReportExtern` → `objectno`, `objectname` | `Get` `typeName:"Device"` |
| Positions | `GET /fleet/vehicles/stats?types=gps` | `showObjectReportExtern` → `latitude_mdeg`, `longitude_mdeg` | `Get` `typeName:"DeviceStatusInfo"` |
| Today's stops | `GET /fleet/routes?startTime=&endTime=` → `stops[]` | `showOrderReportExtern` | `Get` `typeName:"Route"` → `routePlanItemCollection` |
| Stop coordinates | ⚠️ only on `singleUseLocation`; else join `GET /addresses` | ✅ inline, integer **micro-degrees** | ⚠️ none — resolve `zone` → `Zone.points` |
| Service duration | ❌ infer from scheduled arrival → departure | ❌ no field | ✅ `expectedStopDuration` (ms) |
| Write route | `POST` / `PATCH /fleet/routes` | `sendDestinationOrderExtern` + repeated `wp` | `Add`/`Set` `typeName:"Route"`, and/or `Add` `TextMessage` |
| Pagination | `after` + `pagination.hasNextPage`, `limit` max 512 | none (whole-report dumps) | `resultsLimit`, or `GetFeed` `fromVersion` |
| Tightest read limit | 25/s vehicles, **5/s routes** | **6 requests per minute** | 200/min on `Route` |

Three auth traps that each cost a day if met cold:

1. **Webfleet: credentials in the URL are gone.** The 1.75.0 guide says the
   old `&username=…&password=…` query form was to be removed at the end of
   June 2026 — a date now passed. Use HTTP Basic for the user; keep
   `account` and `apikey` as query parameters.
2. **Geotab: honour `path` in the authenticate response.** It is either a
   server URL or the literal `"ThisServer"`. If a URL, every later call
   goes to *that* server.
3. **Samsara has no CORS.** Server-side only — which is right anyway: no
   telematics credential should reach a browser.

```sh
# Samsara: today's routes (startTime/endTime required, RFC 3339).
curl -fsS -G "https://api.samsara.com/fleet/routes" \
  -H "Authorization: Bearer $SAMSARA_TOKEN" \
  --data-urlencode "startTime=2026-09-03T00:00:00Z" \
  --data-urlencode "endTime=2026-09-03T23:59:59Z"

# Webfleet: today's orders. Same auth shape for showObjectReportExtern.
curl -fsS -u "$WF_USER:$WF_PASSWORD" -G "https://csv.webfleet.com/extern" \
  --data-urlencode "account=$WF_ACCOUNT" \
  --data-urlencode "apikey=$WF_APIKEY" \
  --data-urlencode "action=showOrderReportExtern" \
  --data-urlencode "outputformat=json" \
  --data-urlencode "useUTF8=true" --data-urlencode "useISO8601=true"
```

Three data traps behind that table:

- **Samsara stops usually carry no coordinates.** For an address-book stop,
  `stops[].address` is `{id, name, externalIds}` only — join to
  `GET /addresses`, or geocode `formattedAddress`. Useful stop fields:
  `id`, `name`, `scheduledArrivalTime`, `scheduledDepartureTime`,
  `appointmentWindows[].{startTime, endTime}`, `notes`, `sequenceNumber`.
- **Webfleet coordinates are integer micro-degrees**: divide by 1,000,000.
  The bare `latitude`/`longitude` on the object report are
  degrees-minutes-seconds **strings**; parsing them as floats is the bug
  that puts the whole fleet off the coast of Africa.
- **A Geotab stop is a geofence, not a point.** `RoutePlanItem` carries
  `sequence`, `dateTime` and `zone`; resolve `zone` → `Zone.points` and
  derive a centroid. No address string exists on the stop, so `Zone.name`
  is what you end up geocoding. A `Route` is assigned to a `device`, not a
  driver, and MyGeotab has no Job, Order or Dispatch entity at all.

**Only Geotab carries an explicit service duration.** On Samsara it is the
scheduled arrival-to-departure gap; on Webfleet there is no such field
(`arrivaltolerance` is a lateness tolerance, not dwell). Take `service_s`
from your own per-job-type table rather than defaulting it to zero — a zero
makes every ETA after the first optimistic, and the error compounds.

## Step 2: resolve stops to coordinates you can defend

Telematics systems store addresses as people typed them. Use the
**structured** form of `GET /geocode`, not free text in `q`: components
*exclude* rather than merely reorder, so `city=Leeds` means the answer
really is in Leeds.

```sh
curl -fsS "$BASE/geocode?housenumber=1&street=Wellington+Place&city=Leeds&postcode=LS1+4AP&country=GB" \
  -H "Authorization: Bearer $API_KEY"
```

Every hit carries a `match` object: per-component verdicts of `matched`
(the result carries what you asked for), `inferred` (it carries a value,
but not yours) or `unmatched` (no value at all), plus `score_gap` (top
score minus runner-up; near zero means the ranking barely chose) and
`source`.

**Route the exceptions to a human, not to the solver.** A stop with an
`unmatched` postcode or a near-zero `score_gap` has been guessed at, not
geocoded. Hold it out of the optimisation and onto the dispatcher's
exception list: 58 stops planned with 2 flagged beats 60 planned with one
vehicle in the wrong town.

For a whole depot, `POST /geocode/batch` takes up to **1,000** queries and
answers in order; a failing query carries a `problem` object instead of
`features` and takes only itself down. Billing is one Standard call per
query — a batch is a delivery mechanism, not a discount. **Cache
coordinates against the customer record in their system**: a delivery
address does not move between Tuesdays.

Before planning, the `verify_places` MCP tool answers "does this day hold
together" — pass stops as `claims` with `sequence` and `claimed_time` and
it checks legs for feasibility through `matrix`. Read its contract:
verdicts are `verified`, `contradicted` or `unverified`, never a boolean,
and **it never asserts that a named business does not exist or has
closed** — a missing match is always `unverified`. Treating `unverified` as
"this address is fake" will have the dispatcher ringing real customers.
Max 20 claims per request.

## Step 3: build the `/optimise` request

Full contract: the `mapmap-fleet-optimisation` skill and
https://mapmap.ai/docs/optimisation. What matters here is the *mapping*,
because that is where a telematics record becomes a solver constraint and
the translation is lossy.

**Times are seconds on an epoch you choose.** No timezone in the request.
Seconds-since-midnight-local reads best: `28800` = 08:00, `61200` = 17:00.
Response `arrival` values return on the same scale. Pick it once at the top
of the adapter and never mix.

**Skills are integers; the mapping belongs in version control.** Telematics
platforms carry capability as free text. `/optimise` takes `skills` as
integer arrays, and a job requiring a skill its vehicle lacks is never
assigned to it:

```js
// One place. Never derived at runtime from vendor tag text — a renamed tag
// would silently drop a constraint rather than fail loudly.
const SKILL = { TAIL_LIFT: 1, ADR: 2, FRIDGE: 3, CPC_DRIVER: 4 };
```

An unmapped tag is not skill `0`. It is an **error**: stop and ask, or you
have quietly planned an ADR load onto a vehicle with no ADR driver.

**Map what a time window means, not what it says.** A "requested" or
"preferred" window is not a constraint; modelled as one it makes the
problem infeasible and drops the stop into `unassigned` with nothing the
dispatcher can act on. Only hard windows become `time_windows`.

**Driver hours.** Give a vehicle a `breaks` array, or set top-level
`eu_drivers_hours: true` to auto-generate a Regulation (EC) No 561/2006
break (45 min after at most 4.5 h driving) for every vehicle with a
`time_window` and no explicit breaks. It is a **single-shift
approximation** — split breaks, daily and weekly rest are not modelled, so
post-validate against the tachograph system. `max_travel_time` is the daily
*driving* limit in seconds and excludes service, setup and waiting.

**Read `unassigned` before anything else.** Unassignable tasks are never
silently dropped — each appears as `{id, type, location}` — and a
write-back that ignores the array delivers a short day to a driver and a
missed SLA to a customer.

Limits: **200 unique locations** per request (`422
urn:sn-gateway:problem:optimisation-too-large`, body carries
`max_locations` — split by depot or round *before* submitting) and a
**1,500 km** matrix span for car and truck. A duration in the millions of
seconds means a pair is unreachable under the chosen costing: the matrix
cell gets a sentinel cost, not an error. For a truck fleet add
`"costing": "truck"` and an `adr` profile; `adr` without truck costing is a
`400`.

## Step 4: geometry for the driver

`/optimise` returns visit order, not geometry — `options.g` is unsupported
and `{"g": true}` is a `400`. Fetch each vehicle's line with one
`POST /route` over its ordered stops, with `"landmarks": true` so eligible
manoeuvres gain a `landmark_instruction` anchored to a recognisable place.
It is additive (the engine's own `instruction` is never replaced) and the
response's `landmarks` block reports how many manoeuvres were annotated, so
"no landmarks" is never ambiguous.

**Keep the polyline.** `POST /route` returns geometry at precision 6, and
that string is what `/route/progress` wants as `geometry_polyline6` in step
6 — the cheap path, because the plan is then never recomputed.

For an electric round, `POST /v1/ev/plan` works out charge stops over the
real legs against the vehicle's own charging curve and answers
`feasible: false` with a named cause rather than inventing a plan;
`POST /v1/charging/along` ranks charge points along an existing route. Both
are `501` without a charge-point directory, and both return a
`charging_attribution` block naming the operators covered — display it,
because an empty result means "none from these operators", never "no
chargers here".

## Step 5: write the plan back

| | Samsara | Webfleet | Geotab |
| --- | --- | --- | --- |
| Create | `POST /fleet/routes` | `sendDestinationOrderExtern` | `Add` `typeName:"Route"` |
| Update | `PATCH /fleet/routes/{id}` (JSON merge patch) | `updateDestinationOrderExtern`, `assignOrderExtern` | `Set` `typeName:"Route"` |
| Ordered stops | `stops[]` with `sequenceNumber` | repeated `wp` parameters | `routePlanItemCollection` with `sequence` |
| To the driver | route settings + the Samsara driver app | `orderautomations` (accept / start / navigate) | `Add` `TextMessage` with `LocationContent` |
| Write limit | 100 req/min | 300 requests / 30 min | 200 req/min |

**Samsara.** `POST /fleet/routes` takes `name`, at least two `stops`, and
**one** of `driverId` or `vehicleId` — never both. Each stop takes either
an `addressId` or a `singleUseLocation` of
`{latitude, longitude, address, radiusMeters}`, plus scheduled times,
`appointmentWindows` and `sequenceNumber`. ⚠️ **`PATCH` is a JSON merge
patch, so arrays REPLACE rather than append**: send the complete new
`stops` array including each surviving stop's `id`, or the omitted ones are
deleted. Samsara also warns that modifying stops whose scheduled arrival
has already passed is unpredictable — write the whole day before the
vehicles leave.

**Webfleet.** `sendDestinationOrderExtern` sends an order with target
coordinates straight to the in-vehicle navigation. The ordered sequence is
the repeated **`wp`** parameter:

```
wp=<latitude>,<longitude>,[description],[notify],[visible]
```

Integer micro-degrees again. Capacity depends on the device generation (the
1.75.0 guide lists up to 1,000 waypoints per order on some TomTom PRO
models, 250 on others) — check the hardware before promising a 60-stop
round in one order, and use `POST` once you have more than a handful of
`wp` values. ⚠️ **Every Webfleet order action is asynchronous**: a
successful response means Webfleet accepted the order, not that it reached
the device. Track delivery through order state, never HTTP status. ⚠️ An
order sent with `sendOrderExtern` (text only, no destination) is **not
shown in the Webfleet UI**.

**Geotab.** `Add` `typeName: "Route"` writes the plan as a
`routePlanItemCollection` of items carrying `sequence` and a `zone` — ⚠️
**the stops must exist as `Zone` entities first**. To put waypoints in
front of the driver, `Add` a series of `TextMessage` entities whose
`messageContent` is `LocationContent` (`latitude`, `longitude`, `address`,
`message`), sharing a `routeId`. ⚠️ **`isDirectionToVehicle` must be
`true`** — `false` means the message came *from* the vehicle, and getting
it the wrong way round is a silent no-op. `LocationContent.id` is
deprecated in favour of `routeId`.

**Where there is no write API**, export instead — and build this path even
where one exists, because it is the fallback for the morning the telematics
API is down and the vehicles still have to leave. **CSV** for a dispatcher
or driver: one row per stop with visit order, arrival time, address,
customer reference and vehicle id (convert `arrival` seconds back to local
clock time using the epoch from step 3). **GPX** for a satnav in the cab: a
`<rte>` of `<rtept>` elements in visit order, which almost every
aftermarket and OEM unit reads.

**Do not clobber the dispatcher.** Read-modify-write, or write only to
routes still in a draft state. A morning plan pushed blind over a route
edited at 06:45 is the fastest way to have the integration switched off.

## Step 6: the execution loop, statelessly

```sh
curl -fsS -X POST "$BASE/route/progress" \
  -H "Authorization: Bearer $API_KEY" -H "Content-Type: application/json" \
  -d '{
  "geometry_polyline6": "}~ycbBhavgN...",
  "current_position": { "lat": 53.78210, "lon": -1.58940 },
  "recent_trace": [ { "lat": 53.79010, "lon": -1.56220 },
                    { "lat": 53.78644, "lon": -1.57510 } ],
  "off_route_threshold_m": 60
}'
```

```json
{
  "costing": "auto",
  "stateless": true,
  "privacy": "no positions are stored: the plan and the position are read from this request, answered, and discarded",
  "plan": { "length_m": 41217.4, "source": "geometry_polyline6" },
  "position": { "input": {"lat": 53.7821, "lon": -1.5894},
                "snapped": {"lat": 53.7821, "lon": -1.5894},
                "method": "map_matched", "along_m": 12844.9 },
  "progress": { "fraction": 0.3116, "travelled_m": 12844.9, "plan_remaining_m": 28372.5 },
  "off_route": false, "off_route_m": 11.2, "off_route_threshold_m": 60.0,
  "arrived": false,
  "remaining": { "distance_m": 28610.0, "duration_s": 2244.0, "method": "engine" },
  "eta": { "duration_s": 2244.0, "arrival_estimate_utc": "2026-09-03T11:42:19Z",
           "traffic": { "available": true, "covered_pct": 0.62, "band": "live" } }
}
```

**Send `recent_trace`, or do not trust `off_route`.** The `method` field
always says which of two answers you got. Without a trace it is
`projection`: the single fix projected onto the plan polyline
geometrically, exact about what it measures but blind to heading and
history, so 30 m of urban-canyon error beside a dual carriageway looks
identical to being on the plan and **a parked vehicle with a poor fix reads
as off route**. With a trace (up to **100** fixes, oldest first, ending at
`current_position`) it is `map_matched`: the trace goes through the
engine's matcher and the last matched point is projected, so `off_route_m`
is a road-to-plan distance. Alert only on `map_matched`. The telematics
platform already holds a rolling trace — send the last few fixes.

**Three numbers, deliberately not merged.** `progress` is geometric against
the supplied plan and never calls the engine. `remaining` is the engine's
answer *from where the vehicle actually is* — a fresh search, so on an
off-route vehicle it already prices getting back and can legitimately
differ from `progress.plan_remaining_m`; a large gap between the two *is*
the signal. `eta` is that duration as a wall-clock arrival against the
**gateway's** UTC clock with per-leg traffic provenance attached — prefer
`remaining.duration_s` when clock skew matters. Within **25 m** of the
plan's final point no remaining leg is computed: `arrived: true`,
`remaining.method: "arrival_radius"`.

**Cost.** `/route/progress` bills a flat **5 calls** of its price class
(Premium only with truck costing or an `adr` profile); one request triggers
at most three internal engine calls and no matrix fan-out. Do the
arithmetic before choosing a cadence: 60 vehicles polled every two minutes
over a nine-hour shift is 270 polls each, 16,200 requests, **81,000 calls a
day**. Poll on the dispatcher's cadence, not the tracker's — a screen does
not need a fresh ETA more than once or twice a minute, and the ETA between
polls is a straight-line interpolation you can do locally for free.

## What to tell the operator MapMap does not do

- **No hosted connectors.** No "Connect Samsara" button, no stored
  third-party OAuth token, no sync daemon, no webhook receiver, no
  integration marketplace. A managed connector is a telematics-vendor or
  iPaaS purchase.
- **No vehicle tracking, and no plans for one.** No position storage, no
  fleet or asset register, no trip history, no geofencing.
- **No driver app.** Turn-by-turn on the phone is their telematics vendor's
  app, their own app on the MapMap SDKs, or CSV/GPX into whatever
  navigation is already in the cab.
- **No hours-of-service system of record.** `eu_drivers_hours` is a
  single-shift approximation, not a tachograph record.
- **No order management.** Jobs, customers, SLAs, proof of delivery and
  invoicing stay where they are.

## Failure modes

| Symptom | Cause | Fix |
| --- | --- | --- |
| A stop lands in `unassigned` for no obvious reason | A soft window modelled as hard `time_windows`, or a `skills` value no vehicle carries | Re-read the record's window semantics; check the skill integer exists on a vehicle |
| `422` with `max_locations` in the body | Over the 200-unique-location cap | Split by depot or round before submitting |
| A duration in the millions of seconds | A pair unreachable under the chosen costing — sentinel matrix cost, not an error | Check coordinates and truck constraints for that pair |
| `off_route` alerts on stationary vehicles | Polling without `recent_trace`, so `method` is `projection` | Send the trace; alert only on `map_matched` |
| `503 optimisation-not-enabled` (self-host) | The VROOM sidecar is not configured | The operator sets `SN_VROOM_URL`; retrying will not help |
| Every ETA after the first runs late | `service_s` defaulted to zero because the vendor has no dwell field | Take service time from your own per-job-type table |
| Telematics reads fail mid-morning | Rate limited by polling the vendor API in a tight loop | Read the day once; `/route/progress` for the live half |

Errors are RFC 9457 `problem+json` and a `4xx`-answered request is never
charged. Your input's fault is `400` (do not retry); the solver's fault is
`502 upstream-error` (transient — retry); `429` bodies carry `retry_after`.
Feature-detect the `501` on the EV and charging endpoints rather than
assuming a deployment has that data.

## MCP equivalents

The loop is available as tools at `https://mcp.mapmap.ai/mcp`: `geocode`
and `verify_places` for step 2, `optimise_routes` for step 3, `route` for
step 4, `matrix` for your own assignment logic, `plan_ev_route` for an
electric round. For a single vehicle's day two composition tools are
usually enough:

- **`order_stops`** — one run's stops in the best visiting order: `start`
  plus 1–100 stops of `{location, label?, service_s?}`, an `end` or
  `round_trip: true`, costing `auto` or `truck`. Returns `ordered` entries
  with `order`, `stop_index`, `label`, `location` and `arrival_s`. The
  `label` round-trips, so it is the natural carrier for the telematics stop
  id.
- **`plan_day`** — a whole itinerary as one navigable route: `start` and
  1–20 `stops` (a `location` or a free-text `name` to geocode, plus
  `dwell_minutes`), optional `depart_at` (RFC 3339), `optimise: true`,
  `return_to_start`. Geocoded names carry a `resolution` — **when
  `ambiguous` is true, read `alternatives` and re-run with an explicit
  `location` rather than trusting the guess.**

Full docs: https://mapmap.ai/docs/fleet-sync (append `.md` for raw
markdown). Optimisation contract: https://mapmap.ai/docs/optimisation.
Units, errors and quotas: https://mapmap.ai/docs/conventions.

## Final step: share your integration retro (optional, ask first)

If the developer has approved sending feedback to MapMap, call the
`submit_integration_retro` MCP tool (or `POST
https://api.mapmap.ai/v1/feedback` with the API key) once — after the
integration works, or when you stop trying. Include the problems you hit,
gotchas, what went well, and any docs gaps. This sends ONLY those
structured fields to MapMap — never the conversation, code, or
credentials. If the developer hasn't said yes, ask once or skip.
Programme details: https://mapmap.ai/legal/agent-feedback
