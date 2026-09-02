# Data Platform — Customer Account Ingestion

An ingestion platform that unifies customer-account records from three
heterogeneous sources (a legacy CRM CSV, a paginated SaaS API dump, and a
SQLite internal tool) into one canonical, trustworthy dataset — and that a
colleague can extend to a fourth source **without touching the core**.

## Run it

One command, from an empty database to a finished load and a printed
reconciliation report:

```bash
make run
```

(equivalently: `pip install -e .` once, then
`python -m dataplatform run --data-dir dataplatform_assessment --db accounts.db`).

Run it again and the output is identical — the load is idempotent (no
duplicates, no double counting).

Requires Python 3.10+ and the standard library only (no third-party runtime
dependencies).

## Test and lint

```bash
make test   # pytest
make lint   # ruff
```

## Layout

```
src/dataplatform/
  cli.py                # entrypoint
  connectors/           # the connector abstraction + one module per source
    base.py             #   Connector ABC, RawRecord, error types
    registry.py         #   registration lookup
    source_a.py         #   legacy CRM CSV
    source_b.py         #   paginated SaaS JSON
    source_c.py         #   SQLite internal tool
  core/
    models.py           #   canonical schema dataclass
    normalise.py        #   raw record -> canonical fields
    resolve.py          #   identity resolution + precedence
    write.py            #   idempotent loader
    run.py              #   orchestration, retries, reconciliation
```


## Adding a fourth source

1. Write a new module in `src/dataplatform/connectors/` that subclasses
   `Connector` and implements `iter_raw()`.
2. Register it (one decorator line) in the same module.

No edits to the core, the normaliser, the resolver, the writer, or the CLI.

## Documentation

- [`SCHEMA.md`](SCHEMA.md) — canonical schema and field-level precedence rules.
- [`DECISIONS.md`](DECISIONS.md) — design decisions, rejected alternatives,
  identity-resolution rule, and AI-tool declaration.
- [`FINDINGS.md`](FINDINGS.md) — every data problem found, how many records it
  affects, and what the pipeline does about it.
