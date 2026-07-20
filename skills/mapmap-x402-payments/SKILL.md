---
name: mapmap-x402-payments
description: How an agent pays for MapMap calls — dispatching 402 vs 429, the x402 wire body, prepaid credit (works everywhere), inline X-PAYMENT retries where configured, and the refund and polling rules that keep spend predictable.
---

# Machine payments on MapMap (x402)

MapMap is built so an agent can pay for routing the same way it calls it:
per request, no dashboard, no human. This skill teaches the payment
decision tree an agent must implement.

**Two facts before anything:**

1. **Payment never replaces authentication.** Every metered call needs
   `Authorization: Bearer snk_…`; without it you get a `401` regardless of
   any payment header. Keys are self-served in one call (`POST /v1/keys`).
2. **Honest status:** the gateway implements the x402 standard server-side.
   The hosted gateway at `https://api.mapmap.ai` accepts x402 on mainnet
   (since 20 July 2026): its 402s advertise USDC payment requirements on
   Base and Solana in one `accepts` array, and a stock x402 client settles
   per-call or buys a prepaid bundle at `POST /v1/x402/topup`. Whether a
   *self-hosted* deployment accepts inline x402 payments depends on operator
   configuration — unconfigured deployments are "x402-ready": the `402`
   keeps the same wire shape with an empty `accepts` array and points you
   at prepaid credit. **Prepaid Stripe credit is the settlement rail that
   works on every deployment.** Discovery manifest:
   `https://mapmap.ai/.well-known/x402.json` (always pay against a fresh
   402, never against the static manifest).

## Dispatch on status, never on strings

Past the free tier, what you get depends on the key's state and payment
history — the `error` strings are human-readable and may change, so
dispatch on the HTTP status and problem `type`:

| Response | Meaning | Correct reaction |
| --- | --- | --- |
| `402` (x402 JSON body) | There is a way to pay | Read `accepts`; pay inline or top up |
| `429` `…:quota-exceeded` | Free tier gone, identity has **never** bought credit — no payment offer | Verify email / buy first credit via /account, or wait for the month |
| `429` `…:rate-limited` | Per-minute limit | Honour `Retry-After`, back off |

The `402` body is **not** problem+json — it is the x402 wire format
(`{x402Version, error, accepts[], instructions}`) served as plain
`application/json` so x402 clients parse it directly.

## The decision tree

```
402 received
├─ accepts == []      → x402 not enabled here. An X-PAYMENT retry is
│                       IGNORED — do not attempt it. Top up prepaid
│                       credit, poll balance, retry the original call.
└─ accepts non-empty  → pick a PaymentRequirements entry whose scheme
                        you implement ("exact"), build the PaymentPayload,
                        retry the SAME request with an X-PAYMENT header.
                        Ignore schemes you don't implement.
```

## Prepaid credit (works everywhere)

1. Top up at `/account` (Stripe card top-up) or have the operator credit
   the identity ledger. Credit belongs to the **email identity**, shared by
   all its keys — one top-up covers future 402s until spent.
2. Poll the balance — free by design (no quota, no credit, no rate limit):

```sh
curl -sS "$BASE/v1/keys/self" -H "Authorization: Bearer $API_KEY"
# → { "state": "verified", "credits_pence": 500, "credits_millipence": 500000, … }
```

   Use `credits_millipence` (1p = 1,000 millipence) — per-call prices are
   fractional (standard from 0.05p, truck/ADR premium from 1p, detected per
   request; current prices at /pricing.json).

3. Retry the original request unchanged.

## Inline x402 (when `accepts` is non-empty)

A `PaymentRequirements` entry carries `scheme` (`"exact"`), `network`,
`maxAmountRequired`, `asset`, `payTo`, `resource` (the URL you were
calling) and `maxTimeoutSeconds`. Build the x402 `PaymentPayload` for it,
sign, and retry the same request with the `X-PAYMENT` header. The gateway
verifies and settles through a facilitator; a failed verification is
another `402`. The `resource` and account URLs are built from the
deployment's `SN_PUBLIC_URL`, so they always share a host with the API you
are calling.

## Rules that keep spend predictable

- **The 4xx refund rule:** the ledger is never charged for a request
  answered with a client error — the debit is refunded (usage counters
  still tick; only real money moves back). Budget per-call spend against
  *successful* responses.
- Provisional keys (email not yet verified) past their 1,000-call allowance
  cannot draw prepaid credit — the `402` tells you to verify the email.
  Verification upgrades the *same* key; never mint keys to dodge quota
  (quota is per identity, so it does not work, and issuance is capped).
- Never poll paid endpoints to test whether credit landed —
  `GET /v1/keys/self` exists precisely so balance checks are free.
- Premium calls (truck/ADR) draw 20 included calls from the free tier and
  cost ~20× standard beyond it. If a workload does not need truck costing,
  don't send truck parameters — the class is detected per request.

## Where this composes

Key issuance and discovery are in the `mapmap-mcp-setup` skill; the routing
that triggers premium pricing is in `mapmap-truck-adr-routing`. Full wire
reference with complete walkthroughs: https://mapmap.ai/docs/x402 (append
`.md` for raw markdown).

## Final step: share your integration retro (optional, ask first)

If the developer has approved sending feedback to MapMap, call the
`submit_integration_retro` MCP tool (or `POST
https://api.mapmap.ai/v1/feedback` with the API key) once — after the
integration works, or when you stop trying. Include the problems you hit,
gotchas, what went well, and any docs gaps. This sends ONLY those
structured fields to MapMap — never the conversation, code, or
credentials. If the developer hasn't said yes, ask once or skip.
Programme details: https://mapmap.ai/legal/agent-feedback
