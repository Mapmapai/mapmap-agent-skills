---
name: mapmap-self-host-ops
description: Run the MapMap stack on your own infrastructure — Docker Compose distro, first boot, admin API keys, compose profiles (geocoding, MCP), territory packages, trust anchor, and production hardening notes.
---

# Self-hosting MapMap

The whole platform runs from one Docker Compose file: gateway (API, keys,
metering), routing engine with the ADR costing extension, optional Photon
geocoder, optional VROOM optimisation solver, optional MCP server. Source
access is by request (hello@mapmap.ai) while the repository is private; the
checkout ships the `distro/` stack and full production guides.

## Requirements

- Docker Engine 24+ with Compose v2
- ~10 GB disk, 8 GB RAM for a UK-scale first tile build (serving needs less)
- Outbound internet on **first boot only**; air-gapped installs use pre-built
  signed territory packages instead

## First boot

```sh
cd distro
cp .env.example .env
# Admin token protects /admin/* — compose refuses to start without it
sed -i "s/^SN_ADMIN_TOKEN=$/SN_ADMIN_TOKEN=$(openssl rand -hex 32)/" .env
# Simplest first run: build tiles straight from any Geofabrik OSM extract
echo 'VALHALLA_TILE_URLS=https://download.geofabrik.de/europe/united-kingdom-latest.osm.pbf' >> .env

docker compose up -d --build
docker compose logs -f valhalla   # first boot builds tiles: ~30–60 min for the UK
```

**Expected, not broken:** while tiles build, `docker compose ps` shows the
gateway stuck in `Created` — it waits on the routing engine's healthcheck.
You're up when `curl -fsS http://localhost:8080/health` succeeds.

## Issue keys

Operator keys via the admin API (all three fields required):

```sh
source .env
curl -fsS -X POST http://localhost:8080/admin/keys \
  -H "Authorization: Bearer ${SN_ADMIN_TOKEN}" \
  -H "Content-Type: application/json" \
  -d '{"name": "fleet-ops-dev", "monthly_quota": 100000, "rate_per_min": 60}'
```

The `key` field is shown **once** — only its BLAKE3 hash is persisted. Keys,
quotas and usage live in the `gateway_data` sqlite volume: **back it up**.
Alternatively let users self-serve keys via `POST /v1/keys` (same flow as the
hosted gateway). A public unauthenticated demo lane exists behind
`SN_DEMO_RPM` (requests/min per IP, off by default; GET routing and geocoding
only, never metered).

## Optional services (compose profiles)

```sh
docker compose --profile geocoding up -d photon   # /geocode — seed photon_data first
docker compose --profile mcp up -d mcp            # agents at http://<host>:8200/mcp
```

Key environment switches on the gateway:

| Variable | Enables |
| --- | --- |
| `SN_VROOM_URL` | `POST /optimise` (multi-vehicle VRP); `503` without it |
| `SN_PHOTON_URL` | `/geocode`, `/geocode/reverse`; `501` without it |
| `SN_TILES_DIR` | hosted vector tiles (`<territory>.pmtiles` archives) |
| `SN_STYLES_DIR` | hosted style API (`POST /styles`) |
| `SN_MAP_ASSETS_DIR` | glyphs and sprites (`/fonts`, `/sprite`) |
| `SN_ROUTING_ENGINE` | `valhalla` (default), `graphhopper`, or `auto` (failover) |
| `SN_CORS_ORIGINS` | `*` for public APIs (keys are the auth), allowlist for private |
| `SN_TRUST_PROXY` | trust first X-Forwarded-For hop behind a reverse proxy |

## Production notes

- **TLS**: put a reverse proxy in front of port 8080 before exposing beyond
  localhost — API keys travel in the `Authorization` header. If the proxy
  sets `SN_TRUST_PROXY`, make it overwrite (not append) `X-Forwarded-For`
  with the real peer address, or signup rate limits can be spoofed.
- **Tiles**: prefer signed territory packages over the OSM bootstrap build —
  and clear `VALHALLA_TILE_URLS` from `.env` once you do, so a container
  recreate never triggers an accidental rebuild.
- **Trust anchor**: territory packages are ed25519-signed. Self-host
  operators generate their own key pair (`snfactory keygen`) and mobile apps
  pin the 64-hex verifying key at build time — never fetch it over the same
  channel as the packages it validates.
- **MCP security**: the HTTP `/mcp` endpoint is unauthenticated — keep it
  inside the trust boundary or gate it at the proxy; pass `--allowed-host`
  against DNS rebinding.
- **Back up** the `gateway_data` volume (keys, quotas, usage).
- MAU billing is typically disabled on self-host: `SN_PRICE_PER_MAU_PENCE=0`.

## Pointing clients at your deployment

Everything takes a base URL: the web SDK accepts `baseUrl` in map options,
curl examples export `BASE`, compiled styles can repoint `glyphs` to your
gateway's `/fonts` route. Your deployment serves its own `/openapi.json`
(authoritative contract) and `/llms.txt` — same envelope, same keys, same
error shapes as the hosted gateway.

## Procurement pack

For buyer's counsel and security teams the checkout ships: SLA template,
security overview, pre-answered vendor questionnaire, licence-compliance
story (permissive-only gate, ODbL handling), deployment checklist, and a
CycloneDX SBOM regenerated with every tagged release.

Docs: https://mapmap.ai/docs/self-host and /docs/territories (append `.md`
for raw markdown).
