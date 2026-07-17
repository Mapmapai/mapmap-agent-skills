---
name: mapmap-offline-territories
description: Ship offline maps with MapMap — signed territory packages, on-device routing data, differential OTA updates, verifying-key pinning in the mobile SDKs, and the download allowance.
---

# Offline territories & OTA updates

Offline navigation runs on **territory packages**: signed, per-territory
bundles of everything a device needs — routing tiles, base-map tiles and a
geocode index (offline search, including POIs) — built by the map factory
(`snfactory`) from OSM extracts and ADR restriction overlays. Render layers
include ocean and land at every zoom, and styling is a package layer of its
own, so a custom style ships and updates independently of routing data.

## Trust model — verify on device, never trust the transport

- Every package manifest is **ed25519-signed**; every layer is
  content-addressed with **BLAKE3** hashes inside the signed manifest.
- The update channel is dumb by design: nothing but static files, servable by
  any web server or CDN, mirrorable into an air gap with `rsync -aH`. No
  server-side logic participates in the trust model; the gateway hop adds
  auth, metering and HTTP niceties only.
- A hostile CDN or mirror cannot alter what a device accepts — but it can
  deny service or replay an *older signed* index. There is no freshness
  guarantee by default (rollback-by-republish is a deliberate operator
  feature); layer a signed index TTL where that matters.
- Precedents for the shape: The Update Framework and OSTree.

**The trust anchor is the 64-hex verifying key** (the public half of the
factory's ed25519 pair), pinned in the app **at build time** — a build config
field or bundled resource. Never fetch it at runtime over the same channel as
the packages it validates. Key rotation ships as an app update (new pinned
key), then a channel republished with the new key.

## Listing and downloading territories

Five endpoints serve the channel behind normal API-key auth
(`Authorization: Bearer` or `?api_key=`), identical on the hosted gateway
(`https://api.mapmap.ai`) and self-host:

| Endpoint | Returns | Cache |
|---|---|---|
| `GET /territories` | Signed channel index (`index.json`, exact signed bytes) | `max-age=60` |
| `GET /territories/index.sig` | Detached base64 ed25519 signature over the index | `max-age=60` |
| `GET /territories/{id}/{version}/manifest` | The version's signed manifest (exact bytes) | `max-age=3600` |
| `GET /territories/{id}/{version}/manifest.sig` | Detached manifest signature | `max-age=3600` |
| `GET /territories/{id}/{version}/layers/{addr}/{file}` | Content-addressed layer blob (tar + zstd) | `immutable`, 1 year |

`addr` is the first 16 lowercase hex characters of the layer's BLAKE3 hash,
taken from the signed manifest; `file` is the blob file name (e.g.
`valhalla.tar.zst`). The index lists territories with `id`, `display_name`,
`latest_version` and per-version `data_timestamp`, `manifest_path` and
`total_bytes` (installed size — wire blobs are zstd-compressed and smaller).
Index and manifests are served byte-exact so detached signatures verify over
the response body. Every response carries a strong BLAKE3 ETag
(`"b3-<hex>"`), and layer blobs support single-range `Range`/`If-Range`, so
interrupted multi-gigabyte downloads resume rather than restart.

Errors: `304` not modified (costs no allowance), `402` allowance exhausted
(below), `403` provisional key — downloads need a verified account, `404`
unknown territory/version/blob or no channel configured, `416` bad `Range`.

## The download allowance and its 402

Layer blobs are large (around a gigabyte each), so **layer downloads only**
are byte-metered against a monthly offline-download allowance — 2 GiB/month
default on the free tier; a plan or the SDK licence raises it. Metadata
(index, signatures, manifests) is never metered, nor are `304` or `416`
responses. When serving a blob would exceed the allowance the gateway refuses
**before streaming any bytes**, with plain `application/json` (not the
problem envelope, and not the machine-payable x402 challenge body):

```json
{
  "code": "download_allowance_exceeded",
  "allowance_mib": 2048,
  "used_mib": 2048,
  "message": "offline map download allowance exhausted; upgrade to a plan or the SDK licence for production downloads",
  "upgrade": "https://api.mapmap.ai/pricing"
}
```

## Differential OTA update flow

Layers are content-addressed, so versions sharing a layer share a blob —
unchanged tile trees cost no extra download. Devices poll the signed index on
their own schedule via `TerritoryManager` in the navigation core (Kotlin and
Swift over UniFFI). You supply a `LayerFetcher` — a callback
(`fetch(rel_path, expected_blake3, dest)`) backed by OkHttp, URLSession or a
file copy from a mirror; `expected_blake3` is advisory, the core re-verifies
everything itself.

```rust
// 1. Fetch the signed index: GET /territories and /territories/index.sig.
let update = manager.check_for_update("uk", &index_json, &index_sig, &fetcher)?;
// 2. None = channel agrees with the installed version.
if let Some(update) = update {
    println!("update to {}: ~{} bytes", update.version, update.download_bytes);
    manager.apply_update("uk", &update.manifest_json, &update.manifest_sig, &fetcher)?;
}
```

`check_for_update` verifies the index signature over the exact bytes, then
fetches and verifies the remote manifest and plans the differential download.
A channel version *older* than the installed one is still offered — a
rolled-back channel is an instruction to downgrade. `apply_update`
authenticates the manifest before acting on it, stages the new version
(unchanged layers hardlinked; changed layers fetched, unpacked and
BLAKE3-verified), runs full package verification on the staged directory,
then **atomically swaps** it in. A crash, hash mismatch or bad signature at
any point leaves the previous version installed and untouched.

## TerritoryStore in the mobile SDKs

Every install is **verify-then-promote**: a package that fails signature
verification leaves no trace on disk. The pinning call is the constructor.

Android (`ai.mapmap:core`, minSdk 26):

```kotlin
import ai.mapmap.territory.TerritoryStore

// 64-hex factory verifying key, baked in at build time (e.g. BuildConfig) —
// never fetched at runtime.
val store = TerritoryStore(
    rootDir = File(context.filesDir, "territories"),
    verifyingKeyHex = BuildConfig.MAPMAP_FACTORY_PUBKEY_HEX,
)
```

iOS (`MapMapKit`, iOS 16.4, Swift tools 5.9; optional `MapMapValhalla`
product adds the on-device routing engine):

```swift
import MapMapKit

let territoryDir = FileManager.default
    .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
    .appendingPathComponent("territories")

// 64-hex factory verifying key, pinned at build time.
let store = TerritoryStore(rootDir: territoryDir, verifyingKeyHex: mapMapFactoryPubkeyHex)
```

Pinning applies to the mobile SDKs only — the web SDK streams tiles from the
API rather than verifying packages in the browser. Licensing for the
on-device SDK is per vehicle per month for fleets, or metered per monthly
active user for apps (opaque `X-MapMap-User` header — see the SDKs doc).

## Where the verifying key comes from

- **Hosted customers** receive the factory verifying key with SDK early
  access.
- **Self-host operators** generate their own pair with `snfactory keygen`
  and pin their own public key — which is what makes a deployment yours.
  Build and publish with `snfactory build` → `snfactory publish
  --channel-dir` → `snfactory channel-verify`; point the gateway at the
  directory with `SN_CHANNEL_DIR`. The private signing key never leaves the
  factory host; the gateway and CDN hold no secrets.

Docs: https://mapmap.ai/docs/territories and /docs/sdks (append `.md` for
raw markdown).
