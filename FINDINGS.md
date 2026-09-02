# Findings — the data problems

Everything I found by counting first, per tenant, before writing code. Each
entry says how many records are affected and what the pipeline does about it.

## Identity problems (would silently corrupt the merge)

### 1. The same email belongs to two different tenants — 35 emails
A base account and its "(Regional)" counterpart share one contact email but
live in *different tenants*, with different ids and names. Example:
`ops159@soylent.example` → "Soylent Networks 159" (`tnt_amer`) **and**
"Soylent Networks 159 (Regional)" (`tnt_emea`).

**Affects:** 35 emails (70 accounts). **What I did:** made `tenant` part of
the identity key. These are kept as separate accounts. *This is the mistake
the identity rule exists to prevent — merging on email alone would collapse
distinct accounts and look completely correct in the output.*

### 2. Source A rows with no contact email — 22 records
`contact_email` is blank on 22 rows. 9 of them match an email-bearing record
in B/C under the same `(tenant, name)` (e.g. "Tyrell Traders 145" in A has no
email; B and C carry `ops145@tyrell.example`); the other 13 have no
counterpart anywhere.

**Affects:** 22 rows. **What I did:** `(tenant, name)` fallback joins the 9
into their email-bearing account (adopting the email); the 13 are kept as
standalone accounts with `email = NULL`.

## Reliability problems

### 3. Source B page 4 is an upstream timeout — ~120 records
`page_04.json` contains `error: "upstream timeout"` and `retry_after: 2` with
no `data`. This is exactly how a real paginated API fails partway through.

**Affects:** 120 records (page 4 of 6 at 120/page). **What I did:** retried
with backoff (honouring `retry_after`), then surfaced an `error` issue
naming the page, the error and the record count, and continued with pages 5–6.
Nothing crashes; the loss is explicit, not silent.

## Unit / format disagreements

### 4. Revenue units disagree — dollars vs cents
Source A stores monthly revenue in **USD dollars**; B and C in **cents**.
**Affects:** all A rows (710). **What I did:** normalise everything to the
currency's minor unit (cents).

### 5. Currency code disagrees — 19 accounts
19 accounts are recorded as `EUR` in C but as `USD` in A/B, with byte-identical
amounts. The 25 C-only `EUR` records are consistent (no disagreement).
**Affects:** 19 accounts. **What I did:** source precedence (`c > b > a`)
resolves them to `EUR`; all 19 are flagged in `conflicts` and listed in the
reconciliation report for human review.

### 6. Deleted-flag vocabulary differs
`Y`/`N` (A), `archived` boolean (B), `status` text `trialing`/`active`/
`deleted` (C).
**Affects:** every row. **What I did:** normalise to a boolean; `is_deleted`
is OR-ed across sources.

### 7. Date formats differ; A has date-only precision
`DD/MM/YYYY` (A, no time), ISO-8601 (B), epoch seconds (C).
**Affects:** all rows; A's 710 rows carry no time-of-day.
**What I did:** normalise to UTC ISO-8601. A's midnight timestamps are treated
as lower precision — B/C's fuller timestamp wins, and this is *not* flagged as
a conflict (it's expected precision loss, not disagreement).

## Geography problems

### 8. The three sources record three different geography concepts
A records a `country`, B a `region`, C a browser `locale` — and none of them
correlate with the tenant: A's `country`→region disagrees with tenant on
480/710 rows, B's `region` on 408/583, C's `locale` on 418/645. They are not
reconcilable into one trustworthy region field.
**What I did:** derive the canonical `region` from the tenant code (the only
consistent signal) and document the source geography fields as unreliable.

### 9. Source A's country vocabulary is internally inconsistent
`country` mixes ISO codes (`DE`, `US`, `IN`), full names (`Germany`, `USA`,
`India`) and a locale code (`en-IN`) — 7 values for what should be 3 regions.
**Affects:** all 710 A rows. **What I did:** not used for the canonical region
(see #8); documented.

## Hygiene problems (handled, mostly cosmetic)

### 10. Source A contains 25 exact-duplicate rows
**What I did:** collapsed at resolution (25 duplicates removed).

### 11. Source C's "uuid" keys are not real UUIDs
`00000004-c0de` etc. are 13 characters, unique but truncated.
**What I did:** used only as provenance; the canonical key is our own hash.
