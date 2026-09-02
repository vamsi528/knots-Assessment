# Decisions

What I chose, what I rejected, and why. Includes the identity-resolution rule
and the AI-tool declaration.

## Connector abstraction (B1)

Each source is a `Connector` subclass with exactly two responsibilities:

* `extract()` — read the source's own format and return raw records plus
  `Issue`s. Handles pagination, retries and partial failure *locally*.
* `to_canonical(raw)` — map one raw record onto the canonical field set.

A registry (`@register("x")`) makes connectors self-discovering. Adding a
fourth source means writing one module that subclasses `Connector` and
implements those two methods — **no edits to the normaliser, resolver, writer
or CLI**.

**Rejected:** a single monolith `ingest()` function per source (not
extensible); a connector that returns already-merged rows (would leak
cross-source concerns into a per-source class); declarative YAML field-mapping
for the normaliser (nicer for trivial sources, but insufficient once a source
needs code — date parsing, unit conversion, retries — which all three do, so
the mapping would just be Python anyway).

## Identity resolution (B4)

**Key = `(tenant, normalised email)`, with a `(tenant, name)` fallback for
records that have no email.**

This rule exists to prevent one specific mistake: **merging on email without
tenant scoping.** I counted first, per tenant (as the brief advises), and
found 35 emails shared by *two different tenants* — for example
`ops159@soylent.example` is both "Soylent Networks 159" in `tnt_amer` and
"Soylent Networks 159 (Regional)" in `tnt_emea`. Those are different accounts
(different ids, different names, different tenants) that happen to share a
contact. A global email key — the obvious, "looks correct in the output"
choice — would silently merge them. Scoping the key by tenant keeps them
apart.

The `(tenant, name)` fallback exists for the 22 source-A rows with no email:
9 of them correspond to email-bearing records in B/C under the same
`(tenant, name)`, so without the fallback those 9 real accounts would be
double-counted. Name matching is safe here because names are unique per
tenant (the "(Regional)" suffix is never stripped).

**Rejected:** matching on native id (they differ per source by design);
matching on company name alone (works here but fragile — the "(Regional)"
suffix is the only thing keeping a base account and its regional twin apart,
so any fuzzy normalisation would merge them); a source-id fallback for
email-less rows *without* the name lookup (double-counts 9 accounts).

## Precedence

Trust order `c > b > a` (internal tool → SaaS API → legacy CRM), because C is
the system of record, B is the live product, and A is being retired.
`is_deleted` is OR-ed rather than taken from one source: a delete is a fact
that shouldn't be undone because another, stale system didn't get the memo.

## Idempotency (B5)

The whole resolved dataset is written in a single SQLite transaction that
deletes and re-inserts every row (`accounts.db`). Because `account_key` is a
deterministic hash of the identity, running the pipeline twice produces
byte-identical rows — verified by test. No upserts/migrations to reason about.

## Reliability (B6)

Source B's page 4 returns `error: upstream timeout` with `retry_after: 2`.
The B connector retries a failing page (honouring `retry_after`) up to a
configured maximum, then — rather than crashing — records an `error` issue
("120 records lost on page_04.json, upstream timeout") and keeps reading the
remaining pages. A connector that throws mid-run would take the whole
pipeline down; a connector that swallowed the error would silently lose data.
The report surfaces exactly what was lost and why.

## AI-tool declaration

I used an AI assistant (Claude/OpenCode) for this assessment. Specifically it
helped with: exploratory data analysis and counting, drafting the module
structure, and drafting documentation. All design decisions — the connector
abstraction, the `(tenant, email)` identity key, the precedence order, the
idempotency and failure-handling strategy — were made, and can be defended,
by me. The live fourth-connector test is done without assistance.
