# Canonical Schema

Every source is normalised into one canonical account record. This document
defines the schema and the field-level precedence rules used when two or more
sources disagree.

## Table: `accounts`

| Column | Type | Meaning |
|---|---|---|
| `account_key` | TEXT (PK) | Stable, opaque identity key (SHA-256 of the identity — see below). |
| `tenant` | TEXT | Tenant identifier (normalised; `tnt_apac` / `tnt_emea` / `tnt_amer`). |
| `name` | TEXT | Company/account name. |
| `email` | TEXT (nullable) | Contact email, normalised (trimmed, lower-cased). `NULL` when no source has one. |
| `created_at_utc` | TEXT | Account creation time, ISO-8601, UTC. |
| `revenue_minor` | INTEGER | Monthly revenue in **minor units** (cents), for `revenue_currency`. |
| `revenue_currency` | TEXT | ISO-4217 currency (`USD` / `EUR`). |
| `is_deleted` | INTEGER | `1` if deleted, else `0`. |
| `region` | TEXT | Canonical region (`apac` / `emea` / `amer`), derived from `tenant`. |
| `sources` | TEXT | JSON array of `"source:native_id"` provenance for auditability. |
| `conflicts` | TEXT (nullable) | JSON array of field disagreements surfaced for human review. |

## Units and conventions

* **Revenue** is stored in a single unit — the currency's **minor unit
  (cents)** — to avoid floating-point error. The unit is named by
  `revenue_currency`. Source A reports dollars (×100 → cents); B and C already
  report cents.
* **Dates** are stored as UTC ISO-8601. Source A stores only a date (no time),
  so its times are `00:00:00Z`; the resolver prefers the fuller timestamp from
  B/C.
* **Deleted flag** is boolean. A `Y`, B `archived`, C `status == "deleted"`.
* **Region** is derived from the tenant code, which is the only consistent
  geographic signal across sources (see `FINDINGS.md`).

## Identity — what makes two records the same account?

The identity key is **(tenant, normalised email)**:

1. If a record has an email, its identity is `(tenant, email)`.
2. If a record has **no email**, we fall back to `(tenant, name)`: if a record
   with that name and tenant already has an email, the email-less record joins
   that identity (and inherits the email).
3. If nothing matches, the record becomes its own identity
   `(tenant, source, native_id)` with `email = NULL`.

`account_key = SHA-256(identity string)`.

**Why tenant is part of the key:** email is *not* globally unique. 35 emails
are shared by two different tenants (a base account in one tenant and its
"(Regional)" counterpart in another — see `FINDINGS.md`). Keying on email
alone would merge those distinct accounts.

## Field-level precedence

When an account arrives from more than one source, fields are resolved with a
fixed trust order, most-authoritative first:

```
c (internal tool)  >  b (SaaS API)  >  a (legacy CRM)
```

| Field | Rule |
|---|---|
| `tenant`, `email` | Part of the identity — always agree within a group. |
| `name`, `created_at_utc`, `revenue_minor`, `revenue_currency`, `region` | Taken from the highest-precedence source that reports a value. |
| `is_deleted` | **OR**-ed across sources — an account deleted in *any* system is treated as deleted (never resurrected). |

Any disagreement (e.g. `c` says `EUR`, `a`/`b` say `USD`) is recorded in
`conflicts` and listed in the reconciliation report for a human to review.
In the supplied data the only real disagreements are 19 currency conflicts and
A's date-only precision (handled separately).
